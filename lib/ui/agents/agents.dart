/// The list of a session's agents under the prompt, kept out of the
/// widget: `main` and each long-lived child, one row each with its runtime,
/// model and state, laid out to the window's width, a row that does not fit
/// wrapping, a team's members nested under its lead or folded into its row,
/// and to its height; and where ↑ ↓ move the `❯` in it. From the
/// original's `ui/agents/agents.ts`.
library;

import 'dart:math' as math;

import 'package:collection/collection.dart' show mergeSort;

import 'package:chord_tui/chord_tui.dart' show TextLayout, TextSpan, cellWidth;

import '../../session/elapsed.dart';
import '../../session/transcript/types.dart' show LeftOpen;
import '../../session/waits.dart';
import '../../notify.dart' show InputAsk;
import '../prompt/queue.dart';
import 'glyphs.dart';

/// One agent of the front session, as the list is asked to draw it.
final class AgentRow {
  /// A row for the agent [key] names.
  const AgentRow({
    required this.key,
    required this.name,
    required this.runtime,
    required this.wait,
    this.model,
    this.effort,
    this.colour,
    this.picked = false,
    this.failed = false,
    this.team,
    this.branch,
    this.folded,
  });

  /// Its session's key: the main session's for `main`, the child's for a
  /// child.
  final int key;

  /// `main`, or the child's name.
  final String name;

  /// The runtime it runs on.
  final String runtime;

  /// The model as the status line names it; none until known.
  final String? model;

  /// The effort it is on, by its id; none for a runtime with none.
  final String? effort;

  /// Its place among the theme's agent colours; none for `main`.
  final int? colour;

  /// Where it stands with the person.
  final AgentWait wait;

  /// The prompt goes to it.
  final bool picked;

  /// Its agent never came up.
  final bool failed;

  /// A team's lead and each of its members: the lead's key.
  final int? team;

  /// A member's place in its lead's tree, `├─` or `└─`, as [teamRows]
  /// draws it.
  final String? branch;

  /// A lead folded with its open members: they, in their order.
  final List<AgentRow>? folded;

  /// This with its [branch] in its lead's tree, or folded with its
  /// [folded] members.
  AgentRow placed({String? branch, List<AgentRow>? folded}) => AgentRow(
    key: key,
    name: name,
    runtime: runtime,
    wait: wait,
    model: model,
    effort: effort,
    colour: colour,
    picked: picked,
    failed: failed,
    team: team,
    branch: branch ?? this.branch,
    folded: folded ?? this.folded,
  );
}

/// How a state is painted: the theme's role, or dim; [working] is the
/// accent with dim.
enum AgentTone { warning, error, success, dim, working }

/// What a row says of its agent: the glyph, then the words.
final class AgentState {
  /// A state of [glyph] and [words], painted in [tone].
  const AgentState({
    required this.glyph,
    required this.words,
    required this.tone,
  });

  /// The glyph ahead of the words.
  final String glyph;

  /// What it says.
  final String words;

  /// How it is painted.
  final AgentTone tone;

  @override
  bool operator ==(Object other) =>
      other is AgentState &&
      other.glyph == glyph &&
      other.words == words &&
      other.tone == tone;

  @override
  int get hashCode => Object.hash(glyph, words, tone);

  @override
  String toString() => '$glyph $words ($tone)';
}

/// `41s`, `2m`: the first unit of an elapsed time.
String _briefly(num ms) => formatElapsed(ms).split(' ').first;

/// What failed for an agent, gravest first: its process exited, it never
/// came up, or its turn failed while it stayed open, which only an unseen
/// failure says; none when nothing did.
Failure? _failureFor(AgentRow row) => row.wait.exited
    ? Failure.exited
    : row.failed
    ? Failure.start
    : failureOf(row.wait);

/// An agent's state while it is open and does nothing: a hollow dot.
const idleGlyph = '◦';

/// What an agent is doing now, always one: asking, gone, working, or idle
/// since it last stopped. A failed turn is no state, as the agent is still
/// open and idle once its turn failed: what was not yet seen of it is its
/// mark ([agentMark]).
AgentState agentState(AgentRow row, num now) {
  if (row.folded case final members?) return _teamState(row, members, now);
  final wait = row.wait;
  if (wait.asking case final asking?) {
    final kind = asking.on is InputAsk ? 'input' : 'permission';
    return AgentState(
      glyph: WaitGlyph.asking.glyph,
      words: '$kind ${formatElapsed(now - asking.since)}',
      tone: AgentTone.warning,
    );
  }
  final gone = _goneFor(row);
  if (gone != null) {
    return AgentState(
      glyph: WaitGlyph.failed.glyph,
      words: gone == Failure.exited ? 'exited' : 'failed to start',
      tone: AgentTone.error,
    );
  }
  final working = wait.working;
  return working == null
      ? AgentState(
          glyph: idleGlyph,
          words: 'idle ${_briefly(now - (wait.stopped ?? now))}',
          tone: AgentTone.dim,
        )
      : AgentState(
          glyph: WaitGlyph.working.glyph,
          words: 'working ${formatElapsed(now - working)}',
          tone: AgentTone.working,
        );
}

/// How an agent is gone, its process exited or never come up; none while
/// open.
Failure? _goneFor(AgentRow row) {
  final failure = _failureFor(row);
  return failure == Failure.turn ? null : failure;
}

/// What of an agent is not yet seen: a failed turn, a reply, a message to
/// it.
UnseenKind? _unseenOf(AgentRow row) {
  final unseen = row.wait.unseen;
  if (unseen == null) return null;
  // An agent gone says so in its state; only a failed turn is a mark.
  if (unseen.kind == UnseenKind.failed) {
    return _failureFor(row) == Failure.turn ? UnseenKind.failed : null;
  }
  return unseen.kind;
}

const _unseenOrder = [
  UnseenKind.failed,
  UnseenKind.replied,
  UnseenKind.message,
];

/// Beside the state, what of the agent the person has not yet seen, gone
/// once they open it; a folded team's, the first of its lead's and its
/// members', unnamed. None when all of it is seen.
AgentState? agentMark(AgentRow row) {
  final kinds = {
    for (final each in [row, ...?row.folded]) ?_unseenOf(each),
  };
  return _markOf(_unseenOrder.where(kinds.contains).firstOrNull);
}

AgentState? _markOf(UnseenKind? kind) => switch (kind) {
  UnseenKind.failed => AgentState(
    glyph: WaitGlyph.failed.glyph,
    words: 'turn failed',
    tone: AgentTone.error,
  ),
  // Quiet: noticed by its glyph and words, not its colour.
  UnseenKind.replied => AgentState(
    glyph: WaitGlyph.replied.glyph,
    words: 'new reply',
    tone: AgentTone.dim,
  ),
  UnseenKind.message => AgentState(
    glyph: WaitGlyph.message.glyph,
    words: 'new message',
    tone: AgentTone.dim,
  ),
  null => null,
};

/// How urgent an agent's state is, lowest first, then how long it has
/// stood, longest first; none while it is idle.
(int, num)? _urgency(AgentRow row) {
  final wait = row.wait;
  if (wait.asking case final asking?) return (0, asking.since);
  final gone = _goneFor(row);
  if (gone != null) {
    return (gone == Failure.exited ? 1 : 2, wait.unseen?.since ?? 0);
  }
  final working = wait.working;
  return working == null ? null : (3, working);
}

/// A folded team's state: the most urgent among its lead and members,
/// naming the member whose it is, `● tester: permission 12s`; idle from
/// the one that stopped last when all of them are.
AgentState _teamState(AgentRow lead, List<AgentRow> members, num now) {
  final own = AgentRow(
    key: lead.key,
    name: lead.name,
    runtime: lead.runtime,
    wait: lead.wait,
    model: lead.model,
    effort: lead.effort,
    colour: lead.colour,
    picked: lead.picked,
    failed: lead.failed,
    team: lead.team,
  );
  final ranked = [
    for (final row in [own, ...members])
      if (_urgency(row) case final rank?) (row: row, rank: rank),
  ];
  // Stable, as the original's sort: the first of equals stays first.
  mergeSort(
    ranked,
    compare: (a, b) {
      final kind = a.rank.$1.compareTo(b.rank.$1);
      return kind != 0 ? kind : a.rank.$2.compareTo(b.rank.$2);
    },
  );
  final first = ranked.firstOrNull?.row;
  if (first == null) {
    final stopped = [
      for (final row in [own, ...members]) row.wait.stopped ?? now,
    ].reduce(math.max);
    return AgentState(
      glyph: idleGlyph,
      words: 'idle ${_briefly(now - stopped)}',
      tone: AgentTone.dim,
    );
  }
  final state = agentState(first, now);
  return identical(first, own)
      ? state
      : AgentState(
          glyph: state.glyph,
          words: '${first.name}: ${state.words}',
          tone: state.tone,
        );
}

/// The agents as the list draws them: each member under its lead with
/// `├─` and `└─`, and, with [fold], each team but the one whose agent is
/// picked folded into its lead's row, its members kept for its size and
/// its state. A lead with no member open has nothing to fold.
List<AgentRow> teamRows(List<AgentRow> agents, {required bool fold}) {
  final picked = agents.where((row) => row.picked).firstOrNull?.team;
  List<AgentRow> membersOf(int lead) => [
    for (final row in agents)
      if (row.team == lead && row.key != lead) row,
  ];
  return [
    for (final row in agents)
      if (row.team case final team?)
        ...() {
          final members = membersOf(team);
          if (row.key != team) {
            return fold && team != picked
                ? const <AgentRow>[]
                : [
                    row.placed(
                      branch: identical(row, members.last) ? '└─' : '├─',
                    ),
                  ];
          }
          return fold && team != picked && members.isNotEmpty
              ? [row.placed(folded: members)]
              : [row];
        }()
      else
        row,
  ];
}

/// Whether a time on the list goes on counting, so the list ticks: every
/// agent's state has one, idle too, but one that is gone, a folded team's
/// members included.
bool listTimed(List<AgentRow> rows) {
  bool timed(AgentRow row) =>
      _goneFor(row) == null || (row.folded ?? const []).any(timed);
  return rows.any(timed);
}

/// At most this many rows, the queue's own limit: 4 at 24 rows, 6 at 40.
int agentsRowLimit(int rows) => queueRowLimit(rows);

/// The list's rows: the agents, drawn only while there is a child. When
/// they all do not fit [limit] lines, as [height] counts them, each team
/// the pick is not in folds to its lead's row; a row that wraps counts each
/// of its lines.
List<AgentRow> listRows(
  List<AgentRow> agents, {
  num limit = double.infinity,
  int Function(List<AgentRow> rows)? height,
}) {
  final lines = height ?? (rows) => rows.length;
  return teamRows(agents, fold: lines(teamRows(agents, fold: false)) > limit);
}

/// ↑ ↓ in the list: the agent [by] rows from the picked one, by its key;
/// the last stays the last, and none above the first hands the keys back
/// to the box.
int? moveListFocus(List<AgentRow> rows, int by) =>
    switch (moveListTarget(rows, by)) {
      ListAgent(:final key) => key,
      _ => null,
    };

/// Where the list's `❯` goes: an agent's row, by its key, or the
/// background's summary line.
sealed class ListTarget {
  const ListTarget();
}

/// The agent row with [key].
final class ListAgent extends ListTarget {
  const ListAgent(this.key);
  final int key;

  @override
  bool operator ==(Object other) => other is ListAgent && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// The background's summary line.
final class ListSummary extends ListTarget {
  const ListSummary();

  @override
  bool operator ==(Object other) => other is ListSummary;

  @override
  int get hashCode => 0;
}

/// ↑ ↓ in the list: the stop [by] from the focused one, the summary line
/// (when [summary] is drawn) after the agents; the last stays the last,
/// and none above the first hands the keys back to the box. With no agents
/// drawn the summary line is the one stop; [onSummary] while it has the
/// `❯`.
ListTarget? moveListTarget(
  List<AgentRow> rows,
  int by, {
  bool summary = false,
  bool onSummary = false,
}) {
  final stops = rows.length + (summary ? 1 : 0);
  final from = summary && (onSummary || rows.isEmpty)
      ? rows.length
      : math.max(0, rows.indexWhere((row) => row.picked));
  final at = math.min(from + by, stops - 1);
  if (stops == 0 || at < 0) return null;
  return at == rows.length ? const ListSummary() : ListAgent(rows[at].key);
}

/// A run of a line in one tone.
final class Toned {
  /// [text] painted in [tone].
  const Toned(this.text, this.tone);

  /// What it says.
  final String text;

  /// How it is painted.
  final AgentTone tone;

  @override
  bool operator ==(Object other) =>
      other is Toned && other.text == text && other.tone == tone;

  @override
  int get hashCode => Object.hash(text, tone);

  @override
  String toString() => 'Toned($text, $tone)';
}

/// One line of a row in sight: [at] its place in the row, 0 its first, and
/// what stands in the gutter beside it.
typedef ShownLine = ({int at, String gutter});

/// One row laid out: its columns, each padded to the widest.
class LaidRow {
  /// A row laid out of its parts.
  const LaidRow({
    required this.row,
    required this.mark,
    required this.name,
    required this.names,
    required this.nameWidth,
    required this.detail,
    required this.below,
    required this.height,
    this.tree = '',
    this.branch,
    this.state,
    this.unseen,
  });

  /// The agent it draws.
  final AgentRow row;

  /// `❯ ` on the focused row while the list has the keys, else two spaces.
  final String mark;

  /// A member's `├─ ` or `└─ `, drawn dim ahead of its name.
  final String? branch;

  /// The name's first line, padded so with the branch it fills the column.
  final String name;

  /// The name's further lines, each padded so with [tree] it fills the
  /// column.
  final List<String> names;

  /// What stands under a member's branch ahead of each further line of its
  /// name, drawn dim: the tree's `│` past a member that is not the last,
  /// else spaces; empty for a row with no branch.
  final String tree;

  /// The name column's width, branch included, for a line under it.
  final int nameWidth;

  /// Its runtime and model.
  final String detail;

  /// Its state beside the detail, padded so the marks after it start in one
  /// column; none where it went under the detail.
  final Toned? state;

  /// What of it is not yet seen, in its own column after the state.
  final Toned? unseen;

  /// Under the detail, a line each from the row's second line: the rest of
  /// a detail too wide for its line, then the state and mark where the row
  /// had no room for them beside it.
  final List<List<Toned>> below;

  /// How many lines the row takes.
  final int height;
}

/// A row as the list draws it: which of its lines are in sight.
final class ShownRow extends LaidRow {
  /// [laid] with [lines] in sight.
  ShownRow(LaidRow laid, this.lines)
    : super(
        row: laid.row,
        mark: laid.mark,
        branch: laid.branch,
        tree: laid.tree,
        name: laid.name,
        names: laid.names,
        nameWidth: laid.nameWidth,
        detail: laid.detail,
        state: laid.state,
        unseen: laid.unseen,
        below: laid.below,
        height: laid.height,
      );

  /// Its lines in sight, in order, each with what stands in the gutter: the
  /// `❯`, a `↑` or `↓` where lines are out of sight, or two spaces.
  final List<ShownLine> lines;
}

/// The rows the list draws in its lines.
final class AgentsLayout {
  /// A layout of [rows], [more] left out, from line [top].
  const AgentsLayout({
    required this.rows,
    required this.more,
    required this.top,
  });

  /// The rows in sight.
  final List<ShownRow> rows;

  /// How many rows `… +N more` stands for; 0 when all are drawn.
  final int more;

  /// The list's line at the top, counting every row's lines from the first.
  final int top;
}

/// Where the list's lines start while it is read by line: its picked row
/// taller than its budget, or one picked on from such a row. The line at
/// its top, for that row at that width and limit; another row or size
/// starts it again.
final class AgentsView {
  /// The window from line [top] on row [key] at [width] and [limit].
  const AgentsView({
    required this.key,
    required this.width,
    required this.limit,
    required this.top,
  });

  /// The picked row's key.
  final int key;

  /// The width it was read at.
  final int width;

  /// The limit it was read in.
  final int limit;

  /// The list's line at the window's top.
  final int top;

  @override
  bool operator ==(Object other) =>
      other is AgentsView &&
      other.key == key &&
      other.width == width &&
      other.limit == limit &&
      other.top == top;

  @override
  int get hashCode => Object.hash(key, width, limit, top);

  @override
  String toString() =>
      'AgentsView(key: $key, width: $width, '
      'limit: $limit, top: $top)';
}

/// The gap between the columns.
const _gap = '  ';

/// The `❯ ` or two spaces ahead of each row.
const _markWidth = 2;

/// What one way of fitting the rows keeps: an agent's model, its effort,
/// and the words of what is not yet seen beside its glyph.
typedef _Fit = ({bool model, bool effort, bool marks});

/// Each way of fitting, the fullest first: an agent's effort goes first,
/// then its model, then the words of its mark, leaving its glyph. Past the
/// last a row's state goes under its detail.
const List<_Fit> _fits = [
  (model: true, effort: true, marks: true),
  (model: true, effort: false, marks: true),
  (model: false, effort: false, marks: true),
  (model: false, effort: false, marks: false),
];

/// [text] wrapped at its spaces to [width], a word wider broken; never
/// narrower than one column, which the wrapping refuses.
List<String> _wrapped(String text, int width) {
  final lines = [
    for (final line in TextLayout.wrapAnsi(
      TextSpan(text),
      math.max(1, width),
      hard: true,
    ).lines)
      line.map((glyph) => glyph.text).join(),
  ];
  return lines.isEmpty ? [''] : lines;
}

int _widest(Iterable<String> texts) =>
    texts.fold(0, (widest, text) => math.max(widest, cellWidth(text)));

String _pad(String text, int width) =>
    text + ' ' * math.max(0, width - cellWidth(text));

int _heights(Iterable<LaidRow> laid) =>
    laid.fold(0, (sum, row) => sum + row.height);

/// Every row laid out at [width], none left out. The name column is never
/// wider than a third of [width], a longer name wrapping inside it; then,
/// while a row does not fit, its effort goes, then its model, then its
/// mark's words, as [_fits] says, and past them a row whose detail leaves
/// no room puts its state and mark under the detail, wrapped at its spaces.
/// The name and the state's words are never cut.
List<LaidRow> _laidRows(
  List<AgentRow> rows, {
  required int width,
  required bool focused,
  required num now,
}) {
  final states = {for (final row in rows) row: agentState(row, now)};
  final marks = {for (final row in rows) row: agentMark(row)};
  String branchOf(AgentRow row) => row.branch == null ? '' : '${row.branch} ';
  // A folded team's members count too, under their branch as unfolded, so
  // folding never moves a column.
  final names = math.min(
    math.max(1, width ~/ 3),
    _widest([
      for (final row in rows) ...[
        branchOf(row) + row.name,
        for (final member in row.folded ?? const <AgentRow>[])
          '├─ ${member.name}',
      ],
    ]),
  );
  Toned stateOf(AgentRow row) {
    final state = states[row]!;
    return Toned('${state.glyph} ${state.words}', state.tone);
  }

  final detailAt = _markWidth + names + _gap.length;

  for (final fit in _fits) {
    String runtimeOf(AgentRow row) => [
      row.runtime,
      // A folded lead's size stands where its model would: it says more.
      if (row.folded case final folded?)
        '${folded.length + 1} agents'
      else if (fit.model && row.model != null)
        row.model!,
      // After its model, which it tunes.
      if (row.folded == null && fit.model && fit.effort && row.effort != null)
        row.effort!,
    ].join(' · ');
    Toned? markOf(AgentRow row) {
      final mark = marks[row];
      if (mark == null) return null;
      return Toned(
        fit.marks ? '${mark.glyph} ${mark.words}' : mark.glyph,
        mark.tone,
      );
    }

    // Which rows keep their state beside their detail, and how wide the
    // columns are over them.
    ({int detail, int states, int across}) measure(Set<AgentRow> beside) {
      final states = _widest(beside.map((row) => stateOf(row).text));
      final unseen = _widest(beside.map((row) => markOf(row)?.text ?? ''));
      final detail = _widest(beside.map(runtimeOf));
      return (
        detail: detail,
        states: states,
        across:
            detailAt +
            detail +
            _gap.length +
            states +
            (unseen == 0 ? 0 : _gap.length + unseen),
      );
    }

    // What one row would take on its own: its detail, state and mark.
    int own(AgentRow row) {
      final mark = markOf(row);
      return detailAt +
          cellWidth(runtimeOf(row)) +
          _gap.length +
          cellWidth(stateOf(row).text) +
          (mark == null ? 0 : _gap.length + cellWidth(mark.text));
    }

    final beside = {...rows};
    var measured = measure(beside);

    if (!identical(fit, _fits.last)) {
      if (measured.across > width) continue;
    } else {
      // Past the last way of fitting, the row that needs the most room puts
      // its state under its detail, until the rest fit beside theirs.
      while (beside.isNotEmpty && measured.across > width) {
        beside.remove(
          beside.reduce(
            // The lowest of rows that need as much, the top kept whole.
            (one, other) => own(other) >= own(one) ? other : one,
          ),
        );
        measured = measure(beside);
      }
    }

    return [
      for (final row in rows)
        () {
          final branch = branchOf(row);
          final nameRoom = names - cellWidth(branch);
          final lines = [
            for (final line in _wrapped(row.name, nameRoom))
              _pad(line, nameRoom),
          ];
          // Under the branch, the tree goes on past a member that is not
          // the last.
          final under = _pad(row.branch == '├─' ? '│' : '', cellWidth(branch));
          final mark = markOf(row);
          final shown = stateOf(row);
          final isBeside = beside.contains(row);
          // Under the detail: the state, wrapped at its spaces, then the
          // mark after it where it fits, else on a line of its own.
          final below = <List<Toned>>[];
          final room = width - detailAt;
          final runtime = runtimeOf(row);
          // A detail wider than its line on its own wraps under its start,
          // at its spaces, inside a word only where the word alone is wider.
          final details = !isBeside && cellWidth(runtime) > room
              ? _wrapped(runtime, room)
              : [runtime];
          for (final text in details.skip(1)) {
            below.add([Toned(text, AgentTone.dim)]);
          }
          if (!isBeside) {
            for (final text in _wrapped(shown.text, room)) {
              below.add([Toned(text, shown.tone)]);
            }
            if (mark != null) {
              final last = below.last;
              final used = cellWidth(last.map((run) => run.text).join());
              if (used + _gap.length + cellWidth(mark.text) <= room) {
                last.add(Toned('$_gap${mark.text}', mark.tone));
              } else {
                below.add([mark]);
              }
            }
          }
          final state = isBeside && mark != null
              ? Toned(_pad(shown.text, measured.states), shown.tone)
              : shown;
          return LaidRow(
            row: row,
            mark: focused && row.picked ? '❯ ' : '  ',
            branch: branch.isEmpty ? null : branch,
            name: lines.first,
            names: lines.sublist(1),
            tree: under,
            nameWidth: names,
            detail: isBeside
                ? _pad(details.first, measured.detail)
                : details.first,
            state: isBeside ? state : null,
            unseen: isBeside ? mark : null,
            below: below,
            height: math.max(lines.length, 1 + below.length),
          );
        }(),
    ];
  }

  return const [];
}

/// How many lines [rows] take at [width], every row drawn: what folding a
/// team weighs against the list's limit.
int agentsHeight(List<AgentRow> rows, {required int width, required num now}) =>
    _heights(_laidRows(rows, width: width, focused: false, now: now));

/// Whether a picked row [height] lines tall is read by line: when it would
/// not be in sight whole beside the `… +N more` line, the limit less one
/// while rows of [total] lines are out of sight, the whole limit while none
/// are.
bool _tall(int height, int total, int room) =>
    height > (total > room ? room - 1 : room);

/// Where a window on the list read by line starts once its pick is a row
/// that fits: the least move from [top] that brings row [at] whole into
/// sight, so the rows above stay in sight as far as they fit.
int _wholeTop(List<LaidRow> laid, int at, int room, int top) {
  final first = _heights(laid.take(at));
  final total = _heights(laid);
  return math.min(
    math.max(0, total - room),
    math.max(0, math.min(first, math.max(top, first + laid[at].height - room))),
  );
}

/// Every line of [laid] in sight, its gutter the row's own mark.
ShownRow _whole(LaidRow laid) => ShownRow(laid, [
  for (var at = 0; at < laid.height; at++)
    (at: at, gutter: at == 0 ? laid.mark : '  '),
]);

/// The line the list's window starts at while its picked row is taller
/// than the list: [view]'s, where it is that row's at this width, kept so
/// the row's first line or a line of it is in sight; else the least move
/// from the list's top that brings the row's first line into sight.
int _windowTop(
  List<LaidRow> laid,
  int at,
  int limit,
  int width,
  AgentsView? view,
) {
  final first = _heights(laid.take(at));
  final total = _heights(laid);
  final lowest = math.max(0, first - limit + 1);
  final highest = math.max(
    lowest,
    math.min(total - limit, first + laid[at].height - limit),
  );
  final top =
      view != null &&
          view.key == laid[at].row.key &&
          view.width == width &&
          view.limit == limit
      ? view.top
      : lowest;
  return math.min(highest, math.max(lowest, top));
}

/// The rows drawn in [limit] lines at [width], never more: past the limit,
/// the last line is `… +N more`, and while the list has the keys the rows
/// shown move so the picked one is among them. A wrapped row counts as many
/// lines as it has. A row taller than the limit shows the lines that fit,
/// `↓` beside its last in sight; picked while the list has the keys, it is
/// read by line in a window of [limit] lines from [view]'s top, `↑` and `↓`
/// in the gutter where lines are out of sight. [focused] marks the picked
/// row with the `❯`.
AgentsLayout agentsLayout(
  List<AgentRow> rows, {
  required int limit,
  required int width,
  required bool focused,
  required num now,
  AgentsView? view,
}) {
  // Widths over every row, drawn or not, so scrolling never moves a column.
  final laid = _laidRows(rows, width: width, focused: focused, now: now);
  final room = math.max(1, limit);
  final total = _heights(laid);

  if (total <= room) {
    return AgentsLayout(
      rows: [for (final row in laid) _whole(row)],
      more: 0,
      top: 0,
    );
  }

  final at = math.max(0, rows.indexWhere((row) => row.picked));
  final atLaid = at < laid.length ? laid[at] : null;
  final isTall = focused && atLaid != null && _tall(atLaid.height, total, room);
  // Read on by line from a tall row onto one that fits, as [enteredView]
  // gives it a window.
  final readOn =
      focused &&
      !isTall &&
      atLaid != null &&
      view != null &&
      view.key == atLaid.row.key &&
      view.width == width &&
      view.limit == room;

  if (isTall || readOn) {
    // Read by line: a window of the list's lines, no `… +N more`.
    final top = isTall
        ? _windowTop(laid, at, room, width, view)
        : _wholeTop(laid, at, room, view!.top);
    final bottom = top + room;
    final shown = <ShownRow>[];
    var first = 0;
    for (final row in laid) {
      final from = first;
      first += row.height;
      final lines = <ShownLine>[
        for (var line = 0; line < row.height; line++)
          if (from + line >= top && from + line < bottom)
            (
              at: line,
              gutter: line == 0 && row.row.picked
                  ? row.mark
                  : from + line == top && top > 0
                  ? '↑ '
                  : from + line == bottom - 1 && bottom < total
                  ? '↓ '
                  : '  ',
            ),
      ];
      if (lines.isNotEmpty) shown.add(ShownRow(row, lines));
    }
    return AgentsLayout(rows: shown, more: 0, top: top);
  }

  // A line for `… +N more`, but after the last row; the rest from the
  // first, or, while the list has the keys, from where the picked row is
  // the last that fits. A row that cannot fit whole, taller than the list
  // or the first, shows the lines left, `↓` beside its last.
  final budget = math.max(1, room - 1);
  List<ShownRow> fitting(int from) {
    final shown = <ShownRow>[];
    var used = 0;
    for (final row in laid.skip(from)) {
      // The last row takes the `… +N more` line where no row is hidden.
      final left =
          (identical(row, laid.last) && from == 0 ? room : budget) - used;
      if (row.height <= left) {
        shown.add(_whole(row));
        used += row.height;
        continue;
      }
      if (left > 0 && (shown.isEmpty || row.height > room)) {
        shown.add(
          ShownRow(row, [
            for (var line = 0; line < left; line++)
              (
                at: line,
                // The `❯` before the `↓` on a row with one line in sight.
                gutter: line == 0 && row.mark != '  '
                    ? row.mark
                    : line == left - 1
                    ? '↓ '
                    : '  ',
              ),
          ]),
        );
      }
      break;
    }
    return shown;
  }

  var start = 0;
  if (focused) {
    while (start < at && start + fitting(start).length <= at) {
      start += 1;
    }
  }
  final shown = fitting(start);
  return AgentsLayout(
    rows: shown,
    more: rows.length - shown.length,
    top: _heights(laid.take(start)),
  );
}

/// `↑ ↓` in the list on a picked row taller than it: the window a line on
/// while the row has lines that way out of sight; none where it has not,
/// and the pick moves as [moveListFocus] says.
AgentsView? scrolledView(
  List<AgentRow> rows,
  int by, {
  required int limit,
  required int width,
  required num now,
  required AgentsView? view,
}) {
  final laid = _laidRows(rows, width: width, focused: true, now: now);
  final at = rows.indexWhere((row) => row.picked);
  final room = math.max(1, limit);
  final total = _heights(laid);
  if (at < 0 || !_tall(laid[at].height, total, room)) return null;
  final top = _windowTop(laid, at, room, width, view);
  final first = _heights(laid.take(at));
  final key = rows[at].key;
  if (by > 0 && first + laid[at].height > top + room) {
    return AgentsView(key: key, width: width, limit: room, top: top + 1);
  }
  if (by < 0 && first < top) {
    return AgentsView(key: key, width: width, limit: room, top: top - 1);
  }
  return null;
}

/// The window on a row just picked, where it is taller than the list:
/// moved the least from [top], where the list was, that brings its first
/// line into sight. None for a row that fits, unless the list was
/// [reading] by line, when a row that fits is read on that way.
AgentsView? enteredView(
  List<AgentRow> rows,
  int top, {
  required int limit,
  required int width,
  required num now,
  bool reading = false,
}) {
  final laid = _laidRows(rows, width: width, focused: true, now: now);
  final at = rows.indexWhere((row) => row.picked);
  final room = math.max(1, limit);
  final total = _heights(laid);
  if (at < 0 || total <= room) return null;
  final key = rows[at].key;
  if (!_tall(laid[at].height, total, room)) {
    // Read on from a window by line: the least move brings it whole into
    // sight, the rows above kept as far as they fit.
    return reading
        ? AgentsView(
            key: key,
            width: width,
            limit: room,
            top: _wholeTop(laid, at, room, top),
          )
        : null;
  }
  final first = _heights(laid.take(at));
  return AgentsView(
    key: key,
    width: width,
    limit: room,
    top: math.min(first, math.max(first - room + 1, top)),
  );
}

/// What the status line's right side takes beside the hint.
const _rightRoom = 40;

/// The status line's hint while the summary line has the `❯`, shorter
/// where the line has not the room.
String summaryHint(int width) {
  const full = '↑ ↓ to move · enter to open · esc to go back';
  return cellWidth(full) + _rightRoom <= width
      ? full
      : '↑ ↓ move · enter open · esc back';
}

/// The status line's hint while the list has the keys, as a picker's last
/// line says what its keys do; shortened where the full one does not fit.
/// [close] is the key that closes a child; none where none is bound.
String agentsHint(int width, String? close) {
  final full = [
    '↑ ↓ to pick',
    'enter to write to it',
    if (close != null) '$close to close',
    'esc to go back',
  ].join(' · ');
  // Room left for the model and the context beside it, as the status line
  // keeps them; at 80 columns that takes the short words.
  return cellWidth(full) + _rightRoom <= width
      ? full
      : [
          '↑ ↓ pick',
          'enter write',
          if (close != null) '$close close',
          'esc back',
        ].join(' · ');
}

/// The line that stands in a child's transcript where the startup header
/// would: `parser · codex · gpt-5.3-codex · opened by main 4m ago`; a
/// team's lead's says `team` and a member's names its run, each opened by
/// an agent that `send_message` reaches by that name: `tester · claude ·
/// Sonnet · bugfix's member · opened by @bugfix 6m ago`; a fork's says what
/// it was forked from: `fork · claude · Opus · forked from main 2m ago`.
/// [name] is drawn apart from the [rest], in its colour.
({String name, String rest}) childLine({
  required String name,
  required String runtime,
  required num openedAt,
  String? forkedFrom,
  String? team,
  String? leadName,
  required String? model,
  required num now,
}) {
  final ago = _briefly(math.max(0, now - openedAt));
  final inTeam = team != null;
  return (
    name: name,
    rest: [
      '',
      if (inTeam && leadName == null) 'team',
      runtime,
      ?model,
      if (leadName != null) "$leadName's member",
      forkedFrom != null
          ? 'forked from $forkedFrom $ago ago'
          : inTeam
          ? 'opened by @${leadName ?? 'main'} $ago ago'
          : 'opened by main $ago ago',
    ].join(' · '),
  );
}

/// [items] as English lists them: `a`, `a and b`, `a, b, and c`.
String _listed(List<String> items) => switch (items) {
  [] => '',
  [final one] => one,
  [final one, final two] => '$one and $two',
  _ => '${items.sublist(0, items.length - 1).join(', ')}, and ${items.last}',
};

/// The note a resumed session's transcript closes with when long-lived
/// agents were open as it was left: `parser (codex) and docs (claude) were
/// open when this session was left and are not reopened · /resume lists
/// them`; a team's run as `team bugfix (3 agents)`, with how to start the
/// team again.
String leftOpenLine(List<LeftOpen> agents) {
  final names = _listed([
    for (final agent in agents)
      if (agent.team == null)
        '${agent.name} (${agent.runtime})'
      else
        'team ${agent.name} (${agent.agents ?? 1} '
            '${(agent.agents ?? 1) == 1 ? 'agent' : 'agents'})',
  ]);
  final teams = {for (final agent in agents) ?agent.team}.toList();
  final left = agents.length == 1
      ? 'was open when this session was left and is not reopened'
      : 'were open when this session was left and are not reopened';
  // A run is its lead and its members, each a session /resume lists.
  final listed = agents.length == 1 && teams.isEmpty ? 'it' : 'them';
  final back = teams.isEmpty
      ? ''
      : ' · ${_listed([for (final team in teams) '/team run $team'])} '
            '${teams.length == 1 ? 'starts the team again' : 'start the teams again'}';
  return '$names $left · /resume lists $listed$back';
}

/// How many lines the list takes drawn in [limit] lines: the lines of its
/// rows in sight and its `… +N more`. What the window gives it before a
/// short window takes rows back, and the least it keeps.
int agentsLines(
  List<AgentRow> rows, {
  required int limit,
  required int width,
  required bool focused,
  required num now,
  AgentsView? view,
}) {
  if (rows.isEmpty) return 0;
  final layout = agentsLayout(
    rows,
    limit: limit,
    width: width,
    focused: focused,
    now: now,
    view: view,
  );
  return layout.rows.fold(0, (sum, row) => sum + row.lines.length) +
      (layout.more > 0 ? 1 : 0);
}

/// What ↑ or ↓ in the list does: the keys back to the box, or the pick on
/// an agent, and where the list's lines start.
final class ListMove {
  /// A move that [leave]s, or picks [pick], with [view] where the list's
  /// lines start when [viewed].
  const ListMove({
    this.leave = false,
    this.summary = false,
    this.pick,
    this.view,
    this.viewed = false,
  });

  /// Above `main`: the keys go back to the box.
  final bool leave;

  /// Onto the background's summary line, which picks nothing.
  final bool summary;

  /// The agent picked now, by its key; none when the move only read on.
  final int? pick;

  /// Where the list's lines start, when [viewed]; none from the top.
  final AgentsView? view;

  /// Whether the move sets [view].
  final bool viewed;
}

/// ↑ ↓ in the list drawn in [limit] lines at [width], [view] where its
/// lines start: on a picked row taller than the list a line of it first;
/// else the pick [by] rows on, the transcript and the box following, a
/// row so tall picked coming into sight the least move from where the list
/// was; past the last agent, the background's summary line where
/// [summary] draws one; above `main`, the keys back to the box.
ListMove listMove(
  List<AgentRow> rows,
  int by, {
  required int limit,
  required int width,
  required num now,
  required AgentsView? view,
  bool summary = false,
  bool onSummary = false,
}) {
  final scrolled = onSummary
      ? null
      : scrolledView(
          rows,
          by,
          limit: limit,
          width: width,
          now: now,
          view: view,
        );
  if (scrolled != null) return ListMove(view: scrolled, viewed: true);
  final top = agentsLayout(
    rows,
    limit: limit,
    width: width,
    focused: true,
    now: now,
    view: view,
  ).top;
  final int target;
  switch (moveListTarget(rows, by, summary: summary, onSummary: onSummary)) {
    case null:
      return const ListMove(leave: true);
    case ListSummary():
      return const ListMove(summary: true, viewed: true);
    case ListAgent(:final key):
      target = key;
  }
  // The last stays the last: where ↓ leaves the pick on the row it was on,
  // the window stays where that row was read to.
  final stays =
      !onSummary && rows.any((row) => row.picked && row.key == target);
  if (stays) return ListMove(pick: target);
  return ListMove(
    pick: target,
    viewed: true,
    view: enteredView(
      [
        for (final row in rows)
          AgentRow(
            key: row.key,
            name: row.name,
            runtime: row.runtime,
            wait: row.wait,
            model: row.model,
            effort: row.effort,
            colour: row.colour,
            picked: row.key == target,
            failed: row.failed,
          ),
      ],
      top,
      limit: limit,
      width: width,
      now: now,
      reading: view != null,
    ),
  );
}
