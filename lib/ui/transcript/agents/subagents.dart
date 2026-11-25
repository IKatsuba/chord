/// What a subagent reads as in its parent's transcript, kept out of the
/// widgets, from the original's `ui/transcript/agents/subagents.ts`: a block
/// shaped like a tool call, `Agent(<title>)`, with the latest few calls of
/// its work under `⎿` while it runs and how it ended once it has; subagents
/// spawned back to back as one `Running N agents…` tree; the row a child's
/// permission prompt opens with; and the status line's words for subagents
/// that outlive their turn. chord's own task agents read as subagents too,
/// their runtime, model and effort after the title, their spend at the end.
library;

import 'package:characters/characters.dart';
import 'package:chord_tui/chord_tui.dart' show Style, TextSpan, cellWidth;

import '../../../acp/schema.dart' as acp;
import '../../../session/elapsed.dart';
import '../../../notify.dart' show AskingWait;
import '../../../session/transcript/subagents.dart'
    show findSubagent, subagentPath;
import '../../../session/transcript/types.dart';
import '../reports.dart' show formatCost;
import '../spend.dart' show tokensIn;
import '../tools/tools.dart';

/// The subagents drawn together from `entries[index]` on: every subagent
/// from there up to the first entry that is not one. Empty for a subagent
/// a group starting further up already holds; null for an entry that is not
/// a subagent.
List<Subagent>? agentGroup(List<Entry> entries, int index) {
  if (index >= entries.length) return null;
  final first = entries[index];
  if (first is! SubagentEntry) return null;
  // Task agents and the runtime's own subagents never share a group: they
  // come from different places.
  final task = first.subagent.task != null;
  bool sameKind(Entry entry) =>
      entry is SubagentEntry && (entry.subagent.task != null) == task;
  bool hidden(Entry entry) =>
      entry is ToolEntry && guardianView(entry.call) == GuardianView.hidden;
  var before = index - 1;
  while (before >= 0 && hidden(entries[before])) {
    before--;
  }
  if (before >= 0 && sameKind(entries[before])) return const [];
  final group = <Subagent>[];
  for (var at = index; at < entries.length; at++) {
    final entry = entries[at];
    if (hidden(entry)) continue;
    if (entry is! SubagentEntry || !sameKind(entry)) break;
    group.add(entry.subagent);
  }
  return group;
}

/// One block of a subagent's work as ctrl+o draws it.
sealed class WorkItem {
  const WorkItem();
}

/// An entry of its own.
final class WorkEntry extends WorkItem {
  const WorkEntry(this.entry);
  final Entry entry;
}

/// A group of its subagents.
final class WorkAgents extends WorkItem {
  const WorkAgents(this.agents);
  final List<Subagent> agents;
}

/// Its plan, where it first came.
final class WorkPlan extends WorkItem {
  const WorkPlan(this.entries);
  final List<acp.PlanEntry> entries;
}

/// [subagent]'s work in order, its plan drawn once where it first came.
List<WorkItem> workOf(Subagent subagent) {
  final Subagent(:entries, :plan, :planAt) = subagent;
  if (plan.isEmpty || planAt == null) return _grouped(entries);
  // Subagents spawned on both sides of the plan are two groups, not one.
  return [
    ..._grouped(entries.sublist(0, planAt)),
    WorkPlan(plan),
    ..._grouped(entries.sublist(planAt)),
  ];
}

List<WorkItem> _grouped(List<Entry> entries) {
  final visible = [
    for (final entry in entries)
      if (entry is! ToolEntry ||
          guardianView(entry.call) != GuardianView.hidden)
        entry,
  ];
  return [
    for (final (index, entry) in visible.indexed)
      switch (agentGroup(visible, index)) {
        null => WorkEntry(entry),
        final group when group.isEmpty => null,
        final group => WorkAgents(group),
      },
  ].nonNulls.toList();
}

/// `Agent(<title>)`: the headline a subagent reads as, wherever it is
/// named; a task agent's says its runtime, model and effort after, dim, the
/// one thing that tells it apart. [full] false leaves the model and effort
/// out, as the row a task's box opens with names it.
Headline agentHeadline(Subagent subagent, {bool full = true}) {
  final title = subagent.title?.trim();
  final arg = title == null || title.isEmpty ? null : title;
  final task = subagent.task;
  if (task == null) return Headline('Agent', arg: arg);
  // What the task never reported is left out, not shown empty.
  final parts = [
    task.runtime,
    if (full && task.model != null && task.model!.isNotEmpty) task.model!,
    if (full && task.effort != null && task.effort!.isNotEmpty) task.effort!,
  ];
  return Headline('Agent', arg: arg, note: ' · ${parts.join(' · ')}');
}

/// The tools a subagent used: its tool calls and the subagents it started,
/// each of which counts as one.
int toolUses(Subagent subagent) => subagent.entries
    .where(
      (entry) =>
          entry is SubagentEntry ||
          (entry is ToolEntry &&
              guardianView(entry.call) == GuardianView.block),
    )
    .length;

String _uses(int count) => '$count ${count == 1 ? 'tool use' : 'tool uses'}';

/// How long it ran, from its spawn to its ending, once both were timed.
String? ranFor(Subagent subagent) {
  final Subagent(:startedAt, :endedAt) = subagent;
  return startedAt == null || endedAt == null
      ? null
      : formatElapsed(endedAt - startedAt);
}

/// What a subagent did, as its block and its group row say it: its tool
/// uses, unless a task's work was lost with its record, a task's tokens and
/// money once it has ended, and how long it ran.
String _countsOf(Subagent subagent) {
  final task = subagent.task;
  final spent = spentParts(task?.spent);
  return [
    if (task == null || !task.workLost) _uses(toolUses(subagent)),
    ?spent.tokens,
    ?spent.money,
    ?ranFor(subagent),
  ].join(' · ');
}

/// A task's spend as its ended block says it, as Claude Code's task line
/// does with money added: `2.0k tokens · $0.0125`, the cost `~$…` when
/// chord worked it out, and what its agent did not report left out.
({String? tokens, String? money}) spentParts(TaskSpent? spent) {
  final count = tokensIn(spent?.tokens);
  final cost = spent?.cost;
  return (
    tokens: count == null ? null : '${shortCount(count)} tokens',
    money: cost == null
        ? null
        : '${spent!.estimated ? '~' : ''}${formatCost(cost)}',
  );
}

/// `850`, `2.0k`, `12.4k`, `1.2M`, as Claude Code counts tokens.
String shortCount(num count) => count < 1000
    ? '$count'
    : count < 1000000
    ? '${(count / 1000).toStringAsFixed(1)}k'
    : '${(count / 1000000).toStringAsFixed(1)}M';

/// The block's marker: as a call's while it runs, then as it ended.
Tone agentTone(SubagentState state) => switch (state) {
  SubagentState.running => Tone.running,
  SubagentState.completed => Tone.done,
  SubagentState.failed || SubagentState.disconnected => Tone.failed,
  // Dim, as the person stopped it, or as nothing says it failed.
  SubagentState.cancelled ||
  SubagentState.ended ||
  SubagentState.untracked => Tone.pending,
};

/// A word for how it ended, so its colour is never the only signal.
typedef Ending = ({String word, bool failed});

/// How [state] ended; none while it runs.
Ending? endingOf(SubagentState state) => switch (state) {
  SubagentState.running => null,
  SubagentState.completed => (word: 'Done', failed: false),
  SubagentState.failed => (word: 'Failed', failed: true),
  SubagentState.cancelled => (word: 'Cancelled', failed: false),
  SubagentState.disconnected => (word: 'Disconnected', failed: true),
  SubagentState.ended => (word: 'Ended', failed: false),
  SubagentState.untracked => (word: 'Untracked', failed: false),
};

/// The line ctrl+o's view gives under an ending, saying what its word
/// cannot: a failure's message, or why an end claims no cause.
({String text, bool failed})? endNote(
  Subagent subagent,
) => switch (subagent.state) {
  SubagentState.failed when subagent.error != null => (
    text: subagent.error!,
    failed: true,
  ),
  SubagentState.untracked => (
    text: 'The agent no longer reports this subagent; it may still be at work.',
    failed: false,
  ),
  SubagentState.ended => (
    text: 'The agent did not say how it ended.',
    failed: false,
  ),
  _ => null,
};

/// Said after the call a permission request on screen is about.
const waitingNote = ' · waiting for permission';

/// Where an open task's work would be once its record has gone, so an
/// empty block never reads as a task that did nothing.
const workLostNote = "Its work was not kept: the task's record is gone.";

/// One line of a subagent's work: a call it made, or a subagent it started.
final class WorkLine {
  const WorkLine(
    this.headline, {
    this.failed = false,
    this.waiting = false,
    this.reviewing = false,
  });
  final Headline headline;
  final bool failed;

  /// A permission request for it is on screen now.
  final bool waiting;

  /// Guardian's in-progress row has no call headline or marker.
  final bool reviewing;
}

List<WorkLine> _workLines(Subagent subagent, List<PermissionWait> waits) => [
  for (final entry in subagent.entries)
    ...switch (entry) {
      ToolEntry(:final call) => switch (guardianView(call)) {
        GuardianView.hidden => const <WorkLine>[],
        GuardianView.reviewing => [
          const WorkLine(Headline(guardianReviewing), reviewing: true),
        ],
        GuardianView.block => [
          WorkLine(
            firstLine(headline(call)),
            failed: toneOf(call) == Tone.failed,
            waiting: waits.any(
              (wait) =>
                  wait.subagentId == subagent.id && wait.toolCallId == call.id,
            ),
          ),
        ],
      },
      SubagentEntry(subagent: final child) => [
        WorkLine(
          agentHeadline(child),
          failed: endingOf(child.state)?.failed ?? false,
        ),
      ],
      _ => const <WorkLine>[],
    },
];

/// What hangs under a single block's `⎿`, folded.
sealed class BlockFold {
  const BlockFold();
}

/// Running: its latest calls, oldest first, and how many came before.
final class FoldWork extends BlockFold {
  const FoldWork(this.lines, this.more);
  final List<WorkLine> lines;
  final int more;
}

/// Running, with no call made yet.
final class FoldStarting extends BlockFold {
  const FoldStarting();
}

/// Ended: `Done (6 tool uses · 41s)`.
final class FoldEnded extends BlockFold {
  const FoldEnded(this.text, {required this.failed});
  final String text;
  final bool failed;
}

/// A lone subagent's block folded: while it runs, the headlines of its
/// latest three calls; once it has ended, one line of how, with what it did
/// and how long it took.
BlockFold blockFold(Subagent subagent, List<PermissionWait> waits) {
  if (endingOf(subagent.state) case final ending?) {
    final said = _countsOf(subagent);
    return FoldEnded(
      said.isEmpty ? ending.word : '${ending.word} ($said)',
      failed: ending.failed,
    );
  }
  final lines = _workLines(subagent, waits);
  if (lines.isEmpty) return const FoldStarting();
  final shown = lines.length > summaryLines
      ? lines.sublist(lines.length - summaryLines)
      : lines;
  final before = lines.length > summaryLines
      ? lines.sublist(0, lines.length - summaryLines)
      : const <WorkLine>[];
  return FoldWork(shown, before.where((line) => !line.reviewing).length);
}

/// The ending a block's last line says in ctrl+o's view, or none yet.
FoldEnded? endedLine(Subagent subagent) => switch (blockFold(subagent, [])) {
  final FoldEnded ended => ended,
  _ => null,
};

/// The group's first row and its marker: running while any child runs,
/// then finished when all are done, or ended with what went wrong, worst
/// first.
({String text, Tone tone}) groupHeader(List<Subagent> agents) {
  final count = agents.length;
  if (agents.any((agent) => agent.state == SubagentState.running)) {
    return (text: 'Running $count agents…', tone: Tone.running);
  }
  if (agents.every((agent) => agent.state == SubagentState.completed)) {
    return (text: '$count agents finished', tone: Tone.done);
  }
  final wrong = [
    for (final state in const [
      SubagentState.failed,
      SubagentState.disconnected,
      SubagentState.untracked,
      SubagentState.ended,
      SubagentState.cancelled,
    ])
      if (agents.where((agent) => agent.state == state).length case final n
          when n > 0)
        (state: state, count: n),
  ];
  return (
    text:
        '$count agents ended · ${wrong.map((w) => '${w.count} ${w.state.name}').join(', ')}',
    tone:
        wrong.any(
          (w) =>
              w.state == SubagentState.failed ||
              w.state == SubagentState.disconnected,
        )
        ? Tone.failed
        : Tone.pending,
  );
}

/// How a run of a group row is drawn.
enum RunStyle { bold, dim, plain }

/// A run of a group row's line, styled as a call's headline is drawn.
final class RowRun {
  const RowRun(this.text, this.style, {this.counts = false});
  final String text;
  final RunStyle style;

  /// chord's counts after the title, which a selection leaves out.
  final bool counts;

  @override
  bool operator ==(Object other) =>
      other is RowRun &&
      other.text == text &&
      other.style == style &&
      other.counts == counts;

  @override
  int get hashCode => Object.hash(text, style, counts);

  @override
  String toString() => '${style.name}${counts ? '+' : ''}:$text';
}

typedef _Word = List<RowRun>;

int _wordWidth(_Word word) =>
    word.fold(0, (all, run) => all + cellWidth(run.text));

String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// [word] in lines of at most [width] cells, a grapheme never split.
List<List<RowRun>> _broken(_Word word, int width) {
  final lines = <List<RowRun>>[[]];
  var used = 0;
  for (final run in word) {
    for (final char in run.text.characters) {
      final cells = cellWidth(char);
      if (used + cells > width && used > 0) {
        lines.add([]);
        used = 0;
      }
      final line = lines.last;
      final last = line.isEmpty ? null : line.last;
      if (last != null &&
          last.style == run.style &&
          last.counts == run.counts) {
        line[line.length - 1] = RowRun(
          last.text + char,
          last.style,
          counts: last.counts,
        );
      } else {
        line.add(RowRun(char, run.style, counts: run.counts));
      }
      used += cells;
    }
  }
  return lines;
}

/// [text] wrapped at its spaces to [width], trimmed, as wrap-ansi does.
List<String> _wrapWords(String text, int width) {
  final lines = <String>[];
  var line = '';
  for (final word in text.split(' ').where((w) => w.isNotEmpty)) {
    if (line.isEmpty) {
      line = word;
    } else if (cellWidth(line) + 1 + cellWidth(word) <= width) {
      line = '$line $word';
    } else {
      lines.add(line);
      line = word;
    }
  }
  return [...lines, line];
}

/// The runs of a group row's line that are [counts] or are not, as one
/// span: the title selects, chord's counts after it do not.
TextSpan rowSpan(List<RowRun> runs, {required bool counts}) => TextSpan(
  '',
  children: [
    for (final run in runs)
      if (run.counts == counts)
        TextSpan(
          run.text,
          style: switch (run.style) {
            RunStyle.bold => Style.bold,
            RunStyle.dim => Style.dim,
            RunStyle.plain => null,
          },
        ),
  ],
);

/// A child's row in a group, laid out for [width] cells: `Agent(<title>)`,
/// its task's runtime and model, then what it did and, once it has ended,
/// how long it took. Nothing is cut: a row that does not fit wraps after a
/// ` · ` where it can, inside the title at its spaces where it must, and
/// inside a word only where that word alone is wider.
List<List<RowRun>> groupRow(Subagent subagent, int width) {
  final head = agentHeadline(subagent);
  final arg = head.arg == null ? null : _oneLine(head.arg!);
  // Shown on lines of their own making: a model's line breaks and tabs are
  // spaces here, as a title's are.
  final note = head.note == null
      ? null
      : _oneLine(head.note!.replaceFirst(RegExp(r'^ · '), ''));
  final said = _oneLine(_countsOf(subagent));
  // What follows the title, each part whole where it fits: its task's
  // runtime and model, then chord's counts.
  final noted = note == null ? const <String>[] : note.split(' · ');
  final parts = [...noted, if (said.isNotEmpty) ...said.split(' · ')];
  final titled = (arg ?? '').split(' ');
  final words = <_Word>[
    if (arg == null)
      [RowRun(head.name, RunStyle.bold)]
    else
      for (final (at, each) in titled.indexed)
        [
          if (at == 0) ...[
            RowRun(head.name, RunStyle.bold),
            const RowRun('(', RunStyle.plain),
          ],
          RowRun(each, RunStyle.plain),
          if (at == titled.length - 1) const RowRun(')', RunStyle.plain),
        ],
  ];
  final room = width < 1 ? 1 : width;
  final lines = <List<RowRun>>[];
  var line = <RowRun>[];
  var used = 0;
  void start(_Word word) {
    final pieces = _wordWidth(word) <= room
        ? [
            [...word],
          ]
        : word.length == 1
        ? [
            for (final text in _wrapWords(word.single.text, room))
              ..._broken([
                RowRun(text, word.single.style, counts: word.single.counts),
              ], room),
          ]
        : _broken(word, room);
    lines.addAll(pieces.take(pieces.length - 1));
    line = pieces.last;
    used = _wordWidth(line);
  }

  for (final word in words) {
    if (line.isEmpty) {
      start(word);
    } else if (used + 1 + _wordWidth(word) <= room) {
      line.addAll([const RowRun(' ', RunStyle.plain), ...word]);
      used += 1 + _wordWidth(word);
    } else {
      lines.add(line);
      start(word);
    }
  }
  for (final (at, part) in parts.indexed) {
    // A count, and the `·` before it, is chord's.
    final counts = at >= noted.length;
    final word = [RowRun(part, RunStyle.dim, counts: counts)];
    if (used + 3 + _wordWidth(word) <= room) {
      line.add(RowRun(' · $part', RunStyle.dim, counts: counts));
      used += 3 + _wordWidth(word);
    } else if (used + 2 <= room) {
      // Broken after its `·`, the next part starting the next line.
      line.add(RowRun(' ·', RunStyle.dim, counts: counts));
      lines.add(line);
      start(word);
    } else {
      lines.add(line);
      start([RowRun('· $part', RunStyle.dim, counts: counts)]);
    }
  }
  // Each line's runs of one style as one.
  return [
    for (final runs in [...lines, line])
      runs.fold<List<RowRun>>([], (merged, run) {
        final last = merged.isEmpty ? null : merged.last;
        if (last != null &&
            last.style == run.style &&
            last.counts == run.counts) {
          merged[merged.length - 1] = RowRun(
            last.text + run.text,
            last.style,
            counts: last.counts,
          );
        } else {
          merged.add(run);
        }
        return merged;
      }),
  ];
}

/// The line under a child's row in a group.
sealed class RowLine {
  const RowLine();
}

/// Its current call, the one a permission request waits on first.
final class RowCall extends RowLine {
  const RowCall(this.line);
  final WorkLine line;
}

/// Before its first call.
final class RowStarting extends RowLine {
  const RowStarting();
}

/// Once it has ended, how.
final class RowEnded extends RowLine {
  const RowEnded(this.ending);
  final Ending ending;
}

/// The line under [subagent]'s row in a group.
RowLine rowLine(Subagent subagent, List<PermissionWait> waits) {
  if (endingOf(subagent.state) case final ending?) return RowEnded(ending);
  final lines = _workLines(subagent, waits);
  final line =
      lines.where((line) => line.waiting).firstOrNull ?? lines.lastOrNull;
  return line == null ? const RowStarting() : RowCall(line);
}

/// A piece of the row a child's permission prompt opens with.
typedef AskerPiece = ({String text, bool bold});

/// `Agent(<child>) › Agent(<grandchild>) asks`: who a permission request
/// comes from, the way down to it from the session, whole; a task by its
/// runtime too, `Agent(Fix the tokenizer) · fake asks`. None when the
/// session's own agent asks.
List<AskerPiece> askerRow(List<Subagent> path) {
  if (path.isEmpty) return const [];
  return [
    for (final (index, subagent) in path.indexed)
      if (agentHeadline(subagent, full: false) case Headline(
        :final name,
        :final arg,
        :final note,
      )) ...[
        if (index > 0) (text: ' › ', bold: false),
        (text: name, bold: true),
        if (arg != null) (text: '($arg)', bold: false),
        if (note != null) (text: note, bold: false),
      ],
    (text: ' asks', bold: false),
  ];
}

/// The task whose request [on] is, among a session's [entries], by the
/// name its box gives it, `Agent(Fix the tokenizer) · fake`; none when
/// the session's agent or a subagent of its own, not a task, asks.
String? taskAsking(List<Entry> entries, AskingWait? on) {
  final id = on?.subagentId;
  if (id == null) return null;
  final path = subagentPath(entries, id);
  if (path.isEmpty || path.last.task == null) return null;
  final pieces = askerRow(path);
  // The row's own ` asks` is the notice's verb's to say.
  return pieces.take(pieces.length - 1).map((piece) => piece.text).join();
}

/// The subagents a call's content refers to by `{type: "session"}`, in the
/// order sent, each once; one not drawn is left out.
List<Subagent> linkedSubagents(
  List<Map<String, Object?>> content,
  List<Entry> entries,
) {
  final seen = <String>{};
  return [
    for (final item in content)
      if (item['type'] == 'session' &&
          item['sessionId'] is String &&
          seen.add(item['sessionId'] as String))
        ?findSubagent(entries, item['sessionId'] as String),
  ];
}

/// The status line's words once the turn has ended with subagents still at
/// work; none when none is.
String? stillRunning(int count) => count == 0
    ? null
    : '$count ${count == 1 ? 'agent' : 'agents'} still running';

/// A subagent's task as its open view shows it: its prompt, else its
/// description; null when it has neither.
String? taskOf(Subagent subagent) {
  final task = (subagent.prompt ?? subagent.description)?.trim();
  return task == null || task.isEmpty ? null : task;
}
