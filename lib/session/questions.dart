/// The questions an agent asks through a form, in one shape whichever
/// adapter sent them. Each adapter lays its questions out in a form of its
/// own: which of a field's title and description is the question, which text
/// field is a question's own answer, which option stands for one. An
/// enricher reads that layout by the adapter's own marks (`enrichers.dart`)
/// and leaves this shape beside the form under `_meta`, keeping the form as
/// it was sent, so the answer goes back under the adapter's own field ids
/// and anything that does not read the shape answers the same form. From
/// the original's `session/questions.ts`.
library;

import 'enrich.dart' show recordOf;

/// The `_meta` key on an elicitation request that holds its questions.
const questionsKey = 'chord/questions';

/// The adapters whose question forms chord reads.
enum QuestionsAgent { claude, codex, droid, opencode, dimcode }

/// A form's questions, as `_meta["chord/questions"]` holds them.
final class Questions {
  const Questions(this.agent, this.questions, {this.expiresInMs});

  /// Reads [json] as an enricher wrote it; null when it is not that shape.
  static Questions? fromJson(Object? json) {
    final value = recordOf(json);
    final agent = _agent(value['agent']);
    final list = value['questions'];
    if (agent == null || list is! List) return null;
    return Questions(
      agent,
      [for (final each in list) ?Question.fromJson(each)],
      expiresInMs: switch (value['expiresInMs']) {
        final num ms => ms,
        _ => null,
      },
    );
  }

  final QuestionsAgent agent;
  final List<Question> questions;

  /// How long the agent waits before it answers for the person (codex's
  /// `autoResolutionMs`), counted from when the request came.
  final num? expiresInMs;

  /// As it goes under `_meta`.
  Map<String, Object?> toJson() => {
    'agent': agent.name,
    'questions': [for (final each in questions) each.toJson()],
    'expiresInMs': ?expiresInMs,
  };
}

/// One question.
final class Question {
  const Question({
    required this.id,
    required this.text,
    required this.multiSelect,
    required this.required,
    required this.options,
    this.header,
    this.secret,
    this.own,
  });

  static Question? fromJson(Object? json) {
    final value = recordOf(json);
    if (value case {
      'id': final String id,
      'text': final String text,
      'options': final List<Object?> options,
    }) {
      return Question(
        id: id,
        text: text,
        header: _string(value['header']),
        multiSelect: value['multiSelect'] == true,
        required: value['required'] == true,
        secret: switch (value['secret']) {
          final bool secret => secret,
          _ => null,
        },
        options: [for (final each in options) ?QuestionOption.fromJson(each)],
        own: OwnAnswer.fromJson(value['own']),
      );
    }
    return null;
  }

  /// The form field that takes the pick, or the typed answer with no
  /// options.
  final String id;

  /// A short label for the question, when the agent gave one.
  final String? header;

  /// The question itself.
  final String text;
  final bool multiSelect;
  final bool required;

  /// What is typed is not to be shown.
  final bool? secret;

  /// The options to pick from; none for a question answered by typing.
  final List<QuestionOption> options;

  /// The text the person may type besides, or instead of, a pick.
  final OwnAnswer? own;

  Map<String, Object?> toJson() => {
    'id': id,
    'header': ?header,
    'text': text,
    'multiSelect': multiSelect,
    'required': required,
    'secret': ?secret,
    'options': [for (final each in options) each.toJson()],
    if (own case final own?) 'own': own.toJson(),
  };
}

/// One option of a question.
final class QuestionOption {
  const QuestionOption({
    required this.value,
    required this.title,
    this.description,
    this.preview,
  });

  static QuestionOption? fromJson(Object? json) {
    final value = recordOf(json);
    if (value case {'value': final String sent, 'title': final String title}) {
      return QuestionOption(
        value: sent,
        title: title,
        description: _string(value['description']),
        preview: _string(value['preview']),
      );
    }
    return null;
  }

  /// What is sent: the option's `const`.
  final String value;
  final String title;
  final String? description;

  /// claude's preview of what the option makes, not drawn yet.
  final String? preview;

  Map<String, Object?> toJson() => {
    'value': value,
    'title': title,
    'description': ?description,
    'preview': ?preview,
  };
}

/// How a question's own answer goes with a pick.
enum OwnMode {
  /// Both are sent, and the agent reads them together.
  beside,

  /// One or the other, as the agent refuses both.
  instead,

  /// The text goes with [OwnAnswer.value] as the pick, the option the
  /// agent offers for it, which is taken out of the options.
  withValue,
}

/// A question's own answer, and how it goes with a pick.
final class OwnAnswer {
  const OwnAnswer({
    required this.field,
    required this.mode,
    this.value,
    this.placeholder,
  });

  static OwnAnswer? fromJson(Object? json) {
    final value = recordOf(json);
    final mode = OwnMode.values.asNameMap()[value['mode']];
    if (value case {'field': final String field} when mode != null) {
      return OwnAnswer(
        field: field,
        mode: mode,
        value: _string(value['value']),
        placeholder: _string(value['placeholder']),
      );
    }
    return null;
  }

  /// The form field the text goes in.
  final String field;
  final OwnMode mode;
  final String? value;

  /// The field's description, shown while it is empty.
  final String? placeholder;

  Map<String, Object?> toJson() => {
    'field': field,
    'mode': mode.name,
    'value': ?value,
    'placeholder': ?placeholder,
  };
}

/// The questions an elicitation request carries, when an enricher read any.
Questions? questionsOf(Map<String, Object?> request) =>
    Questions.fromJson(recordOf(request['_meta'])[questionsKey]);

/// One property of a requested schema, as the readers take it.
typedef Property = Map<String, Object?>;

/// A form's properties in order, and which it requires.
final class FormFields {
  const FormFields(this.properties, this.required);

  final List<(String, Property)> properties;
  final Set<String> required;
}

/// The properties of a form request's schema; none for anything else.
FormFields? formFields(Object? params) {
  final request = recordOf(params);
  final schema = recordOf(request['requestedSchema']);
  final properties = [
    for (final MapEntry(:key, :value) in recordOf(schema['properties']).entries)
      (key, recordOf(value)),
  ];
  if (request['mode'] != 'form' || properties.isEmpty) return null;
  return FormFields(properties, {
    if (schema['required'] case final List<Object?> keys)
      for (final key in keys)
        if (key case final String key) key,
  });
}

/// A string, when [value] is a non-empty one.
String? text(Object? value) => value is String && value != '' ? value : null;

/// A property's titled options, and whether it takes several: a string's
/// `oneOf` or an array's `anyOf`, each option a `const`. Anything else, such
/// as a plain `enum` or no options at all, is none, as the readers take only
/// the shapes the adapters send.
({List<QuestionOption> options, bool multiSelect})? choices(Property property) {
  final multiSelect = property['type'] == 'array';
  final list = multiSelect
      ? recordOf(property['items'])['anyOf']
      : property['type'] == 'string'
      ? property['oneOf']
      : null;
  if (list is! List || list.isEmpty) return null;

  final options = <QuestionOption>[];
  for (final entry in list.map(recordOf)) {
    final value = entry['const'];
    if (value is! String) return null;
    final meta = recordOf(entry['_meta']);
    options.add(
      QuestionOption(
        value: value,
        title: text(entry['title']) ?? value,
        description: text(entry['description']),
        preview: text(
          recordOf(meta['_claude/askUserQuestionOption'])['preview'],
        ),
      ),
    );
  }
  return (options: options, multiSelect: multiSelect);
}

/// A plain text property, as an own answer or a typed question takes.
bool isText(Property property) =>
    property['type'] == 'string' &&
    !property.containsKey('oneOf') &&
    !property.containsKey('enum');

/// What the person gave one question: the options picked, by value; the
/// text typed as the answer to a question with no options; the text typed
/// in its own answer; and, where that text stands for an option (`instead`,
/// `withValue`), whether its row is the one chosen.
final class QuestionAnswer {
  const QuestionAnswer({
    this.picks = const [],
    this.text = '',
    this.own = '',
    this.ownChosen = false,
  });

  final List<String> picks;
  final String text;
  final String own;
  final bool ownChosen;
}

/// The content an accepted form sends for [answers], under the agent's own
/// field ids: each pick in its question's field (a list where it takes
/// several), or the text typed for a question with no options; the own text
/// in its own field, beside the pick, instead of it when its row is chosen,
/// or, with `withValue`, with the option it stands for. A question left
/// without an answer sends nothing.
Map<String, Object?> answerOf(
  Questions questions,
  Map<String, QuestionAnswer> answers,
) {
  final content = <String, Object?>{};

  for (final question in questions.questions) {
    final answer = answers[question.id];
    if (answer == null) continue;

    final own = question.own;
    final typed = answer.own.trim();
    final ownSent =
        own != null &&
        typed != '' &&
        (own.mode == OwnMode.beside || answer.ownChosen);
    final picks = own?.mode == OwnMode.instead && ownSent
        ? <String>[]
        : own?.mode == OwnMode.withValue && ownSent && own.value != null
        ? [...answer.picks, own.value!]
        : [...answer.picks];
    final text = answer.text.trim();

    if (question.options.isEmpty) {
      if (text != '') content[question.id] = text;
    } else if (question.multiSelect) {
      if (picks.isNotEmpty) content[question.id] = picks;
    } else if (picks.isNotEmpty) {
      content[question.id] = picks.last;
    }

    if (ownSent) content[own.field] = typed;
  }

  return content;
}

/// [content] without what was given for a secret question, which must not
/// reach a file: its own field and its own answer's.
Map<String, Object?> withoutSecrets(
  Questions? questions,
  Map<String, Object?> content,
) {
  final hidden = {
    for (final question in questions?.questions ?? const <Question>[])
      if (question.secret == true) ...[
        question.id,
        if (question.own case final own?) own.field,
      ],
  };
  return {
    for (final MapEntry(:key, :value) in content.entries)
      if (!hidden.contains(key)) key: value,
  };
}

QuestionsAgent? _agent(Object? name) =>
    name is String ? QuestionsAgent.values.asNameMap()[name] : null;

String? _string(Object? value) => value is String ? value : null;
