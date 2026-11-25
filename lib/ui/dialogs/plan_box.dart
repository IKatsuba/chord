/// The box an agent's plan is put to the person in, from the original's
/// `ui/dialogs/PlanBox.tsx`: above the prompt in the permission box's place
/// and look, `Approve Plan`, the agent's choices numbered, the Note row sent
/// with keep planning, and the hint. The plan itself is in the transcript,
/// under its call. Its keys are bound through Actions while it is shown.
library;

import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';

import '../../session/transcript/types.dart';
import '../app/context.dart' show hintKeyOf;
import 'permission.dart'
    show countRoom, hiddenRows, requestCount, requestRule, requestView;
import 'plan.dart';
import 'plan_scroll.dart';
import 'questions.dart' show askKeyOf;

/// The plan box for [wait], asked by [agent] as the window names it, in a
/// window [windowRows] high with [maxRows] left for it.
class PlanBox extends StatefulWidget {
  const PlanBox({
    super.key,
    required this.wait,
    required this.agent,
    required this.onAnswer,
    required this.windowRows,
    required this.maxRows,
    this.focusNode,
    this.onShape,
    this.scroll,
    this.onOverflow,
    this.away = false,
    this.onLeave,
  });

  /// The list of agents has the keys: no `❯` and no hint is drawn, the
  /// hint's line kept blank so the box holds still.
  final bool away;

  /// ↓ from the Note's last row, where there is a list of agents to go to.
  final void Function()? onLeave;

  final PlanWait wait;
  final String agent;
  final void Function(PlanAnswer answer) onAnswer;

  /// The window's rows: the Note takes up to half of them.
  final int windowRows;

  /// The rows the box may take, the rest of the window's furniture laid.
  final int maxRows;

  /// What holds the box's keys while it is on a choice.
  final FocusNode? focusNode;

  /// Told, once laid out, where the box is and how many lines its Note
  /// wraps to, whenever either changes: what the window needs for
  /// [planNatural] before its next layout.
  final void Function(PlanShape shape)? onShape;

  /// Where the window pages the Note from, while it overflows; the box
  /// keeps its own when none is given.
  final PlanNoteScroll? scroll;

  /// Told, once laid out, whether the page keys are the Note's: the `❯`
  /// on it, and it taller than its room.
  final void Function(bool overflows)? onOverflow;

  @override
  State<PlanBox> createState() => _PlanBoxState();
}

/// What the window reads of a plan box to know its height: where it is,
/// and the lines its Note wraps to.
typedef PlanShape = ({PlanBoxState state, int noteLines});

/// A plan box as it opens: on its first choice, its Note empty, one line.
const PlanShape openPlanShape = (state: openPlanBox, noteLines: 1);

/// The rows of a plan box [boxWidth] wide that never give way, but the
/// Note's: the border, title, question, choices, the gaps and the hint,
/// as they wrap.
int planPinned(PlanWait wait, String agent, PlanBoxState state, int boxWidth) {
  final inside = math.max(boxWidth - 4, 1);
  int rowsOf(String text) =>
      TextLayout.compute(TextSpan(text), maxWidth: inside).height;
  return 2 +
      1 +
      1 +
      rowsOf(planQuestion(agent, wait)) +
      planChoices(wait.agent).length +
      1 +
      1 +
      rowsOf(planHint(wait.agent, state));
}

/// A plan box's height before layout, [boxWidth] wide in a window
/// [windowRows] high, as [shape] says it is: [fixed], with one line of the
/// Note, and [natural], with the Note's lines up to half the window.
({int fixed, int natural}) planNatural(
  PlanWait wait,
  String agent,
  int boxWidth, {
  required int windowRows,
  PlanShape shape = openPlanShape,
}) {
  final pinned = planPinned(wait, agent, shape.state, boxWidth);
  return (
    fixed: pinned + 1,
    natural:
        pinned +
        math.max(math.min(windowRows ~/ 2, math.max(shape.noteLines, 1)), 1),
  );
}

class _PlanBoxState extends State<PlanBox> {
  PlanBoxState _state = openPlanBox;
  var _answered = false;

  int get _noteRow => planChoices(widget.wait.agent).length;

  PlanNoteScroll? _ownScroll;

  PlanNoteScroll get _scroll =>
      widget.scroll ?? (_ownScroll ??= PlanNoteScroll());

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_boxFocused);
    _scroll.addListener(_scrolled);
  }

  void _scrolled() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(PlanBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_boxFocused);
      widget.focusNode?.addListener(_boxFocused);
    }
    if (oldWidget.scroll != widget.scroll) {
      (oldWidget.scroll ?? _ownScroll)?.removeListener(_scrolled);
      _scroll.addListener(_scrolled);
    }
  }

  /// The Note's cursor cell is drawn only while the box has the keys.
  void _boxFocused() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_boxFocused);
    _scroll.removeListener(_scrolled);
    _ownScroll?.dispose();
    super.dispose();
  }

  PlanShape _reported = openPlanShape;

  /// Tells the window a new shape once this frame is laid out.
  void _reportShape(int noteLines) {
    final shape = (state: _state, noteLines: noteLines);
    if (shape == _reported) return;
    _reported = shape;
    final report = widget.onShape;
    if (report == null) return;
    context.owner.afterLayout(() {
      if (mounted) report(shape);
    });
  }

  bool? _overflowReported;

  /// Tells the window, once this frame is laid out, whether the page keys
  /// are the Note's.
  void _reportOverflow(bool overflows) {
    if (_overflowReported == overflows) return;
    _overflowReported = overflows;
    final report = widget.onOverflow;
    if (report == null) return;
    context.owner.afterLayout(() {
      if (mounted) report(overflows);
    });
  }

  /// A new note brings the view back to the cursor.
  void _set(PlanBoxState next) {
    if (next.note != _state.note) _scroll.follow();
    setState(() => _state = next);
  }

  void _press(String key) {
    if (_answered) return;
    final step = planKey(widget.wait.agent, _state, key);
    _set(step.state);
    if (step.answer case final answer?) {
      _answered = true;
      widget.onAnswer(answer);
    }
  }

  /// On the Note row the note takes what it types and deletes, as the
  /// original's row edited at its end.
  bool _onKey(KeyEvent event) {
    if (_answered || _state.row != _noteRow) return false;
    final (input, key) = askKeyOf(event);
    final next = planNoteKey(_state, input, key);
    if (next == null) return false;
    _set(next);
    return true;
  }

  /// A paste goes into the note on the Note row; elsewhere it is dropped.
  bool _onPaste(String text) {
    if (!_answered) {
      _set(planPaste(widget.wait.agent, _state, text));
    }
    return true;
  }

  List<Binding> _bindings() {
    final choices = planChoices(widget.wait.agent);
    final onNote = _state.row == _noteRow;
    return [
      Binding('esc', 'Keep planning', () => _press('escape')),
      Binding(
        'enter',
        onNote ? 'Keep planning with this note' : 'Pick the choice',
        () => _press('enter'),
      ),
      Binding(
        'up',
        onNote ? 'Back to the options' : 'Previous choice',
        () => _press('up'),
      ),
      // On the Note row, digits and j and k are typed, and ↓ goes into the
      // agents list, where there is one.
      if (onNote) ...[
        if (widget.onLeave case final leave?)
          Binding('down', 'To the agents list', () {
            if (!_answered) leave();
          }),
      ] else ...[
        Binding('down', 'Next choice or the note', () => _press('down')),
        Binding('k', 'Previous choice', () => _press('k')),
        Binding('j', 'Next choice or the note', () => _press('j')),
        for (final (index, choice) in choices.indexed)
          Binding('${index + 1}', choice.label, () => _press('${index + 1}')),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      // The framework's focus role is the original permission colour.
      final permission = theme.focus;
      final choices = planChoices(widget.wait.agent);
      final onNote = _state.row == _noteRow;
      // The box has the keys: the Note's cursor cell is drawn.
      final active =
          !widget.away && (widget.focusNode?.hasFocus ?? true) && !_answered;
      // The number is the keep-planning choice's, 2 for either agent.
      final placeholder =
          'Tell ${widget.agent} what to change, sent with 2 (optional)';
      final question = planQuestion(widget.agent, widget.wait);
      final hint = planHint(widget.wait.agent, _state);
      // What never gives way; the Note takes up to half the window of the
      // rest, at least one row.
      final pinned = planPinned(
        widget.wait,
        widget.agent,
        _state,
        constraints.maxWidth,
      );
      final room = math.max(
        math.min(widget.windowRows ~/ 2, widget.maxRows - pinned),
        1,
      );
      // The `❯`, `Note  ` and the box's border and padding take twelve.
      final noteWidth = math.max(constraints.maxWidth - 12, 1);
      final whole = noteLines(_state.note, noteWidth);
      _reportShape(whole.length);
      // A room of one row has none for a rule: what is hidden is said
      // beside the row, which wraps to the cells the count leaves.
      final counted = room <= 1 && whole.length > 1;
      final lines = counted
          ? noteLines(_state.note, noteWidth - countRoom(whole.length) - 1)
          : whole;
      final total = lines.length;
      // The view follows the cursor, the note's end, until the page keys
      // move it.
      _scroll.configure(total, room);
      _reportOverflow(onNote && total > room);
      final view = requestView(total, room, _scroll.at);
      final hidden = hiddenRows(total, view.top, view.shown);
      Widget marker(int row) => Text(
        row == _state.row && !widget.away ? '❯ ' : '  ',
        style: permission,
      );
      Widget rule(String way, int count) => Text(
        requestRule(
          way,
          count,
          onNote
              ? hintKeyOf(
                  context,
                  way == '↑' ? 'scroll:pageUp' : 'scroll:pageDown',
                )
              : null,
          noteWidth,
        ),
        style: theme.dim,
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.clip,
      );
      const cursor = TextSpan(' ', style: Style.inverse);
      Widget row(TextSpan span) => Text.rich(
        span,
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.clip,
      );
      final noteRows = <Widget>[
        if (view.above) rule('↑', hidden.above),
        if (_state.note.isEmpty)
          row(
            TextSpan(
              '',
              children: [
                if (onNote && active) cursor,
                TextSpan(
                  // While away the cursor's cell is blank, so the text
                  // keeps its column.
                  '${onNote && !active && widget.away ? ' ' : ''}'
                  '${onNote && (active || widget.away) ? ' ' : ''}'
                  '${truncate(placeholder, math.max(noteWidth - 1, 1))}',
                  style: theme.dim,
                ),
              ],
            ),
          )
        else
          for (var at = view.top; at < view.top + view.shown; at++)
            Row(
              children: [
                Expanded(
                  child: row(
                    TextSpan(
                      lines[at],
                      children: [
                        if (onNote && active && at == total - 1) cursor,
                      ],
                    ),
                  ),
                ),
                if (counted)
                  Text(
                    requestCount(hidden),
                    style: theme.dim,
                    softWrap: false,
                    maxLines: 1,
                  ),
              ],
            ),
        if (view.below) rule('↓', hidden.below),
      ];
      return Actions(
        bindings: _bindings(),
        child: Focus(
          focusNode: widget.focusNode,
          onKey: _onKey,
          onPaste: _onPaste,
          child: SelectionContainer.disabled(
            child: Box(
              border: Border.rounded.withStyle(permission),
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Approve Plan', style: permission.merge(Style.bold)),
                  const SizedBox(height: 1),
                  Text(question),
                  for (final (index, choice) in choices.indexed)
                    Row(
                      children: [
                        marker(index),
                        Expanded(
                          child: Text(
                            '${index + 1}. ${choice.label}',
                            style: index == _state.row ? permission : null,
                            softWrap: false,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 1),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      marker(_noteRow),
                      Text(
                        'Note  ',
                        style: onNote ? permission.merge(Style.bold) : null,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: noteRows,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(widget.away ? ' ' : hint, style: theme.dim),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
