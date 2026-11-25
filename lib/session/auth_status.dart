/// What an agent says of the account its connection is signed in to, from
/// the original's `session/auth_status.ts`: its answer to `auth/status` and
/// its `auth/status_update` pushes, folded in the order they arrive, as ACP
/// carries no revision. Never recorded.
library;

import 'package:chord_tui/chord_tui.dart' show stripAnsi;

import '../js_trim.dart';

/// Where an agent's account stands, as chord heard it.
sealed class AccountState {
  const AccountState();
}

/// The agent does not advertise `auth.status`.
final class AccountNone extends AccountState {
  /// Nothing to hear.
  const AccountNone();
}

/// Asked, nothing heard yet.
final class AccountPending extends AccountState {
  /// Waiting for the answer.
  const AccountPending();
}

/// An answer or a push, the last of them.
final class AccountHeard extends AccountState {
  /// The account as [status] says it.
  const AccountHeard(this.status);

  /// ACP's `AuthStatusResponse`, its `state` one of ACP's words.
  final Map<String, Object?> status;
}

/// The request failed and nothing was heard.
final class AccountFailed extends AccountState {
  /// No account heard.
  const AccountFailed();
}

/// Nothing advertised.
const noAccount = AccountNone();

/// What changes the account: the request sent, a status heard, the request
/// failed.
sealed class AccountEvent {
  const AccountEvent();
}

/// `auth/status` was sent.
final class AccountAsked extends AccountEvent {
  /// The one ask.
  const AccountAsked();
}

/// A status came, as an answer or a push.
final class AccountStatus extends AccountEvent {
  /// The [status] heard.
  const AccountStatus(this.status);

  /// What the agent said.
  final Map<String, Object?> status;
}

/// `auth/status` failed.
final class AccountAskFailed extends AccountEvent {
  /// The one failure.
  const AccountAskFailed();
}

const _states = {'authenticated', 'unauthenticated', 'not_required', 'unknown'};

/// [state] with [event] folded in: a status heard is the last word, a word
/// ACP's schema leaves open reading `unknown`; a failed request after a
/// status keeps the status, and one before any is failed.
AccountState foldAccount(AccountState state, AccountEvent event) =>
    switch (event) {
      AccountAsked() => state is AccountNone ? const AccountPending() : state,
      AccountStatus(:final status) => AccountHeard(
        _states.contains(status['state'])
            ? status
            : {...status, 'state': 'unknown'},
      ),
      AccountAskFailed() =>
        state is AccountHeard ? state : const AccountFailed(),
    };

/// An agent's string as chord draws it: its escapes gone, on one line.
String _clean(String text) =>
    jsTrim(stripAnsi(text).replaceAll(RegExp(r'\s+'), ' '));

/// An account's parts, each only when sent, cleaned and joined by ` · `,
/// as the original's `accountLine`.
String accountLine(Map<String, Object?> account) => [
  for (final key in ['label', 'description', 'name', 'email', 'organization'])
    if (account[key] case final String part) _clean(part),
].where((part) => part.isNotEmpty).join(' · ');

/// The accounts chord names: the active ones, or all when none is marked.
List<Map<String, Object?>> shownAccounts(Object? accounts) {
  final all = [
    if (accounts is List)
      for (final each in accounts)
        if (each is Map<String, Object?>) each,
  ];
  final active = all.where((each) => each['active'] == true).toList();
  return active.isNotEmpty ? active : all;
}
