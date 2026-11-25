/// The window's agents: the person's session, `main`, and the long-lived
/// agents it opened, which one of them the prompt goes to, and the order
/// the ones that want the person come in. From the original's
/// `session/window_agents.ts`.
library;

import '../agent_name.dart';
import '../js_trim.dart';
import '../notify.dart';
import 'conversation.dart';
import 'transcript/types.dart';
import 'waits.dart';

/// The long-lived agents one session may have open at once, a team's lead
/// counting as one and its members as none of them: with `main`, the list
/// under the prompt holds no more than nine rows and the teams' members.
const maxChildren = 8;

/// A long-lived agent a session opened with `open_agent`, as its row in the
/// list under the prompt names it.
class ChildInfo {
  const ChildInfo({
    required this.id,
    required this.name,
    required this.runtime,
    required this.openedAt,
    this.colour = 0,
    this.model,
    this.mode,
    this.team,
    this.lead,
    this.forkedFrom,
  });

  /// chord's id for it, which `open_agent` answered.
  final String id;
  final String name;
  final String runtime;

  /// The model asked for; null when the runtime's own was left.
  final String? model;

  /// The mode a team file set it on; null for one the file left.
  final String? mode;

  /// The team it is of, by its file's name: set on a lead and its members.
  final String? team;

  /// A member's lead, by chord's id for it; null for any other agent.
  final String? lead;

  /// A fork's source, by the name it went by: `main` or another fork. A
  /// fork is no one's child; it stands beside main.
  final String? forkedFrom;

  /// Its place among the theme's agent colours: the session's children
  /// take them in the order they opened, so closing one recolours none;
  /// [openChild] sets it.
  final int colour;

  /// When it opened, epoch milliseconds.
  final num openedAt;

  /// This with [colour].
  ChildInfo withColour(int colour) => ChildInfo(
    id: id,
    name: name,
    runtime: runtime,
    model: model,
    mode: mode,
    team: team,
    lead: lead,
    forkedFrom: forkedFrom,
    colour: colour,
    openedAt: openedAt,
  );
}

/// A long-lived agent open in the window: a session the person can pick in
/// the list under the prompt, keyed as main is, from the same keys.
final class Child<C> {
  const Child(this.info, this.key, this.conversation, this.wait);

  final ChildInfo info;
  final int key;
  final C conversation;
  final AgentWait wait;

  String get id => info.id;
  String get name => info.name;
  String get runtime => info.runtime;
  int get colour => info.colour;
  String? get forkedFrom => info.forkedFrom;
  String? get lead => info.lead;
  String? get team => info.team;

  Child<C> withWait(AgentWait wait) => Child(info, key, conversation, wait);
}

/// The person's session. Its key never changes: `/clear` and a `/resume`
/// pick start its next session under the same one.
final class MainAgent<C> {
  const MainAgent(this.key, this.agent, this.conversation, this.wait);

  final int key;
  final String agent;
  final C conversation;
  final AgentWait wait;

  MainAgent<C> withWait(AgentWait wait) =>
      MainAgent(key, agent, conversation, wait);
}

/// An agent's place in the attention order, compared field by field.
typedef Rank = ({bool unseen, num since, int key});

/// The window's main session and its children.
final class WindowAgents<C> {
  const WindowAgents({
    this.main,
    this.children = const [],
    this.picked = 1,
    this.closed = const [],
    this.runs = const [],
    this.opened = 0,
    this.nextKey = 1,
    this.attended,
  });

  /// The person's session; null before it starts.
  final MainAgent<C>? main;

  /// Its long-lived agents, in the order they opened.
  final List<Child<C>> children;

  /// The agent the prompt goes to: main's key, or a child's.
  final int picked;

  /// The children closed, so a message to one answers that it is closed
  /// rather than that it never was. Emptied with the session on `/clear`
  /// and a `/resume` pick.
  final List<ChildInfo> closed;

  /// The names of the team runs closed while the window is open, which
  /// `/clear` and `/resume` leave as they are: a run's number is never
  /// given again, so a name in an old message, a resumed transcript's or a
  /// record's, still means the run it meant.
  final List<String> runs;

  /// How many children have opened, which colours the next.
  final int opened;

  /// The key the next agent opened gets; keys are never reused.
  final int nextKey;

  /// The agent `attend` last went to and its place in the attention order
  /// then, kept until another is picked: going there clears an unseen
  /// reply, which takes it out of the order, and the next press still has
  /// to know where in the queue it stood.
  final ({int key, Rank rank})? attended;

  WindowAgents<C> copyWith({
    MainAgent<C>? main,
    bool noMain = false,
    List<Child<C>>? children,
    int? picked,
    List<ChildInfo>? closed,
    List<String>? runs,
    int? opened,
    int? nextKey,
    ({int key, Rank rank})? attended,
    bool unattended = false,
  }) => WindowAgents(
    main: noMain ? null : main ?? this.main,
    children: children ?? this.children,
    picked: picked ?? this.picked,
    closed: closed ?? this.closed,
    runs: runs ?? this.runs,
    opened: opened ?? this.opened,
    nextKey: nextKey ?? this.nextKey,
    attended: unattended ? null : attended ?? this.attended,
  );
}

/// No agents yet.
WindowAgents<C> noAgents<C>() => WindowAgents<C>();

/// The window's session, picked; once, as a second call changes nothing.
WindowAgents<C> openMain<C>(
  WindowAgents<C> agents,
  String agent,
  C conversation,
) {
  if (agents.main != null) return agents;
  final key = agents.nextKey;
  return agents.copyWith(
    main: MainAgent(key, agent, conversation, idle),
    picked: key,
    nextKey: key + 1,
  );
}

/// Main, [key] naming it, or the child [key] names; null for a key that is
/// neither open.
({MainAgent<C>? main, Child<C>? child})? agentOf<C>(
  WindowAgents<C> agents,
  int key,
) {
  final main = agents.main;
  if (main != null && main.key == key) return (main: main, child: null);
  for (final child in agents.children) {
    if (child.key == key) return (main: null, child: child);
  }
  return null;
}

/// The wait of agent [key], main or a child; null when it is not open.
AgentWait? waitOf<C>(WindowAgents<C> agents, int key) {
  final found = agentOf(agents, key);
  return found?.child?.wait ?? found?.main?.wait;
}

/// The key whose session fills the window; null before main starts.
int? shownKey<C>(WindowAgents<C> agents) =>
    agents.main == null ? null : agents.picked;

/// The child the prompt goes to; null while `main` is picked.
Child<C>? pickedChild<C>(WindowAgents<C> agents) {
  for (final child in agents.children) {
    if (child.key == agents.picked) return child;
  }
  return null;
}

/// Whether [child] is a team's lead rather than a member or a plain child.
bool isLead(ChildInfo child) => child.team != null && child.lead == null;

/// The open members of the lead with chord's id [lead], in their order.
List<Child<C>> membersOf<C>(WindowAgents<C> agents, String lead) => [
  for (final child in agents.children)
    if (child.lead == lead) child,
];

/// One open session send_message reaches, by its name or child id.
typedef MessageRecipient = ({int key, String name, String? id});

/// Who send_message reaches from [sourceKey]: main's own children; a
/// child's parent; a lead's main, members and other leads; a member's lead
/// and peers. Only open long-lived sessions live here, never tasks or
/// unopened runtimes.
List<MessageRecipient> messageRecipients<C>(
  WindowAgents<C> agents,
  int sourceKey,
) {
  final main = agents.main;
  if (main == null) return const [];
  if (sourceKey == main.key) {
    return [
      for (final child in ownChildren(agents))
        (key: child.key, name: child.name, id: child.id),
    ];
  }
  final self = agentOf(agents, sourceKey)?.child;
  // A fork has no parent, and main does not reach it.
  if (self == null || self.forkedFrom != null) return const [];
  final MessageRecipient parent = (key: main.key, name: 'main', id: null);
  if (self.team == null) return [parent];
  MessageRecipient named(Child<C> child) =>
      (key: child.key, name: child.name, id: child.id);
  final lead = isLead(self.info)
      ? self
      : agents.children.where((child) => child.id == self.lead).firstOrNull;
  if (lead == null) return const [];
  final members = [
    for (final child in membersOf(agents, lead.id))
      if (!identical(child, self)) child,
  ];
  return identical(self, lead)
      ? [
          parent,
          ...members.map(named),
          for (final child in ownChildren(agents))
            if (isLead(child.info) && !identical(child, self)) named(child),
        ]
      : [named(lead), ...members.map(named)];
}

/// A child as a sentence about it names it: its own name, or a member's
/// with its run after it, `tester · bugfix 2`, while another agent of the
/// window has that name too, as two runs each have a `tester`.
String namedChild<C>(WindowAgents<C> agents, ChildInfo child) {
  final lead = child.lead == null
      ? null
      : agents.children.where((each) => each.id == child.lead).firstOrNull;
  final shared = agents.children.any(
    (each) => each.id != child.id && each.name == child.name,
  );
  return lead != null && shared ? '${child.name} · ${lead.name}' : child.name;
}

/// What a notification calls agent [key]: main by its agent, a child by its
/// name, and a member with its run, `tester (bugfix)`, as the person may be
/// looking anywhere when it comes; null for a key that is not open.
String? notifiedName<C>(WindowAgents<C> agents, int key) {
  final found = agentOf(agents, key);
  final main = found?.main;
  if (main != null) return main.agent;
  final child = found?.child;
  if (child == null) return null;
  final lead = child.lead == null
      ? null
      : agents.children.where((each) => each.id == child.lead).firstOrNull;
  return lead == null ? child.name : '${child.name} (${lead.name})';
}

/// A child's name: the one asked for, or its runtime, numbered past the
/// first (`codex`, `codex 2`), and never one another open agent of the
/// session goes by, `main` and `chord` included, as a message names its
/// sender so. Throws with [agentNameProblem]'s words for a name that may
/// not be used.
String childName<C>(WindowAgents<C> agents, String? asked, String runtime) {
  final trimmed = asked == null ? '' : jsTrim(asked);
  return _numbered(trimmed.isEmpty ? runtime : trimmed, takenNames(agents));
}

/// The names a child may not be given as they are: `main`, `chord` and
/// every open child's, as a message names its sender so.
Set<String> takenNames<C>(WindowAgents<C> agents) => {
  'main',
  'chord',
  for (final child in agents.children) child.name,
};

/// A run's lead's name: the team's, numbered past the first run as a
/// second child of one runtime is (`bugfix 2`); a closed run's number is
/// not given again while the window is open, so a name in an old message
/// still means the run it meant.
String runName<C>(WindowAgents<C> agents, String team) =>
    _numbered(team, {...takenNames(agents), ...agents.runs});

String _numbered(String base, Set<String> taken) {
  final problem = agentNameProblem(base);
  if (problem != null) throw ArgumentError(problem);
  if (!taken.contains(base)) return base;
  var n = 2;
  while (taken.contains('$base $n')) {
    n++;
  }
  return '$base $n';
}

/// What chord tells a long-lived child's parent when [event] ends the
/// child's work without the parent hearing it: its agent gone, with its
/// last words, or a turn that failed while it stayed up; null for any other
/// event. [gone] is the agent's last words once it has gone; a turn that
/// failed because it went is the exit's to tell. A [lead]'s exit closes
/// its members, which its words say.
String? childEnded(
  String name,
  ConversationEvent event,
  String? gone, {
  bool lead = false,
}) {
  final action = event is Transcribed ? event.action : null;
  if (action is DisconnectedAction) {
    final words = gone == null || gone.isEmpty ? '' : ': ${_sentence(gone)}';
    return lead
        ? "$name's lead exited$words. Its members are closed; run_team "
              'starts the team again.'
        : "$name's agent exited$words. open_agent opens it again.";
  }
  if (action is ResultAction && action.result is TurnFailed && gone == null) {
    final message = (action.result as TurnFailed).message;
    return "$name's turn failed: ${_sentence(message)}. It is still open; "
        'send_message reaches it.';
  }
  return null;
}

/// Words that go on into chord's sentence, without a full stop of their
/// own.
String _sentence(String words) {
  final trimmed = jsTrim(words);
  return trimmed.endsWith('.')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

/// Opens a child under the next key, with the next colour, at the end of
/// main's own children, before any fork, or a member after its lead's
/// last, so a team's agents stay together; a fork at the very end. The
/// pick stays where it is. Null before main starts, or, for one of main's own,
/// with [maxChildren] of them already open.
({WindowAgents<C> agents, int key})? openChild<C>(
  WindowAgents<C> agents,
  ChildInfo info,
  C conversation,
) {
  if (agents.main == null ||
      (info.lead == null &&
          info.forkedFrom == null &&
          ownChildren(agents).length >= maxChildren)) {
    return null;
  }
  final key = agents.nextKey;
  final child = Child(info.withColour(agents.opened), key, conversation, idle);
  // A member after its run; main's own before the forks, which come after
  // main's whole tree.
  final firstFork = agents.children.indexWhere((c) => c.forkedFrom != null);
  final at = info.lead != null
      ? agents.children.lastIndexWhere(
              (each) => each.id == info.lead || each.lead == info.lead,
            ) +
            1
      : info.forkedFrom == null && firstFork != -1
      ? firstFork
      : agents.children.length;
  return (
    key: key,
    agents: agents.copyWith(
      children: [...agents.children]..insert(at, child),
      opened: agents.opened + 1,
      nextKey: key + 1,
    ),
  );
}

/// The session's own children: those it opened, a team's lead among
/// them, never a member or a fork, which is no one's.
List<Child<C>> ownChildren<C>(WindowAgents<C> agents) => [
  for (final child in agents.children)
    if (child.lead == null && child.forkedFrom == null) child,
];

/// Takes child [key] out and keeps it among the closed; a pick on it goes
/// back to `main`.
WindowAgents<C> closeChild<C>(WindowAgents<C> agents, int key) {
  final child = agentOf(agents, key)?.child;
  if (child == null) return agents;
  return agents.copyWith(
    unattended: agents.attended?.key == key,
    children: [
      for (final other in agents.children)
        if (!identical(other, child)) other,
    ],
    picked: agents.picked == key
        ? (agents.main?.key ?? agents.picked)
        : agents.picked,
    closed: [...agents.closed, child.info],
    runs: isLead(child.info) ? [...agents.runs, child.name] : null,
  );
}

/// [agents] with no children closed, as a new or resumed session starts:
/// the record then says what was closed. Run names stay taken.
WindowAgents<C> forgetClosed<C>(WindowAgents<C> agents) =>
    agents.closed.isEmpty ? agents : agents.copyWith(closed: const []);

/// [wait] with its `✓` or `✗` seen, and its turn's end.
AgentWait _seen(AgentWait wait) => wait.unseen == null && wait.ended == null
    ? wait
    : AgentWait(
        watch: wait.watch,
        asking: wait.asking,
        working: wait.working,
        stopped: wait.stopped,
        exited: wait.exited,
      );

WindowAgents<C> _withWait<C>(
  WindowAgents<C> agents,
  int key,
  AgentWait Function(AgentWait wait) change,
) {
  final main = agents.main;
  return agents.copyWith(
    main: main != null && main.key == key
        ? main.withWait(change(main.wait))
        : main,
    children: [
      for (final child in agents.children)
        child.key == key ? child.withWait(change(child.wait)) : child,
    ],
  );
}

/// A key pressed in chord: the agent shown has been looked at, so its
/// turn's end is seen. Its `✓` or `✗` is already gone, as it was shown.
WindowAgents<C> keyedAgents<C>(WindowAgents<C> agents) {
  final key = shownKey(agents);
  if (key == null || waitOf(agents, key)?.ended == null) return agents;
  return _withWait(agents, key, keyed);
}

/// Picks agent [key], `main` by its key or a child by its: the transcript
/// and the prompt are that agent's, and its marks are seen.
WindowAgents<C> pick<C>(WindowAgents<C> agents, int key) {
  if (agentOf(agents, key) == null) return agents;
  return _withWait(agents, key, _seen).copyWith(picked: key, unattended: true);
}

/// Moves the pick [by] rows down the list, `main` first; null when it would
/// go above `main`, which hands the focus back to the box. The last row
/// stays the last.
WindowAgents<C>? movePick<C>(WindowAgents<C> agents, int by) {
  final main = agents.main;
  if (main == null) return agents;
  final keys = [main.key, for (final child in agents.children) child.key];
  final at = keys.indexOf(agents.picked) + by;
  if (at < 0) return null;
  return pick(agents, keys[at < keys.length ? at : keys.length - 1]);
}

int _compare(Rank a, Rank b) {
  final unseen = (a.unseen ? 1 : 0) - (b.unseen ? 1 : 0);
  if (unseen != 0) return unseen;
  final since = a.since.compareTo(b.since);
  if (since != 0) return since;
  return a.key - b.key;
}

/// The agents that want the person, most urgent first: those that wait on
/// a permission or form, longest waiting first, then those with a reply or
/// failure not yet seen, oldest first.
List<({int key, Rank rank})> _ranked<C>(WindowAgents<C> agents) {
  final main = agents.main;
  final all = [
    if (main != null) (main.key, main.wait),
    for (final child in agents.children) (child.key, child.wait),
  ];
  final ranked = <({int key, Rank rank})>[
    for (final (key, wait) in all)
      if (wait.asking case final asking?)
        (key: key, rank: (unseen: false, since: asking.since, key: key))
      // A message between agents wants no one: the turn it starts says so.
      else if (wait.unseen case final unseen?
          when unseen.kind != UnseenKind.message)
        (key: key, rank: (unseen: true, since: unseen.since, key: key)),
  ];
  ranked.sort((a, b) => _compare(a.rank, b.rank));
  return ranked;
}

/// The keys of the agents that want the person, most urgent first.
List<int> attentionOrder<C>(WindowAgents<C> agents) => [
  for (final each in _ranked(agents)) each.key,
];

/// Goes to the agent after the one shown in the attention order, or to the
/// first when the one shown has no place in it, round to the first after
/// the last; null when no other agent wants the person. Going from the
/// shown one's place rather than from the top is what lets pressing it
/// again reach every one.
WindowAgents<C>? attend<C>(WindowAgents<C> agents) {
  final order = _ranked(agents);
  final shown = shownKey(agents);
  final byHand = agents.attended?.key != shown;
  Rank? from;
  if (byHand) {
    for (final each in order) {
      if (each.key == shown) from = each.rank;
    }
  } else {
    from = agents.attended?.rank;
  }
  final others = [
    for (final each in order)
      if (each.key != shown) each,
  ];
  // From an agent picked by hand, the first goes to what the status line
  // names, the longest wait behind it; the walk goes on from there.
  ({int key, Rank rank})? next;
  if (byHand) {
    for (final each in others) {
      if (!each.rank.unseen) {
        next = each;
        break;
      }
    }
  }
  if (next == null && from != null) {
    for (final each in others) {
      if (_compare(each.rank, from) > 0) {
        next = each;
        break;
      }
    }
  }
  next ??= others.isEmpty ? null : others.first;
  if (next == null) return null;
  return pick(agents, next.key).copyWith(attended: next);
}

/// Folds one of agent [key]'s events into its wait, and says the wait it
/// starts, if any, as `notify.dart` classes waits, shown or not.
({WindowAgents<C> agents, Wait? wait}) hear<C>(
  WindowAgents<C> agents,
  int key,
  ConversationEvent event,
  num now,
) {
  final before = waitOf(agents, key);
  if (before == null) return (agents: agents, wait: null);
  final heard = heardWait(before, event, now, front: shownKey(agents) == key);
  return (
    agents: _withWait(agents, key, (_) => heard.wait),
    wait: heard.started,
  );
}

/// [agents] while [key] is main's: what a session of the window owns; null
/// otherwise.
WindowAgents<C>? ownedBy<C>(WindowAgents<C> agents, int? key) {
  final main = agents.main;
  return main != null && main.key == key ? agents : null;
}
