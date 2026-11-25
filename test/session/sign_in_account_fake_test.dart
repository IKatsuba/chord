// A sign-in carries what the agent says of its account (CHD-629): a prompt
// refused with authRequired mid-session, as the original's session.ts
// 885-907, and a start refused for want of a login, as its 751-757, both
// waiting up to authWait for an account still being asked for.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';

import 'package:chord/session/auth_status.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/sign_in.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'session_fake.dart';

const _signedIn = {
  'state': 'authenticated',
  'accounts': [
    {
      'label': 'Claude Max',
      'email': 'name@example.com',
      'organization': 'Example Org',
      'active': true,
    },
  ],
};

/// The error a start of the fake with [flags] fails with.
Future<Object> _startFailure(List<String> flags) async {
  final dir = Directory.systemTemp.createTempSync('chord-sign-in-');
  addTearDown(() => dir.deleteSync(recursive: true));
  try {
    final session = await openSession(
      agent: 'fake',
      command: fakeAgentCommand(null, flags),
      cwd: dir.path,
      open: fakeOpenerWith(),
    );
    await session.close();
    fail('the start did not fail');
  } catch (error) {
    if (error is TestFailure) rethrow;
    return error;
  }
}

void main() {
  group('tester CTUI-160: pending account cancellation', skip: fakeAgentSkip, () {
    for (final close in [false, true]) {
      test(
        '${close ? 'close' : 'cancel'} releases a sign-in waiting for account',
        () async {
          await withSession((session, traffic) async {
            final turn = session.prompt('hello');
            await traffic.next(
              (event) =>
                  event is AgentTraffic &&
                  event.message['error'] is Map &&
                  (event.message['error'] as Map)['code'] == authRequired,
            );
            // Let the prompt enter the bounded account wait before retiring it.
            await Future<void>.delayed(const Duration(milliseconds: 50));
            expect(session.account, isA<AccountPending>());
            final watch = Stopwatch()..start();
            final stopping = close ? session.close() : turn.cancel();
            final result = await turn.result.timeout(
              const Duration(seconds: 3),
            );
            expect(watch.elapsed, lessThan(authWait));
            expect(
              (result as TurnFailed).signIn!.account,
              isA<AccountPending>(),
            );
            await stopping;
          }, flags: ['--auth-required', 'prompt', '--auth-status', 'hang']);
        },
      );
    }

    test(
      'an already cancelled turn token never waits the account timeout',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'chord-account-cancel-',
        );
        final pids = <int>[];
        Turn? turn;
        final session = await openSession(
          agent: 'fake',
          command: fakeAgentCommand(null, [
            '--auth-required',
            'prompt',
            '--auth-status',
            'hang',
          ]),
          cwd: dir.path,
          open: fakeOpenerWith(onPid: pids.add),
          onTraffic: (event) {
            if (event is AgentTraffic &&
                event.message['error'] is Map &&
                (event.message['error'] as Map)['code'] == authRequired) {
              turn?.cancel().ignore();
            }
          },
        );
        try {
          final watch = Stopwatch()..start();
          turn = session.prompt('hello');
          final result = await turn.result.timeout(const Duration(seconds: 3));
          expect(watch.elapsed, lessThan(authWait));
          expect((result as TurnFailed).signIn!.account, isA<AccountPending>());
        } finally {
          await session.close();
          expect(
            pids.where(
              (pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0,
            ),
            isEmpty,
          );
          dir.deleteSync(recursive: true);
        }
      },
    );

    test(
      'cancelling startup during the pending account wait stops its fake',
      () async {
        final dir = Directory.systemTemp.createTempSync('chord-account-start-');
        final pids = <int>[];
        final token = CancellationToken();
        Timer? cancel;
        try {
          final opening = openSession(
            agent: 'fake',
            command: fakeAgentCommand(null, [
              '--auth-required',
              'methods',
              '--auth-status',
              'hang',
            ]),
            cwd: dir.path,
            open: fakeOpenerWith(onPid: pids.add),
            cancellationToken: token,
            onTraffic: (event) {
              if (event is AgentTraffic &&
                  event.message['error'] is Map &&
                  (event.message['error'] as Map)['code'] == authRequired) {
                cancel = Timer(const Duration(milliseconds: 50), token.cancel);
              }
            },
          );
          await expectLater(
            opening.timeout(const Duration(seconds: 3)),
            throwsA(isNot(isA<TimeoutException>())),
          );
          expect(token.isCancelled, isTrue);
        } finally {
          cancel?.cancel();
          token.cancel();
          expect(
            pids.where(
              (pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0,
            ),
            isEmpty,
          );
          dir.deleteSync(recursive: true);
        }
      },
    );
  });
  final skip = fakeAgentSkip;

  group('CTUI-160: a prompt refused for want of a login', () {
    test('is its sign-in, with the account the agent says', () async {
      await withSession(
        (session, _) async {
          final ran = await run(session, 'hello');
          final failed = ran.result as TurnFailed;
          expect(failed.code, authRequired);
          expect(failed.signIn, isNotNull);
          expect(failed.signIn!.message, failed.message);
          expect(failed.signIn!.ways, isEmpty);
          expect((failed.signIn!.account as AccountHeard).status, _signedIn);
        },
        flags: ['--auth-required', 'prompt', '--auth-status', 'authenticated'],
      );
    });

    test('says no account where the agent advertises no auth.status', () async {
      await withSession((session, _) async {
        final failed = (await run(session, 'hello')).result as TurnFailed;
        expect(failed.signIn!.account, isA<AccountNone>());
      }, flags: ['--auth-required', 'prompt']);
    });

    test('gives up on an account still pending after authWait', () async {
      await withSession((session, _) async {
        final watch = Stopwatch()..start();
        final failed = (await run(session, 'hello')).result as TurnFailed;
        expect(failed.signIn!.account, isA<AccountPending>());
        expect(watch.elapsed, greaterThanOrEqualTo(authWait));
      }, flags: ['--auth-required', 'prompt', '--auth-status', 'hang']);
    });

    test('another failure carries none', () async {
      await withSession((session, _) async {
        final failed = (await run(session, 'error')).result as TurnFailed;
        expect(failed.signIn, isNull);
      });
    });
  }, skip: skip);

  group('CTUI-160: a start refused for want of a login', () {
    test('carries the account the agent says', () async {
      final signIn = signInOf(
        await _startFailure([
          '--auth-required',
          'methods',
          '--auth-status',
          'unauthenticated',
        ]),
      );
      expect(signIn, isNotNull);
      expect(signIn!.ways, isNotEmpty);
      expect((signIn.account as AccountHeard).status, {
        'state': 'unauthenticated',
      });
    });

    test('carries none where the agent advertises no auth.status', () async {
      final signIn = signInOf(
        await _startFailure(['--auth-required', 'methods']),
      );
      expect(signIn!.account, isNull);
    });
  }, skip: skip);
}
