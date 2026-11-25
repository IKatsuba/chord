/// The port's dev runner, as the original's `bun dev`, kept to its `chord`
/// command:
///
///     dart run tool/dev.dart chord [--fake] [--qa [name]] [args…]
///
/// runs chord from source with `dart run`, from the repository's root, with
/// the terminal handed over, and exits with its status. `--fake` runs it as
/// `chord fake --agent-command` with the Dart fake agent,
/// `test/fixtures/fake_agent/main.dart` built to a snapshot, its state kept
/// in [fakeState]
/// instead of the person's own. `--qa` runs it in a capture's directory made
/// afresh ([qaDir]), its state and configuration beside it. Either one builds
/// chord with fixture resource readers (`CHORD_RESOURCE_FIXTURE`), so a dev
/// run never reads a provider's real limits. `--fake` also builds it with
/// [fakeRuntimesDefine] and runs it with [fakeChildEnv], so every runtime it
/// starts, children, teams and `/new` included, is the fake.
/// Everything from chord's first word or option on is chord's; an argument
/// the runner would read as its own, or an empty one, goes after `--`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../test/fixtures/fake.dart';

/// Where a `--fake` run keeps chord's state: one fixed place, as the
/// original's.
const fakeState = '/tmp/chord-fake';

const _usage =
    'Usage: dart run tool/dev.dart chord [--fake] [--qa [name]] '
    '[args…]\n'
    '\n'
    "Run chord from source; the rest of the arguments are chord's, an empty "
    'one only after --.\n'
    '\n'
    '  --fake       On the fake agent in test/fixtures/fake_agent/ '
    'instead of a real one.\n'
    '  --qa [name]  In /tmp/chord-qa.<name>, made afresh, as its directory: '
    "a capture's neutral place (letters, digits, . _ -); with no name, "
    '/tmp/chord-qa. An empty name is dropped: chord then runs as with no --qa.';

/// Where `chord --qa [name]` runs: a fixed place under /tmp, named by the
/// capture, never the per-user temp directory, whose path names the machine;
/// `/tmp/chord-qa` for a bare `--qa` ([name] null). A name that is not a
/// plain word is refused with a [FormatException].
String qaDir(String? name) {
  if (name == null) return '/tmp/chord-qa';
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name) ||
      RegExp(r'^\.+$').hasMatch(name)) {
    throw FormatException(
      '--qa takes letters, digits, . _ and -, not ${jsonEncode(name)}',
    );
  }
  return '/tmp/chord-qa.$name';
}

/// Where a `--qa` run keeps chord's state: beside its directory, made afresh
/// with it, never the person's own; not in it, where the @ file picker would
/// list it in captures.
String qaState(String dir) => '$dir.state';

/// Where a `--qa` run keeps chord's configuration, its user settings and
/// user teams: beside its directory and made afresh too, so a capture shows
/// only what it stages.
String qaConfig(String dir) => '$dir.config';

/// Makes each of [dirs] afresh: emptied if there.
void qaPlace(List<String> dirs) {
  for (final dir in dirs) {
    final directory = Directory(dir);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
    directory.createSync(recursive: true);
  }
}

/// A call to the runner's `chord`: whether on the fake, the capture
/// directory of `--qa` (null without it), and chord's own arguments.
typedef DevChord = ({bool fake, String? qa, List<String> args});

/// Reads `chord [--fake] [--qa [name]] [args…]`, or null when [argv] is not
/// that call. As the original's Cliffy command: the first `--` ends the
/// words it parses, and what follows goes to chord as it is; before it, the
/// runner's options come first, in any order, every word from chord's first
/// one on is chord's, and an empty word is dropped. `--qa` takes the next
/// word as its name unless that is an option, or is written `--qa=name`; an
/// empty name is dropped, as with no `--qa`. A name [qaDir] refuses throws
/// its [FormatException].
DevChord? parseDev(List<String> argv) {
  if (argv.isEmpty || argv.first != 'chord') return null;
  final words = argv.sublist(1);
  final end = words.indexOf('--');
  final parsed = end < 0 ? words : words.sublist(0, end);
  final literal = end < 0 ? const <String>[] : words.sublist(end + 1);
  var fake = false;
  String? qa;
  var first = 0;
  while (first < parsed.length) {
    final word = parsed[first];
    if (word == '--fake') {
      fake = true;
      first++;
    } else if (word == '--qa') {
      first++;
      final name = first < parsed.length && !parsed[first].startsWith('-')
          ? parsed[first++]
          : null;
      qa = name == '' ? null : qaDir(name);
    } else if (word.startsWith('--qa=')) {
      first++;
      final name = word.substring('--qa='.length);
      qa = name.isEmpty ? null : qaDir(name);
    } else {
      break;
    }
  }
  return (
    fake: fake,
    qa: qa,
    args: [
      for (final word in parsed.skip(first))
        if (word.isNotEmpty) word,
      ...literal,
    ],
  );
}

/// [word] as the port's command line splits it back into one word: as it
/// is when nothing in it is special, else in single quotes, a quote in it
/// written '\''.
String shellWord(String word) =>
    RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$').hasMatch(word)
    ? word
    : "'${word.replaceAll("'", r"'\''")}'";

/// The define that builds chord with fixture resource readers.
const fixtureDefine = '-DCHORD_RESOURCE_FIXTURE=true';

/// The define that builds chord to start every runtime as its
/// `--agent-command`, the fake, and nothing without one.
const fakeRuntimesDefine = '-DCHORD_FAKE_RUNTIMES=true';

/// What a `--fake` run lays over chord's environment: the fake's own
/// children ask for the fake runtime, not codex.
const fakeChildEnv = {'CHORD_FAKE_CHILD_RUNTIME': 'fake'};

/// The argv that runs chord from source: [dart] running the port's
/// `bin/chord.dart` under [portDir], on the fake agent [fake] starts with
/// when given, then
/// [args]. On the fake, or with [fixtureResources], chord is built with
/// [fixtureDefine], as the original's dev tools build it; on the fake also
/// with [fakeRuntimesDefine].
List<String> chordArgv({
  required String dart,
  required String portDir,
  required List<String> args,
  List<String>? fake,
  bool fixtureResources = false,
}) => [
  dart,
  'run',
  if (fake != null || fixtureResources) fixtureDefine,
  if (fake != null) fakeRuntimesDefine,
  p.join(portDir, 'bin', 'chord.dart'),
  if (fake != null) ...[
    'fake',
    '--agent-command',
    fake.map(shellWord).join(' '),
  ],
  ...args,
];

/// The environment laid over the runner's for chord: [state] made if
/// missing and named as `XDG_STATE_HOME`, and [config], when given, as
/// `XDG_CONFIG_HOME`; nothing without them.
Map<String, String> stateEnv(String? state, {String? config}) {
  if (state != null) Directory(state).createSync(recursive: true);
  return {'XDG_STATE_HOME': ?state, 'XDG_CONFIG_HOME': ?config};
}

/// chord's arguments for [call]: `-C <dir>` first on a capture, as the
/// original passes it, so chord shows the directory as given, never the
/// path a symlink such as /tmp resolves to; then [call]'s own.
List<String> chordArgs(DevChord call) => [
  if (call.qa case final qa?) ...['-C', qa],
  ...call.args,
];

/// The environment laid over the runner's for [call]: a capture's state and
/// configuration, else the fake's state, as [stateEnv] makes them, and on
/// the fake [fakeChildEnv].
Map<String, String> chordEnv(DevChord call) => {
  ...switch (call.qa) {
    final qa? => stateEnv(qaState(qa), config: qaConfig(qa)),
    null => stateEnv(call.fake ? fakeState : null),
  },
  if (call.fake) ...fakeChildEnv,
};

/// A child's exit status as a shell gives it: a signal is 128 + its number.
int shellStatus(int exitCode) => exitCode < 0 ? 128 - exitCode : exitCode;

Future<void> main(List<String> argv) async {
  final DevChord? call;
  try {
    call = parseDev(argv);
  } on FormatException catch (error) {
    stderr.writeln('$_usage\n\nerror: ${error.message}');
    exit(2);
  }
  if (call == null) {
    stderr.writeln(_usage);
    exit(2);
  }
  List<String>? fake;
  if (call.fake) {
    if (fakeAgent.reason case final reason?) {
      stderr.writeln('dev: the fake agent cannot run: $reason');
      exit(1);
    }
    fake = fakeAgentCommand();
  }
  final portDir = portPackageDir();
  final qa = call.qa;
  if (qa != null) qaPlace([qa, qaState(qa), qaConfig(qa)]);
  final command = chordArgv(
    dart: Platform.resolvedExecutable,
    portDir: portDir,
    args: chordArgs(call),
    fake: fake,
    fixtureResources: qa != null,
  );
  final child = await Process.start(
    command.first,
    command.sublist(1),
    workingDirectory: portDir,
    environment: chordEnv(call),
    mode: ProcessStartMode.inheritStdio,
  );
  exit(shellStatus(await child.exitCode));
}
