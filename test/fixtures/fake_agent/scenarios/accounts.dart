// The account an agent's connection is signed in to (CHD-629), as the
// original's scenarios/accounts.ts: its answer to `auth/status` as
// `--auth-status` plays it, and the push `--auth-push` sends.
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../options.dart';
import '../rpc.dart';
import '../turn.dart';

/// A subscription, as Claude's adapter says one.
const signedIn = <String, Object?>{
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

/// An API key, as Claude's adapter says one.
const apiKey = <String, Object?>{
  'state': 'authenticated',
  'accounts': [
    {
      'label': 'Anthropic API key',
      'description': 'ANTHROPIC_API_KEY',
      'active': true,
    },
  ],
};

/// Two accounts, neither marked active, for `--auth-status several`.
const several = <String, Object?>{
  'state': 'authenticated',
  'accounts': [
    {
      'label': 'Claude Max',
      'email': 'a.very.long.address.for.the.capture@engineering.example.com',
      'organization': 'Example Organisation of Long Names',
    },
    {'label': 'Anthropic API key', 'description': 'ANTHROPIC_API_KEY'},
  ],
};

Map<String, Object?> _statusOf() =>
    authStatusMode == 'unauthenticated' || authStatusMode == 'unknown'
    ? {'state': authStatusMode}
    : authStatusMode == 'several'
    ? several
    : signedIn;

/// Answers `auth/status` as `--auth-status` says, with `--auth-race`'s push.
Future<Map<String, Object?>> authStatus(Client client) async {
  if (authRace == 'push-first') {
    await client.notify('auth/status_update', apiKey);
  } else if (authRace == 'answer-first') {
    later(0, () => client.notify('auth/status_update', apiKey).ignore());
  }
  if (authStatusMode == 'error') {
    throw RequestError(-32603, 'The fake agent cannot tell.');
  }
  if (authStatusMode == 'hang') await Completer<Never>().future;
  if (authStatusMode == 'held') await _released();
  return _statusOf();
}

/// Until `<cwd>/.fake-gate/release` exists in the agent's own directory, or
/// 10 s on the monotonic clock.
Future<void> _released() async {
  final at = p.join(Directory.current.path, '.fake-gate', 'release');
  final deadline = now() + 10000;
  while (!File(at).existsSync() && now() < deadline) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Pushes the account, as Claude's adapter does once its probe lands.
void pushStatus(Client client) =>
    later(0, () => client.notify('auth/status_update', _statusOf()).ignore());

final Map<String, Play> accounts = {
  // Another account mid-turn, as a prompt's probe finds one.
  'authchanged': (turn) async {
    await turn.say(['Checking who is signed in. ']);
    await turn.client.notify('auth/status_update', apiKey);
    await turn.say(['Done.']);
    return 'end_turn';
  },
};
