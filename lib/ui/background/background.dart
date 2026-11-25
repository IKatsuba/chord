/// The background of the session, kept out of the widgets: every monitor
/// and `spawn_task` task its agents run, and every subagent of theirs that
/// can be stopped alone, as items in start order, and the summary line under
/// the agents list that counts them by state, wrapped between its groups
/// and never cut. From the original's `ui/background/background.ts`.
library;

import 'package:chord_tui/chord_tui.dart'
    show SelectionSource, cellWidth, selectionSourceRowOf;

import '../../session/monitors.dart';
import '../../session/transcript/subagents.dart'
    show agentItemName, isAgentItem;
import '../../session/transcript/types.dart';
import '../transcript/agents/subagents.dart' show agentGroup;

/// What an item is, in the order the summary line names them.
enum BackgroundKind {
  monitor('monitor', 'monitors'),
  task('task', 'tasks'),
  agent('agent', 'agents');

  const BackgroundKind(this.one, this.many);

  /// The word for one, and for more.
  final String one, many;
}

/// Where an item stands, as the summary line groups them, most urgent
/// first, each with the glyph it is marked by.
enum BackgroundGroup {
  // As the agents list's glyphs (ui/agents/glyphs.dart) mark them.
  asking('●'),
  failed('✗'),
  untracked('?'),
  running(null),
  done('✓'),
  stopped('■');

  const BackgroundGroup(this.glyph);

  /// The glyph before its group on the summary line; none for running.
  final String? glyph;
}

/// What an asking item asks for: a permission or a form chord holds, or,
/// for an agent, nothing of its that reaches the person.
enum AskingOn { permission, input, waiting }

/// An agent's end that its group does not word: no cause seen, or its
/// agent gone, said in its detail.
enum EndWord { ended, disconnected }

/// An item's state: at work, asking the person, or ended and how.
sealed class ItemStatus {
  const ItemStatus();

  /// Its group on the summary line.
  BackgroundGroup get group;
}

/// At work; [stopping], an agent the person stopped, until its agent says
/// it ended.
final class ItemRunning extends ItemStatus {
  const ItemRunning({this.stopping = false});

  final bool stopping;

  @override
  BackgroundGroup get group => BackgroundGroup.running;

  @override
  bool operator ==(Object other) =>
      other is ItemRunning && other.stopping == stopping;

  @override
  int get hashCode => stopping.hashCode;
}

/// Asking the person [on], since [since], epoch milliseconds.
final class ItemAsking extends ItemStatus {
  const ItemAsking(this.on, this.since);

  final AskingOn on;
  final num since;

  @override
  BackgroundGroup get group => BackgroundGroup.asking;

  @override
  bool operator ==(Object other) =>
      other is ItemAsking && other.on == on && other.since == since;

  @override
  int get hashCode => Object.hash(on, since);
}

/// Ended, in [group], at [endedAt], which its time stands still at, or,
/// untracked, an agent its agent lost sight of, which a later state takes
/// back; a monitor's [end], which its row words; an agent's [word].
final class ItemEnded extends ItemStatus {
  const ItemEnded(this.group, this.endedAt, {this.end, this.word})
    : assert(
        group != BackgroundGroup.running && group != BackgroundGroup.asking,
      );

  @override
  final BackgroundGroup group;
  final num endedAt;
  final MonitorEnd? end;
  final EndWord? word;

  @override
  bool operator ==(Object other) =>
      other is ItemEnded &&
      other.group == group &&
      other.endedAt == endedAt &&
      other.end == end &&
      other.word == word;

  @override
  int get hashCode => Object.hash(group, endedAt, end, word);
}

/// Whose an item is: a child's name and colour; none for `main`.
typedef ItemOwner = ({String name, int colour});

/// One monitor or task of the session's agents.
final class BackgroundItem {
  const BackgroundItem({
    required this.kind,
    required this.id,
    required this.key,
    required this.name,
    required this.startedAt,
    required this.status,
    this.owner,
    this.events,
    this.command,
    this.timeoutMs,
    this.lastEvent,
    this.runtime,
    this.model,
    this.callId,
    this.stoppable = false,
    this.parent,
    this.parentAt,
  });

  final BackgroundKind kind;

  /// Its id in its owner's session: a monitor's `m1`, a task's own.
  final String id;

  /// Its owner's session key.
  final int key;
  final ItemOwner? owner;

  /// A monitor's description, a task's title.
  final String name;

  /// When it started, epoch milliseconds.
  final num startedAt;
  final ItemStatus status;

  /// A monitor's batches handed on so far.
  final int? events;

  /// A monitor's command, its timeout and its last batch.
  final String? command;
  final int? timeoutMs;
  final MonitorEvent? lastEvent;

  /// A task's runtime and model, as the agents list names an agent's.
  final String? runtime, model;

  /// A task's `spawn_task` call, which `enter` scrolls to.
  final String? callId;

  /// An agent's own stop: its agent still offers one.
  final bool stoppable;

  /// An agent item's: the listed agent whose transcript announced it, by
  /// the name the agents list gives it, `main` or a child's.
  final String? parent;

  /// Its parent's place in the agents list, which orders the parents.
  final int? parentAt;
}

/// One agent of the session, as its items are read from its own.
final class BackgroundAgent {
  const BackgroundAgent({
    required this.key,
    this.owner,
    this.since,
    this.monitors = const [],
    this.endedMonitors = const [],
    this.transcript = Transcript.empty,
    this.stopping = const {},
  });

  final int key;
  final ItemOwner? owner;

  /// When its session came up; a task from before is its past, not an
  /// item; none while it is not up, when nothing of it counts.
  final num? since;
  final List<RunningMonitor> monitors;
  final List<EndedMonitor> endedMonitors;
  final Transcript transcript;

  /// Its agent items the person stopped, by id, that have not ended yet.
  final Set<String> stopping;
}

/// The session's items, oldest first, each keeping its place as it changes:
/// the running, asking and untracked ones, as every kind leaves once it
/// ends; and
/// [keep], the item whose detail is open, ended or not, until the person
/// leaves it. Two that started in the same millisecond keep the order of
/// their agents, then of each agent's monitors by id and tasks as its
/// transcript has them, which no change of state moves.
List<BackgroundItem> backgroundItems(
  List<BackgroundAgent> agents, {
  ({int key, String id})? keep,
}) {
  final items = [
    for (final (at, agent) in agents.indexed) ...[
      ..._monitorItems(agent),
      ..._taskItems(agent),
      ..._agentItems(agent, at),
    ],
  ];
  final kept = [
    for (final item in items)
      if ((keep != null && item.key == keep.key && item.id == keep.id) ||
          !leavesList(item))
        item,
  ];
  // A stable sort, as the original's: equal starts keep their order.
  return _stableSort(
    kept,
    compare: (a, b) => a.startedAt.compareTo(b.startedAt),
  );
}

List<BackgroundItem> _stableSort(
  List<BackgroundItem> items, {
  required int Function(BackgroundItem, BackgroundItem) compare,
}) {
  final indexed = [...items.indexed]
    ..sort((a, b) {
      final by = compare(a.$2, b.$2);
      return by != 0 ? by : a.$1.compareTo(b.$1);
    });
  return [for (final (_, item) in indexed) item];
}

List<BackgroundItem> _monitorItems(BackgroundAgent agent) {
  BackgroundItem item(RunningMonitor monitor, ItemStatus status) =>
      BackgroundItem(
        kind: BackgroundKind.monitor,
        id: monitor.info.id,
        key: agent.key,
        owner: agent.owner,
        name: monitor.info.description,
        startedAt: monitor.info.startedAt,
        status: status,
        events: monitor.events,
        command: monitor.info.command,
        timeoutMs: monitor.info.timeoutMs,
        lastEvent: monitor.lastEvent,
      );
  // In id order, which is start order, so two started in the same
  // millisecond keep their places whichever ends first.
  return [
    for (final monitor in agent.endedMonitors)
      item(
        monitor,
        ItemEnded(
          _monitorGroup(monitor.end),
          monitor.endedAt,
          end: monitor.end,
        ),
      ),
    for (final monitor in agent.monitors) item(monitor, const ItemRunning()),
  ]..sort((a, b) => _monitorNumber(a.id).compareTo(_monitorNumber(b.id)));
}

/// `m12`'s 12.
int _monitorNumber(String id) => int.tryParse(id.substring(1)) ?? 0;

/// A monitor's end as a group: exit 0 is done, a stop or its own timeout
/// stopped, else failed.
BackgroundGroup _monitorGroup(MonitorEnd end) => switch (end) {
  MonitorStopped() || MonitorTimedOut() => BackgroundGroup.stopped,
  MonitorExited(code: 0) => BackgroundGroup.done,
  _ => BackgroundGroup.failed,
};

List<BackgroundItem> _taskItems(BackgroundAgent agent) {
  final since = agent.since;
  if (since == null) return const [];
  return [
    for (final subagent in _tasksIn(agent.transcript.entries))
      if (subagent.startedAt case final startedAt? when startedAt >= since)
        BackgroundItem(
          kind: BackgroundKind.task,
          id: subagent.id,
          key: agent.key,
          owner: agent.owner,
          name: subagent.task!.name,
          startedAt: startedAt,
          status: _taskStatus(subagent, startedAt, agent.transcript),
          runtime: subagent.task!.runtime,
          model: subagent.task!.model,
          callId: subagent.callId,
        ),
  ];
}

/// Every task agent among [entries], a subagent's own included.
List<Subagent> _tasksIn(List<Entry> entries) => [
  for (final entry in entries)
    if (entry is SubagentEntry) ...[
      if (entry.subagent.task != null) entry.subagent,
      ..._tasksIn(entry.subagent.entries),
    ],
];

ItemStatus _taskStatus(
  Subagent subagent,
  num startedAt,
  Transcript transcript,
) {
  final endedAt = subagent.endedAt ?? startedAt;
  return switch (subagent.state) {
    SubagentState.running =>
      _taskAsking(subagent.id, transcript) ?? const ItemRunning(),
    SubagentState.completed => ItemEnded(BackgroundGroup.done, endedAt),
    SubagentState.cancelled => ItemEnded(BackgroundGroup.stopped, endedAt),
    SubagentState.failed ||
    SubagentState.disconnected => ItemEnded(BackgroundGroup.failed, endedAt),
    // chord's own tasks never end so: only an adapter's subagents do.
    SubagentState.ended ||
    SubagentState.untracked => ItemEnded(BackgroundGroup.stopped, endedAt),
  };
}

/// The request of task [id] the person has had longest, if one is open.
ItemStatus? _taskAsking(String id, Transcript transcript) {
  final turn = transcript.turn;
  final since = turn is AwaitingPermission ? turn.since : 0;
  final asked = [
    if (turn is AwaitingPermission)
      for (final wait in turn.permissions)
        if (wait.subagentId == id)
          ItemAsking(AskingOn.permission, wait.at ?? since),
    for (final wait in transcript.asking)
      if (wait.subagentId == id) ItemAsking(AskingOn.input, wait.at ?? 0),
  ];
  if (asked.isEmpty) return null;
  // The oldest; of two asked at once, the first listed.
  return asked.reduce((a, b) => b.since < a.since ? b : a);
}

/// Whether [item] has ended in a way that takes it off the list: an agent
/// once done, failed or stopped, a monitor, whose end its agent's
/// transcript says already, and a task, whose report or failure says it, or
/// a stop's line. Untracked, which a later state takes back, is not ended
/// and stays.
bool leavesList(BackgroundItem item) => switch (item.status.group) {
  BackgroundGroup.done ||
  BackgroundGroup.failed ||
  BackgroundGroup.stopped => true,
  BackgroundGroup.running ||
  BackgroundGroup.asking ||
  BackgroundGroup.untracked => false,
};

/// The name the agents list gives the main session's agent.
const _mainName = 'main';

/// The subagents of an agent's that are items, a subagent's own included,
/// started since its session came up. One that lost its cancel since stays
/// an item, with no stop.
List<BackgroundItem> _agentItems(BackgroundAgent agent, int at) {
  final since = agent.since;
  if (since == null) return const [];
  return [
    for (final subagent in _agentsIn(agent.transcript.entries))
      if (subagent.startedAt case final startedAt? when startedAt >= since)
        BackgroundItem(
          kind: BackgroundKind.agent,
          id: subagent.id,
          key: agent.key,
          owner: agent.owner,
          name: agentItemName(subagent),
          startedAt: startedAt,
          status: _agentStatus(
            subagent,
            startedAt,
            agent.transcript,
            agent.stopping.contains(subagent.id),
          ),
          stoppable: subagent.cancellable,
          parent: agent.owner?.name ?? _mainName,
          parentAt: at,
        ),
  ];
}

/// The ids of the agent items among [entries] the person stopped.
Set<String> stoppingIn(List<Entry> entries) => {
  for (final subagent in _agentsIn(entries))
    if (subagent.stopping) subagent.id,
};

/// Every agent item among [entries], a subagent's own included.
List<Subagent> _agentsIn(List<Entry> entries) => [
  for (final entry in entries)
    if (entry is SubagentEntry) ...[
      if (isAgentItem(entry.subagent)) entry.subagent,
      ..._agentsIn(entry.subagent.entries),
    ],
];

/// An agent item's state, as the original's CHD-2 table says it.
ItemStatus _agentStatus(
  Subagent subagent,
  num startedAt,
  Transcript transcript,
  bool stopping,
) {
  final endedAt = subagent.endedAt ?? startedAt;
  return switch (subagent.state) {
    // Stopped by the person, it reads so while its request stays up.
    SubagentState.running when stopping => const ItemRunning(stopping: true),
    SubagentState.running =>
      _taskAsking(subagent.id, transcript) ??
          (subagent.waiting == null
              ? const ItemRunning()
              : ItemAsking(
                  AskingOn.waiting,
                  subagent.waiting!.since ?? startedAt,
                )),
    SubagentState.completed => ItemEnded(BackgroundGroup.done, endedAt),
    SubagentState.failed => ItemEnded(BackgroundGroup.failed, endedAt),
    SubagentState.disconnected => ItemEnded(
      BackgroundGroup.failed,
      endedAt,
      word: EndWord.disconnected,
    ),
    SubagentState.cancelled => ItemEnded(BackgroundGroup.stopped, endedAt),
    SubagentState.ended => ItemEnded(
      BackgroundGroup.stopped,
      endedAt,
      word: EndWord.ended,
    ),
    SubagentState.untracked => ItemEnded(BackgroundGroup.untracked, endedAt),
  };
}

/// One state's group on the summary line: its words, with its glyph.
typedef SummaryGroup = ({BackgroundGroup group, String text});

/// The summary line's groups, most urgent first, an empty one left out; in
/// each, its kinds in their order joined by `and`, each counted.
List<SummaryGroup> summaryGroups(List<BackgroundItem> items) => [
  for (final group in BackgroundGroup.values)
    if ([
          for (final kind in BackgroundKind.values)
            if (items.where((i) => i.kind == kind && i.status.group == group)
                case final of when of.isNotEmpty)
              if (kind == BackgroundKind.agent)
                ..._agentPhrases(of)
              else
                '${of.length} ${of.length == 1 ? kind.one : kind.many}',
        ]
        case final counted when counted.isNotEmpty)
      (
        group: group,
        text:
            '${group.glyph == null ? '' : '${group.glyph} '}'
            '${counted.join(' and ')} ${group.name}',
      ),
];

/// A group's agent items by their parent, in the agents list's order
/// (`main` first, then the rows under it): `main's agent`, `main's 2
/// agents`.
List<String> _agentPhrases(Iterable<BackgroundItem> agents) {
  final parents = <String, ({int at, int count})>{};
  for (final item in agents) {
    final parent = item.parent ?? _mainName;
    parents[parent] = (
      at: item.parentAt ?? 0,
      count: (parents[parent]?.count ?? 0) + 1,
    );
  }
  final ordered = parents.entries.toList();
  // A stable sort, as the original's: equal places keep their order.
  final sorted = [...ordered.indexed]
    ..sort((a, b) {
      final by = a.$2.value.at.compareTo(b.$2.value.at);
      return by != 0 ? by : a.$1.compareTo(b.$1);
    });
  return [
    for (final (_, MapEntry(key: parent, value: (:count, at: _))) in sorted)
      count == 1 ? "$parent's agent" : "$parent's $count agents",
  ];
}

/// The word the summary line opens with.
const summaryLabel = 'background';

/// What the label and its two spaces take; a wrapped line starts past it.
final summaryIndent = cellWidth(summaryLabel) + 2;

/// How a run of the summary line is drawn: the label, plain, or a group's.
sealed class SummaryTone {
  const SummaryTone();
}

/// The label's tone.
final class LabelTone extends SummaryTone {
  const LabelTone();

  @override
  bool operator ==(Object other) => other is LabelTone;

  @override
  int get hashCode => 1;
}

/// As the text is.
final class PlainTone extends SummaryTone {
  const PlainTone();

  @override
  bool operator ==(Object other) => other is PlainTone;

  @override
  int get hashCode => 2;
}

/// A group's tone.
final class GroupTone extends SummaryTone {
  const GroupTone(this.group);

  final BackgroundGroup group;

  @override
  bool operator ==(Object other) => other is GroupTone && other.group == group;

  @override
  int get hashCode => group.hashCode;
}

/// A run of the summary line in one tone.
typedef SummaryPiece = ({String text, SummaryTone tone});

/// The summary line in [width] cells: `background`, then the groups joined
/// by ` · `, breaking between groups, a wrapped line starting under the
/// first group. A group longer than a line alone breaks between its words.
List<List<SummaryPiece>> summaryLines(List<SummaryGroup> groups, int width) {
  const plain = PlainTone();
  final lines = <List<SummaryPiece>>[
    [(text: summaryLabel, tone: const LabelTone()), (text: '  ', tone: plain)],
  ];
  var used = summaryIndent;
  // Whether the line has a group on it yet, which the next one follows.
  var started = false;
  void newLine() {
    lines.add([(text: ' ' * summaryIndent, tone: plain)]);
    used = summaryIndent;
    started = false;
  }

  void put(SummaryPiece piece) {
    lines.last.add(piece);
    used += cellWidth(piece.text);
  }

  for (final (index, (:group, :text)) in groups.indexed) {
    final tone = GroupTone(group);
    final sep = index < groups.length - 1 ? ' ·' : '';
    final size = cellWidth(text + sep);
    if (started && used + 1 + size > width) newLine();
    if (started) put((text: ' ', tone: plain));
    if (used + size <= width) {
      put((text: text, tone: tone));
    } else {
      // Alone and still too long: word by word, the separator kept with the
      // last word so it never starts a line.
      final words = text.split(' ');
      for (final (at, word) in words.indexed) {
        final tail = at == words.length - 1 ? sep : '';
        final room = cellWidth(word + tail);
        final first = used == summaryIndent;
        if (!first && used + 1 + room > width) {
          newLine();
        } else if (!first) {
          put((text: ' ', tone: tone));
        }
        put((text: word, tone: tone));
      }
    }
    if (sep.isNotEmpty) put((text: sep, tone: plain));
    started = true;
  }
  return lines;
}

/// The id a drawn tool call's box carries, by the call's id.
String callTarget(String id) => 'call:$id';

/// The id a subagent's block, or its row in a group, carries.
String agentTarget(String id) => 'agent:$id';

/// Where the call that started an item is drawn in its owner's transcript:
/// the [entry] that draws it (its own, the group of tasks that draws it, or
/// the subagent whose work holds it) and the [target] id of its own box.
typedef CallPlace = ({int entry, String target});

/// Where the call that started [item] is drawn: a monitor's `Monitor(…)`,
/// by the id its answer gave, or a task's `Agent(…)`, which stands where
/// its `spawn_task` call was; none once the call is gone.
CallPlace? callPlace(List<Entry> entries, BackgroundItem item) {
  String? own(Entry entry) => switch ((item.kind, entry)) {
    (
      BackgroundKind.monitor,
      ToolEntry(
        call: ToolCall(
          :final id,
          chord: ChordCall(
            tool: ChordTool.monitor,
            answer: {'id': final answer},
          ),
        ),
      ),
    )
        when answer == item.id =>
      callTarget(id),
    (
      BackgroundKind.task || BackgroundKind.agent,
      SubagentEntry(:final subagent),
    )
        when subagent.id == item.id =>
      agentTarget(item.id),
    _ => null,
  };
  String? find(Entry entry) =>
      own(entry) ??
      (entry is SubagentEntry
          ? entry.subagent.entries.map(find).nonNulls.firstOrNull
          : null);
  for (final (index, entry) in entries.indexed) {
    if (find(entry) case final target?) {
      var at = index;
      // A group of tasks is drawn by its first.
      while (agentGroup(entries, at)?.isEmpty ?? false) {
        at -= 1;
      }
      return (entry: at, target: target);
    }
  }
  return null;
}

/// How many rows into its entry [place]'s box is drawn, the entry's [source]
/// laid out at [width]: the box's own first line, past the blank line it
/// keeps above it, as the original's jump puts it on top (layout.ts rowOf).
/// A box not drawn, in a block's folded work, gives the entry's own first
/// line.
int callRows(
  List<Entry> entries,
  CallPlace place,
  SelectionSource source,
  int width,
) {
  final target = place.target;
  // A source child's id is its parent's and its own role.
  (Object, Object)? split(Object id) => id is (Object, Object) ? id : null;
  bool where(Object id) {
    final (parent, role) = split(id) ?? (null, null);
    if (target.startsWith('agent:')) {
      final agent = target.substring('agent:'.length);
      // A row in a group, or a lone block's title: in the entry itself, or
      // in the work of the block that holds it.
      return switch (role) {
        ('agent-row' || 'agent-row-pad', final String id, 0) => id == agent,
        'agent-title' => switch (entries[place.entry]) {
          SubagentEntry(:final subagent) when parent == source.id =>
            subagent.id == agent,
          _ => switch (split(parent ?? '')?.$2) {
            ('work-agents', final String first) => first == agent,
            _ => false,
          },
        },
        _ => false,
      };
    }
    final call = target.substring('call:'.length);
    if (role != 'headline') return false;
    // The tool entry's own headline: the entry itself, or a work item.
    if (parent == source.id) {
      return switch (entries[place.entry]) {
        ToolEntry(call: ToolCall(:final id)) => id == call,
        _ => false,
      };
    }
    return switch (split(parent ?? '')?.$2) {
      ('work', final EntryIdentity identity) => _callAt(
        entries,
        identity,
        call,
      ),
      _ => false,
    };
  }

  return selectionSourceRowOf(source, width: width, where: where) ?? 1;
}

/// Whether the entry [identity] names, at any depth of [entries], is the
/// tool call [id].
bool _callAt(List<Entry> entries, EntryIdentity identity, String id) {
  for (final entry in entries) {
    if (entry.identity == identity) {
      return entry is ToolEntry && entry.call.id == id;
    }
    if (entry is SubagentEntry &&
        _callAt(entry.subagent.entries, identity, id)) {
      return true;
    }
  }
  return false;
}

/// The subagent an agent's or a task's item stands for, at any depth of
/// [entries], whose work its detail draws; none for a monitor.
Subagent? itemSubagent(List<Entry> entries, BackgroundItem item) {
  if (item.kind == BackgroundKind.monitor) return null;
  for (final entry in entries) {
    if (entry is! SubagentEntry) continue;
    final found = entry.subagent.id == item.id
        ? entry.subagent
        : itemSubagent(entry.subagent.entries, item);
    if (found != null) return found;
  }
  return null;
}

/// An item by its owner's session and its id there.
typedef ItemRef = ({int key, String id});
