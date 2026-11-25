import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/runner.dart';
import '../../../tool/release/selftest.dart';
import 'fixtures/recording_runner.dart';

Matcher dies(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

const fake = "bun '/chord/tests/fixtures/fake_agent/main.ts'";

/// `chord acp` as the fake makes it answer: initialize, a session, then a
/// prompt that asks a permission and answers once it is given.
/// [permission] false answers the prompt without asking.
ScriptedStarted acp({bool permission = true, int? status = 0}) =>
    ScriptedStarted((line) {
      final message = jsonDecode(line) as Map<String, Object?>;
      String reply(Map<String, Object?> body) =>
          jsonEncode({'jsonrpc': '2.0', ...body});
      return switch (message) {
        {'method': 'initialize'} => [
          reply({'id': 1, 'result': <String, Object>{}}),
        ],
        {'method': 'session/new'} => [
          reply({
            'id': 2,
            'result': {'sessionId': 's1'},
          }),
        ],
        {'method': 'session/prompt'} when permission => [
          reply({'id': 'p1', 'method': 'session/request_permission'}),
        ],
        {'method': 'session/prompt'} => [
          reply({
            'id': 3,
            'result': {'stopReason': 'end_turn'},
          }),
        ],
        {'id': 'p1', 'result': _} => [
          reply({
            'id': 3,
            'result': {'stopReason': 'end_turn'},
          }),
        ],
        _ => const [],
      };
    }, status: status);

void main() {
  late Directory place;
  late String binary;
  late List<String> said;
  setUp(() {
    place = Directory.systemTemp.createTempSync('selftest_test');
    binary = p.join(place.path, 'chord');
    File(binary).writeAsStringSync('bin');
    said = [];
  });
  tearDown(() => place.deleteSync(recursive: true));

  /// A machine where everything the self-test runs answers as a good
  /// binary does, but for what [override] answers first.
  ({RecordingRunner runner, ScriptedStarted acp}) machine({
    Ran? Function(List<String> argv)? override,
    ScriptedStarted? started,
    List<String> screens = const ['', 'Ready  ? for shortcuts'],
  }) {
    final acpChild = started ?? acp();
    var shown = 0;
    var answered = false;
    final runner = RecordingRunner((argv) {
      if (override?.call(argv) case final ran?) return ran;
      switch (argv) {
        case [..., '--version']:
          return const Ran(0, stdout: 'chord 1.2.3\n');
        case [..., '-p', 'text']:
          return const Ran(0, stdout: 'Hello, world. This reply came.\n');
        case ['tmux', _, _, 'send-keys', ...]:
          answered = true;
          return const Ran(0);
        case ['tmux', _, _, 'capture-pane', ...]:
          if (answered) return const Ran(0, stdout: 'Hello, world.\n');
          final screen =
              screens[shown < screens.length ? shown : screens.length - 1];
          shown++;
          return Ran(0, stdout: '$screen\n');
      }
      return null;
    }, (_) => acpChild);
    return (runner: runner, acp: acpChild);
  }

  Future<void> run(
    RecordingRunner runner, {
    String? arch,
    Stream<ProcessSignal> Function(ProcessSignal)? watch,
    void Function(ProcessSignal)? raise,
    Future<void> Function(Duration)? sleep,
    Duration acpAnswer = const Duration(seconds: 5),
    Duration acpExit = const Duration(seconds: 5),
  }) => selftest(
    runner,
    binary: binary,
    version: '1.2.3',
    fake: fake,
    socket: 'chord-selftest-test',
    sleep: sleep ?? (_) async {},
    report: said.add,
    arch: arch,
    watch: watch ?? (_) => const Stream.empty(),
    raise: raise ?? (_) => fail('no signal was sent'),
    acpAnswer: acpAnswer,
    acpExit: acpExit,
  );

  /// Runs a self-test whose `chord acp` is [child], expecting it to die
  /// saying [why], then checks the child was killed, reaped and no longer
  /// heard, and the scratch directory is gone.
  Future<void> failsInAcp(
    ScriptedStarted child,
    String why, {
    Duration acpAnswer = const Duration(seconds: 5),
    Duration acpExit = const Duration(seconds: 5),
  }) async {
    final (:runner, acp: _) = machine(started: child);
    await expectLater(
      run(runner, acpAnswer: acpAnswer, acpExit: acpExit),
      dies(why),
    );
    expect(child.killed, isTrue, reason: 'killed');
    expect(child.ended, isTrue, reason: 'reaped');
    expect(child.heard, isFalse, reason: 'no listener left');
    expect(Directory(scratchOf(runner)).existsSync(), isFalse);
  }

  group('the acp child is ended however the step fails', () {
    List<String> silent(String _) => const [];

    test('a write that throws', () async {
      await failsInAcp(
        ScriptedStarted(silent, writeError: StateError('broken pipe')),
        '$binary acp could not be written to: Bad state: broken pipe',
      );
    });

    test('output that cannot be read', () async {
      await failsInAcp(
        ScriptedStarted(silent, linesError: const FormatException('bad utf8')),
        "$binary acp's output could not be read: FormatException: bad utf8",
      );
    });

    test('an EOF that cannot be sent', () async {
      final child = acp();
      await failsInAcp(
        ScriptedStarted(child.reply, closeError: StateError('closed')),
        '$binary acp could not be sent EOF: Bad state: closed',
      );
    });

    test('no answer within the limit', () async {
      await failsInAcp(
        ScriptedStarted(silent, status: null),
        '$binary acp never answered',
        acpAnswer: const Duration(milliseconds: 50),
      );
    });

    test('no exit within the limit after EOF', () async {
      await failsInAcp(
        ScriptedStarted(acp().reply, status: null),
        '$binary acp did not leave cleanly at EOF (-1)',
        acpExit: const Duration(milliseconds: 50),
      );
    });

    test('a kill that takes a while is waited for', () async {
      await failsInAcp(
        ScriptedStarted(
          silent,
          status: null,
          killDelay: const Duration(milliseconds: 100),
        ),
        '$binary acp never answered',
        acpAnswer: const Duration(milliseconds: 50),
      );
    });
  });

  test('a signal during the acp step ends the acp child too', () async {
    final hup = StreamController<ProcessSignal>.broadcast();
    final raised = <ProcessSignal>[];
    final child = ScriptedStarted((_) => const [], status: null);
    var reapedBeforeScratch = false;
    late RecordingRunner runner;
    final made = machine(started: child);
    runner = RecordingRunner(made.runner.answer, (argv) {
      // The signal comes once the child is running.
      scheduleMicrotask(() => hup.add(ProcessSignal.sighup));
      return child;
    });
    final ran = run(
      runner,
      watch: (signal) =>
          signal == ProcessSignal.sighup ? hup.stream : const Stream.empty(),
      raise: (signal) {
        reapedBeforeScratch = child.ended;
        raised.add(signal);
      },
      acpAnswer: const Duration(milliseconds: 200),
    );
    // The cleanup killed the child, so the step dies by its early exit.
    await expectLater(ran, dies('acp exited early'));
    expect(raised, [ProcessSignal.sighup]);
    expect(reapedBeforeScratch, isTrue);
    expect(child.killed, isTrue);
    expect(Directory(scratchOf(runner)).existsSync(), isFalse);
    expect(hup.hasListener, isFalse);
    await hup.close();
  });

  test('a good binary passes every step, and leaves nothing behind', () async {
    final (:runner, acp: child) = machine();
    await run(runner);
    final scratch = scratchOf(runner);
    final project = p.join(scratch, 'project');
    expect(runner.argvs[0], ['sh', '-c', 'command -v tmux']);
    expect(runner.argvs[1], [binary, '--version']);
    expect(runner.argvs[2], [
      binary,
      'fake',
      '--agent-command',
      fake,
      '-p',
      'text',
    ]);
    expect(runner.calls[2].cwd, project);
    expect(runner.calls[2].env, {
      'XDG_STATE_HOME': p.join(scratch, 'state'),
      'XDG_CONFIG_HOME': p.join(scratch, 'config'),
    });
    expect(runner.argvs[3], [binary, 'acp', 'fake', '--agent-command', fake]);
    expect(runner.calls[3].cwd, project);
    expect(
      [for (final line in child.written) (jsonDecode(line) as Map)['method']],
      ['initialize', 'session/new', 'session/prompt', null],
    );
    expect(runner.argvs[4].take(9), [
      'tmux',
      '-L',
      'chord-selftest-test',
      'new-session',
      '-d',
      '-s',
      'selftest',
      '-x',
      '100',
    ]);
    expect(
      runner.argvs[4].last,
      "'$binary' fake --agent-command \"$fake\" "
      "2>'${p.join(scratch, 'stderr')}'; sleep 60",
    );
    expect(
      runner.argvs,
      anyElement(
        equals([
          'tmux',
          '-L',
          'chord-selftest-test',
          'send-keys',
          '-t',
          'selftest',
          'text',
          'Enter',
        ]),
      ),
    );
    expect(runner.argvs.last, [
      'tmux',
      '-L',
      'chord-selftest-test',
      'kill-server',
    ]);
    expect(Directory(scratch).existsSync(), isFalse);
    expect(said, ['self-tested $binary']);
  });

  test('under Rosetta every run goes through arch -x86_64', () async {
    final (:runner, acp: _) = machine();
    await run(runner, arch: 'x86_64');
    expect(runner.argvs[1], ['arch', '-x86_64', binary, '--version']);
    expect(runner.argvs[3].take(4), ['arch', '-x86_64', binary, 'acp']);
    expect(runner.argvs[4].last, startsWith("arch -x86_64 '$binary' fake"));
    expect(said, ['self-tested $binary under x86_64']);
  });

  test('a binary that is not there dies before anything runs', () async {
    File(binary).deleteSync();
    final (:runner, acp: _) = machine();
    await expectLater(run(runner), dies('no binary at $binary'));
    expect(runner.calls, isEmpty);
  });

  test('without tmux it dies', () async {
    final (:runner, acp: _) = machine(
      override: (argv) => argv.first == 'sh' ? const Ran(1) : null,
    );
    await expectLater(run(runner), dies('the self-test needs tmux'));
  });

  test('a version other than pubspec.yaml\'s dies, scratch removed', () async {
    final (:runner, acp: _) = machine(
      override: (argv) => argv.last == '--version'
          ? const Ran(0, stdout: 'chord 0.0.1\n')
          : null,
    );
    await expectLater(
      run(runner),
      dies('$binary --version said chord 0.0.1, not 1.2.3'),
    );
    expect(Directory(scratchOf(runner)).existsSync(), isFalse);
    expect(runner.argvs.last.last, 'kill-server');
  });

  test('a -p that fails dies with what it said', () async {
    final (:runner, acp: _) = machine(
      override: (argv) =>
          argv.last == 'text' ? const Ran(1, stderr: 'no agent\n') : null,
    );
    await expectLater(run(runner), dies('$binary -p failed: no agent'));
  });

  test('a -p that answers otherwise dies with the answer', () async {
    final (:runner, acp: _) = machine(
      override: (argv) =>
          argv.last == 'text' ? const Ran(0, stdout: 'Goodbye\n') : null,
    );
    await expectLater(run(runner), dies('$binary -p answered: Goodbye'));
  });

  test("an acp prompt answered without its permission dies", () async {
    final (:runner, acp: child) = machine(started: acp(permission: false));
    await expectLater(run(runner), dies("$binary acp's prompt answered: "));
    expect(child.killed, isTrue);
  });

  test('an acp that does not leave cleanly at EOF dies', () async {
    final (:runner, acp: _) = machine(started: acp(status: 1));
    await expectLater(
      run(runner),
      dies('$binary acp did not leave cleanly at EOF (1)'),
    );
  });

  test('a window that never shows its prompt dies with its screen, scratch '
      'removed', () async {
    final (:runner, acp: _) = machine(screens: ['starting…']);
    var slept = 0;
    await expectLater(
      run(runner, sleep: (_) async => slept++),
      dies(
        "$binary's window never showed \"for shortcuts\"; stderr:  "
        'screen:\nstarting…',
      ),
    );
    expect(slept, 60);
    expect(Directory(scratchOf(runner)).existsSync(), isFalse);
  });

  test('a signal while it waits ends its tmux and removes its scratch, and '
      'ends the run by that signal', () async {
    final signals = {
      for (final signal in [
        ProcessSignal.sigterm,
        ProcessSignal.sigint,
        ProcessSignal.sighup,
      ])
        signal: StreamController<ProcessSignal>.broadcast(),
    };
    final raised = <ProcessSignal>[];
    final (:runner, acp: _) = machine(screens: ['starting…']);
    var slept = 0;
    late String scratch;
    final ran = run(
      runner,
      watch: (signal) => signals[signal]!.stream,
      raise: raised.add,
      sleep: (_) async {
        if (++slept == 3) {
          scratch = scratchOf(runner);
          signals[ProcessSignal.sighup]!.add(ProcessSignal.sighup);
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);
        }
      },
    );
    // The fake raise does not end this test's process, so the run goes on
    // to its own end; what matters is what the signal did first.
    await expectLater(ran, dies('never showed'));
    expect(raised, [ProcessSignal.sighup]);
    expect(Directory(scratch).existsSync(), isFalse);
    expect(
      runner.argvs.where((argv) => argv.last == 'kill-server'),
      hasLength(1),
    );
    for (final controller in signals.values) {
      expect(controller.hasListener, isFalse);
      await controller.close();
    }
  });

  group('tester: self-test event and ownership boundaries', () {
    test('malformed JSON output still releases child and scratch', () async {
      await failsInAcp(
        ScriptedStarted((_) => ['not JSON']),
        'acp wrote a line that is not JSON',
      );
    });

    test(
      'an exit completed before listening is still observed and cleaned',
      () async {
        final child = ScriptedStarted((_) => [], status: 3);
        await child.close();
        await failsInAcp(child, 'acp exited early');
      },
    );

    test(
      'two simultaneous runs keep disjoint scratch state and cleanup',
      () async {
        final first = machine();
        final second = machine();
        await Future.wait([run(first.runner), run(second.runner)]);
        final a = scratchOf(first.runner);
        final b = scratchOf(second.runner);
        expect(a, isNot(b));
        expect(Directory(a).existsSync(), isFalse);
        expect(Directory(b).existsSync(), isFalse);
        expect(first.acp.heard, isFalse);
        expect(second.acp.heard, isFalse);
      },
    );
  });
}

/// The scratch directory a run used, from the environment it gave.
String scratchOf(RecordingRunner runner) => p.dirname(
  runner.calls
      .firstWhere((call) => call.env.containsKey('XDG_STATE_HOME'))
      .env['XDG_STATE_HOME']!,
);
