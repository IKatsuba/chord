// The account an agent says its connection is signed in to, on the
// original's fake agent, as `--auth-status` and its pushes play it.
@Tags(['fake_agent'])
library;

import 'dart:async';

import 'package:chord/session/auth_status.dart';
import 'package:chord/session/session.dart';
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

const _apiKey = {
  'state': 'authenticated',
  'accounts': [
    {
      'label': 'Anthropic API key',
      'description': 'ANTHROPIC_API_KEY',
      'active': true,
    },
  ],
};

/// The account once it is no longer pending.
Future<AccountState> _settled(Session session) async {
  if (session.account is! AccountPending) return session.account;
  final done = Completer<AccountState>();
  final stop = session.subscribeAccount((account) {
    if (account is! AccountPending && !done.isCompleted) done.complete(account);
  });
  try {
    return await done.future.timeout(const Duration(seconds: 20));
  } finally {
    stop();
  }
}

Map<String, Object?>? _status(AccountState state) =>
    state is AccountHeard ? state.status : null;

void main() {
  final skip = fakeAgentSkip;

  test('an agent that does not advertise auth.status has none', () async {
    await withSession((session, _) async {
      expect(session.account, isA<AccountNone>());
    });
  }, skip: skip);

  test('its answer is the account; an unknown state reads unknown', () async {
    await withSession((session, _) async {
      expect(_status(await _settled(session)), _signedIn);
    }, flags: ['--auth-status', 'authenticated']);
    await withSession((session, _) async {
      expect(_status(await _settled(session)), {'state': 'unauthenticated'});
    }, flags: ['--auth-status', 'unauthenticated']);
  }, skip: skip);

  test('a failed ask is failed', () async {
    await withSession((session, _) async {
      expect(await _settled(session), isA<AccountFailed>());
    }, flags: ['--auth-status', 'error']);
  }, skip: skip);

  test('a push just before the answer wins over it', () async {
    await withSession((session, _) async {
      expect(_status(await _settled(session)), _apiKey);
    }, flags: ['--auth-status', 'authenticated', '--auth-race', 'push-first']);
  }, skip: skip);

  test('another account mid-turn is heard', () async {
    await withSession((session, _) async {
      expect(_status(await _settled(session)), _signedIn);
      await run(session, 'authchanged');
      expect(_status(session.account), _apiKey);
    }, flags: ['--auth-status', 'authenticated']);
  }, skip: skip);
}
