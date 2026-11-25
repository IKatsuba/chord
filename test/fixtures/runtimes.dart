// The one catalog of runtimes a test may start: each name maps to the
// original's fake agent or to a scripted opener, and any other name, a real
// runtime's above all, is refused before a process starts. It runs in a
// home of its own, and the fake's children are always on the fake.
import 'dart:io';

import 'package:chord/session/session.dart' show SessionOpener;

import 'fake_harness.dart';

/// Said of a runtime a test asked for that is not in the catalog.
final class NotATestRuntime implements Exception {
  const NotATestRuntime(this.runtime);

  final String runtime;

  @override
  String toString() =>
      '$runtime is not a test runtime; a test starts only the fake or a '
      'scripted opener';
}

/// The runtimes a test admits, and the environment they run in.
final class TestRuntimes {
  /// The fake, as each of [fakes] (scenario and flags given per name), and
  /// each of [scripted] as its own opener.
  TestRuntimes({
    Map<String, ({String? scenario, List<String> flags})> fakes = const {
      'fake': (scenario: null, flags: []),
    },
    Map<String, SessionOpener> scripted = const {},
    void Function(int pid)? onPid,
  }) : _byName = fakes,
       _openers = scripted,
       _heardPid = onPid,
       home = Directory.systemTemp.createTempSync('chord-runtimes-');

  final Map<String, ({String? scenario, List<String> flags})> _byName;
  final Map<String, SessionOpener> _openers;
  final void Function(int pid)? _heardPid;
  // Each issued argv, by identity, with its runtime and a copy of its
  // words: the opener starts the copy, so changing the list given out
  // cannot start another program.
  final _issued = <Object, ({String runtime, List<String> argv})>{};

  /// The home, config, state and cache the runtimes see, deleted by
  /// [dispose].
  final Directory home;

  /// Every runtime name the catalog admits.
  List<String> get names => [..._byName.keys, ..._openers.keys];

  /// What a session of [runtime] starts with: the fake's argv, or a
  /// scripted opener's marker; throws [NotATestRuntime] for any other.
  Object commandOf(String runtime) {
    final List<String> command;
    if (_byName[runtime] case final fake?) {
      command = List.unmodifiable(fakeAgentCommand(fake.scenario, fake.flags));
    } else if (_openers.containsKey(runtime)) {
      command = List.unmodifiable(['scripted', runtime]);
    } else {
      throw NotATestRuntime(runtime);
    }
    _issued[command] = (runtime: runtime, argv: [...command]);
    return command;
  }

  /// The environment every runtime runs in: nothing of the person's.
  Map<String, String> get env => {
    'HOME': home.path,
    'XDG_CONFIG_HOME': '${home.path}/config',
    'XDG_STATE_HOME': '${home.path}/state',
    'XDG_CACHE_HOME': '${home.path}/cache',
    'PATH': Platform.environment['PATH'] ?? '',
    // The fake's children default to codex, which must never start.
    'CHORD_FAKE_CHILD_RUNTIME': 'fake',
  };

  /// The opener sessions use: it starts only a command [commandOf] gave,
  /// and refuses any other before a process starts.
  SessionOpener get opener =>
      ({
        required command,
        env,
        required cwd,
        required onTraffic,
        required onPermission,
        relay,
        cancellationToken,
      }) async {
        final issued = _issued[command];
        if (issued == null) {
          throw NotATestRuntime(
            command is List && command.isNotEmpty
                ? '${command.first}'
                : '$command',
          );
        }
        final open =
            _openers[issued.runtime] ?? fakeOpenerWith(onPid: _heardPid);
        return await open(
          command: List<String>.unmodifiable(issued.argv),
          env: {...?env, ...this.env},
          cwd: cwd,
          onTraffic: onTraffic,
          onPermission: onPermission,
          relay: relay,
          cancellationToken: cancellationToken,
        );
      };

  /// Deletes [home].
  void dispose() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  }
}
