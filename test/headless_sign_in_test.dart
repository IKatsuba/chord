// What -p says when its agent does not start: the sign-in it needs (CHD-435)
// and the version chord pins (CHD-454), as the original's
// tests/headless_test.ts and sign-in cases say them.
import 'dart:io';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/headless.dart';
import 'package:chord/session/session.dart' show SessionOpener;
import 'package:chord/session/sign_in.dart';
import 'package:chord/session/start_failure.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../tool/dev.dart' show shellWord;
import 'fixtures/fake_harness.dart';

const _wayOn =
    "chord: chord does not sign agents in. Sign in with memory's own CLI in a "
    'terminal, or set its API key where it offers one.';

/// An agent in memory that answers initialize with [methods] and refuses
/// the session with authRequired; or, with [exitCode], exits first.
SessionOpener _agent({int? exitCode, required MemoryAgentProcess process}) =>
    ({
      required command,
      env,
      required cwd,
      required onTraffic,
      required onPermission,
      relay,
      cancellationToken,
    }) {
      if (exitCode != null) {
        process.writeStderr('boom\n');
        process.closeStderr();
        process.exit(Exit(exitCode));
        process.closeStdout();
      }
      return connectAgent(
        process,
        onTraffic: onTraffic,
        onPermission: onPermission,
        relay: relay,
        cancellationToken: cancellationToken,
      );
    };

/// Runs `-p` on an in-memory agent under fake time; its code and stderr.
({int code, String stderr}) _run(
  SessionOpener Function(MemoryAgentProcess process) open, {
  void Function(MemoryAgentProcess process)? answer,
  String? pinned,
}) {
  late int code;
  final err = StringBuffer();
  fakeAsync((async) {
    late final MemoryAgentProcess process;
    process = MemoryAgentProcess(
      onSignal: (_) {
        if (process.exited) return;
        process.exit(const Exit(143, 'SIGTERM'));
        process.closeStdout();
        process.closeStderr();
      },
    );
    var done = false;
    runHeadless(
      agent: 'memory',
      command: 'memory',
      cwd: '/w',
      prompt: 'hello',
      format: 'text',
      open: open(process),
      pinned: pinned,
      stdout: (_) async {},
      stderr: (text) async => err.write(text),
    ).then((value) {
      code = value;
      done = true;
    });
    for (var i = 0; i < 100 && !done; i++) {
      async.flushMicrotasks();
      answer?.call(process);
      async.elapse(const Duration(milliseconds: 100));
    }
    expect(done, isTrue);
  });
  return (code: code, stderr: '$err');
}

/// Answers initialize with [methods], then refuses session/new.
void Function(MemoryAgentProcess) _refusing(
  List<Map<String, Object?>>? methods,
) {
  final answered = <Object?>{};
  return (process) {
    for (final message in [...process.stdin.messages]) {
      final id = message['id'];
      if (id == null || !answered.add(id)) continue;
      if (message['method'] == 'initialize') {
        process.send({
          'jsonrpc': '2.0',
          'id': id,
          'result': {'protocolVersion': 1, 'authMethods': ?methods},
        });
      } else if (message['method'] == 'session/new') {
        process.send({
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': -32000, 'message': 'Authentication required'},
        });
      }
    }
  };
}

void main() {
  group('tester: CTUI-28 auth failure ownership', () {
    test(
      'auth failure with no methods closes before returning and never prompts',
      () {
        late MemoryAgentProcess owned;
        final result = _run((process) {
          owned = process;
          return _agent(process: process);
        }, answer: _refusing([]));
        expect(result.code, 1);
        expect(result.stderr, contains(_wayOn));
        expect(result.stderr, isNot(contains('offers:')));
        expect(owned.exited, isTrue);
        expect(
          owned.stdin.messages.where(
            (message) => message['method'] == 'session/prompt',
          ),
          isEmpty,
        );
      },
    );

    test(
      'auth code rather than authentication words decides sign-in guidance',
      () {
        late MemoryAgentProcess owned;
        final answered = <Object?>{};
        final result = _run(
          (process) {
            owned = process;
            return _agent(process: process);
          },
          answer: (process) {
            for (final message in [...process.stdin.messages]) {
              final id = message['id'];
              if (id == null || !answered.add(id)) continue;
              process.send({
                'jsonrpc': '2.0',
                'id': id,
                if (message['method'] == 'initialize')
                  'result': {'protocolVersion': 1}
                else
                  'error': {
                    'code': -32602,
                    'message': 'Authentication required words only',
                  },
              });
            }
          },
        );
        expect(result.code, 1);
        expect(
          result.stderr,
          contains(
            'it refused session/new: Authentication required words only',
          ),
        );
        expect(result.stderr, isNot(contains('does not sign agents in')));
        expect(owned.exited, isTrue);
      },
    );

    test('the pin precedes auth ways and description-only methods survive', () {
      final result = _run(
        (process) => _agent(process: process),
        answer: _refusing([
          {'id': 'one', 'name': ' ', 'description': ' Browser only '},
        ]),
        pinned: 'memory-acp@1.2.3',
      );
      expect(result.stderr.split('\n'), [
        'chord: memory did not start: Authentication required',
        'chord: chord ran memory-acp@1.2.3, the version this chord pins.',
        'chord: memory offers: Browser only',
        _wayOn,
        '',
      ]);
    });
  });
  test('the ways in a method names: its name and description, or either '
      'alone; one with neither is left out', () {
    expect(
      waysOf([
        acp.AuthMethod.fromJson({
          'id': 'a',
          'name': ' Log in ',
          'description': 'with your browser',
        }),
        acp.AuthMethod.fromJson({'id': 'b', 'name': 'API key'}),
        acp.AuthMethod.fromJson({'id': 'c', 'name': ' ', 'description': ''}),
      ]),
      [
        (name: 'Log in', description: 'with your browser'),
        (name: 'API key', description: null),
      ],
    );
    expect(waysOf(null), isEmpty);
  });

  test('a login the agent needs is said with its ways in and the way on', () {
    final run = _run(
      (process) => _agent(process: process),
      answer: _refusing([
        {'id': 'a', 'name': 'Log in', 'description': 'with your browser'},
        {'id': 'b', 'name': 'API key'},
      ]),
    );
    expect(run.code, 1);
    expect(run.stderr.split('\n'), [
      'chord: memory did not start: Authentication required',
      'chord: memory offers: Log in (with your browser), API key',
      _wayOn,
      '',
    ]);
  });

  test('an agent that offers no way in gets the way on alone', () {
    final run = _run(
      (process) => _agent(process: process),
      answer: _refusing(null),
    );
    expect(run.stderr.split('\n'), [
      'chord: memory did not start: Authentication required',
      _wayOn,
      '',
    ]);
  });

  test("the version chord pins heads what it knows of the failure", () {
    final run = _run(
      (process) => _agent(process: process, exitCode: 99),
      pinned: 'memory-acp@1.2.3',
    );
    expect(run.code, 1);
    expect(run.stderr.split('\n'), [
      'chord: memory did not start: it exited with code 99 before answering '
          'initialize.',
      'chord: chord ran memory-acp@1.2.3, the version this chord pins.',
      'chord: $stderrHeading',
      'chord:   boom',
      '',
    ]);
  });

  test(
    "the fake that needs a login says so, as the original's",
    () async {
      final dir = Directory.systemTemp.createTempSync('chord-sign-in-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final err = StringBuffer();
      final code = await runHeadless(
        agent: 'fake',
        command: fakeAgentCommand(null, [
          '--auth-required',
          'methods',
        ]).map(shellWord).join(' '),
        cwd: dir.path,
        prompt: 'text',
        format: 'text',
        stdout: (_) async {},
        stderr: (text) async => err.write(text),
      );
      expect(code, 1);
      expect('$err'.split('\n'), [
        'chord: fake did not start: Authentication required: run `fake login` '
            'from your terminal, or set FAKE_API_KEY',
        'chord: fake offers: Log in with the fake (Run `fake login` in the '
            'terminal), Log in with SSO',
        "chord: chord does not sign agents in. Sign in with fake's own CLI in a "
            'terminal, or set its API key where it offers one.',
        '',
      ]);
    },
    skip: fakeAgentSkip,
    tags: ['fake_agent'],
  );
}
