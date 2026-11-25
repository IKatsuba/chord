/// The enrichers M1 runs on every session, in the original's order: a tool
/// call's title and kind carried onto its updates, Codex's MCP call and its
/// Guardian review filed, a result sent only as `rawOutput` as content, and
/// an adapter's question form read into chord's one shape of questions.
/// Each fills in only what the agent left out.
library;

import 'dart:convert';

import 'enrich.dart';
import 'models.dart';
import 'modes.dart';
import 'prices.dart';
import 'questions.dart';
import 'usage.dart';
import 'transcript/tools.dart' show guardianReviewKey, mcpCallKey;

/// A `tool_call_update`, or the tool call a permission asks about, gets the
/// title and kind the call had when the agent gave them before and leaves
/// them out now.
List<Message> toolCallFacts(Message message, Wire wire) {
  final notification = notificationOf(message);

  if (notification != null) {
    final (sessionId, update) = notification;

    if (update['sessionUpdate'] != 'tool_call_update') {
      return [message];
    }

    final filled = _carried(update, wire.tools[sessionId]);

    return [if (filled == null) message else withUpdate(message, filled)];
  }

  if (!message.containsKey('id') ||
      message['method'] != 'session/request_permission') {
    return [message];
  }

  final params = recordOf(message['params']);
  final toolCall = params['toolCall'];
  final sessionId = params['sessionId'];
  final filled = toolCall is Map<String, Object?> && sessionId is String
      ? _carried(toolCall, wire.tools[sessionId])
      : null;

  return [
    if (filled == null)
      message
    else
      withParams(message, {...params, 'toolCall': filled}),
  ];
}

/// Files an MCP call's server, tool and arguments under
/// `_meta["chord/mcp"]` where codex-acp wraps them in the call's
/// `rawInput` and says `_meta.is_mcp_tool_call`. The `rawInput` stays as
/// the agent sent it.
List<Message> codexMcpCall(Message message, Wire wire) {
  final update = notificationOf(message)?.$2;

  if (update == null || !_isToolUpdate(update)) {
    return [message];
  }

  final meta = recordOf(update['_meta']);
  final wrapped = recordOf(update['rawInput']);

  if (meta['is_mcp_tool_call'] != true ||
      meta.containsKey(mcpCallKey) ||
      wrapped['server'] is! String ||
      wrapped['tool'] is! String) {
    return [message];
  }

  return [
    withUpdate(message, {
      ...update,
      '_meta': {
        ...markFilled(update['_meta'], [mcpCallKey]),
        mcpCallKey: {
          'server': wrapped['server'],
          'tool': wrapped['tool'],
          if (wrapped.containsKey('arguments'))
            'arguments': wrapped['arguments'],
        },
      },
    }),
  ];
}

/// Files Codex Guardian's structured review status, which codex-acp sends
/// as `rawInput.review.status` on a `tool_call` and `rawOutput.review.status`
/// on an update named `guardian_assessment:<id>`; never its rendered text.
List<Message> codexGuardianReview(Message message, Wire wire) {
  final update = notificationOf(message)?.$2;
  if (update == null) return [message];
  final reviewed = guardianReview(update);
  return [
    identical(reviewed, update) ? message : withUpdate(message, reviewed),
  ];
}

/// Interprets Guardian's structured status for both old records and live traffic.
Message guardianReview(Message update) {
  if (!_isToolUpdate(update)) return update;
  final id = update['toolCallId'];
  if (id is! String ||
      !id.startsWith('guardian_assessment:') ||
      id == 'guardian_assessment:') {
    return update;
  }
  final raw = recordOf(
    update['sessionUpdate'] == 'tool_call'
        ? update['rawInput']
        : update['rawOutput'],
  );
  final status = recordOf(raw['review'])['status'];
  if (status is! String) return update;
  return {
    ...update,
    '_meta': {
      ...markFilled(update['_meta'], [guardianReviewKey]),
      guardianReviewKey: status,
    },
  };
}

/// The keys of a `rawOutput` object read as its text, in this order.
const _outputKeys = ['stdout', 'stderr', 'output', 'result'];

/// A tool call whose result comes only in `rawOutput`, with no `content`:
/// the `rawOutput` filled in as one text block. A string is the text; an
/// object whose `stdout`, `stderr`, `output` or `result` are strings is
/// those, in that order, and its `exitCode` other than 0 fails a call said
/// `completed`; anything else is its JSON. Content the agent sent stays, in
/// this message or an earlier one a later leaves as it is. A bare successful
/// `exit_code` is bookkeeping, so it contributes no text.
List<Message> rawOutputContent(Message message, Wire wire) {
  final notification = notificationOf(message);

  if (notification == null) {
    return [message];
  }

  final (sessionId, update) = notification;
  final content = update['content'];
  final raw = update['rawOutput'];

  if (!_isToolUpdate(update) ||
      (content is List && content.isNotEmpty) ||
      (content != null && content is! List) ||
      (content == null &&
          wire.tools[sessionId]?[update['toolCallId']]?.ownContent == true) ||
      raw == null) {
    return [message];
  }

  final fields = raw is Map<String, Object?> ? raw : const <String, Object?>{};
  // Codex may send successful bookkeeping before the file's content.
  if (fields.length == 1 && fields['exit_code'] == 0) {
    return [message];
  }

  final named = [
    for (final key in _outputKeys)
      if (fields[key] is String) key,
  ];
  final keyed = raw is Map<String, Object?> && named.isNotEmpty;
  final text = raw is String
      ? raw
      : keyed
      ? [
          for (final key in named) _withoutLastNewline(fields[key] as String),
        ].where((part) => part.isNotEmpty).join('\n')
      : const JsonEncoder.withIndent('  ').convert(raw);
  final exitCode = fields['exitCode'];
  final failed =
      keyed &&
      update['status'] == 'completed' &&
      exitCode is num &&
      exitCode != 0;

  if (text.isEmpty && !failed) {
    return [message];
  }

  return [
    withUpdate(message, {
      ...update,
      if (text.isNotEmpty)
        'content': [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': text},
          },
        ],
      if (failed) 'status': 'failed',
      '_meta': markFilled(update['_meta'], [
        if (text.isNotEmpty) 'content',
        if (failed) 'status',
      ]),
    }),
  ];
}

/// Fills an empty mode acknowledgement only when no mode report arrived
/// while that request was open; the agent's report always wins.
List<Message> modeReadBack(Message message, Wire wire) {
  final asked = message.containsKey('method') || message.containsKey('error')
      ? null
      : wire.asked['${message['id']}'];
  if (asked == null || asked.modeReported || !message.containsKey('result')) {
    return [message];
  }
  final sessionId = asked.params['sessionId'];
  final state = wire.sessions[sessionId];
  if (sessionId is! String || state == null) return [message];
  if (asked.method == 'session/set_mode') {
    final mode = asked.params['modeId'];
    if (mode is! String ||
        modesFrom(state.configOptions, state.modes)?.current == mode) {
      return [message];
    }
    return [
      {
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': sessionId,
          'update': {
            'sessionUpdate': 'current_mode_update',
            'currentModeId': mode,
            '_meta': markFilled(null, ['currentModeId']),
          },
        },
      },
      message,
    ];
  }
  final key = modeConfigId(state.configOptions);
  final result = recordOf(message['result']);
  final options = result['configOptions'];
  final value = asked.params['value'];
  if (asked.method != 'session/set_config_option' ||
      key == null ||
      asked.params['configId'] != key ||
      value is! String ||
      (options is List && options.isNotEmpty)) {
    return [message];
  }
  return [
    {
      ...message,
      'result': {
        ...result,
        'configOptions': [
          for (final o in state.configOptions)
            o['id'] == key && o['type'] == 'select'
                ? {...o, 'currentValue': value}
                : o,
        ],
        '_meta': markFilled(result['_meta'], ['configOptions']),
      },
    },
  ];
}

/// Prices a turn whose answer carries its tokens, for an agent that has
/// given no cost of its own: a `usage_update` with chord's estimate of the
/// session's cost so far goes ahead of the answer, as Claude's adapter sends
/// its own, with the context as the agent last gave it, or else as the
/// turn's tokens make it. An agent's own `usage_update` without a cost gets
/// the estimate so far. An answer that gives the session's running total has
/// what it grew by since the last priced, at the model that answered.
List<Message> costFromTokens(Message message, Wire wire) {
  if (notificationOf(message) case (final sessionId, final update)) {
    final costs = wire.costs[sessionId];
    final estimate = costs?.estimate;
    if (update['sessionUpdate'] != 'usage_update' ||
        update['cost'] != null ||
        estimate == null ||
        costs!.agentCost) {
      return [message];
    }
    return [
      withUpdate(message, {
        ...update,
        'cost': {'amount': estimate, 'currency': priceCurrency},
        '_meta': markFilled(update['_meta'], ['cost']),
      }),
    ];
  }

  final asked = message.containsKey('method') || message.containsKey('error')
      ? null
      : wire.asked['${message['id']}'];
  final sessionId = asked?.params['sessionId'];
  if (asked?.method != 'session/prompt' || sessionId is! String) {
    return [message];
  }
  final usage = recordOf(message['result'])['usage'];
  final costs = wire.costs[sessionId] ?? SessionCosts.none;
  final state = wire.sessions[sessionId];
  final model = state == null
      ? null
      : modelsFrom(state.configOptions, state.models)?.current;
  if (usage is! Map<String, Object?> || costs.agentCost || model == null) {
    return [message];
  }
  final tokens = tokensOf(usage);
  final cost = turnCost(
    model,
    wire.totals ? grownBy(costs.total, tokens) : tokens,
  );
  if (cost == null) return [message];
  final known = costs.usage;
  return [
    {
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {
        'sessionId': sessionId,
        'update': {
          'sessionUpdate': 'usage_update',
          'used': known?.used ?? contextFrom(tokens),
          'size': known?.size ?? 0,
          'cost': {
            'amount': (costs.estimate ?? 0) + cost,
            'currency': priceCurrency,
          },
          '_meta': markFilled(
            null,
            known != null ? ['cost'] : ['used', 'cost'],
          ),
        },
      },
    },
    message,
  ];
}

/// A `usage_update` with no window gets the model's, when the data has it.
List<Message> windowFromModel(Message message, Wire wire) {
  final notification = notificationOf(message);
  if (notification == null) return [message];
  final (sessionId, update) = notification;
  final size = update['size'];
  if (update['sessionUpdate'] != 'usage_update' || (size is num && size > 0)) {
    return [message];
  }
  final state = wire.sessions[sessionId];
  final model = state == null
      ? null
      : modelsFrom(state.configOptions, state.models)?.current;
  final window = model == null || model.isEmpty ? null : contextWindow(model);
  if (window == null) return [message];
  return [
    withUpdate(message, {
      ...update,
      'size': window,
      '_meta': markFilled(update['_meta'], ['size']),
    }),
  ];
}

/// Marks a subagent's update as its title naming it, on Claude's adapter.
List<Message> claudeSubagentName(Message message, Wire wire) {
  final notification = notificationOf(message);
  if (wire.adapter != claudeAdapter ||
      notification?.$2['sessionUpdate'] != 'subagent_update') {
    return [message];
  }
  final update = notification!.$2;
  return [
    withUpdate(message, {
      ...update,
      '_meta': {...recordOf(update['_meta']), namedByTitleKey: true},
    }),
  ];
}

/// A subagent as ACP's `subagent_update` says it, from the shape Claude's
/// adapter once sent and Codex's before 2.4 sends (ACP's draft PR #1992):
/// `subagent_spawned`'s `subagentSessionId`, `name`, `task` and
/// `capabilities` become `sessionId`, `title`, `description` and
/// `capabilities`, and `subagent_state_update`'s `state`, a word, becomes a
/// state object of that word. The rest of the draft goes under `_meta`. An
/// agent that sends `subagent_update` already passes as it is, so the rest of
/// chord reads one shape.
List<Message> subagentShape(Message message, Wire wire) {
  final notification = notificationOf(message);
  final draft = notification?.$2 ?? const <String, Object?>{};
  final sessionUpdate = draft['sessionUpdate'];
  final subagentSessionId = draft['subagentSessionId'];
  if (notification == null ||
      subagentSessionId is! String ||
      (sessionUpdate != 'subagent_spawned' &&
          sessionUpdate != 'subagent_state_update')) {
    return [message];
  }
  const renamed = {'name': 'title', 'task': 'description'};
  final rest = <String, Object?>{};
  final update = <String, Object?>{
    'sessionUpdate': 'subagent_update',
    'sessionId': subagentSessionId,
  };
  for (final MapEntry(:key, :value) in draft.entries) {
    if (key == 'sessionUpdate' ||
        key == 'subagentSessionId' ||
        key == '_meta') {
      continue;
    }
    final as = renamed[key];
    if (as != null && value is String) {
      update[as] = value;
    } else if (key == 'capabilities' && value is Map<String, Object?>) {
      update['capabilities'] = value;
    } else if (key == 'state' && value is String) {
      update['state'] = {'state': value};
    } else {
      rest[key] = value;
    }
  }
  update['_meta'] = {
    ...recordOf(draft['_meta']),
    subagentDraftKey: {'sessionUpdate': sessionUpdate, ...rest},
  };
  return [withUpdate(message, update)];
}

/// A form field: its key and its schema.
typedef _Field = (String, Property);

/// A form's questions as one adapter lays them out, read from the request's
/// params and its fields; none unless every mark of the adapter's is there
/// and every field has its place, so no field a person must fill in is
/// hidden.
typedef _QuestionReader =
    Questions? Function(Map<String, Object?> params, FormFields fields);

/// [message] with what [read] finds under `_meta["chord/questions"]`,
/// leaving the form as the agent sent it. A request another enricher has
/// already read passes as it is.
List<Message> _questionShape(Message message, _QuestionReader read) {
  if (!message.containsKey('method') ||
      !message.containsKey('id') ||
      message['method'] != 'elicitation/create') {
    return [message];
  }
  final params = recordOf(message['params']);
  final meta = recordOf(params['_meta']);
  final fields = formFields(params);
  if (meta[questionsKey] != null || fields == null) return [message];

  final questions = read(params, fields);
  return questions == null
      ? [message]
      : [
          withParams(message, {
            ...params,
            '_meta': markFilled(
              {...meta, questionsKey: questions.toJson()},
              [questionsKey],
            ),
          }),
        ];
}

/// Pairs each question field with the own-answer field its key names, as
/// claude's, factory-droid's and opencode's forms key them: [question] and
/// [own] match a key, [own] with the question's key as its first group.
/// Every key must be one or the other, and every own answer must have its
/// question.
List<({String id, Property property, _Field? own})>? _pairedByKey(
  FormFields fields,
  RegExp question,
  RegExp own,
) {
  final owns = <String, _Field>{};
  final questions = <_Field>[];
  for (final (key, property) in fields.properties) {
    final ownOf = own.firstMatch(key)?.group(1);
    if (ownOf != null) {
      owns[ownOf] = (key, property);
    } else if (question.hasMatch(key)) {
      questions.add((key, property));
    } else {
      return null;
    }
  }
  if (owns.keys.any((id) => !questions.any((each) => each.$1 == id))) {
    return null;
  }
  return [
    for (final (id, property) in questions)
      (id: id, property: property, own: owns[id]),
  ];
}

/// A typed question's choices: no options, one answer.
const _typed = (options: <QuestionOption>[], multiSelect: false);

/// claude's AskUserQuestion: `question_<n>` with its header as the title and
/// the question as the description, or, alone, as the form's message; then
/// `question_<n>_custom`, titled `Other`, the own answer beside the pick.
List<Message> claudeQuestions(Message message, Wire wire) =>
    _questionShape(message, (params, fields) {
      final pairs = _pairedByKey(
        fields,
        RegExp(r'^question_\d+$'),
        RegExp(r'^(question_\d+)_custom$'),
      );
      if (pairs == null) return null;
      final questions = <Question>[];
      for (final (:id, :property, :own) in pairs) {
        final picks = choices(property);
        final question =
            text(property['description']) ??
            (pairs.length == 1 ? text(params['message']) : null);
        if (picks == null ||
            picks.options.isEmpty ||
            question == null ||
            own == null ||
            own.$2['title'] != 'Other' ||
            !isText(own.$2)) {
          return null;
        }
        questions.add(
          Question(
            id: id,
            header: text(property['title']),
            text: question,
            options: picks.options,
            multiSelect: picks.multiSelect,
            required: fields.required.contains(id),
            own: OwnAnswer(
              field: own.$1,
              mode: OwnMode.beside,
              placeholder: text(own.$2['description']),
            ),
          ),
        );
      }
      return Questions(QuestionsAgent.claude, questions);
    });

/// codex's `request_user_input`: each question's field carries
/// `_meta.codex`, with the question as its title and the header as its
/// description, options or none, and its note, which `_meta.codex` marks a
/// `user_note` for its `questionId`, goes beside the pick. The request's own
/// `_meta.codex` gives how long codex waits for the person.
List<Message> codexQuestions(Message message, Wire wire) =>
    _questionShape(message, (params, fields) {
      final codex = recordOf(params['_meta'])['codex'];
      if (codex is! Map<String, Object?>) return null;

      final notes = <String, _Field>{};
      final asked = <(String, Property, Map<String, Object?>)>[];
      for (final (key, property) in fields.properties) {
        final mark = recordOf(property['_meta'])['codex'];
        if (mark is! Map<String, Object?>) return null;
        if (mark['role'] == 'user_note') {
          final questionId = mark['questionId'];
          if (questionId is! String ||
              !isText(property) ||
              notes.containsKey(questionId)) {
            return null;
          }
          notes[questionId] = (key, property);
        } else {
          asked.add((key, property, mark));
        }
      }
      if (notes.keys.any((id) => !asked.any((each) => each.$1 == id))) {
        return null;
      }

      final questions = <Question>[];
      for (final (id, property, mark) in asked) {
        final picks = isText(property) ? _typed : choices(property);
        final question = text(property['title']);
        final note = notes[id];
        if (picks == null || question == null) return null;
        questions.add(
          Question(
            id: id,
            header: text(property['description']),
            text: question,
            options: picks.options,
            multiSelect: picks.multiSelect,
            required: fields.required.contains(id),
            secret: mark['isSecret'] == true ? true : null,
            own: note == null
                ? null
                : OwnAnswer(
                    field: note.$1,
                    mode: OwnMode.beside,
                    placeholder:
                        text(note.$2['description']) ?? text(note.$2['title']),
                  ),
          ),
        );
      }
      final wait = codex['autoResolutionMs'];
      return Questions(
        QuestionsAgent.codex,
        questions,
        expiresInMs: wait is num && wait >= 0 ? wait : null,
      );
    });

/// The message factory-droid's question forms open with.
const _droidMessage = 'Droid needs your answers to continue.';

/// factory-droid's questions: `question_<i>`, its topic as the title and the
/// question as the description, its options `option_<k>` and a last
/// `other`, which `question_<i>_other` gives the text of; or a typed
/// question with no options.
List<Message> droidQuestions(Message message, Wire wire) =>
    _questionShape(message, (params, fields) {
      final pairs = params['message'] == _droidMessage
          ? _pairedByKey(
              fields,
              RegExp(r'^question_\d+$'),
              RegExp(r'^(question_\d+)_other$'),
            )
          : null;
      if (pairs == null) return null;
      final optionValue = RegExp(r'^option_\d+$');
      final questions = <Question>[];
      for (final (:id, :property, :own) in pairs) {
        final picks = isText(property) ? _typed : choices(property);
        final question = text(property['description']);
        if (picks == null || question == null) return null;
        final options = [
          for (final option in picks.options)
            if (option.value != 'other') option,
        ];
        final offersOther = options.length != picks.options.length;
        if (options.any((option) => !optionValue.hasMatch(option.value)) ||
            offersOther != (own != null) ||
            (own != null && !isText(own.$2))) {
          return null;
        }
        questions.add(
          Question(
            id: id,
            header: text(property['title']),
            text: question,
            options: options,
            multiSelect: picks.multiSelect,
            required: fields.required.contains(id),
            own: own == null
                ? null
                : OwnAnswer(
                    field: own.$1,
                    mode: OwnMode.withValue,
                    value: 'other',
                  ),
          ),
        );
      }
      return Questions(QuestionsAgent.droid, questions);
    });

/// opencode's questions, under the message `Questions`: `q<i>`, its header
/// as the title and the question as the description, then `q<i>_custom`,
/// titled `(other)`, the own answer beside the pick.
List<Message> opencodeQuestions(Message message, Wire wire) =>
    _questionShape(message, (params, fields) {
      final pairs = params['message'] == 'Questions'
          ? _pairedByKey(fields, RegExp(r'^q\d+$'), RegExp(r'^(q\d+)_custom$'))
          : null;
      if (pairs == null) return null;
      final questions = <Question>[];
      for (final (:id, :property, :own) in pairs) {
        final picks = choices(property);
        final question = text(property['description']);
        if (picks == null ||
            picks.options.isEmpty ||
            question == null ||
            own == null ||
            own.$2['title'] != '(other)' ||
            !isText(own.$2)) {
          return null;
        }
        questions.add(
          Question(
            id: id,
            header: text(property['title']),
            text: question,
            options: picks.options,
            multiSelect: picks.multiSelect,
            required: fields.required.contains(id),
            own: OwnAnswer(
              field: own.$1,
              mode: OwnMode.beside,
              placeholder: text(own.$2['description']),
            ),
          ),
        );
      }
      return Questions(QuestionsAgent.opencode, questions);
    });

/// dimcode's questions, the request marked `_meta.lody.elicitation`: each
/// question's field keyed by its id, its header as the title and the
/// question as the description, and `__custom_<i>`, whose
/// `_meta.lody.elicitation` names the question it answers instead of a
/// pick, as dimcode refuses both.
List<Message> dimcodeQuestions(Message message, Wire wire) =>
    _questionShape(message, (params, fields) {
      Object? lody(Object? value) =>
          recordOf(recordOf(recordOf(value)['_meta'])['lody'])['elicitation'];
      if (lody(params) is! Map<String, Object?>) return null;

      final custom = RegExp(r'^__custom_\d+$');
      final owns = <String, _Field>{};
      final asked = <_Field>[];
      for (final (key, property) in fields.properties) {
        final answers = recordOf(lody(property))['customAnswerFor'];
        if (answers is String) {
          if (!custom.hasMatch(key) ||
              !isText(property) ||
              owns.containsKey(answers)) {
            return null;
          }
          owns[answers] = (key, property);
        } else {
          asked.add((key, property));
        }
      }
      if (owns.keys.any((id) => !asked.any((each) => each.$1 == id))) {
        return null;
      }

      final questions = <Question>[];
      for (final (id, property) in asked) {
        final picks = choices(property);
        final question = text(property['description']);
        final own = owns[id];
        if (picks == null || picks.options.isEmpty || question == null) {
          return null;
        }
        questions.add(
          Question(
            id: id,
            header: text(property['title']),
            text: question,
            options: picks.options,
            multiSelect: picks.multiSelect,
            required: fields.required.contains(id),
            own: own == null
                ? null
                : OwnAnswer(field: own.$1, mode: OwnMode.instead),
          ),
        );
      }
      return Questions(QuestionsAgent.dimcode, questions);
    });

/// Every enricher, in the order each runs over what the last one made.
const List<Enricher> m1Enrichers = [
  subagentShape,
  claudeSubagentName,
  toolCallFacts,
  codexMcpCall,
  codexGuardianReview,
  rawOutputContent,
  modeReadBack,
  costFromTokens,
  windowFromModel,
  claudeQuestions,
  codexQuestions,
  droidQuestions,
  opencodeQuestions,
  dimcodeQuestions,
];

bool _isToolUpdate(Message update) =>
    update['sessionUpdate'] == 'tool_call' ||
    update['sessionUpdate'] == 'tool_call_update';

String _withoutLastNewline(String text) =>
    text.endsWith('\n') ? text.substring(0, text.length - 1) : text;

bool _missing(Object? value) => value == null || value == '';

/// [call] with the title and kind the session knows for it, where it has
/// none; null when nothing is missing or nothing is known.
Message? _carried(Message call, Map<String, ToolFacts>? session) {
  final known = session?[call['toolCallId']];
  final title = _missing(call['title']) && !_missing(known?.title)
      ? known!.title
      : null;
  final kind = _missing(call['kind']) && !_missing(known?.kind)
      ? known!.kind
      : null;
  final fields = [if (title != null) 'title', if (kind != null) 'kind'];

  if (fields.isEmpty) {
    return null;
  }

  return {
    ...call,
    'title': ?title,
    'kind': ?kind,
    '_meta': markFilled(call['_meta'], fields),
  };
}
