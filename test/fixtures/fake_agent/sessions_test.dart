// The original's tests/fixtures/fake_agent/sessions_test.ts: a wait for a
// steered message, and what the screenshots ask of the fake's sessions,
// these through chord's own session on the Dart fake.
import 'dart:async';
import 'dart:io';

import 'package:chord/session/session.dart';
import 'package:test/test.dart';

import '../fake.dart';
import '../fake_harness.dart' show fakeSessionOpener;
import 'sessions.dart';
import 'signals.dart';

void main() {
  test('a wait for a steered message settles on one, and stops listening '
      '(CHD-470)', () async {
    final waiting = steeredInto('s1', Aborter().signal);
    emitSteer('s1');
    await waiting.steered;
    waiting.stop();
    expect(steerListeners('s1'), 0);
  });

  test('a wait the turn ends before awaiting stops listening and raises '
      'nothing unhandled (CHD-470)', () async {
    final unhandled = <Object>[];
    await runZonedGuarded(() async {
      // Cancelled while it set up, never awaited.
      final turn = Aborter();
      final cancelled = steeredInto('s2', turn.signal);
      turn.abort();
      cancelled.stop();

      // Stopped at once, never awaited.
      steeredInto('s3', Aborter().signal).stop();

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(steerListeners('s2') + steerListeners('s3'), 0);
      await expectLater(cancelled.steered, throwsA(anything));
    }, (error, _) => unhandled.add(error));
    expect(unhandled, isEmpty);
  });

  group('CHD-470 tester: steering waiter isolation and cancellation', () {
    test('an already cancelled turn installs no listener', () async {
      final turn = Aborter()..abort();
      final waiting = steeredInto('tester-pre-cancelled', turn.signal);
      try {
        await expectLater(waiting.steered, throwsA(anything));
        expect(steerListeners('tester-pre-cancelled'), 0);
      } finally {
        waiting.stop();
      }
    });

    test('steering one session leaves another pending until that turn is '
        'cancelled', () async {
      final first = steeredInto('tester-first', Aborter().signal);
      final turn = Aborter();
      final second = steeredInto('tester-second', turn.signal);
      var settled = false;
      second.steered
          .then((_) => settled = true, onError: (Object _) => settled = true)
          .ignore();
      try {
        emitSteer('tester-first');
        await first.steered;
        await Future<void>.value();
        expect(settled, isFalse);
        expect(steerListeners('tester-second'), 1);
        turn.abort();
        await expectLater(second.steered, throwsA(anything));
        expect(steerListeners('tester-first'), 0);
        expect(steerListeners('tester-second'), 0);
      } finally {
        first.stop();
        second.stop();
      }
    });

    test('repeated cleanup of an abandoned setup does not detach a new '
        'waiter for the same session', () async {
      final old = steeredInto('tester-reused', Aborter().signal);
      final current = steeredInto('tester-reused', Aborter().signal);
      try {
        old
          ..stop()
          ..stop();
        await expectLater(old.steered, throwsA(anything));
        expect(steerListeners('tester-reused'), 1);
        emitSteer('tester-reused');
        await current.steered;
        expect(steerListeners('tester-reused'), 0);
      } finally {
        old.stop();
        current.stop();
      }
    });
  });

  group("what the screenshots ask of the fake's sessions (CHD-560)", () {
    const source = '11111111-1111-4111-8111-111111111111';

    /// What [read] finds of a session opened on the Dart fake with
    /// [flags], and [env] around it, closed after.
    Future<T> opened<T>(
      List<String> flags,
      FutureOr<T> Function(Session session) read, {
      String? fork,
      List<String> env = const [],
    }) async {
      final dir = Directory.systemTemp.createTempSync('chord-fake-sessions-');
      final session = await openSession(
        agent: 'fake',
        command: [
          'env',
          '-u',
          'CHORD_FAKE_AUTO_MODE',
          '-u',
          'CHORD_FAKE_FORK_MODEL',
          ...env,
          ...dartFakeCommand(null, flags),
        ],
        cwd: dir.path,
        open: fakeSessionOpener(),
        fork: fork,
      );
      try {
        return await read(session);
      } finally {
        await session.close();
        await session.exited;
        dir.deleteSync(recursive: true);
      }
    }

    List<Object?>? modes(Session session) => [
      for (final mode
          in (session.state.modes?['availableModes'] as List?) ?? const [])
        (mode as Map)['id'],
    ];
    Object? mode(Session session) => session.state.configOptions.firstWhere(
      (option) => option['category'] == 'mode',
    )['currentValue'];
    Object? model(Session session) => session.state.configOptions.firstWhere(
      (option) => option['category'] == 'model',
    )['currentValue'];

    test(
      'its modes are the three, and --auto-mode adds auto after them',
      () async {
        expect(await opened(const [], modes), [
          'default',
          'acceptEdits',
          'plan',
        ]);
        expect(await opened(const ['--auto-mode'], modes), [
          'default',
          'acceptEdits',
          'plan',
          'auto',
        ]);
      },
    );

    test(
      'a fork is on its first model, and on the one --fork-model names',
      () async {
        expect(
          await opened(const ['--fork'], model, fork: source),
          'fake-large',
        );
        expect(
          await opened(
            const ['--fork', '--fork-model', 'fake-small'],
            model,
            fork: source,
          ),
          'fake-small',
        );
      },
    );

    test('environment-enabled auto is selectable while another process '
        'keeps the default modes', () async {
      await Future.wait([
        opened(const [], (session) async {
          expect(modes(session), ['default', 'acceptEdits', 'plan', 'auto']);
          await session.setMode('auto');
          expect(mode(session), 'auto');
        }, env: const ['CHORD_FAKE_AUTO_MODE=1']),
        opened(const [], (session) {
          expect(modes(session), ['default', 'acceptEdits', 'plan']);
          expect(mode(session), 'default');
        }),
      ]);
    });

    test('only the documented environment value enables auto, while the '
        'flag still enables it', () async {
      bool hasAuto(Session session) => modes(session)!.contains('auto');
      for (final value in ['0', 'true']) {
        expect(
          await opened(const [], hasAuto, env: ['CHORD_FAKE_AUTO_MODE=$value']),
          isFalse,
        );
      }
      expect(
        await opened(
          const ['--auto-mode'],
          hasAuto,
          env: const ['CHORD_FAKE_AUTO_MODE=0'],
        ),
        isTrue,
      );
    });

    test('the fork model environment affects forks only and the explicit '
        'flag wins', () async {
      const env = ['CHORD_FAKE_FORK_MODEL=fake-small'];
      expect(
        await opened(const ['--fork'], model, fork: source, env: env),
        'fake-small',
      );
      expect(await opened(const ['--fork'], model, env: env), 'fake-large');
      expect(
        await opened(
          const ['--fork', '--fork-model', 'fake-large'],
          model,
          fork: source,
          env: env,
        ),
        'fake-large',
      );
      expect(await opened(const ['--fork'], model, fork: source), 'fake-large');
    });
  });
}
