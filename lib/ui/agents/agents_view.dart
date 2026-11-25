/// The agents list under the status line and the line a child's view opens
/// with, drawn from the pure layout in `agents.dart`, and the one clock
/// both count on. From the original's `ui/agents/Agents.tsx`; teams' rows
/// come with CTUI-37, the background with CTUI-36.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';
import 'package:clock/clock.dart' show clock;

import '../theme/theme.dart';
import 'agents.dart';

/// The time the list's rows and a child's opening line count on: one
/// timer, a second at a time, for every widget that draws a time, so the
/// ages on screen move together; running only while one is subscribed.
abstract final class AgentsClock {
  static final _listeners = <void Function(int now)>{};
  static Timer? _timer;

  /// Whether the timer runs: something on screen has a time that counts.
  static bool get running => _timer != null;

  /// How many widgets count on it now.
  static int get subscribers => _listeners.length;

  /// The time now, as every subscriber is told it.
  static int now() => clock.now().millisecondsSinceEpoch;

  /// Tells [listener] the time each second until the returned function is
  /// called; the last to leave stops the timer.
  static void Function() subscribe(void Function(int now) listener) {
    _listeners.add(listener);
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final at = now();
      // A listener may leave while told, so tell a copy.
      for (final told in List.of(_listeners)) {
        told(at);
      }
    });
    return () {
      _listeners.remove(listener);
      if (_listeners.isEmpty) {
        _timer?.cancel();
        _timer = null;
      }
    };
  }
}

/// A widget's hold on [AgentsClock]: subscribed while [timed], its time
/// read again on subscribing, as the original's `useAgentsClock`.
mixin _OnAgentsClock<T extends StatefulWidget> on State<T> {
  late int now = AgentsClock.now();
  void Function()? _release;

  /// Whether what is drawn has a time that goes on counting.
  bool get timed;

  void _sync() {
    if (timed && _release == null) {
      now = AgentsClock.now();
      _release = AgentsClock.subscribe((at) => setState(() => now = at));
    } else if (!timed && _release != null) {
      _release!();
      _release = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _release?.call();
    _release = null;
    super.dispose();
  }
}

/// Whether [colour] is one of the terminal's sixteen by name.
bool _named(String colour) =>
    !colour.startsWith('#') && !colour.startsWith('ansi256(');

Color? _colour(String? colour) => colour == null ? null : colorOf(colour);

/// A tone as [palette] paints it: its role's colour, none for dim, and for
/// working the accent, dim; in the two 16-colour themes, whose accent is
/// the warning's yellow, the success's green, which nothing else in the
/// list takes (CHD-483). No colour where the palette has none.
Style agentToneStyle(AgentTone tone, Palette palette) => switch (tone) {
  AgentTone.dim => const Style(dim: true),
  AgentTone.working => Style(
    fg: _colour(
      palette.accent != null && _named(palette.accent!)
          ? palette.success
          : palette.accent,
    ),
    dim: true,
  ),
  AgentTone.warning => Style(fg: _colour(palette.warning)),
  AgentTone.error => Style(fg: _colour(palette.error)),
  AgentTone.success => Style(fg: _colour(palette.success)),
};

/// The session's agents under the status line: `main`, then each
/// long-lived child, drawn only while there is a child. Its rows are
/// furniture: a drag across them selects nothing. It takes no keys itself;
/// the window routes them and passes what they changed back in.
class AgentsList extends StatefulWidget {
  /// The list of [rows] in at most [limit] lines, as wide as it is laid.
  const AgentsList({
    super.key,
    required this.rows,
    required this.limit,
    required this.focused,
    required this.palette,
    this.view,
  });

  /// `main` first, then the children in opening order.
  final List<AgentRow> rows;

  /// The most lines it takes, `… +N more` among them.
  final int limit;

  /// The list has the keys: the picked row carries the `❯`.
  final bool focused;

  /// Where the lines start on a picked row taller than the list.
  final AgentsView? view;

  /// The theme's colours: the agents', the roles' and the permission's.
  final Palette palette;

  @override
  State<AgentsList> createState() => _AgentsListState();
}

class _AgentsListState extends State<AgentsList>
    with _OnAgentsClock<AgentsList> {
  // Only `main`, no child: nothing is drawn, so nothing counts.
  bool get _shown => widget.rows.length > 1;

  // The times on the rows go on counting, as the working line's does.
  @override
  bool get timed => _shown && listTimed(widget.rows);

  @override
  Widget build(BuildContext context) {
    if (!_shown) return const SizedBox();
    return SelectionContainer.disabled(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: LayoutBuilder(
          builder: (context, constraints) => _lines(
            agentsLayout(
              widget.rows,
              limit: widget.limit,
              width: math.max(0, constraints.maxWidth),
              focused: widget.focused,
              now: now,
              view: widget.view,
            ),
          ),
        ),
      ),
    );
  }

  Widget _lines(AgentsLayout layout) {
    final palette = widget.palette;
    const dim = Style(dim: true);
    TextSpan toned(Toned run, {String before = ''}) => TextSpan(
      '$before${run.text}',
      style: agentToneStyle(run.tone, palette),
    );
    // The `❯` in the permission's colour; a `↑` or `↓` for lines out of
    // sight, dim.
    TextSpan gutter(String text) => TextSpan(
      text,
      style: text.trim().isEmpty
          ? Style.plain
          : text.startsWith('❯')
          ? Style(fg: _colour(palette.permission))
          : dim,
    );
    Widget line(List<TextSpan> spans) => Text.rich(
      TextSpan('', children: spans),
      softWrap: false,
      maxLines: 1,
      overflow: TextOverflow.middle,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final laid in layout.rows)
          for (final (:at, gutter: beside) in laid.lines)
            () {
              final row = laid.row;
              TextSpan name(String text) => parseAnsi(
                text,
                base: Style(
                  fg: _colour(agentColour(palette, row.colour)),
                  bold: row.picked,
                ),
              );
              if (at == 0) {
                return line([
                  gutter(beside),
                  if (laid.branch case final branch?)
                    TextSpan(branch, style: dim),
                  name(laid.name),
                  parseAnsi('  ${laid.detail}', base: dim),
                  if (laid.state case final state?) toned(state, before: '  '),
                  if (laid.unseen case final unseen?)
                    toned(unseen, before: '  '),
                ]);
              }
              // Under the name its next line, or as many spaces, then what
              // went under the detail.
              final under = at - 1 < laid.names.length
                  ? laid.names[at - 1]
                  : null;
              final below = at - 1 < laid.below.length
                  ? laid.below[at - 1]
                  : const <Toned>[];
              return line([
                gutter(beside),
                if (under == null)
                  TextSpan(' ' * laid.nameWidth)
                else ...[
                  TextSpan(laid.tree, style: dim),
                  name(under),
                ],
                if (below.isNotEmpty) const TextSpan('  '),
                for (final run in below) toned(run),
              ]);
            }(),
        if (layout.more > 0)
          Text('  … +${layout.more} more', style: dim, softWrap: false),
      ],
    );
  }
}

/// The line a child's view opens with, in place of the startup header:
/// `parser · codex · gpt-5.3-codex · opened by main 4m ago`, its age
/// counting on the list's clock.
class ChildLine extends StatefulWidget {
  /// The line of the child [name], opened at [openedAt] on [runtime].
  const ChildLine({
    super.key,
    required this.name,
    required this.runtime,
    required this.openedAt,
    required this.colour,
    required this.palette,
    this.model,
    this.forkedFrom,
    this.team,
    this.leadName,
  });

  /// The team it is of, by its file's name: a lead's or a member's.
  final String? team;

  /// A member's lead, by its name.
  final String? leadName;

  /// The child's name.
  final String name;

  /// The runtime it runs on.
  final String runtime;

  /// When it was opened, in milliseconds since the epoch.
  final num openedAt;

  /// Its place among the theme's agent colours.
  final int colour;

  /// The model as the status line names it; none until known.
  final String? model;

  /// The agent it was forked from, for a fork.
  final String? forkedFrom;

  /// The theme's colours.
  final Palette palette;

  @override
  State<ChildLine> createState() => _ChildLineState();
}

class _ChildLineState extends State<ChildLine> with _OnAgentsClock<ChildLine> {
  // Its age goes on with the window idle.
  @override
  bool get timed => true;

  @override
  Widget build(BuildContext context) {
    final line = childLine(
      name: widget.name,
      runtime: widget.runtime,
      openedAt: widget.openedAt,
      forkedFrom: widget.forkedFrom,
      team: widget.team,
      leadName: widget.leadName,
      model: widget.model,
      now: now,
    );
    return Text.rich(
      TextSpan(
        '',
        children: [
          parseAnsi(
            line.name,
            base: Style(
              fg: _colour(agentColour(widget.palette, widget.colour)),
              bold: true,
            ),
          ),
          parseAnsi(line.rest, base: const Style(dim: true)),
        ],
      ),
      softWrap: false,
      maxLines: 1,
      overflow: TextOverflow.middle,
    );
  }
}
