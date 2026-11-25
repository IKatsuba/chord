import 'dart:convert';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'acp/connection.dart' show openHeadlessAgent;
import 'acp_agent.dart' show AcpStart;
import 'agents.dart';
import 'closest_string.dart';
import 'headless.dart' show joinPiped, outputFormats, runHeadless;
import 'js_trim.dart';
import 'mcp.dart';
import 'notify.dart' show NotifChannel;
import 'session/session.dart' show SessionOpener;
import 'session/conversation.dart' show Starting;
import 'session/place.dart'
    show
        SessionStart,
        childStart,
        fakeRuntimesFlag,
        fakeRuntimesRefusal,
        mcpServersTaken;
import 'session/starting.dart';
import 'settings.dart';
import 'resume_args.dart';
import 'session/sessions.dart';
import 'session/state_dir.dart';
import 'ui/app/startup_choice.dart';
import 'ui/shortcuts/bindings.dart' show Keybindings, keybindingsNotice;
import 'upgrade.dart';
import 'version.dart';

const _description =
    'A full-screen terminal client for ACP coding agents. A new unnamed '
    'interactive start asks which agent to use for this invocation; explicit '
    'commands, headless and resume routes keep their existing behavior.';

const _agentsDescription =
    'List the agents chord can start: name, title, command, and for those '
    'started by their own CLI whether PATH has it.';

const _acpDescription =
    'Serve ACP on stdin and stdout, for a client that starts chord as its '
    'agent; draws nothing.';

const _upgradeDescription =
    'Upgrade chord executable to latest or given version.';

/// The examples of the original's help for what the port does.
const _examples = [
  ('Claude Code', 'chord claude'),
  ('Pick up where you left off', 'chord claude --continue'),
  ('Pick an earlier session', 'chord --resume'),
  ('Codex in another directory', 'chord codex -C ~/src/app'),
  ('One question, for a script', 'chord -p "What does this do?"'),
  (
    'Piped input with the prompt',
    'git diff | chord -p "Review this" --output-format json',
  ),
  (
    'An agent chord does not know',
    'chord my-agent --agent-command "my-agent --acp"',
  ),
];

ArgParser _withHelp() =>
    ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

/// chord's flags, without what it does with them.
final ArgParser chordParser = _withHelp()
  ..addFlag(
    'version',
    abbr: 'V',
    negatable: false,
    help: 'Show the version number for this program.',
  )
  ..addOption(
    'cwd',
    abbr: 'C',
    valueHelp: 'dir',
    help: 'Directory the session works in.',
  )
  ..addOption(
    'agent-command',
    valueHelp: 'command',
    help:
        "Start this ACP agent command instead of chord's own; [agent] only names it.",
  )
  ..addOption(
    'model',
    abbr: 'm',
    valueHelp: 'model',
    help: "Start each of [agent]'s sessions on this model, by its id for it.",
  )
  ..addOption(
    'effort',
    valueHelp: 'effort',
    help: "Start each of [agent]'s sessions on this effort, by its id for it.",
  )
  ..addOption(
    'permission-mode',
    valueHelp: 'mode',
    help: "Start each of [agent]'s sessions in this mode, by its id for it.",
  )
  ..addFlag(
    'no-mcp-servers',
    negatable: false,
    help:
        "Start each of [agent]'s sessions with no MCP servers, chord's own included.",
  )
  ..addFlag(
    'continue',
    abbr: 'c',
    negatable: false,
    help: "Open the agent's latest session in this directory again.",
  )
  ..addFlag(
    'resume',
    abbr: 'r',
    negatable: false,
    help:
        'Open a session by the id chord prints on quit; with no id, pick one.',
  )
  ..addOption(
    'print',
    abbr: 'p',
    valueHelp: 'prompt',
    help: 'Send this prompt, print the reply and exit; piped input joins it.',
  )
  ..addFlag(
    'dangerously-skip-permissions',
    negatable: false,
    help: 'Allow every permission the agent asks for. Only with -p.',
  )
  ..addOption(
    'output-format',
    valueHelp: 'format',
    help:
        'How -p prints: the reply as it streams, or one JSON object at the end.',
  )
  ..addCommand(
    'agents',
    _withHelp()
      ..addOption(
        'cwd',
        abbr: 'C',
        valueHelp: 'dir',
        help: 'Directory whose settings to read.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help:
            'Print one JSON object instead: the preferred agent, each agent '
            'with how it starts and whether it is offered and startable, and '
            'the settings problems.',
      ),
  );

/// `chord acp`'s flags, without what it does with them.
final ArgParser acpParser = _withHelp()
  ..addOption(
    'agent-command',
    valueHelp: 'command',
    help:
        "Start this ACP agent command instead of chord's own; [agent] only names it.",
  )
  ..addOption(
    'model',
    abbr: 'm',
    valueHelp: 'model',
    help: "Start each of [agent]'s sessions on this model, by its id for it.",
  )
  ..addOption(
    'effort',
    valueHelp: 'effort',
    help: "Start each of [agent]'s sessions on this effort, by its id for it.",
  )
  ..addOption(
    'permission-mode',
    valueHelp: 'mode',
    help: "Start each of [agent]'s sessions in this mode, by its id for it.",
  )
  ..addFlag(
    'no-mcp-servers',
    negatable: false,
    help:
        "Start each of [agent]'s sessions with no MCP servers, chord's own included.",
  );

/// `chord upgrade`'s flags, without what it does with them: cliffy's
/// upgrade command's, less the registry choice and spinner switch it hides
/// with one provider and no spinner.
final ArgParser upgradeParser = _withHelp()
  ..addFlag(
    'list-versions',
    abbr: 'l',
    negatable: false,
    help: 'Show available versions.',
  )
  ..addOption(
    'version',
    valueHelp: 'version',
    defaultsTo: 'latest',
    help: 'The version to upgrade to.',
  )
  ..addFlag(
    'force',
    abbr: 'f',
    negatable: false,
    help: 'Replace current installation even if not out-of-date.',
  )
  ..addFlag(
    'verbose',
    abbr: 'v',
    negatable: false,
    help: 'Log verbose output.',
  );

String _columns(List<(String, String)> rows) {
  final width = rows
      .map((row) => row.$1.length)
      .reduce((a, b) => a > b ? a : b);

  return [
    for (final (left, right) in rows) '  ${left.padRight(width)}  $right',
  ].join('\n');
}

/// `chord --help`.
final String chordHelp = [
  'Usage: chord [agent]',
  'Version: $version',
  '',
  _description,
  '',
  'Options:',
  // `[id]` takes its cells from the padding, so the help stays in its
  // column: args pads every flag to the longest, which is not --resume.
  _indent(chordParser.usage.replaceFirst('--resume     ', '--resume [id]')),
  '',
  'Commands:',
  _columns([
    ('agents', _agentsDescription),
    ('acp', _acpDescription),
    ('upgrade', _upgradeDescription),
  ]),
  '',
  'Examples:',
  _columns(_examples),
].join('\n');

/// `chord agents --help`.
final String agentsHelp = [
  'Usage: chord agents',
  'Version: $version',
  '',
  _agentsDescription,
  '',
  'Options:',
  _indent(chordParser.commands['agents']!.usage),
].join('\n');

/// `chord acp --help`.
final String acpHelp = [
  'Usage: chord acp [agent]',
  'Version: $version',
  '',
  _acpDescription,
  '',
  'Options:',
  _indent(acpParser.usage),
].join('\n');

/// `chord upgrade --help`.
final String upgradeHelp = [
  'Usage: chord upgrade',
  'Version: $version',
  '',
  _upgradeDescription,
  '',
  'Options:',
  _indent(upgradeParser.usage),
].join('\n');

/// The interactive start page, injected so CLI flow is testable without a terminal.
typedef PickStartupAgent =
    Future<String?> Function({
      required List<ListedAgent> agents,
      required String version,
      required String directory,
      required String preferred,
      required List<String>? offered,
    });

/// Startup resume selection before any agent process exists.
typedef PickStartupResume =
    Future<EarlierSession?> Function({
      required List<EarlierSession> sessions,
      required String agent,
      required String version,
      required String directory,
      required String cwd,
      required String? home,
    });

/// What chord opens once nothing has refused the call.
class Launch {
  /// The agent named [name] to open, at chord's version, in the directory
  /// as shown, through [agentCommand] when the call gives one.
  const Launch({
    required this.name,
    required this.agent,
    this.agentCommand,
    required this.version,
    required this.directory,
    this.cwd,
    this.childStart,
    this.runtimeNames,
    this.resume,
    this.command,
    this.starting = const Starting(),
    this.copyOnSelect = true,
    this.notifChannel = NotifChannel.auto,
    this.warnings = const [],
    this.keymap,
    this.keysFailed,
    this.vim = false,
    this.theme,
    this.settingsFile,
    this.shownSettingsFile,
    this.configHome,
    this.home,
    this.mcpServers = const [],
    this.mcpIgnored = const [],
    this.noMcpServers = false,
    this.noMcpServersFrom,
    this.readListed,
    this.offered,
  });

  /// Reads the agents as `chord agents` lists them, PATH looked at, for
  /// `/new` to describe and order [runtimeNames] by: the launcher reads it
  /// before the window opens, as the original's main does, so deciding
  /// what to launch looks at no PATH; none describes nothing.
  final Future<List<ListedAgent>> Function()? readListed;

  /// The `offeredAgents` setting, which sets what `/new` lists from
  /// what [readListed] gives; null without it.
  final List<String>? offered;

  /// The MCP servers the session's directory gives it, each with its file
  /// as chord shows it.
  final List<DefinedServer> mcpServers;

  /// What those files defined that chord did not pass, as shown.
  final List<Ignored> mcpIgnored;

  /// The agent takes no MCP servers: `--no-mcp-servers`, its setting, or
  /// chord's own table.
  final bool noMcpServers;

  /// What set [noMcpServers]: the flag, or the file; none for chord's own
  /// table.
  final String? noMcpServersFrom;

  /// The name the call gives the agent, or the default's.
  final String name;

  /// The catalog's agent of that name; null for a name only an
  /// [agentCommand] starts.
  final KnownAgent? agent;

  /// The command `--agent-command` gives, which starts the agent in place
  /// of the catalog's; null without it. The resume line repeats it.
  final String? agentCommand;

  /// What starts the agent in place of the catalog's: the flag's command,
  /// else the settings files'; null for the catalog's own.
  final SettingsCommand? command;

  /// The model, effort and mode each session starts on, with where each
  /// was set.
  final Starting starting;

  /// Whether a drag's release copies its selection: `copyOnSelect` from
  /// the user's settings file, on by default.
  final bool copyOnSelect;

  /// How the window tells the terminal it waits: `preferredNotifChannel`
  /// from the settings files, `auto` by default.
  final NotifChannel notifChannel;

  /// The settings problems, as the transcript says them first.
  final List<String> warnings;

  /// The keybindings file read over the defaults; the defaults when none.
  final Keybindings? keymap;

  /// What the status line says of the keybindings file's problems.
  final String? keysFailed;

  /// Whether the prompt starts in vim mode: `editorMode` in the user's
  /// file.
  final bool vim;

  /// The `theme` setting from the user's file; `auto` without one.
  final String? theme;

  /// The user's settings file, where `/vim` and `/theme` save; none
  /// without a config home.
  final String? settingsFile;

  /// [settingsFile] as chord shows it, from `~`.
  final String? shownSettingsFile;

  /// Where the user's settings are, which chord's `settings` tool reads
  /// and writes; none without a home.
  final String? configHome;

  /// The person's home, which paths are shown from as `~`.
  final String? home;

  /// chord's own version.
  final String version;

  /// The directory the window works in, `-C` resolved; null for the
  /// process's own.
  final String? cwd;

  /// The working directory as chord shows it, `~` for home.
  final String directory;

  /// The selected past and its own directory; null for a new session.
  final Resume? resume;

  /// How a child of a runtime starts where the window works, as the
  /// launch directory's settings say; null leaves children unstartable.
  final SessionStart? Function(String runtime)? childStart;

  /// Every agent a child may be opened on, by name, as the original's
  /// `knownAgents` lists them; null for chord's catalog alone.
  final List<String>? runtimeNames;
}

/// The launch's override with no catalog environment, or its catalog start.
({Object command, Map<String, String> env}) agentStart(Launch launch) {
  final Object? override = switch (launch.command) {
    CommandLine(:final line) => line,
    CommandArgv(:final argv) => argv,
    null => launch.agentCommand,
  };
  if (override != null) return (command: override, env: const {});
  final agent = launch.agent;
  if (agent == null) throw StateError('Unknown agent "${launch.name}".');
  return (command: agent.start.command, env: agent.start.env);
}

/// What a call to chord came to: the exit code, and on success what to open.
class CliOutcome {
  /// An exit with [code], and [launch] when there is a window to open.
  const CliOutcome(this.code, [this.launch]) : acp = null;

  /// `chord acp` to serve [acp], which ends the process itself.
  const CliOutcome.acp(AcpStart this.acp) : code = 0, launch = null;

  /// What `chord acp` serves, when the call is one.
  final AcpStart? acp;

  /// The process's exit code.
  final int code;

  /// What to open, when the call opens a window.
  final Launch? launch;
}

/// A call chord refuses as the original's Cliffy does: the help on stdout,
/// the message on stderr between blank lines.
class _Refusal {
  _Refusal(this.message, this.help);

  final String message;
  final String help;
}

/// `chord agents`'s options as Cliffy offers them for a suggestion: each
/// option's name, then its alias, in the order declared.
final List<String> _agentsFlags = [
  for (final option in chordParser.commands['agents']!.options.values) ...[
    '--${option.name}',
    if (option.abbr case final abbr?) '-$abbr',
  ],
];

/// `chord agents`'s refusal of [option], as Cliffy's `didYouMeanOption`
/// words it: its nearest option by Levenshtein distance over code points,
/// case ignored, the first of equals, with no limit; the word is measured
/// as typed, as Cliffy's getFlag keeps a word with a leading dash: `--c`
/// is nearest -C, `-C.` too.
String unknownAgentsOption(String option) {
  final nearest = closestString(option, _agentsFlags);
  return 'Unknown option "$option". Did you mean option "$nearest"?';
}

/// `chord agents`'s [words] as Cliffy's splitFlags reads a short cluster
/// before `--`: `-abc` is `-a -b -c`, one ending in a digit or in
/// JavaScript whitespace is its first letter and the rest, and each piece
/// is read again as a word, so -C takes the next piece as its directory.
/// `-C=dir` is -C with dir. A cluster whose third character is a dot names
/// no option; it stands in the words as a placeholder args reads as an
/// argument, [dotted] mapping it back.
List<String> _agentsWords(List<String> words, Map<String, String> dotted) {
  final out = <String>[];
  final pending = List.of(words);
  for (var i = 0; i < pending.length; i++) {
    final word = pending[i];
    if (word == '--') {
      out.addAll(pending.skip(i));
      break;
    }
    if (word == '-C' || word == '--cwd') {
      out.add(word);
      if (i + 1 < pending.length) out.add(pending[++i]);
      continue;
    }
    if (word.length < 3 || word[0] != '-' || word[1] == '-') {
      out.add(word);
      continue;
    }
    if (word[2] == '.') {
      var token = '__chord_agents_word_${dotted.length}__';
      while (words.contains(token)) {
        token += '_';
      }
      dotted[token] = word;
      out.add(token);
      continue;
    }
    if (word[2] == '=') {
      out.addAll(word[1] == 'C' ? ['-C', word.substring(3)] : [word]);
      continue;
    }
    final letters = word.substring(1).split('=').first.split('');
    final value = word.contains('=') ? word.substring(word.indexOf('=')) : '';
    final pieces = !_numberChar(word[word.length - 1])
        ? [for (final letter in letters) '-$letter']
        : ['-${letters.first}', if (letters.length > 1) letters.skip(1).join()];
    pieces.last += value;
    pending.replaceRange(i, i + 1, pieces);
    i--;
  }
  return out;
}

/// Whether Cliffy's `!isNaN(Number(char))` holds for one UTF-16 unit:
/// a digit, or whitespace, which `Number` trims to the empty string, 0.
bool _numberChar(String char) =>
    jsTrim(char).isEmpty ||
    (char.compareTo('0') >= 0 && char.compareTo('9') <= 0);

/// [error] as the original's Cliffy words it, for the failures in scope.
_Refusal _refusal(ArgParserException error, List<String> args) {
  final help = error.commands.contains('agents') ? agentsHelp : chordHelp;
  final message = error.message;

  if (message.startsWith('Could not find') ||
      message.startsWith('Cannot negate')) {
    final option = error.argumentName ?? '';
    return _Refusal(
      help == agentsHelp
          ? unknownAgentsOption(option)
          : 'Unknown option "$option".',
      help,
    );
  }
  if (message.startsWith('Missing argument for')) {
    return _Refusal(
      'Missing value for option "${_long(error.argumentName)}".',
      help,
    );
  }
  if (message == 'Cannot specify arguments before a command.') {
    final positional = args.where((arg) => !arg.startsWith('-')).skip(1);
    return _Refusal('Too many arguments: ${positional.join(' ')}', help);
  }
  return _Refusal(message, help);
}

/// Runs a call to chord up to the window: prints what the call prints and
/// says what to open. [columns] is the terminal's width, or null when stdout
/// is not a terminal.
Future<CliOutcome> runCli(
  List<String> args, {
  required StringSink stdout,
  required StringSink stderr,
  required String cwd,
  required String? home,
  int? columns,
  Lookup lookup = onPath,
  KnownAgent? Function(String) find = findAgent,
  bool stdinTTY = false,
  bool stdoutTTY = false,
  Map<String, String> environment = const {},
  Future<String> Function()? readPiped,
  SessionOpener open = openHeadlessAgent,
  PickStartupAgent? pickAgent,
  PickStartupResume? pickResume,
  Future<List<SessionRecord>> Function()? readSessionRecords,
  // The targeted reads; when only [readSessionRecords] is given, they are
  // taken from what it reads, so nothing reads the state directory.
  Future<List<SessionRecord>> Function(String id)? readSessionRecordsWithId,
  Future<List<SessionRecord>> Function(String id)? readNamedSessionRecord,
  Future<List<SessionRecord>> Function({
    required String agent,
    required String cwd,
  })?
  readLatestSessionRecord,
  String Function() stateDirectory = chordStateDir,
  void Function(Settings settings)? onSettings,
  void Function(Keybindings keymap)? onKeymap,
  // Has the heap signal write snapshots into the directory it names.
  void Function(String Function() heaps)? watchHeap,
  bool fakeRuntimes = fakeRuntimesFlag,
  String Function() executablePath = resolvedExecutablePath,
  Runner runner = const ProcessRunner(),
  OpenVersions openVersions = RegistryReader.open,
  bool official = officialBuild,
}) async {
  CliOutcome refuse(_Refusal refusal) {
    stdout.writeln(refusal.help);
    stderr.write('\n  error: ${refusal.message}\n\n');
    return const CliOutcome(2);
  }

  // Its stdout is the protocol: nothing of a refusal goes there.
  if (args.firstOrNull == 'acp') {
    return _acp(
      args.sublist(1),
      stdout: stdout,
      stderr: stderr,
      cwd: cwd,
      home: home,
      environment: environment,
      find: find,
    );
  }

  if (args.firstOrNull == 'upgrade') {
    return _upgrade(
      args.sublist(1),
      stdout: stdout,
      stderr: stderr,
      environment: environment,
      executablePath: executablePath,
      runner: runner,
      openVersions: openVersions,
      official: official,
    );
  }

  // Its short clusters as the original reads them.
  final dotted = <String, String>{};
  if (args.firstOrNull == 'agents') {
    args = ['agents', ..._agentsWords(args.sublist(1), dotted)];
  }

  // What args lets pass and Cliffy refuses as it reads: an option given
  // twice, and help or version beside another option.
  final agents = args.firstOrNull == 'agents';
  final reading = agents ? chordParser.commands['agents']! : chordParser;
  final readHelp = agents ? agentsHelp : chordHelp;
  final (:twice, terminator: _, :standalone) = _optionWords(
    reading,
    agents ? args.sublist(1) : args,
  );
  if (twice != null) {
    return refuse(
      _Refusal(
        'Option "$twice" can only occur once, but was found several times.',
        readHelp,
      ),
    );
  }

  final ArgResults results;
  final ResumeArguments adapted;
  try {
    adapted = adaptResumeArguments(args);
    results = chordParser.parse(adapted.arguments);
  } on ResumeArgumentsError catch (error) {
    return refuse(_Refusal(error.message, chordHelp));
  } on ArgParserException catch (error) {
    return refuse(_refusal(error, args));
  }

  final command = results.command;
  final rest = results.rest.map(adapted.positional).toList();
  final intent = adapted.intent;
  // What follows `--` is no option, and Cliffy gives it to no argument of
  // `agents` either.
  // A `--` -C takes as its directory ends nothing.
  var terminator = -1;
  for (var i = 0; i < args.length; i++) {
    if (command != null && (args[i] == '-C' || args[i] == '--cwd')) {
      i++;
    } else if (args[i] == '--') {
      terminator = i;
      break;
    }
  }
  final options = terminator < 0 ? args : args.sublist(0, terminator);
  final literal = terminator < 0 ? 0 : args.length - terminator - 1;

  if (command != null) {
    // args hands `agents -V` and `agents --agent-command` up to chord's
    // own options; `agents` has neither of its own, so the original
    // refuses them.
    // A word -C or --cwd takes as its directory is no option, whatever it
    // looks like, as Cliffy reads it.
    final words = options.skip(options.indexOf('agents') + 1).toList();
    final unconsumed = <String>[];
    for (var i = 0; i < words.length; i++) {
      unconsumed.add(words[i]);
      if (words[i] == '-C' || words[i] == '--cwd') i++;
    }
    final stray = unconsumed
        .map((arg) => arg.split('=').first)
        .where(
          (arg) =>
              arg == '-V' ||
              arg == '--version' ||
              arg == '--agent-command' ||
              arg == '-m' ||
              arg == '--model' ||
              arg == '--effort' ||
              arg == '--permission-mode' ||
              arg == '-c' ||
              arg == '--continue' ||
              arg == '-r' ||
              arg == '--resume' ||
              arg == '-p' ||
              arg == '--print' ||
              arg == '--dangerously-skip-permissions' ||
              arg == '--no-mcp-servers' ||
              arg == '--output-format',
        )
        .firstOrNull;

    if (stray != null) {
      return refuse(_Refusal(unknownAgentsOption(stray), agentsHelp));
    }
  }
  if (standalone != null) {
    final given = agents ? results.command! : results;
    if (intent.kind != ResumeKind.absent ||
        reading.options.keys.any(
          (name) => '--$name' != standalone && given.wasParsed(name),
        )) {
      return refuse(
        _Refusal(
          'Option "$standalone" cannot be combined with other options.',
          readHelp,
        ),
      );
    }
  }
  // `chord agents` reads its own -C, from where chord was started.
  final started = cwd;
  // As the original's resolve(options.cwd): relative to where chord was
  // started, the current directory when not given.
  cwd = p.normalize(p.join(cwd, results.option('cwd') ?? '.'));
  if (results.flag('help')) {
    stdout.writeln(chordHelp);
    return const CliOutcome(0);
  }
  if (results.flag('version')) {
    // As Cliffy does: the long flag names the program, the short one not,
    // and Cliffy looks for the long one in every word, `--` or not.
    stdout.writeln(args.contains('--version') ? 'chord $version' : version);
    return const CliOutcome(0);
  }
  // As Cliffy checks them, in the order the options are declared.
  final print = results.option('print');
  final format = results.option('output-format');
  if (results.option('model') != null && print != null) {
    return refuse(
      _Refusal('Option "--model" conflicts with option "--print".', chordHelp),
    );
  }
  if (print != null && intent.kind == ResumeKind.continuing) {
    return refuse(
      _Refusal(
        'Option "--print" conflicts with option "--continue".',
        chordHelp,
      ),
    );
  }
  if (print != null && intent.kind != ResumeKind.absent) {
    return refuse(
      _Refusal('Option "--print" conflicts with option "--resume".', chordHelp),
    );
  }
  if (format != null && !outputFormats.contains(format)) {
    return refuse(
      _Refusal(
        'Option "--output-format" must be of type "format", but got '
        '"$format". Expected values: "text", "json"',
        chordHelp,
      ),
    );
  }
  if (format != null && print == null) {
    return refuse(
      _Refusal(
        'Option "--output-format" depends on option "--print".',
        chordHelp,
      ),
    );
  }
  // Checked by chord rather than Cliffy, so its refusal says what it is for.
  if (results.flag('dangerously-skip-permissions') && print == null) {
    return refuse(
      _Refusal('--dangerously-skip-permissions works only with -p', chordHelp),
    );
  }
  final configDirectory = configHome(environment);
  LoadedSettings? read;
  Future<LoadedSettings> settings() async => read ??= await loadSettings(
    configHome: configDirectory,
    cwd: cwd,
    home: home,
  );
  // On stderr for scripts; the window says them again, as the alternate
  // screen hides these until chord quits.
  void report(List<SettingsProblem> found) {
    for (final problem in found) {
      stderr.writeln(problemLine(problem));
    }
  }

  Map<String, SettingsCommand> commands() => agentCommands(read!.layers);

  if (command != null) {
    if (command.flag('help')) {
      stdout.writeln(agentsHelp);
      return const CliOutcome(0);
    }
    // A word args cannot read as an option, `--d😀` or `--a.b`, is still
    // one to Cliffy, and refused as unknown before any argument.
    final malformed = command.rest
        .map((word) => dotted[word] ?? word)
        .take(command.rest.length - literal)
        .where((word) => word.length > 1 && word.startsWith('-'))
        .firstOrNull;
    if (malformed != null) {
      // A long option's value after = is no part of its name.
      final name = malformed.startsWith('--')
          ? malformed.split('=').first
          : malformed;
      return refuse(_Refusal(unknownAgentsOption(name), agentsHelp));
    }
    if (command.rest.length > literal) {
      return refuse(
        _Refusal(
          'No arguments allowed for command "chord agents".',
          agentsHelp,
        ),
      );
    }
    final loaded = await loadSettings(
      configHome: configDirectory,
      cwd: p.normalize(p.join(started, command.option('cwd') ?? '.')),
      home: home,
    );
    report(loaded.problems);
    final listed = await listedAgents(lookup, agentCommands(loaded.layers));
    stdout.writeln(
      command.flag('json')
          ? jsonEncode(
              agentsJson(
                listed: listed,
                offered: loaded.settings.offeredAgents,
                preferred: loaded.settings.agent ?? defaultAgent,
                problems: loaded.problems,
                refused: refusedAgents(loaded.layers),
              ),
            )
          : agentTable(listed, columns),
    );
    return const CliOutcome(0);
  }
  if (rest.length > 1) {
    return refuse(
      _Refusal('Too many arguments: ${rest.skip(1).join(' ')}', chordHelp),
    );
  }
  final loaded = await settings();
  // The keybindings file, read once: the start pages and the window take
  // the same keymap, its problems said where the window says them.
  Future<({Keybindings keymap, List<SettingsProblem> problems})>? keysRead;
  Future<({Keybindings keymap, List<SettingsProblem> problems})> keys() async {
    final first = keysRead == null;
    final file = await (keysRead ??= loadKeybindings(
      keybindingsFile(configDirectory),
    ));
    if (first) onKeymap?.call(file.keymap);
    return file;
  }

  // Before any picker takes the terminal: the mouse is the setting's.
  onSettings?.call(loaded.settings);
  final problems = [...loaded.problems];
  report(problems);

  // A window's start alone reads the list, as it is what the start page
  // offers; a name it lacks is a problem of the user's file.
  final userFile = userSettingsFile(configDirectory);
  // `-p` offers nothing, so only a window's start reads the list.
  final offered = userFile == null || print != null
      ? null
      : loaded.settings.offeredAgents;
  List<ListedAgent>? listed;
  if (offered != null) {
    listed = await listedAgents(lookup, commands());
    final unknown = unknownOffered(
      userFile!,
      offeredFrom(listed, offered).unknown,
    );
    report(unknown);
    problems.addAll(unknown);
  }

  final named = rest.firstOrNull;
  final agentCommand = results.option('agent-command');
  // The picker needs every record; an id or --continue reads only what
  // its choice needs.
  final records = recordsOnce(
    readSessionRecords ?? () => readRecords(stateDirectory()),
  );
  final withId = intent.id == null
      ? null
      : recordsOnce(
          () =>
              (readSessionRecordsWithId ??
              (readSessionRecords == null
                  ? (id) => readRecordsWithId(stateDirectory(), id)
                  : (id) async =>
                        recordsWithIdOf(await records(), id)))(intent.id!),
        );
  // chord prints its own record id to resume with; an agent's id, or the
  // original's, is looked up when no record file has the name.
  final printed = intent.id == null
      ? null
      : recordsOnce(
          () =>
              (readNamedSessionRecord ??
              (readSessionRecords == null
                  ? (id) => readNamedRecord(stateDirectory(), id)
                  : (id) async =>
                        namedRecordOf(await records(), id)))(intent.id!),
        );
  Future<List<SessionRecord>> latest({
    required String agent,
    required String cwd,
  }) async => readLatestSessionRecord != null
      ? readLatestSessionRecord(agent: agent, cwd: cwd)
      : readSessionRecords == null
      ? readLatestRecord(stateDirectory(), agent: agent, cwd: cwd)
      : latestRecordOf(await records(), agent: agent, cwd: cwd);
  final recorded =
      named == null && agentCommand == null && intent.kind == ResumeKind.id
      ? (await printed!()).firstOrNull?.agent ??
            recordedAgent(await withId!(), intent.id!)
      : null;
  String? selected = named;
  if (chooseAgentAtStart(
    named: named,
    agentCommand: agentCommand,
    print: print,
    continuing: intent.kind == ResumeKind.continuing,
    resume: intent.kind == ResumeKind.absent ? null : intent,
    stdinTTY: stdinTTY,
    stdoutTTY: stdoutTTY,
  )) {
    await keys();
    final picker = pickAgent;
    if (picker == null) throw ArgumentError.notNull('pickAgent');
    final picked = await picker(
      // The default catalog without the setting; the whole one with it,
      // as the setting may name an own CLI PATH lacks.
      agents: listed ?? offeredAgents(await listedAgents(lookup, commands())),
      offered: offered,
      version: version,
      directory: homePath(cwd, home),
      preferred: loaded.settings.agent ?? defaultAgent,
    );
    if (picked == null) return const CliOutcome(0);
    selected = picked;
  }
  final flags = Flags(
    agent: selected ?? recorded,
    agentCommand: agentCommand,
    model: results.option('model'),
    effort: results.option('effort'),
    permissionMode: results.option('permission-mode'),
  );
  final invoked = resolveStartup(flags, loaded.layers, defaultAgent);
  final name = invoked.agent;
  final agent = find(name);
  // A dev build on the fake starts nothing but the command line's fake.
  if (fakeRuntimes && agentCommand == null) {
    stderr.writeln('chord: ${fakeRuntimesRefusal(name)}');
    return const CliOutcome(1);
  }

  // With a command of its own, the name only names it: no catalog entry or
  // PATH check is needed, as the original's missingCommand skips it.
  if (agent == null &&
      invoked.agentCommand == null &&
      invoked.refused == null) {
    return refuse(
      _Refusal('Unknown agent "$name". `chord agents` lists them.', chordHelp),
    );
  }

  if (print != null) {
    if (invoked.refused case final refused?) {
      stderr.writeln(
        'chord: ${refusalLine(name, refused, cwd: cwd, home: home)}',
      );
      return const CliOutcome(1);
    }
    if (invoked.agentCommand == null) {
      final missing = await missingCommand(name, lookup);
      if (missing != null) {
        stderr.writeln(missing);
        return const CliOutcome(1);
      }
    }
    final mcp = await loadMcpServers(layers: loaded.layers, cwd: cwd);
    report(mcp.problems);
    final taking = mcpServersTaken(
      name,
      loaded.layers,
      flag: results.flag('no-mcp-servers'),
      known: agent,
    );
    final piped = stdinTTY || readPiped == null ? null : await readPiped();
    final (:command, :env) = switch (invoked.agentCommand) {
      CommandLine(:final line) => (
        command: line as Object,
        env: const <String, String>{},
      ),
      CommandArgv(:final argv) => (
        command: argv as Object,
        env: const <String, String>{},
      ),
      null => (command: agent!.start.command as Object, env: agent.start.env),
    };
    StartingValue? starting(Sourced? value) => value == null
        ? null
        : StartingValue(
            value.id,
            from: setWhere(value.from, cwd: cwd, home: home),
          );
    final code = await runHeadless(
      agent: name,
      command: command,
      env: env,
      cwd: cwd,
      prompt: joinPiped(print, piped),
      format: format ?? 'text',
      effort: starting(invoked.effort),
      mode: starting(invoked.permissionMode),
      allowAll: results.flag('dangerously-skip-permissions'),
      stdout: (text) async => stdout.write(text),
      stderr: (text) async => stderr.write(text),
      open: open,
      // The registry's version, when chord runs its own start of the agent.
      pinned: invoked.agentCommand == null ? agent?.pinned : null,
      mcpServers: [for (final defined in mcp.servers) defined.server],
      noMcpServers: taking.none,
    );
    return CliOutcome(code);
  }

  // `kill -USR2 <pid>` looks inside a window that has run for hours
  // without stopping it, as the original's main does here.
  watchHeap?.call(() => p.join(stateDirectory(), 'heaps'));

  Resume? resume;
  try {
    var id = intent.id;
    if (intent.kind == ResumeKind.pick) {
      if (!stdinTTY || !stdoutTTY) {
        return refuse(
          _Refusal('--resume needs an id when not in a terminal', chordHelp),
        );
      }
      final sessions = earlierSessions(await records(), agent: name);
      if (sessions.isEmpty) {
        return refuse(
          _Refusal('No earlier $name session to resume.', chordHelp),
        );
      }
      await keys();
      final picker = pickResume;
      if (picker == null) throw ArgumentError.notNull('pickResume');
      final chosen = await picker(
        sessions: sessions,
        agent: name,
        version: version,
        directory: homePath(cwd, home),
        cwd: cwd,
        home: home,
      );
      if (chosen == null) return const CliOutcome(0);
      id = chosen.resume.sessionId;
    }
    if (intent.kind == ResumeKind.continuing) {
      resume = latestSession(
        await latest(agent: name, cwd: cwd),
        agent: name,
        cwd: cwd,
      );
    } else if (id != null) {
      final record = intent.kind == ResumeKind.id
          ? (await printed!()).firstOrNull
          : null;
      resume = record != null
          ? namedSession(record, id, agent: name)
          // A picked id is among the records the picker already read.
          : sessionById(
              intent.kind == ResumeKind.id ? await withId!() : await records(),
              id,
              agent: name,
              cwd: cwd,
            );
    }
  } on ResumeError catch (error) {
    return refuse(_Refusal(error.message, chordHelp));
  }

  // The directory the session works in, whose files may refuse what the
  // command line's would not: a resumed session's own.
  final place = resume?.cwd ?? cwd;
  var layers = loaded.layers;
  if (place != cwd) {
    final there = await loadSettings(
      configHome: configDirectory,
      cwd: place,
      home: home,
    );
    final added = unseenProblems(problems, there.problems);
    report(added);
    problems.addAll(added);
    layers = there.layers;
  }
  // The directory's servers, its problems said once, as the settings'.
  final mcp = await loadMcpServers(layers: layers, cwd: place);
  final mcpProblems = unseenProblems(problems, mcp.problems);
  report(mcpProblems);
  problems.addAll(mcpProblems);
  final taking = mcpServersTaken(
    name,
    layers,
    flag: results.flag('no-mcp-servers'),
    known: agent,
  );
  final startup = resumedStartup(invoked, flags, layers);
  final refused = agentCommand == null
      ? resolveStartup(Flags(agent: name), layers, name).refused
      : null;
  if (refused != null) {
    stderr.writeln(
      'chord: ${refusalLine(name, refused, cwd: place, home: home)}',
    );
    return const CliOutcome(1);
  }

  if (startup.agentCommand == null) {
    final missing = await missingCommand(name, lookup);

    if (missing != null) {
      stderr.writeln(missing);
      return const CliOutcome(1);
    }
  }

  StartingValue? starting(Sourced? value) => value == null
      ? null
      : StartingValue(
          value.id,
          from: setWhere(value.from, cwd: place, home: home),
        );

  // Each in the transcript, as settings problems are, so all of them can be
  // read at any width; the status line counts them and names the first.
  final bound = await keys();
  report(bound.problems);
  problems.addAll(bound.problems);

  return CliOutcome(
    0,
    Launch(
      name: name,
      agent: agent,
      cwd: cwd,
      agentCommand: agentCommand,
      command: startup.agentCommand,
      version: version,
      directory: homePath(place, home),
      resume: resume,
      childStart: (runtime) => childStart(
        runtime,
        layers,
        cwd: place,
        home: home,
        invoked: invoked,
        flags: flags,
        noMcpServers: results.flag('no-mcp-servers'),
        mcp: mcp,
        find: find,
        fakeRuntimes: fakeRuntimes,
      ),
      runtimeNames: knownAgents(invoked, layers, [
        for (final known in listAgents()) known.name,
      ]),
      starting: Starting(
        model: starting(startup.model),
        effort: starting(startup.effort),
        mode: starting(startup.permissionMode),
      ),
      copyOnSelect: loaded.settings.copyOnSelect != false,
      notifChannel:
          NotifChannel.named(loaded.settings.preferredNotifChannel) ??
          NotifChannel.auto,
      warnings: [
        for (final problem in problems)
          problemNote(problem, cwd: place, home: home),
      ],
      keymap: bound.keymap,
      mcpServers: [
        for (final defined in mcp.servers)
          DefinedServer(
            defined.server,
            shownPath(defined.from, cwd: place, home: home),
          ),
      ],
      mcpIgnored: [
        for (final lost in mcp.ignored)
          Ignored(shownPath(lost.from, cwd: place, home: home), lost.servers),
      ],
      noMcpServers: taking.none,
      noMcpServersFrom: taking.from,
      // The start page's reading when it made one; PATH looked at once.
      readListed: () async => listed ?? await listedAgents(lookup, commands()),
      offered: offered,
      keysFailed: keybindingsNotice('keybindings.json', [
        for (final problem in bound.problems) problem.message,
      ]),
      vim: loaded.settings.editorMode == 'vim',
      theme: loaded.settings.theme,
      settingsFile: userSettingsFile(configDirectory),
      configHome: configDirectory,
      home: home,
      shownSettingsFile: switch (userSettingsFile(configDirectory)) {
        final file? => shownPath(file, cwd: place, home: home),
        null => null,
      },
    ),
  );
}

/// [text] indented as the help's other sections are.
String _indent(String text) =>
    text.split('\n').map((line) => '  $line').join('\n');

/// An option as Cliffy names it in a refusal: by its long name, whichever
/// form was typed.
String? _long(String? name) {
  if (name == null || name.startsWith('--')) return name;
  final abbr = name.replaceFirst('-', '');
  for (final MapEntry(:key, :value) in chordParser.options.entries) {
    if (value.abbr == abbr) return '--$key';
  }
  return name;
}

/// `chord acp` up to serving: a usage error, a refused command or an unknown
/// agent said on [stderr] alone, as the original's `throwErrors` has it.
Future<CliOutcome> _acp(
  List<String> args, {
  required StringSink stdout,
  required StringSink stderr,
  required String cwd,
  required String? home,
  required Map<String, String> environment,
  required KnownAgent? Function(String) find,
}) async {
  final (:twice, terminator: _, :standalone) = _optionWords(acpParser, args);
  if (twice != null) {
    stderr.writeln(
      'chord: Option "$twice" can only occur once, but was found several '
      'times.',
    );
    return const CliOutcome(2);
  }
  final ArgResults results;
  try {
    results = acpParser.parse(args);
  } on ArgParserException catch (error) {
    // A missing value in Cliffy's words, as the main command has it; an
    // unknown option keeps args' words (CTUI-56).
    final message = error.message.startsWith('Missing argument for')
        ? 'Missing value for option "${_long(error.argumentName)}".'
        : error.message;
    stderr.writeln('chord: $message');
    return const CliOutcome(2);
  }
  if (standalone != null &&
      acpParser.options.keys.any(
        (name) => name != 'help' && results.wasParsed(name),
      )) {
    stderr.writeln(
      'chord: Option "$standalone" cannot be combined with other options.',
    );
    return const CliOutcome(2);
  }
  if (results.flag('help')) {
    stdout.writeln(acpHelp);
    return const CliOutcome(0);
  }
  if (results.rest.length > 1) {
    stderr.writeln(
      'chord: Too many arguments: ${results.rest.skip(1).join(' ')}',
    );
    return const CliOutcome(2);
  }
  final configDirectory = configHome(environment);
  final loaded = await loadSettings(
    configHome: configDirectory,
    cwd: cwd,
    home: home,
  );
  for (final problem in loaded.problems) {
    stderr.writeln(problemLine(problem));
  }
  final flags = Flags(
    agent: results.rest.firstOrNull,
    agentCommand: results.option('agent-command'),
    model: results.option('model'),
    effort: results.option('effort'),
    permissionMode: results.option('permission-mode'),
  );
  final invoked = resolveStartup(flags, loaded.layers, defaultAgent);
  final name = invoked.agent;
  if (invoked.refused case final refused?) {
    // As the original's serveAcp says it: the line alone.
    stderr.writeln(refusalLine(name, refused, cwd: cwd, home: home));
    return const CliOutcome(1);
  }
  if (invoked.agentCommand == null && find(name) == null) {
    stderr.writeln('chord: Unknown agent "$name". `chord agents` lists them.');
    return const CliOutcome(2);
  }
  return CliOutcome.acp(
    AcpStart(
      agent: name,
      flags: flags,
      launched: loaded,
      noMcpServers: results.flag('no-mcp-servers'),
      cwd: cwd,
      configHome: configDirectory,
      home: home,
    ),
  );
}

/// `chord upgrade`'s options as Cliffy offers them for a suggestion: each
/// option's name, then its alias, in the order declared.
final List<String> _upgradeFlags = [
  for (final option in upgradeParser.options.values) ...[
    '--${option.name}',
    if (option.abbr case final abbr?) '-$abbr',
  ],
];

/// What args does not check in [words] for [parser] and Cliffy does as
/// it reads them in order: the first option given twice, as typed, where
/// `--` ends the options, and the last of help and version given, which
/// Cliffy's standalone check names. A word args cannot read ends the look,
/// as args then refuses it first.
({String? twice, int terminator, String? standalone}) _optionWords(
  ArgParser parser,
  List<String> words,
) {
  final seen = <String>{};
  String? standalone;
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    if (word == '--') {
      return (twice: null, terminator: i, standalone: standalone);
    }
    if (word.length < 2 || !word.startsWith('-')) continue;
    final long = word.startsWith('--');
    final names = long
        ? [word.split('=').first]
        : [for (final letter in word.substring(1).split('')) '-$letter'];
    for (final (index, flag) in names.indexed) {
      final option = long
          ? parser.options[flag.substring(2)]
          : parser.findByAbbreviation(flag.substring(1));
      if (option == null) {
        return (twice: null, terminator: -1, standalone: standalone);
      }
      if (!seen.add(option.name)) {
        return (twice: flag, terminator: -1, standalone: standalone);
      }
      if (option.name == 'help' || option.name == 'version') {
        standalone = '--${option.name}';
      }
      if (option.isSingle) {
        // A short option's value is the rest of its cluster, else the next
        // word, as a long one's is after `=`, else the next word.
        if (long ? !word.contains('=') : index == names.length - 1) i++;
        break;
      }
    }
  }
  return (twice: null, terminator: -1, standalone: standalone);
}

/// `chord upgrade`: its usage errors as the port's other refusals, its
/// help, or the upgrade itself. Help and refusals open no registry client.
Future<CliOutcome> _upgrade(
  List<String> args, {
  required StringSink stdout,
  required StringSink stderr,
  required Map<String, String> environment,
  required String Function() executablePath,
  required Runner runner,
  required OpenVersions openVersions,
  required bool official,
}) async {
  CliOutcome refuse(String message) {
    stdout.writeln(upgradeHelp);
    stderr.write('\n  error: $message\n\n');
    return const CliOutcome(2);
  }

  final (:twice, :terminator, standalone: _) = _optionWords(
    upgradeParser,
    args,
  );
  if (twice != null) {
    return refuse(
      'Option "$twice" can only occur once, but was found several times.',
    );
  }
  final ArgResults results;
  try {
    results = upgradeParser.parse(args);
  } on ArgParserException catch (error) {
    final message = error.message;
    final name = error.argumentName ?? '';
    if (message.startsWith('Could not find') ||
        message.startsWith('Cannot negate')) {
      return refuse(
        'Unknown option "$name". Did you mean option '
        '"${closestString(name, _upgradeFlags)}"?',
      );
    }
    if (message.startsWith('Missing argument for')) {
      return refuse('Missing value for option "$name".');
    }
    if (message.endsWith('should not be given a value.')) {
      final word = args.firstWhere(
        (arg) => arg.startsWith('$name='),
        orElse: () => '$name=',
      );
      return refuse(
        'Option "$name" doesn\'t take a value, but got '
        '"${word.substring(name.length + 1)}".',
      );
    }
    return refuse(message);
  }
  // Cliffy's help stands alone; --version's default is no option given.
  if (results.flag('help') &&
      upgradeParser.options.keys.any(
        (name) => name != 'help' && results.wasParsed(name),
      )) {
    return refuse('Option "--help" cannot be combined with other options.');
  }
  // What follows `--` is no argument to Cliffy, so nothing to refuse.
  final literal = terminator < 0 ? 0 : args.length - terminator - 1;
  if (results.rest.length > literal) {
    return refuse('No arguments allowed for command "chord upgrade".');
  }
  if (results.flag('help')) {
    stdout.writeln(upgradeHelp);
    return const CliOutcome(0);
  }
  final source = openVersions(version);
  try {
    return CliOutcome(
      await runUpgrade(
        UpgradeRequest(
          list: results.flag('list-versions'),
          to: results.option('version')!,
          force: results.flag('force'),
          verbose: results.flag('verbose'),
        ),
        running: version,
        realPath: executablePath,
        env: environment,
        runner: runner,
        source: source,
        stdout: stdout,
        stderr: stderr,
        official: official,
      ),
    );
  } finally {
    source.close();
  }
}
