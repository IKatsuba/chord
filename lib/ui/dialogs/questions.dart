/// The question box, kept out of the widget: an agent's questions one step
/// at a time, then a Submit step; what each key does to them, the rows a
/// step draws, the hint line and the answer it sends, under the agent's own
/// field ids (`answerOf`). A form the enrichers read no questions in keeps
/// the field table (`form.dart`). From the original's
/// `ui/dialogs/questions.ts`.
library;

import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart' show KeyEvent;

import '../../session/elicitations.dart' hide answerOf;
import '../../session/questions.dart';
import 'form.dart' show checkValue;

/// The box as the person has it: the step, the row and the answers.
final class AskState {
  const AskState({
    required this.step,
    required this.row,
    this.answers = const {},
    this.noteCursors = const {},
  });

  /// A question's index, or the questions' count for Submit.
  final int step;

  /// The row the `❯` is on within the step.
  final int row;
  final Map<String, QuestionAnswer> answers;

  /// The Note editor's cursor offsets, kept with this request across focus
  /// changes.
  final Map<String, int> noteCursors;

  AskState copyWith({
    int? step,
    int? row,
    Map<String, QuestionAnswer>? answers,
    Map<String, int>? noteCursors,
  }) => AskState(
    step: step ?? this.step,
    row: row ?? this.row,
    answers: answers ?? this.answers,
    noteCursors: noteCursors ?? this.noteCursors,
  );
}

/// One row a question step's `❯` moves through.
sealed class StepRow {
  const StepRow();
}

/// Option [index] of the question.
final class OptionRow extends StepRow {
  const OptionRow(this.index);
  final int index;

  @override
  bool operator ==(Object other) => other is OptionRow && other.index == index;

  @override
  int get hashCode => index.hashCode;
}

/// A question with no options: its answer, typed.
final class TextRow extends StepRow {
  const TextRow();
}

/// Its own answer: a `Note` beside the pick, or a last numbered option.
final class OwnRow extends StepRow {
  const OwnRow();
}

const _empty = QuestionAnswer();

/// The rows of [question]'s step, in order.
List<StepRow> rowsOf(Question question) => [
  for (var index = 0; index < question.options.length; index++)
    OptionRow(index),
  if (question.options.isEmpty) const TextRow(),
  if (question.own != null) const OwnRow(),
];

/// Only non-secret notes beside choices use the Note's cursor editor.
bool editableNote(Question question) =>
    question.secret != true &&
    question.options.isNotEmpty &&
    question.own?.mode == OwnMode.beside;

/// Whether the own answer is a numbered option of its own, not a note.
bool ownIsOption(Question question) =>
    question.own != null && question.own!.mode != OwnMode.beside;

/// What the person gave [question] so far.
QuestionAnswer answerTo(AskState state, Question question) =>
    state.answers[question.id] ?? _empty;

/// The content Send gives the agent.
Map<String, Object?> contentOf(Questions questions, AskState state) =>
    answerOf(questions, state.answers);

/// Whether [question] has an answer that would be sent.
bool answered(Question question, AskState state) => answerOf(
  Questions(QuestionsAgent.claude, [question]),
  state.answers,
).isNotEmpty;

/// What the field table finds wrong with [content] against [schema], by
/// field: `Required` for a required one left out, else the field's own
/// words.
Map<String, String> _problemsOf(
  Map<String, Object?> schema,
  Map<String, Object?> content,
) {
  final required = {...?(schema['required'] as List?)?.whereType<String>()};
  final problems = <String, String>{};
  final properties = switch (schema['properties']) {
    final Map<String, Object?> properties => properties,
    _ => const <String, Object?>{},
  };
  for (final MapEntry(:key, value: raw) in properties.entries) {
    final value = content[key];
    if (value == null) {
      if (required.contains(key)) problems[key] = 'Required';
      continue;
    }
    final property = raw is Map<String, Object?>
        ? raw
        : const <String, Object?>{};
    if (checkValue(property, value) case final problem?) {
      problems[key] = problem;
    }
  }
  return problems;
}

/// What stops Send, by question: a required one with no answer, or what
/// the agent's own schema finds wrong with the content, in the field
/// table's words, against the question its field belongs to.
Map<String, String> blockers(
  Questions questions,
  Map<String, Object?> schema,
  AskState state,
) {
  final problems = _problemsOf(schema, contentOf(questions, state));
  final found = <String, String>{};
  for (final question in questions.questions) {
    final problem =
        problems[question.id] ??
        (question.own == null ? null : problems[question.own!.field]);
    if (problem == 'Required' ||
        (question.required && !answered(question, state))) {
      found[question.id] = 'required';
    } else if (problem != null) {
      found[question.id] = problem;
    }
  }
  return found;
}

/// The box as it opens: the first question, on its picked or first row.
AskState openAsk(Questions questions) =>
    _enter(const AskState(step: 0, row: 0), questions, 0);

/// The row `❯` takes on entering a step: the picked one, else the first.
AskState _enter(AskState state, Questions questions, int step) {
  if (step >= questions.questions.length) {
    return state.copyWith(step: step, row: 0);
  }
  final question = questions.questions[step];
  final QuestionAnswer(:picks, :ownChosen) = answerTo(state, question);
  final picked = rowsOf(question).indexWhere(
    (row) => switch (row) {
      OptionRow(:final index) => picks.contains(question.options[index].value),
      OwnRow() => ownChosen && ownIsOption(question),
      TextRow() => false,
    },
  );
  return state.copyWith(step: step, row: math.max(picked, 0));
}

/// The Submit step's rows: Send, which may be out of reach, and Skip.
const _send = 0;
const _skip = 1;

QuestionAnswer _with(
  QuestionAnswer answer, {
  List<String>? picks,
  String? text,
  String? own,
  bool? ownChosen,
}) => QuestionAnswer(
  picks: picks ?? answer.picks,
  text: text ?? answer.text,
  own: own ?? answer.own,
  ownChosen: ownChosen ?? answer.ownChosen,
);

AskState _setAnswer(
  AskState state,
  Question question,
  QuestionAnswer Function(QuestionAnswer answer) change,
) => state.copyWith(
  answers: {...state.answers, question.id: change(answerTo(state, question))},
);

/// A Note edit keeps its text and the cursor with the request's answers.
AskState changedNote(
  AskState state,
  Question question,
  String own,
  int cursor,
) => _setAnswer(
  state,
  question,
  (answer) => _with(answer, own: own),
).copyWith(noteCursors: {...state.noteCursors, question.id: cursor});

/// What a key press did: the box after it, and the answer if it gave one.
final class AskStep {
  const AskStep(this.state, {this.response, this.leave = false});

  final AskState state;
  final ElicitationReply? response;

  /// ↓ on the box's last active row, a step's last or Skip: the keys go to
  /// the list of agents, the answers kept as they are.
  final bool leave;
}

/// The parts of a press the box reads: the text it types, and the keys
/// held or named.
final class AskKey {
  const AskKey({
    this.ctrl = false,
    this.escape = false,
    this.shift = false,
    this.upArrow = false,
    this.downArrow = false,
    this.leftArrow = false,
    this.rightArrow = false,
    this.tab = false,
    this.backspace = false,
    this.enter = false,
    this.meta = false,
    this.superKey = false,
  });

  final bool ctrl;
  final bool escape;
  final bool shift;
  final bool upArrow;
  final bool downArrow;
  final bool leftArrow;
  final bool rightArrow;
  final bool tab;
  final bool backspace;

  /// Return.
  final bool enter;
  final bool meta;

  /// cmd, which only a terminal speaking kitty's keyboard protocol reports.
  final bool superKey;
}

/// Keys owned by the Note's editor; navigation stays with the dialog.
bool noteEdits(String input, AskKey key) {
  if (!key.shift &&
      !key.ctrl &&
      (key.meta || key.superKey) &&
      (key.leftArrow || key.rightArrow)) {
    return true;
  }
  return key.backspace ||
      (key.ctrl && input == 'w') ||
      (input != '' &&
          input != '\n' &&
          !key.ctrl &&
          !key.meta &&
          !key.superKey &&
          !key.enter &&
          !key.tab &&
          !key.escape &&
          !key.upArrow &&
          !key.downArrow &&
          !key.leftArrow &&
          !key.rightArrow);
}

final _lineBreak = RegExp(r'\r\n|\r|\n');
final _lastWord = RegExp(r'\S*\s*$');

/// [event] as a question or plan box reads a press: the text it types and its keys.
(String, AskKey) askKeyOf(KeyEvent event) {
  final input = switch (event.key) {
    'space' => ' ',
    final key when key.runes.length == 1 => key,
    _ => '',
  };
  return (
    input,
    AskKey(
      ctrl: event.ctrl,
      escape: event.key == 'escape',
      shift: event.shift,
      upArrow: event.key == 'up',
      downArrow: event.key == 'down',
      leftArrow: event.key == 'left',
      rightArrow: event.key == 'right',
      tab: event.key == 'tab',
      backspace: event.key == 'backspace',
      enter: event.key == 'enter',
      meta: event.alt || event.meta,
      superKey: event.superKey,
    ),
  );
}

/// Typing and deleting at the end of a text row's value.
String? edited(String value, String input, AskKey key) {
  if (key.backspace) {
    final runes = value.runes.toList();
    return runes.isEmpty
        ? ''
        : String.fromCharCodes(runes.sublist(0, runes.length - 1));
  }
  if (key.ctrl && input == 'u') return '';
  if (key.ctrl && input == 'w') return value.replaceFirst(_lastWord, '');
  if (key.ctrl ||
      key.meta ||
      input == '' ||
      key.tab ||
      key.enter ||
      key.escape) {
    return null;
  }
  // A line break pasted into one line of text is a space.
  return value + input.replaceAll(_lineBreak, ' ');
}

/// Picks or toggles option [index] of [question].
AskState _pick(AskState state, Question question, int index) {
  if (index < 0 || index >= question.options.length) return state;
  final option = question.options[index];
  final answer = answerTo(state, question);

  if (!question.multiSelect) {
    return _setAnswer(
      state,
      question,
      (answer) => _with(
        answer,
        picks: [option.value],
        // A single question's own option and a pick are one choice.
        ownChosen: ownIsOption(question) ? false : answer.ownChosen,
      ),
    );
  }

  final ticked = answer.picks.contains(option.value)
      ? [
          for (final value in answer.picks)
            if (value != option.value) value,
        ]
      : [...answer.picks, option.value];
  final ordered = [
    for (final entry in question.options)
      if (ticked.contains(entry.value)) entry.value,
  ];
  // dimcode refuses its own answer beside a pick.
  return _setAnswer(
    state,
    question,
    (answer) => _with(
      answer,
      picks: ordered,
      ownChosen: question.own?.mode == OwnMode.instead ? false : null,
    ),
  );
}

/// Typing in the own answer's row.
AskState _typeOwn(AskState state, Question question, String own) {
  final mode = question.own?.mode;
  final chosen = own != '';
  if (mode == OwnMode.beside) {
    return _setAnswer(state, question, (answer) => _with(answer, own: own));
  }
  return _setAnswer(
    state,
    question,
    (answer) => _with(
      answer,
      own: own,
      ownChosen: chosen,
      // Typing an answer of one's own is the one choice on a single
      // question, and stands instead of every pick on dimcode's.
      picks: chosen && (mode == OwnMode.instead || !question.multiSelect)
          ? const []
          : null,
    ),
  );
}

final _digit = RegExp(r'^[1-9]$');

/// What a key does to the box. Esc answers `cancel`; Send `accept` with the
/// content, and Skip `decline`.
AskStep askKey(
  Questions questions,
  Map<String, Object?> schema,
  AskState state,
  String input,
  AskKey key,
) {
  final count = questions.questions.length;
  AskStep go(int step) =>
      AskStep(_enter(state, questions, step.clamp(0, count)));

  if (key.escape) return AskStep(state, response: const CancelReply());

  // shift+↑ and shift+↓ scroll the transcript; they are the window's.
  if (key.shift && (key.upArrow || key.downArrow)) return AskStep(state);

  if (key.tab) return go(state.step + (key.shift ? -1 : 1));
  if (key.leftArrow) return go(state.step - 1);
  if (key.rightArrow) return go(state.step + 1);

  if (state.step >= count) {
    final sendable = blockers(questions, schema, state).isEmpty;
    AskStep choose(int row) => row == _send
        ? AskStep(state, response: AcceptReply(contentOf(questions, state)))
        : AskStep(state, response: const DeclineReply());

    if (key.upArrow && sendable) return AskStep(state.copyWith(row: _send));
    if (key.downArrow) {
      return state.row == _skip
          ? AskStep(state, leave: true)
          : AskStep(state.copyWith(row: _skip));
    }
    if (key.enter) return choose(sendable ? state.row : _skip);
    if (input == '1' && sendable) return choose(_send);
    if (input == '2') return choose(_skip);
    return AskStep(state);
  }

  final question = questions.questions[state.step];
  final rows = rowsOf(question);
  final row = state.row < rows.length ? rows[state.row] : null;

  if (key.upArrow) {
    return AskStep(state.copyWith(row: math.max(state.row - 1, 0)));
  }
  if (key.downArrow) {
    return state.row >= rows.length - 1
        ? AskStep(state, leave: true)
        : AskStep(state.copyWith(row: state.row + 1));
  }

  if (row is TextRow) {
    if (key.enter) return go(state.step + 1);
    final text = edited(answerTo(state, question).text, input, key);
    return AskStep(
      text == null
          ? state
          : _setAnswer(state, question, (answer) => _with(answer, text: text)),
    );
  }

  if (row is OwnRow) {
    if (key.enter) return go(state.step + 1);
    final own = edited(answerTo(state, question).own, input, key);
    return AskStep(own == null ? state : _typeOwn(state, question, own));
  }

  final digit = _digit.hasMatch(input) ? int.parse(input) - 1 : null;

  if (digit != null && digit < question.options.length) {
    final picked = _pick(state, question, digit);
    return question.multiSelect
        ? AskStep(picked.copyWith(row: digit))
        : AskStep(_enter(picked, questions, state.step + 1));
  }

  // The own answer's number takes the `❯` there to type, and picks it if
  // something is typed in it already.
  if (digit == question.options.length && ownIsOption(question)) {
    final own = answerTo(state, question).own;
    final at = state.copyWith(row: digit);
    return AskStep(own == '' ? at : _typeOwn(at, question, own));
  }

  if (row is! OptionRow) return AskStep(state);

  if (question.multiSelect) {
    if (input == ' ') return AskStep(_pick(state, question, row.index));
    return key.enter ? go(state.step + 1) : AskStep(state);
  }

  if (key.enter || input == ' ') {
    final picked = _pick(state, question, row.index);
    return key.enter
        ? AskStep(_enter(picked, questions, state.step + 1))
        : AskStep(picked);
  }

  return AskStep(state);
}

/// The wide hint from this inner width, where it fits.
const wideAskHint = 100;

/// The hint line's keys for where the `❯` is.
String askHint(Questions questions, AskState state, int width) {
  String pickHint(String long, String short) =>
      width >= wideAskHint && long.length <= width ? long : short;

  if (state.step >= questions.questions.length) {
    return pickHint(
      'Enter to choose · ←→ or Tab for the questions · Esc to cancel',
      'Enter to choose · ←→ questions · Esc to cancel',
    );
  }

  final question = questions.questions[state.step];
  final rows = rowsOf(question);
  final row = state.row < rows.length ? rows[state.row] : null;

  if (row is TextRow || (row is OwnRow && ownIsOption(question))) {
    return pickHint(
      'Type your answer · Enter for the next · ←→ or Tab for the questions · '
          'Esc to cancel',
      'Type your answer · Enter for the next · ←→ questions · Esc to cancel',
    );
  }

  if (row is OwnRow) {
    return pickHint(
      'Enter for the next · ↑ to the options · ←→ or Tab for the questions · '
          'Esc to cancel',
      'Enter for the next · ↑ options · ←→ questions · Esc to cancel',
    );
  }

  if (question.multiSelect) {
    return pickHint(
      'Space to toggle · Enter for the next · ↑↓ to move · ←→ or Tab for the '
          'questions · Esc to cancel',
      'Space to toggle · Enter for the next · ↑↓ · ←→ questions · Esc to '
          'cancel',
    );
  }

  final digits =
      '1–${math.min(question.options.length + (ownIsOption(question) ? 1 : 0), 9)}';

  return pickHint(
    'Enter to pick · $digits · ↑↓ to move · ←→ or Tab for the questions · '
        'Esc to cancel',
    'Enter to pick · $digits · ↑↓ · ←→ questions · Esc to cancel',
  );
}

/// A question's label on its chip and in the summary.
String headerOf(Questions questions, int index) =>
    (index < questions.questions.length
        ? questions.questions[index].header
        : null) ??
    'Question ${index + 1}';

/// `claude asks you 2 questions`, or `a question` for one.
String askHeading(String agent, Questions questions) =>
    '$agent ${asksYou(questions)}';

/// What the heading says the asker does: `asks you 2 questions`.
String asksYou(Questions questions) {
  final count = questions.questions.length;
  return 'asks you ${count == 1 ? 'a question' : '$count questions'}';
}

/// What is left of the agent's wait, if it has one: `answers itself in
/// 4:32`.
num? expiresIn(Questions questions, num askedAt, num now) {
  final expires = questions.expiresInMs;
  return expires == null ? null : math.max(askedAt + expires - now, 0);
}

/// A bracketed paste into the row the `❯` is on, when it takes text: as
/// typed there, a line break a space; anywhere else it does nothing, so a
/// pasted digit never picks an option.
AskState askPaste(Questions questions, AskState state, String text) {
  if (state.step >= questions.questions.length) return state;
  final question = questions.questions[state.step];
  final rows = rowsOf(question);
  final row = state.row < rows.length ? rows[state.row] : null;
  final pasted = text.replaceAll(_lineBreak, ' ');
  if (pasted == '') return state;

  final answer = answerTo(state, question);
  return switch (row) {
    TextRow() => _setAnswer(
      state,
      question,
      (answer) => _with(answer, text: answer.text + pasted),
    ),
    OwnRow() => _typeOwn(state, question, answer.own + pasted),
    _ => state,
  };
}

/// [ms] as minutes and seconds, rounded up: `4:32`.
String clock(num ms) {
  final seconds = (ms / 1000).ceil();
  return '${seconds ~/ 60}:${'${seconds % 60}'.padLeft(2, '0')}';
}

/// A question's answer as the summary reads it: the options picked, by
/// their titles, the text typed, its own answer after ` · `, `•` for each
/// character of a secret one; none when it has no answer.
String? answerText(Question question, AskState state) {
  if (!answered(question, state)) return null;

  final QuestionAnswer(:picks, :text, :own, :ownChosen) = answerTo(
    state,
    question,
  );
  String hide(String value) =>
      question.secret == true ? '•' * value.runes.length : value;
  final mode = question.own?.mode;
  final ownSent = own.trim() != '' && (mode == OwnMode.beside || ownChosen);
  final picked = mode == OwnMode.instead && ownSent
      ? const <String>[]
      : [for (final value in picks) _titleOf(question, value)];
  final main = [...picked, if (text.trim() != '') hide(text.trim())];
  if (ownSent && mode != OwnMode.beside) main.add(hide(own.trim()));
  final note = ownSent && mode == OwnMode.beside ? hide(own.trim()) : null;

  return [main.join(', '), ?note].where((part) => part != '').join(' · ');
}

String _titleOf(Question question, String value) =>
    question.options
        .where((option) => option.value == value)
        .firstOrNull
        ?.title ??
    value;

/// The lines of a step on screen, and the rows cut off above and below.
typedef AskWindow = ({int top, int end, int above, int below});

/// Which of a step's lines fit [limit], given the row each line belongs to
/// (none for the question's text and blanks): all of them where they fit,
/// else the focused row's whole, a line saying how many rows are cut off on
/// each side that has any.
AskWindow windowOf(List<int?> rowOfLine, int focus, int limit) {
  final count = rowOfLine.length;
  if (count <= limit) return (top: 0, end: count, above: 0, below: 0);

  final first = math.max(rowOfLine.indexOf(focus), 0);
  final last = math.max(rowOfLine.lastIndexOf(focus), first);
  var top = 0;
  var end = limit - 1;

  // Down from the top, keeping a line for what is below, until the focused
  // row is whole; then a line for what is above too.
  if (last >= end) {
    end = math.min(last + 1, count);
    top = math.max(end - (limit - (end < count ? 2 : 1)), 0);
    top = math.min(top, first);

    // Never an option's description without its title above it.
    while (top < first &&
        rowOfLine[top] != null &&
        top > 0 &&
        rowOfLine[top] == rowOfLine[top - 1]) {
      top++;
    }
  }

  // Never another option cut at the bottom: the window ends before it, and
  // it is counted below whole.
  while (end < count &&
      end > top &&
      rowOfLine[end] != null &&
      rowOfLine[end] != focus &&
      rowOfLine[end] == rowOfLine[end - 1]) {
    end--;
  }

  // A focused row taller than the room is cut at its end: the box never
  // takes more than its rows.
  while (end - top + (top > 0 ? 1 : 0) + (end < count ? 1 : 0) > limit &&
      end > top + 1) {
    end--;
  }

  final shown = rowOfLine.sublist(top, end).toSet();
  final above = {
    for (final row in rowOfLine.sublist(0, top))
      if (row != null && !shown.contains(row)) row,
  }.length;
  final below = {
    for (final row in rowOfLine.sublist(end))
      if (row != null && !shown.contains(row)) row,
  }.length;

  return (top: top, end: end, above: above, below: below);
}

final _lastCharacter = RegExp(r'\s*\S?$');

/// At most [most] of an option's description lines, the last of them
/// ending in `…` where more were cut, so its title and the rows around it
/// keep their place in the box.
List<String> capLines(List<String> lines, int most) {
  if (lines.length <= most) return [...lines];
  final kept = lines.sublist(0, math.max(most, 1));
  return [
    ...kept.sublist(0, kept.length - 1),
    '${kept.last.replaceFirst(_lastCharacter, '')}…',
  ];
}

/// `Language, Checks`: what a box not answered asked, by its headers.
String askedHeaders(Questions questions) => [
  for (var index = 0; index < questions.questions.length; index++)
    headerOf(questions, index),
].join(', ');

/// One question's row in an answered box's record.
typedef AnsweredQuestion = ({String label, String value});

/// What an accepted box sent, a row per question, read back from the
/// content under the agent's field ids: the options' titles, the text
/// typed, the own answer (after ` · ` where it went beside a pick),
/// `(hidden)` for a secret, whose values a reopened record does not keep,
/// and `skipped` for a question left without an answer.
List<AnsweredQuestion> answeredQuestions(
  Questions questions,
  Map<String, Object?> content,
) => [
  for (final (index, question) in questions.questions.indexed)
    _answeredQuestion(headerOf(questions, index), question, content),
];

AnsweredQuestion _answeredQuestion(
  String label,
  Question question,
  Map<String, Object?> content,
) {
  if (question.secret == true) return (label: label, value: '(hidden)');
  final sent = content[question.id];
  final own = question.own == null ? null : content[question.own!.field];
  final values = [
    for (final value in sent is List ? sent : [?sent])
      if (_string(value) case final value when value != question.own?.value)
        value,
  ];
  final titles = [for (final value in values) _titleOf(question, value)];
  final ownText = own is String && own != '' ? own : null;
  final beside = question.own?.mode == OwnMode.beside;
  final main = [...titles, if (ownText != null && !beside) ownText];
  final value = [
    main.join(', '),
    if (ownText != null && beside) ownText,
  ].where((part) => part != '').join(' · ');
  return (label: label, value: value == '' ? 'skipped' : value);
}

/// [value] as JavaScript's `String` writes it, for what an agent sent.
String _string(Object? value) => switch (value) {
  null => 'null',
  final double number when number == number.truncateToDouble() =>
    number.toInt().toString(),
  _ => '$value',
};
