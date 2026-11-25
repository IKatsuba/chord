/// An agent's questions in the prompt box's place, one step at a time,
/// then Submit, from the original's `ui/dialogs/Questions.tsx`. What each
/// key does is `askKey`'s; this only draws and dispatches. Its keys are
/// bound through Actions while it is shown; typing on a row that takes
/// text, and the Note's editor, take the keys before them.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';

import '../../session/elicitations.dart' hide answerOf;
import '../../session/questions.dart';
import '../../session/transcript/types.dart';
import '../transcript/agents/subagents.dart' show AskerPiece;
import 'asker.dart';
import 'fold.dart';
import 'form_box.dart' show formRowLimit;
import 'questions.dart';

/// The box's rows besides a step's: the border, the heading, the steps,
/// the hint and the blank rows between them.
const questionBoxChrome = 8;

List<String> _wrapped(String text, int columns) => [
  for (final line in TextLayout.wrapAnsi(
    TextSpan(text),
    math.max(columns, 1),
    hard: true,
    trim: false,
  ).lines)
    line.map((glyph) => glyph.text).join(),
];

/// The rows the Note beside a question's choices takes, [width] wide, as
/// [answer]'s own text wraps, at most what [limit] leaves it.
int _editorRows(QuestionAnswer answer, int width, int limit) => math.min(
  TextLayout.wrapAnsi(
    TextSpan('${answer.own} '),
    math.max(width - 8, 1),
    hard: true,
    trim: false,
  ).height,
  math.max(math.max(limit, 6) - 3, 1),
);

/// The rows one question's step takes, [width] wide in [limit] rows, as
/// [state] has it: its text, its options with their descriptions, its own
/// answer, windowed round the `❯` with a row for what is out of sight
/// above and below.
int questionStepRows(Question question, AskState state, int width, int limit) {
  final answer = answerTo(state, question);
  final indent = question.multiSelect ? 9 : 5;
  // Each line's row, by the `❯` it goes with, and its height.
  final lines = <({int? row, int height})>[
    for (final _ in _wrapped(
      '${question.text}${question.multiSelect ? ' (pick any)' : ''}',
      width,
    ))
      (row: null, height: 1),
    (row: null, height: 1),
  ];
  var editorRows = 1;
  for (final (index, row) in rowsOf(question).indexed) {
    switch (row) {
      case OptionRow(index: final option):
        lines.add((row: index, height: 1));
        if (question.options[option].description case final description?) {
          for (final _ in capLines(
            _wrapped(description, math.max(width - indent, 10)),
            math.max(limit, 6) - 3,
          )) {
            lines.add((row: index, height: 1));
          }
        }
      case TextRow():
        lines.add((row: index, height: 1));
      case OwnRow():
        if (ownIsOption(question)) {
          lines.add((row: index, height: 1));
          break;
        }
        lines.add((row: null, height: 1));
        if (editableNote(question)) {
          editorRows = _editorRows(answer, width, limit);
          lines.add((row: index, height: editorRows));
        } else {
          lines.add((row: index, height: 1));
        }
    }
  }
  final window = windowOf(
    [for (final line in lines) line.row],
    state.row,
    math.max(limit, 6) - (editorRows - 1),
  );
  return (window.top > 0 ? 1 : 0) +
      lines
          .sublist(window.top, window.end)
          .fold<int>(0, (sum, line) => sum + line.height) +
      (window.end < lines.length ? 1 : 0);
}

/// A question box's height before layout, [boxWidth] wide in a window
/// [windowRows] high, on the step [state] is at: whole unless [held], when
/// its lines fold to one; held, its hint is drawn only with a [hint] key.
({int fixed, int natural}) questionNatural(
  Questions questions,
  AskState state,
  int boxWidth, {
  required int windowRows,
  bool held = false,
  bool hint = true,
}) {
  final inner = math.max(boxWidth - 4, 10);
  final limit = formRowLimit(windowRows) - questionBoxChrome;
  final shown = held ? state.copyWith(row: -1) : state;
  final body = state.step < questions.questions.length
      ? questionStepRows(questions.questions[state.step], shown, inner, limit)
      : questions.questions.length + 3;
  return heldNatural(4 + body, chrome: 4 + (!held || hint ? 1 : 0), held: held);
}

/// Under this much of the agent's wait, the countdown turns `warning`.
const _warnMs = 30000;

/// The Note's placeholder, in the grey the original's textarea draws it in,
/// whatever the theme.
const _notePlaceholder = Style(fg: RgbColor(0x66, 0x66, 0x66));

/// The question box for [wait]'s [questions], asked by [agent], answered
/// through [onAnswer]. [filled] is the box as it was left, kept by the
/// window through [onFill]. Held, asked between turns with the keys
/// elsewhere, it draws no `❯` and no hint but the one that takes it.
class QuestionBox extends StatefulWidget {
  const QuestionBox({
    super.key,
    required this.wait,
    required this.questions,
    required this.agent,
    this.asker = const [],
    this.picked,
    required this.windowRows,
    required this.onAnswer,
    this.filled,
    this.onFill,
    this.focusNode,
    this.between = false,
    this.held = false,
    this.attendKey,
    this.maxRows,
    this.now = _clockNow,
    this.away = false,
    this.onLeave,
  });

  /// The list of agents has the keys: no row reads as where they are, and
  /// the hint's line is blank, so the box holds still.
  final bool away;

  /// ↓ from the last row of a step, or from Skip, where there is a list of
  /// agents to go to.
  final void Function()? onLeave;

  final FormWait wait;
  final Questions questions;
  final String agent;

  /// Who asks, when a subagent or task does: its way down from the
  /// session, as the permission box's row names it, without `asks`; none
  /// when the session's own agent does.
  final List<AskerPiece> asker;

  /// The child in front, whose session asks, named when no subagent of
  /// its does.
  final PickedAsker? picked;
  final int windowRows;
  final void Function(ElicitationReply reply) onAnswer;
  final AskState? filled;
  final void Function(AskState state)? onFill;

  /// What holds the box's keys, but on the Note.
  final FocusNode? focusNode;

  /// Asked with no turn running: the heading says so.
  final bool between;

  /// Asked between turns and not taken into yet: no keys.
  final bool held;

  /// The key that takes the keys into it while [held].
  final String? attendKey;

  /// The rows the box may take, the rest of the window's furniture laid:
  /// held, its body folds into them, keeping the hint in sight.
  final int? maxRows;

  /// The time, in milliseconds, the countdown runs on.
  final num Function() now;

  @override
  State<QuestionBox> createState() => _QuestionBoxState();
}

num _clockNow() => DateTime.now().millisecondsSinceEpoch;

class _QuestionBoxState extends State<QuestionBox> {
  late AskState _state = widget.filled ?? openAsk(widget.questions);
  final _note = TextAreaController();
  // A node per question's Note: the editor of the step left is let go
  // after the next one's is built, and would let go of a shared node.
  final _noteFocuses = <String, FocusNode>{};

  FocusNode get _noteFocus => _noteFocuses[_question?.id ?? ''] ??= FocusNode(
    debugLabel: 'question note',
  );
  // The Note's question, whose text the editor holds.
  String? _noteOf;
  late num _time = widget.now();
  // A request drawn with no time of its own counts from when it was first
  // drawn.
  late final num _shownAt = _time;
  Timer? _ticker;

  Questions get _questions => widget.questions;

  Question? get _question => _state.step < _questions.questions.length
      ? _questions.questions[_state.step]
      : null;

  StepRow? get _row {
    final question = _question;
    if (question == null) return null;
    final rows = rowsOf(question);
    return _state.row >= 0 && _state.row < rows.length
        ? rows[_state.row]
        : null;
  }

  /// The ❯ is on a non-secret note beside a pick: its editor has the keys.
  bool get _onNote =>
      _question != null && editableNote(_question!) && _row is OwnRow;

  @override
  void initState() {
    super.initState();
    _note.addListener(_noteChanged);
    _syncNote();
    widget.focusNode?.addListener(_boxFocused);
    if (_questions.expiresInMs != null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _time = widget.now());
      });
    }
  }

  @override
  void didUpdateWidget(QuestionBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_boxFocused);
      widget.focusNode?.addListener(_boxFocused);
    }
  }

  /// The box given the keys, as the window does when it shows it again,
  /// passes them on to the Note where the `❯` was left on it.
  void _boxFocused() {
    if (!(widget.focusNode?.hasPrimaryFocus ?? false) ||
        !_onNote ||
        widget.held) {
      return;
    }
    context.owner.afterLayout(() {
      if (mounted && _onNote && !widget.held) _noteFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_boxFocused);
    _ticker?.cancel();
    _note.removeListener(_noteChanged);
    _note.dispose();
    for (final node in _noteFocuses.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// The editor holds the Note of the question on screen, its cursor where
  /// it was left.
  void _syncNote() {
    final question = _question;
    if (question == null || !editableNote(question)) return;
    if (_noteOf == question.id) return;
    // Taken before the editor is set: setting it tells _noteChanged, which
    // must not write its cursor at the end over the one left.
    final text = answerTo(_state, question).own;
    final cursor = _state.noteCursors[question.id];
    _noteOf = null;
    _note.text = text;
    _note.cursor = cursor ?? _note.length;
    _noteOf = question.id;
  }

  final _lineBreak = RegExp(r'\r\n|\r|\n');

  void _noteChanged() {
    final question = _question;
    if (question == null || _noteOf != question.id) return;
    // The Note keeps to one line: a pasted line break is a space.
    if (_lineBreak.hasMatch(_note.text)) {
      final cursor = _note.cursor;
      _note.text = _note.text.replaceAll(_lineBreak, ' ');
      _note.cursor = cursor;
      return;
    }
    final answer = answerTo(_state, question);
    if (answer.own == _note.text &&
        _state.noteCursors[question.id] == _note.cursor) {
      return;
    }
    _set(changedNote(_state, question, _note.text, _note.cursor));
  }

  void _set(AskState next) {
    final wasOnNote = _onNote;
    setState(() => _state = next);
    _syncNote();
    widget.onFill?.call(next);
    if (wasOnNote != _onNote) {
      context.owner.afterLayout(() {
        if (!mounted || widget.held) return;
        (_onNote ? _noteFocus : widget.focusNode)?.requestFocus();
      });
    }
  }

  var _answered = false;

  void _press(String input, AskKey key) {
    if (_answered) return;
    final step = askKey(_questions, widget.wait.schema, _state, input, key);
    _set(step.state);
    if (step.response case final response?) {
      _answered = true;
      widget.onAnswer(response);
    }
    if (step.leave) widget.onLeave?.call();
  }

  /// Typing on a row that takes text goes before the bindings, so a digit
  /// or a space is typed there rather than picking.
  bool _onKey(KeyEvent event) {
    final row = _row;
    final typing = row is TextRow || (row is OwnRow && !_onNote);
    if (!typing) return false;
    final (input, key) = askKeyOf(event);
    final text = edited('', input, key);
    final deletes =
        key.backspace || (key.ctrl && (input == 'u' || input == 'w'));
    if (text == null && !deletes) return false;
    _press(input, key);
    return true;
  }

  bool _onPaste(String text) {
    if (_answered) return true;
    _set(askPaste(_questions, _state, text));
    return true;
  }

  /// The Note's editor takes its edits; the box the rest, as the original
  /// does.
  bool _onNoteKey(KeyEvent event) {
    final (input, key) = askKeyOf(event);
    if (noteEdits(input, key)) return false;
    if (key.ctrl && input == 'u') {
      _note.clear();
      return true;
    }
    _press(input, key);
    return true;
  }

  List<Binding> _bindings() {
    void press(AskKey key, [String input = '']) => _press(input, key);
    final question = _question;
    final row = _row;
    final onSubmit = question == null;
    return [
      Binding(
        'esc',
        'Cancel the questions',
        () => press(const AskKey(escape: true)),
      ),
      Binding(
        'enter',
        onSubmit
            ? 'Send or skip'
            : row is OptionRow && !question.multiSelect
            ? 'Pick the option'
            : 'Next question',
        () => press(const AskKey(enter: true)),
      ),
      Binding('tab', 'Next question', () => press(const AskKey(tab: true))),
      Binding(
        'shift+tab',
        'Previous question',
        () => press(const AskKey(tab: true, shift: true)),
      ),
      Binding(
        'left',
        'Previous question',
        () => press(const AskKey(leftArrow: true)),
      ),
      Binding(
        'right',
        'Next question',
        () => press(const AskKey(rightArrow: true)),
      ),
      Binding('up', 'Previous row', () => press(const AskKey(upArrow: true))),
      Binding('down', 'Next row', () => press(const AskKey(downArrow: true))),
      if (question != null && row is OptionRow)
        Binding(
          'space',
          question.multiSelect ? 'Toggle the option' : 'Pick the option',
          () => press(const AskKey(), ' '),
        ),
      if (question != null)
        for (
          var index = 0;
          index <
              math.min(
                question.options.length + (ownIsOption(question) ? 1 : 0),
                9,
              );
          index++
        )
          Binding(
            '${index + 1}',
            index < question.options.length
                ? 'Pick ${question.options[index].title}'
                : 'Your own answer',
            () => press(const AskKey(), '${index + 1}'),
          )
      else ...[
        Binding('1', 'Send the answers', () => press(const AskKey(), '1')),
        Binding('2', 'Skip these questions', () => press(const AskKey(), '2')),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final permission = theme.focus;
      final inner = math.max(constraints.maxWidth - 4, 10);
      final left = expiresIn(_questions, widget.wait.at ?? _shownAt, _time);
      final problems = blockers(_questions, widget.wait.schema, _state);
      // Held, no row reads as where the keys are, as they are not here.
      final shown = widget.held || widget.away
          ? _state.copyWith(row: -1)
          : _state;
      final question = _question;
      final limit = formRowLimit(widget.windowRows) - questionBoxChrome;
      final body = question == null
          ? _submitStep(theme, shown, problems)
          : _questionStep(theme, question, shown, inner, limit);
      final heading = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text.rich(
              askerHeading(
                asker: widget.asker,
                picked: widget.picked,
                agent: widget.agent,
                says: asksYou(_questions),
                between: widget.between,
                style: permission.merge(Style.bold),
                theme: theme,
              ),
            ),
          ),
          if (left != null)
            Text(
              'answers itself in ${clock(left)}',
              style: left < _warnMs ? theme.warning : theme.dim,
              softWrap: false,
              maxLines: 1,
            ),
        ],
      );
      final steps = _steps(theme, problems);
      final lines = 1 + 1 + 1 + 1 + body.rows;
      // The window counts this box's rows with the same arithmetic.
      assert(
        questionNatural(
              _questions,
              _state,
              constraints.maxWidth,
              windowRows: widget.windowRows,
              held: widget.held,
              hint: widget.attendKey != null,
            ).natural ==
            lines + (widget.held && widget.attendKey == null ? 4 : 5),
      );
      // Its margin, borders and the hint with the row above it.
      final room = widget.maxRows == null
          ? null
          : math.max(widget.maxRows! - 5, 0);
      return Actions(
        bindings: widget.held || widget.away ? const [] : _bindings(),
        child: Focus(
          focusNode: widget.focusNode,
          onKey: widget.held || widget.away ? null : _onKey,
          onPaste: widget.held || widget.away ? null : _onPaste,
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Box(
              border: Border.rounded.withStyle(permission),
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: SelectionContainer.disabled(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HeldFold(
                      held: widget.held,
                      lines: lines,
                      room: room,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          heading,
                          const SizedBox(height: 1),
                          steps,
                          const SizedBox(height: 1),
                          body.widget,
                        ],
                      ),
                    ),
                    const SizedBox(height: 1),
                    if (widget.held)
                      if (widget.attendKey case final key?)
                        Text('$key to answer', style: theme.dim)
                      else
                        const SizedBox(height: 0)
                    else
                      Text(
                        widget.away ? ' ' : askHint(_questions, _state, inner),
                        style: theme.dim,
                        softWrap: false,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  /// `← ◉ Language   ○ Verbosity   ○ Submit →`: a question answered as
  /// the agent takes it `✔`, one it would refuse still `○`.
  Widget _steps(ThemeData theme, Map<String, String> problems) {
    final permission = theme.focus;
    final onSubmit = _state.step == _questions.questions.length;
    return Text.rich(
      TextSpan(
        '← ',
        children: [
          for (final (index, question) in _questions.questions.indexed) ...[
            if (question.required) TextSpan('* ', style: theme.warning),
            if (index == _state.step)
              TextSpan('◉', style: permission)
            else if (answered(question, _state) &&
                !problems.containsKey(question.id))
              TextSpan('✔', style: theme.success)
            else
              const TextSpan('○'),
            TextSpan(
              ' ${headerOf(_questions, index)}',
              style: index == _state.step ? Style.bold : null,
            ),
            const TextSpan('   '),
          ],
          onSubmit ? TextSpan('◉', style: permission) : const TextSpan('○'),
          TextSpan(' Submit', style: onSubmit ? Style.bold : null),
          const TextSpan(' →'),
        ],
      ),
      softWrap: false,
      maxLines: 1,
      overflow: TextOverflow.clip,
    );
  }

  /// A text row's value: the cursor at its end while the `❯` is on it.
  List<TextSpan> _typed(
    ThemeData theme,
    String text, {
    String? placeholder,
    required bool focused,
    bool secret = false,
  }) {
    final shown = secret ? '•' * text.runes.length : text;
    return [
      if (shown != '') TextSpan(shown),
      if (focused) const TextSpan(' ', style: Style.inverse),
      if (shown == '' && placeholder != null)
        TextSpan('${focused ? ' ' : ''}$placeholder', style: theme.dim),
    ];
  }

  static Widget _line(TextSpan span, {Style? style}) => Text.rich(
    span,
    style: style,
    softWrap: false,
    maxLines: 1,
    overflow: TextOverflow.clip,
  );

  /// One question: its text, its options, its own answer, windowed to
  /// [limit] rows.
  ({Widget widget, int rows}) _questionStep(
    ThemeData theme,
    Question question,
    AskState state,
    int width,
    int limit,
  ) {
    final permission = theme.focus;
    final answer = answerTo(state, question);
    final rows = rowsOf(question);
    final lines = <({Widget widget, int? row, int height})>[];
    var editorRows = 1;
    Widget marker(int index) => SizedBox(
      width: 2,
      child: Text(index == state.row ? '❯' : ' ', style: permission),
    );
    String box(bool ticked) =>
        question.multiSelect ? '[${ticked ? '✔' : ' '}] ' : '';
    final indent = question.multiSelect ? 9 : 5;
    const wrap = _wrapped;
    void add(Widget widget, [int? row, int height = 1]) =>
        lines.add((widget: widget, row: row, height: height));

    for (final line in wrap(
      '${question.text}${question.multiSelect ? ' (pick any)' : ''}',
      width,
    )) {
      add(Text.ansi(line, style: Style.bold, softWrap: false, maxLines: 1));
    }
    add(const SizedBox(height: 1));

    for (final (index, row) in rows.indexed) {
      final focused = index == state.row;
      final tone = focused ? permission : null;
      switch (row) {
        case OptionRow(index: final option):
          final choice = question.options[option];
          final picked = answer.picks.contains(choice.value);
          add(
            Row(
              children: [
                marker(index),
                Expanded(
                  child: _line(
                    TextSpan(
                      '${box(picked)}${option + 1}. ',
                      children: [
                        TextSpan(choice.title),
                        if (!question.multiSelect && picked)
                          const TextSpan(' ✔'),
                      ],
                    ),
                    style: tone,
                  ),
                ),
              ],
            ),
            index,
          );
          // An option's title and the two rows that count what is cut off
          // always fit beside its description.
          if (choice.description case final description?) {
            for (final part in capLines(
              wrap(description, math.max(width - indent, 10)),
              math.max(limit, 6) - 3,
            )) {
              add(
                Padding(
                  padding: EdgeInsets.only(left: indent),
                  child: _line(TextSpan(part), style: theme.dim),
                ),
                index,
              );
            }
          }
        case TextRow():
          add(
            Row(
              children: [
                marker(index),
                Expanded(
                  child: _line(
                    TextSpan(
                      '',
                      children: _typed(
                        theme,
                        answer.text,
                        focused: focused,
                        secret: question.secret == true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            index,
          );
        case OwnRow():
          final own = question.own!;
          if (ownIsOption(question)) {
            final label = own.mode == OwnMode.instead
                ? 'Your own answer'
                : 'Other answer';
            add(
              Row(
                children: [
                  marker(index),
                  Expanded(
                    child: _line(
                      TextSpan(
                        '${box(answer.ownChosen)}'
                        '${question.options.length + 1}. $label: ',
                        children: _typed(
                          theme,
                          answer.own,
                          focused: focused,
                          secret: question.secret == true,
                        ),
                      ),
                      style: tone,
                    ),
                  ),
                ],
              ),
              index,
            );
            break;
          }
          // The `❯`, `Note  ` and the cursor's cell.
          final placeholder = truncate(
            own.placeholder ?? 'your own answer (optional)',
            math.max(width - 9, 1),
          );
          add(const SizedBox(height: 1));
          final noteLabel = Text(
            'Note  ',
            style: focused ? (tone ?? Style.plain).merge(Style.bold) : null,
          );
          if (editableNote(question)) {
            editorRows = _editorRows(answer, width, limit);
            add(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  marker(index),
                  noteLabel,
                  Expanded(
                    child: TextArea(
                      controller: _note,
                      focusNode: _noteFocus,
                      maxHeight: editorRows,
                      placeholder: placeholder,
                      placeholderStyle: _notePlaceholder,
                      placeholderGap: false,
                      onKey: _onNoteKey,
                    ),
                  ),
                ],
              ),
              index,
              editorRows,
            );
          } else {
            add(
              Row(
                children: [
                  marker(index),
                  noteLabel,
                  Expanded(
                    child: _line(
                      TextSpan(
                        '',
                        children: _typed(
                          theme,
                          answer.own,
                          placeholder: placeholder,
                          focused: focused,
                          secret: question.secret == true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              index,
            );
          }
      }
    }

    final window = windowOf(
      [for (final line in lines) line.row],
      state.row,
      math.max(limit, 6) - (editorRows - 1),
    );
    Widget more(int count, String arrow) =>
        Text(count > 0 ? '  $arrow $count more' : '  $arrow', style: theme.dim);
    final shown = [
      if (window.top > 0) (widget: more(window.above, '↑'), height: 1),
      for (final line in lines.sublist(window.top, window.end))
        (widget: line.widget, height: line.height),
      if (window.end < lines.length)
        (widget: more(window.below, '↓'), height: 1),
    ];
    return (
      widget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final line in shown) line.widget],
      ),
      rows: shown.fold(0, (sum, line) => sum + line.height),
    );
  }

  /// Submit: each answer, then Send and Skip.
  ({Widget widget, int rows}) _submitStep(
    ThemeData theme,
    AskState state,
    Map<String, String> problems,
  ) {
    final permission = theme.focus;
    final labels = [
      for (var index = 0; index < _questions.questions.length; index++)
        headerOf(_questions, index),
    ];
    final labelWidth = labels.fold(
      0,
      (widest, label) => math.max(widest, cellWidth(label)),
    );
    final sendable = problems.isEmpty;
    final onSkip = (!sendable && state.row >= 0) || state.row == 1;
    Widget marker(bool on) =>
        SizedBox(width: 2, child: Text(on ? '❯' : ' ', style: permission));
    return (
      widget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, question) in _questions.questions.indexed)
            Row(
              children: [
                SizedBox(
                  width: labelWidth + 2,
                  child: _line(TextSpan(labels[index])),
                ),
                Expanded(
                  child: switch ((
                    problems[question.id],
                    answerText(question, state),
                  )) {
                    (final problem?, _) => _line(
                      TextSpan(
                        problem == 'required'
                            ? 'no answer yet, and ${widget.agent} needs one'
                            : problem,
                      ),
                      style: theme.warning,
                    ),
                    (null, null) => _line(
                      const TextSpan('no answer'),
                      style: theme.dim,
                    ),
                    (null, final text?) => _line(TextSpan(text)),
                  },
                ),
              ],
            ),
          const SizedBox(height: 1),
          Row(
            children: [
              marker(sendable && state.row == 0),
              Text(
                '1. Send the answers',
                style: !sendable
                    ? theme.dim
                    : state.row == 0
                    ? permission
                    : null,
              ),
            ],
          ),
          Row(
            children: [
              marker(onSkip),
              Text(
                '2. Skip these questions',
                style: onSkip ? permission : null,
              ),
            ],
          ),
        ],
      ),
      rows: _questions.questions.length + 3,
    );
  }
}
