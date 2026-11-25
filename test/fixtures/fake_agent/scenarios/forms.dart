// Elicitations: a form to fill in, a link to open, and each adapter's
// question form, as the original's scenarios/forms.ts.
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../forms.dart';
import '../../questions.dart';
import '../options.dart';
import '../rpc.dart';
import '../sessions.dart';
import '../turn.dart';
import 'agents.dart';

/// Asks the client for input and says what came back: the action, and an
/// accepted form's content as one line of JSON.
Future<String> elicit(Turn turn, Map<String, Object?> request) async {
  final answer = await turn.client.request('elicitation/create', request);

  // The client answers `cancel` for a turn being cancelled.
  if (turn.signal.aborted) return 'cancelled';

  if (request['mode'] == 'url' && answer['action'] == 'accept') {
    await turn.client.notify('elicitation/complete', {
      'elicitationId': request['elicitationId'],
    });
  }

  final content = answer['action'] == 'accept' && _truthy(answer['content'])
      ? '  \n${stringify(answer['content'])}'
      : '';
  await turn.say(['Elicitation answer: ${_js(answer['action'])}$content']);
  return 'end_turn';
}

bool _truthy(Object? value) =>
    value != null &&
    value != false &&
    value != 0 &&
    value != '' &&
    !(value is double && value.isNaN);

/// [value] as a template literal writes it.
String _js(Object? value) => value == null ? 'undefined' : '$value';

/// Each of claude's questions by its field, with its text.
List<(String, String)> _claudeQuestions(Map<String, Object?> form) {
  final schema = form['requestedSchema'] as Map;
  final properties = (schema['properties'] as Map?) ?? const {};
  return [
    for (final MapEntry(:key, :value) in properties.entries)
      if (RegExp(r'^question_\d+$').hasMatch(key as String))
        (
          key,
          ((value as Map)['description'] as String?) ?? '${form['message']}',
        ),
  ];
}

/// Asks claude's questions as claude-agent-acp 0.93.0 does.
Play _askClaude(Map<String, Object?> form) => (turn) async {
  final toolCallId = turn.callId('ask');
  final questions = _claudeQuestions(form);

  await turn.send({
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    'title': questions.length == 1
        ? questions.single.$2
        : 'Asking for your input',
    'kind': 'other',
    'status': 'pending',
    'rawInput': {
      'questions': [
        for (final (_, text) in questions) {'question': text},
      ],
    },
    'content': [
      for (final (_, text) in questions)
        {
          'type': 'content',
          'content': {'type': 'text', 'text': text},
        },
    ],
  });

  final answer = await turn.client.request('elicitation/create', {
    ...form,
    'sessionId': turn.sessionId,
    'toolCallId': toolCallId,
  });
  if (turn.signal.aborted) return 'cancelled';

  final accepted = answer['action'] == 'accept';
  final content = accepted && answer['content'] is Map
      ? answer['content'] as Map
      : const {};
  final answered = [
    for (final (key, text) in questions)
      if (content.containsKey(key))
        '"$text"="${content[key] is List ? (content[key] as List).map(_js).join(', ') : _js(content[key])}"',
  ];
  final result = answer['action'] == 'cancel'
      ? 'Tool use aborted'
      : 'User has answered your questions: ${answered.join(', ')}. You can '
            "now continue with the user's answers in mind.";
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': answer['action'] == 'cancel' ? 'failed' : 'completed',
    'content': [
      {
        'type': 'content',
        'content': {'type': 'text', 'text': result},
      },
    ],
  });
  final echoed = accepted && _truthy(answer['content'])
      ? '  \n${stringify(answer['content'])}'
      : '';
  await turn.say(['Elicitation answer: ${_js(answer['action'])}$echoed']);
  return 'end_turn';
};

/// Asks an adapter's question form, as that adapter sends it.
Play _ask(Map<String, Object?> form) =>
    (turn) => elicit(turn, {...form, 'sessionId': turn.sessionId});

/// `leftform`'s play: the form asked, then the turn ended with it open.
Future<String> _leftForm(Turn turn, bool gated) async {
  final client = turn.client;
  final sessionId = turn.sessionId;
  () async {
    try {
      final answer = await client.request('elicitation/create', {
        'sessionId': sessionId,
        'mode': 'form',
        'message': 'Set up the deploy target',
        'requestedSchema': formSchema,
      });
      await client.notify('session/update', {
        'sessionId': sessionId,
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {
            'type': 'text',
            'text': 'Elicitation answer: ${_js(answer['action'])}',
          },
        },
      });
    } catch (_) {
      // The client went before it was answered.
    }
  }();
  if (gated) {
    await gateOpened(turn, gateRelease);
  } else {
    await pause(turn.signal, stepMs * 100);
  }
  await turn.say(['I asked; the turn ends with the form open.']);
  return 'end_turn';
}

final Map<String, Play> forms = {
  // Each adapter's question form, as `tests/fixtures/questions.ts` has it.
  'askclaude': _askClaude(claudeQuestionsForm),
  'askclaudeone': _askClaude(claudeQuestionForm),
  'askcodex': _ask(codexQuestionsForm),
  'askdroid': _ask(droidQuestionsForm),
  'askopencode': _ask(opencodeQuestionsForm),
  'askdimcode': _ask(dimcodeQuestionsForm),

  // codex's questions with a wait of 300 ms, withdrawn once it runs out.
  'askcodexwait': (turn) async {
    const wait = 300;
    final timer = Aborter();
    final timeout = later(wait, timer.abort);
    Map<String, Object?>? answer;
    try {
      answer = await turn.client.request('elicitation/create', {
        ...codexQuestionsForm,
        '_meta': {
          'codex': {'autoResolutionMs': wait},
        },
        'sessionId': turn.sessionId,
      }, cancellation: timer.signal);
    } catch (_) {
      answer = null;
    } finally {
      timeout.cancel();
    }
    await turn.say([
      timer.signal.aborted
          ? 'Elicitation answer: timed out'
          : 'Elicitation answer: ${answer?['action'] ?? 'none'}',
    ]);
    return 'end_turn';
  },

  // codex's questions delivered async: the turn ends without waiting, and
  // the form is withdrawn by `$/cancel_request` a while after.
  'askcodexasync': (turn) async {
    final withdraw = Aborter();
    turn.client.request('elicitation/create', {
      ...codexQuestionsForm,
      '_meta': {
        'codex': {'delivery': 'async'},
      },
      'sessionId': turn.sessionId,
    }, cancellation: withdraw.signal).ignore();
    () async {
      try {
        await turn.over;
        final at = p.join(cwds[turn.sessionId] ?? '.', gate);
        if (Directory(at).existsSync()) {
          final deadline = now() + 10000;
          while (!File(p.join(at, gateRelease)).existsSync() &&
              now() < deadline) {
            await pause(lifetime.signal, stepMs * 2);
          }
        } else {
          await pause(lifetime.signal, 2000);
        }
        withdraw.abort();
      } catch (_) {
        // The client went first.
      }
    }();
    await turn.say(['I asked; the answer can come later.']);
    return 'end_turn';
  },

  // The form asked in its turn, which then ends with it open (the owner's
  // Q53, CHD-158).
  'leftform': (turn) => _leftForm(turn, false),

  // As `leftform`, its turn ending once the gate is released (CHD-399).
  'leftformgated': (turn) => _leftForm(turn, true),

  // A form with a field of each kind, then what came back.
  'form': (turn) => elicit(turn, {
    'sessionId': turn.sessionId,
    'mode': 'form',
    'message': 'Set up the deploy target',
    'requestedSchema': formSchema,
  }),

  // A form scoped to a request of the agent's own and to no session.
  'requestform': (turn) => elicit(turn, {
    'requestId': 'own-request',
    'mode': 'form',
    'message': 'Not for any session',
    'requestedSchema': formSchema,
  }),

  // A form naming a session this agent never announced.
  'strangerform': (turn) => elicit(turn, {
    'sessionId': 'stranger-session',
    'mode': 'form',
    'message': 'Not for this session',
    'requestedSchema': formSchema,
  }),

  // A link to open; the client opens nothing without a key press.
  'link': (turn) => elicit(turn, {
    'sessionId': turn.sessionId,
    'mode': 'url',
    'elicitationId': turn.callId('link'),
    'message': 'Sign in to Example to continue',
    'url': linkUrl,
  }),
};
