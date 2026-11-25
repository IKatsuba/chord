/// The plan box, kept out of the widget, from the original's
/// `ui/dialogs/plan.ts`: the choices each agent's plan takes, the Note row
/// sent with keep planning, what each key does to them, and the hint line.
/// Keys are the framework's chord spellings.
library;

import 'package:chord_tui/chord_tui.dart' show TextLayout, TextSpan, cellWidth;

import '../../session/transcript/types.dart';
import 'questions.dart' show AskKey, edited;

/// What a choice sends.
enum PlanChoiceKind { accepted, kept, left }

/// One choice: its words, and the answer it sends.
typedef PlanChoice = ({String label, PlanChoiceKind answer});

/// cursor's yes and no; grok's, and its way out of plan mode.
List<PlanChoice> planChoices(PlanAgent agent) => agent == PlanAgent.cursor
    ? const [
        (label: 'Yes, accept the plan', answer: PlanChoiceKind.accepted),
        (label: 'No, keep planning', answer: PlanChoiceKind.kept),
      ]
    : const [
        (label: 'Yes, start implementing', answer: PlanChoiceKind.accepted),
        (label: 'No, keep planning', answer: PlanChoiceKind.kept),
        (label: 'No, and leave plan mode', answer: PlanChoiceKind.left),
      ];

/// The box's question, [agent] named as the window names it: whether it
/// has a plan, or wrote none, which grok may ask about all the same.
String planQuestion(String agent, PlanWait wait) {
  final written = [
    wait.overview,
    wait.plan,
  ].any((part) => part != null && part.trim().isNotEmpty);
  return '$agent ${written ? 'has a plan' : 'has written no plan'}. '
      'Do you want to proceed?';
}

/// The box as the person has it: the `❯`'s row, the Note row last.
typedef PlanBoxState = ({int row, String note});

/// A box just opened.
const PlanBoxState openPlanBox = (row: 0, note: '');

/// What a key did: the box as it now is, and the answer if one was given.
typedef PlanStep = ({PlanBoxState state, PlanAnswer? answer});

PlanAnswer _answerOf(PlanChoice choice, String note) {
  final said = note.trim();
  return switch (choice.answer) {
    PlanChoiceKind.kept => PlanKept(said.isEmpty ? null : said),
    PlanChoiceKind.accepted => const PlanAccepted(),
    PlanChoiceKind.left => const PlanLeft(),
  };
}

/// [key] in the box: up and down or j and k move, the Note row past the
/// last choice; a digit picks that choice; enter picks the one under the
/// `❯`, or on the Note row keeps planning with the note; esc keeps planning
/// with none. On the Note row, digits and j and k type, which the Note's
/// own input takes.
PlanStep planKey(PlanAgent agent, PlanBoxState state, String key) {
  final choices = planChoices(agent);
  final noteRow = choices.length;
  final kept = choices.firstWhere(
    (choice) => choice.answer == PlanChoiceKind.kept,
  );
  if (key == 'escape') return (state: state, answer: const PlanKept());
  if (state.row == noteRow) {
    if (key == 'enter') {
      return (state: state, answer: _answerOf(kept, state.note));
    }
    if (key == 'up') {
      return (state: (row: noteRow - 1, note: state.note), answer: null);
    }
    return (state: state, answer: null);
  }
  if (key == 'enter') {
    return (state: state, answer: _answerOf(choices[state.row], state.note));
  }
  if (key == 'up' || key == 'k') {
    return (
      state: (row: state.row > 0 ? state.row - 1 : 0, note: state.note),
      answer: null,
    );
  }
  if (key == 'down' || key == 'j') {
    return (
      state: (
        row: state.row < noteRow ? state.row + 1 : noteRow,
        note: state.note,
      ),
      answer: null,
    );
  }
  final digit = int.tryParse(key);
  if (key.length == 1 &&
      digit != null &&
      digit >= 1 &&
      digit <= choices.length) {
    return (state: state, answer: _answerOf(choices[digit - 1], state.note));
  }
  return (state: state, answer: null);
}

/// A press on the Note row as its text takes it, from the original's
/// `planKey`: typing appends; backspace, shift+backspace and alt+backspace
/// take the last character, ctrl+w the last word and ctrl+u the whole note;
/// nothing moves a cursor, which is always at the end. Null for a press the
/// note does not take. A cmd press types nothing, though the original's
/// types its letter there.
PlanBoxState? planNoteKey(PlanBoxState state, String input, AskKey key) {
  if (key.superKey && !key.backspace) return null;
  final note = edited(state.note, input, key);
  return note == null ? null : (row: state.row, note: note);
}

/// The Note's text in lines of at most [width] cells, wrapped at its spaces
/// with none left at a break, never cut; the spaces typed last stay on the
/// last line, and a cell is left there for the cursor, a full line handing
/// it to a line of its own. One empty line for no note.
List<String> noteLines(String note, int width) {
  if (note.isEmpty) return const [''];
  final room = width < 1 ? 1 : width;
  final lines = [
    for (final line in TextLayout.wrapAnsi(
      TextSpan(note),
      room,
      hard: true,
      trim: true,
    ).lines)
      line.map((glyph) => glyph.text).join(),
  ];
  final trailing = RegExp(r'\s*$').firstMatch(note)![0]!;
  final last = '${lines.isEmpty ? '' : lines.removeLast()}$trailing';
  return cellWidth(last) < room
      ? [...lines, last]
      : [...lines, last.trimRight(), ''];
}

/// Text pasted onto the Note row, its whitespace one space at a time.
String pastedNote(String note, String text) =>
    '$note${text.replaceAll(RegExp(r'\s+'), ' ')}';

/// Text pasted into the box: into the note on the Note row, as one line;
/// elsewhere it is dropped.
PlanBoxState planPaste(PlanAgent agent, PlanBoxState state, String text) =>
    state.row == planChoices(agent).length
    ? (row: state.row, note: pastedNote(state.note, text))
    : state;

/// The hint under the box, on a choice or on the Note row.
String planHint(PlanAgent agent, PlanBoxState state) {
  final count = planChoices(agent).length;
  return state.row == count
      ? 'Enter to keep planning with this note · ↑ to the options · Esc to '
            'keep planning'
      : 'Enter to pick · 1–$count · ↑↓ to move · Esc to keep planning';
}
