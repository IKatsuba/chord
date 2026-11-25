/// The background view: the pickers' frame above the prompt, full width, a
/// row per item of the session, the `❯` on one, as tall as its rows up to
/// half the window; or an item's detail in place of the rows. It only draws
/// the frame [backgroundFrame] lays out; the window routes its keys. From
/// the original's `ui/background/BackgroundView.tsx`.
library;

import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';

import '../../session/transcript/types.dart' show Idle, TurnState;
import '../dialogs/permission.dart' show countRoom, requestCount, requestRule;
import '../theme/theme.dart';
import '../transcript/agents/agents.dart' show AgentWork;
import 'background.dart';
import 'view.dart';

/// The background frame [frame] over [items], in the theme's [palette].
class BackgroundBox extends StatelessWidget {
  /// The frame as laid out, its rows' owners among [items].
  const BackgroundBox({
    super.key,
    required this.frame,
    required this.palette,
    this.turn,
    this.agent,
    this.log,
    this.pageUp,
    this.pageDown,
    this.onLogLines,
    this.logScroll,
  });

  /// Where a task's log is read, kept by the window.
  final ScrollController? logScroll;

  /// Told a task's log's lines as laid out, which the frame takes up to
  /// its room.
  final void Function(int lines)? onLogLines;

  final BackgroundFrame frame;
  final Palette palette;

  /// A task's owner's turn, which its calls' waiting is read from, and the
  /// agent its owner runs, as the transcript names it.
  final TurnState? turn;
  final String? agent;

  /// Where the window pages a task's log.
  final LogScroller? log;

  /// The keys a log's rules name.
  final String? pageUp, pageDown;

  Style _fg(String? colour, {bool dim = false, bool bold = false}) => Style(
    fg: colour == null ? null : colorOf(colour),
    dim: dim && colour == null,
    bold: bold,
  );

  /// A run's style by what it is: the `❯` in the permission's colour, a
  /// focused name bold, a state in its group's colour or dim, an owner in
  /// its agent's colour or dim, the rest dim but a detail's own text.
  Style _cell(ViewCell cell, {required bool focused, ItemOwner? owner}) =>
      switch (cell.role) {
        CellRole.mark => _fg(palette.permission),
        CellRole.edge => const Style(dim: true),
        CellRole.name => focused ? Style.bold : Style.plain,
        CellRole.text => Style.plain,
        CellRole.state => _fg(switch (cell.group) {
          BackgroundGroup.asking => palette.warning,
          BackgroundGroup.failed => palette.error,
          BackgroundGroup.done => palette.success,
          _ => null,
        }, dim: true),
        CellRole.owner => _fg(agentColour(palette, owner?.colour), dim: true),
        _ => const Style(dim: true),
      };

  @override
  Widget build(BuildContext context) {
    Widget line(FrameLine line) {
      final (:cells, :item, :focused) = line;
      return Text.rich(
        TextSpan(
          '',
          children: [
            for (final cell in cells)
              TextSpan(
                cell.text,
                style: _cell(cell, focused: focused, owner: item?.owner),
              ),
          ],
        ),
        softWrap: false,
      );
    }

    return SelectionContainer.disabled(
      child: Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Box(
          border: Border.rounded.withStyle(_fg(palette.permission)),
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  '',
                  children: [
                    TextSpan(
                      frame.title,
                      style: _fg(palette.permission, bold: true),
                    ),
                    TextSpan(frame.note, style: const Style(dim: true)),
                  ],
                ),
                softWrap: false,
              ),
              const SizedBox(height: 1),
              for (final each in frame.body) line(each),
              if ((frame.log, logScroll) case (
                (:final subagent, :final task, :final rows),
                final scroll?,
              ))
                () {
                  final work = _WorkLog(
                    key: ValueKey(subagent.id),
                    task: task,
                    work: AgentWork(
                      subagent,
                      turn: turn ?? const Idle(),
                      agent: agent,
                    ),
                    rows: rows > 0 ? rows : 1,
                    scroll: scroll,
                    scroller: log,
                    pageUp: pageUp,
                    pageDown: pageDown,
                    onLines: onLogLines,
                  );
                  // With no row, still laid out a row tall, out of sight, so
                  // its lines are counted and it pages, as the original's.
                  return rows > 0
                      ? SizedBox(height: rows, child: work)
                      : SizedBox(
                          height: 0,
                          child: Stack(
                            children: [
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 0,
                                height: 1,
                                child: work,
                              ),
                            ],
                          ),
                        );
                }(),
              const SizedBox(height: 1),
              for (final said in frame.hint)
                Text.rich(
                  TextSpan('', children: [parseAnsi(said)]),
                  style: const Style(dim: true),
                  softWrap: false,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the window pages a task's log in the background's detail.
final class LogScroller {
  void Function(ScrollStep step)? _scroll;

  /// Pages the log by [step]; whether a log took it.
  bool scroll(ScrollStep step) {
    final scroll = _scroll;
    if (scroll == null) return false;
    scroll(step);
    return true;
  }
}

/// A task's log in its detail: its whole task after `› `, then its work,
/// read from the end and following it as it comes while not paged up; a
/// dim rule says what is out of view.
class _WorkLog extends StatefulWidget {
  const _WorkLog({
    super.key,
    required this.task,
    required this.work,
    required this.rows,
    required this.scroll,
    this.scroller,
    this.pageUp,
    this.pageDown,
    this.onLines,
  });

  /// Where it is read, kept by the window across a hidden view and a room
  /// of no rows, as the original's scrollbox stays laid out.
  final ScrollController scroll;
  final void Function(int lines)? onLines;
  final String? task;
  final Widget work;
  final int rows;
  final LogScroller? scroller;
  final String? pageUp, pageDown;

  @override
  State<_WorkLog> createState() => _WorkLogState();
}

class _WorkLogState extends State<_WorkLog> {
  ScrollController get _scroll => widget.scroll;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_moved);
    widget.scroller?._scroll = _step;
  }

  @override
  void didUpdateWidget(_WorkLog old) {
    super.didUpdateWidget(old);
    if (!identical(old.scroll, widget.scroll)) {
      old.scroll.removeListener(_moved);
      widget.scroll.addListener(_moved);
    }
    if (!identical(old.scroller, widget.scroller)) {
      old.scroller?._scroll = null;
      widget.scroller?._scroll = _step;
    }
  }

  @override
  void dispose() {
    if (widget.scroller?._scroll == _step) widget.scroller?._scroll = null;
    _scroll.removeListener(_moved);
    super.dispose();
  }

  void _moved() => setState(() {});

  int? _told;

  /// Its lines as laid out, told once they change: read after layout, as
  /// the list measures them only then.
  void _measure() {
    if (!mounted) return;
    final lines = _scroll.contentRows;
    if (lines > 0 && lines != _told) {
      _told = lines;
      widget.onLines?.call(lines);
    }
  }

  /// A page key: back to following once it reaches the end, and `end` back
  /// to it always.
  void _step(ScrollStep step) {
    final next = logStep(
      step,
      _scroll.contentRows,
      math.max(1, _scroll.viewRows),
      _scroll.offset,
    );
    if (next == following) {
      _scroll.toBottom();
    } else {
      _scroll.jumpTo(next.toInt());
    }
  }

  Widget _list() => ListView.builder(
    controller: _scroll,
    itemCount: 2,
    itemBuilder: (context, index) => index == 0
        ? widget.task == null
              ? const SizedBox()
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('› ', style: const Style(dim: true)),
                    Expanded(child: Text.ansi(widget.task!)),
                  ],
                )
        : widget.work,
  );

  @override
  Widget build(BuildContext context) {
    context.owner.afterLayout(_measure);
    final lines = _scroll.contentRows;
    // A room of one row has no row for a rule: what is hidden is said
    // beside the row.
    if (widget.rows == 1 && lines > 1) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final count = requestCount((
            above: _scroll.offset,
            below: _scroll.rowsBelow,
          ));
          return Row(
            children: [
              SizedBox(
                width: math.max(1, constraints.maxWidth - countRoom(lines) - 1),
                child: _list(),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    count,
                    style: const Style(dim: true),
                    softWrap: false,
                  ),
                ),
              ),
            ],
          );
        },
      );
    }
    // A log that fits its rows has nothing out of view.
    final fits = lines <= widget.rows;
    final above = fits ? 0 : _scroll.offset;
    final below = fits ? 0 : _scroll.rowsBelow;
    // Rules take their rows from the log's, as a request's do.
    final rules = (above > 0 ? 1 : 0) + (below > 0 ? 1 : 0);
    final room = widget.rows - rules;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (above > 0 && room > 0)
            Text(
              requestRule('↑', above, widget.pageUp, constraints.maxWidth),
              style: const Style(dim: true),
              softWrap: false,
            ),
          SizedBox(height: room > 0 ? room : widget.rows, child: _list()),
          if (below > 0 && room > 0)
            Text(
              requestRule('↓', below, widget.pageDown, constraints.maxWidth),
              style: const Style(dim: true),
              softWrap: false,
            ),
        ],
      ),
    );
  }
}
