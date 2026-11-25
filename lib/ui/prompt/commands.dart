import 'dart:math' as math;
import 'package:chord_tui/chord_tui.dart' show Fzf, FzfCasing;
import '../../acp/schema.dart' as acp;
import '../../agents.dart'
    show AgentRunner, ListedAgent, agentNote, offeredFrom;

/// A typed local command; completion uses the same submission parser.
typedef TypedCommand = ({String name, String args});

/// Session setting commands handled by the settings window.
const settingCommandNames = {'model', 'config', 'effort', 'fast'};

/// One local or agent command offered in the completion menu.
final class CommandItem {
  const CommandItem(
    this.name,
    this.description, {
    this.local = true,
    this.of,
    this.verb,
  });
  final String name;
  final String? description;
  final bool local;

  /// The command it is a name for, as an agent is `/new`'s; null for a
  /// command.
  final String? of;

  /// The form of [of] the name follows, as a team's follows `/team run`.
  final String? verb;
}

/// chord's own commands; the agent never hears of them.
const localCommands = [
  CommandItem('clear', 'Start a new session with an empty transcript'),
  CommandItem(
    'config',
    "Change the agent's settings for this session, such as effort",
  ),
  CommandItem('context', "Show how full the agent's context window is"),
  CommandItem('cost', 'Show the tokens and cost this session has spent'),
  CommandItem('effort', "Change the agent's effort for this session"),
  CommandItem('exit', 'Quit chord'),
  CommandItem('fast', "Turn the agent's fast mode on or off for this session"),
  CommandItem('fork', 'Fork the conversation into a new agent'),
  CommandItem('help', 'Show keyboard shortcuts'),
  CommandItem('mcp', 'Show the MCP servers chord passed to the agent'),
  CommandItem('model', "Switch the agent's model"),
  CommandItem(
    'new',
    'Open a new agent beside main and go to it; --name names it',
  ),
  CommandItem(
    'rename',
    "Rename this session; the agent's own title may replace it",
  ),
  CommandItem(
    'resume',
    'Resume an earlier session, here or from another directory',
  ),
  CommandItem('status', 'Show the agent, model, mode, session and directory'),
  CommandItem('team', 'Describe, keep and run teams of agents'),
  CommandItem('theme', "Choose chord's colours for a dark or light terminal"),
  CommandItem('vim', 'Turn vim mode for the prompt on or off'),
];

/// Main's bounded collation fallback after the maintained package trials.
int compareCommandNames(String a, String b) {
  final folded = a.toLowerCase().compareTo(b.toLowerCase());
  return folded == 0 ? a.compareTo(b) : folded;
}

/// chord's commands and the agent's, by name. An agent command named like
/// one of chord's is left out: chord's is the one that runs.
List<CommandItem> commandItems(List<acp.AvailableCommand> agent) {
  final items = [...localCommands];
  final own = {for (final command in localCommands) command.name};
  for (final command in agent) {
    try {
      if (own.contains(command.name)) continue;
      final summary = command.description.trim().split('\n').first.trim();
      items.add(
        CommandItem(
          command.name,
          summary.isEmpty ? null : summary,
          local: false,
        ),
      );
    } on TypeError {
      // A malformed advertised command cannot be offered or accepted.
    }
  }
  return items..sort((a, b) => compareCommandNames(a.name, b.name));
}

/// The command name being typed, until a space or second line closes the list.
String? commandQuery(String draft) => RegExp(r'^/(\S*)$').firstMatch(draft)?[1];

/// The agent being named after `/new ` and nothing else; null once it holds
/// a second word or line, when the list of agents is put away.
String? agentQuery(String draft) =>
    RegExp(r'^/new +(\S*)$').firstMatch(draft)?[1];

/// The agents `/new` offers, by name, as chord can start them in the
/// window, each described as `chord agents` lists it in [listed]; one it
/// does not list, as `--agent-command` names, by its name alone. Those the
/// settings files start come first, then own CLIs PATH has, then the
/// registry's, and own CLIs PATH lacks last, so what will start is on top.
/// With the `offeredAgents` setting, [offered], its known names alone and
/// in its order; [names] is then only what a typed `/new` may start.
List<CommandItem> agentItems(
  List<String> names,
  List<ListedAgent> listed, {
  List<String>? offered,
}) {
  CommandItem itemOf(String name, ListedAgent? agent) =>
      CommandItem(name, agent == null ? null : agentNote(agent), of: 'new');

  // Not for an absent setting: `/new` keeps the own CLIs PATH lacks, last,
  // as the original's does, where the start page leaves them out.
  if (offered != null) {
    return [
      for (final agent in offeredFrom(listed, offered).agents)
        itemOf(agent.name, agent),
    ];
  }
  final ranked = [
    for (final (index, name) in names.indexed)
      (
        index: index,
        agent: listed.where((each) => each.name == name).firstOrNull,
        name: name,
      ),
  ];
  // By readiness, the given order within each: Dart's sort is not stable.
  ranked.sort((a, b) {
    final by = _readiness(a.agent) - _readiness(b.agent);
    return by != 0 ? by : a.index - b.index;
  });
  return [for (final each in ranked) itemOf(each.name, each.agent)];
}

/// How sure an agent is to start: an unlisted name, as `--agent-command`
/// gives, ranks with those the settings files start.
int _readiness(ListedAgent? agent) => switch (agent) {
  null => 0,
  ListedAgent(from: AgentRunner.settings) => 0,
  ListedAgent(from: AgentRunner.cli, found: true) => 1,
  ListedAgent(from: AgentRunner.cli, found: false) => 3,
  _ => 2,
};

/// The forms of `/team` that take a team's name next.
const namedForms = {'show', 'run', 'stop'};

/// The form and the name being typed after `/team show `, `run ` or `stop `
/// and nothing else; null once a word follows the name, when the list of
/// names is put away. `stop` takes a run's name, which may be numbered
/// (`bugfix 2`), so its name runs on to the end of the line.
({String form, String name})? teamQuery(String draft) {
  final match = RegExp(r'^/team +(show|run|stop) +([^\n]*)$').firstMatch(draft);
  if (match == null) return null;
  final (form, name) = (match[1]!, match[2]!);
  return form == 'stop' || !RegExp(r'\s').hasMatch(name)
      ? (form: form, name: name)
      : null;
}

/// The saved teams by name, a broken file marked, and the runs open, as the
/// prompt offers them after `/team <form> `.
typedef TeamNames = ({
  List<({String name, bool broken})> teams,
  List<String> runs,
});

/// The names `/team <form> ` offers: the saved teams' that chord can run
/// for `show` and `run`, and the open runs' for `stop`.
List<CommandItem> teamItems(String form, TeamNames names) => [
  for (final name
      in form == 'stop'
          ? names.runs
          : [
              for (final team in names.teams)
                if (!team.broken) team.name,
            ])
    CommandItem(name, null, of: 'team', verb: form),
];

/// Reads a typed slash command and its trimmed arguments once.
TypedCommand? typedCommand(String draft) {
  final match = RegExp(r'^/(\S+)(?:\s+([\s\S]*))?$').firstMatch(draft.trim());
  return match == null ? null : (name: match[1]!, args: match[2]?.trim() ?? '');
}

/// Original fzf matching over names, preserving source order for an empty query.
List<CommandItem> matchCommands(List<CommandItem> items, String query) =>
    query.isEmpty
    ? [...items]
    : Fzf(
        items,
        selector: (item) => item.name,
        casing: FzfCasing.caseInsensitive,
      ).find(query).map((result) => result.item).toList();

/// Wrapping menu navigation.
int moveHighlight(int index, int count, int step) =>
    count == 0 ? 0 : (index + step + count) % count;

/// The least-moving result window retaining the highlighted command.
({int start, int end}) visibleRange(
  int count,
  int highlighted,
  int rows, [
  int start = 0,
]) {
  if (count <= rows) return (start: 0, end: count);
  final from = math.min(
    math.max(math.max(start, highlighted - rows + 1), 0),
    math.min(highlighted, count - rows),
  );
  return (start: from, end: from + rows);
}

/// The original quarter-window completion and picker row limit.
int menuRowLimit(int rows) => math.max(3, rows ~/ 4);

/// How the list writes an item: a command with its slash, a name bare.
String itemLabel(CommandItem item) =>
    item.of == null ? '/${item.name}' : item.name;

/// What Tab puts in the prompt: the command's name, or for a name a command
/// takes the command with it, and room for what follows.
String completion(CommandItem item) => item.of == null
    ? '/${item.name} '
    : '/${item.of} ${item.verb == null ? '' : '${item.verb} '}${item.name} ';

/// What Enter does with a command or ordinary prompt.
sealed class Submitted {
  const Submitted();
}

/// A supported command run only by the client.
final class LocalSubmitted extends Submitted {
  const LocalSubmitted(this.name, this.args);
  final String name;
  final String args;
}

/// A name put into the box, as Tab puts it, for more to be typed: a team's
/// run needs its job after the name.
final class CompleteSubmitted extends Submitted {
  const CompleteSubmitted(this.text);
  final String text;
}

/// Ordinary text or an agent-owned command sent as the original does.
final class SendSubmitted extends Submitted {
  const SendSubmitted(this.text);
  final String text;
}

/// Highlighted items run by name; typed local commands retain their arguments.
Submitted submitted(String draft, [CommandItem? highlighted]) {
  // A team's run needs its job after the name, which is still to be typed.
  if (highlighted?.verb == 'run') {
    return CompleteSubmitted(completion(highlighted!));
  }
  // A highlighted name runs its command on it: `/new fa` opens fake.
  if (highlighted?.of case final of?) {
    final verb = highlighted!.verb;
    return LocalSubmitted(
      of,
      verb == null ? highlighted.name : '$verb ${highlighted.name}',
    );
  }
  final typed = typedCommand(draft);
  final name = highlighted?.name ?? typed?.name;
  if (localCommands.any((command) => command.name == name)) {
    return LocalSubmitted(name!, highlighted == null ? typed?.args ?? '' : '');
  }
  return SendSubmitted(
    highlighted == null ? draft.trim() : '/${highlighted.name}',
  );
}
