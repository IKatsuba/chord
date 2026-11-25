/// A start that failed because the agent needs a login: chord does not sign
/// agents in, so it says so with the agent's own words and the ways in the
/// agent offers, read from the protocol, never from the text.
library;

import '../acp/schema.dart' as acp;
import 'auth_status.dart';
import 'sessions.dart' show ResumeError;
import 'start_failure.dart';

/// ACP's `authRequired`: the agent needs a login before it opens a session.
const authRequired = -32000;

/// A way in the agent offers, in its own words.
typedef SignInWay = ({String? name, String? description});

/// Why a start failed for want of a login, and the agent's ways in.
class SignIn {
  const SignIn(this.message, this.ways, {this.account});

  /// The agent's own words for the failure.
  final String message;
  final List<SignInWay> ways;

  /// What the agent said of its account when it refused, the block's first
  /// line worded from it; null when it advertises no `auth.status`.
  final AccountState? account;
}

/// A start that needs a login, around the failure it was.
final class SignInNeeded implements Exception {
  const SignInNeeded(this.signIn, this.cause);
  final SignIn signIn;
  final StartFailed cause;

  @override
  String toString() => cause.message;
}

/// The ways in [methods] names, each by its name and description; one with
/// neither says nothing and is left out.
List<SignInWay> waysOf(List<acp.AuthMethod>? methods) => [
  for (final method in methods ?? const <acp.AuthMethod>[])
    if ((
          name: _orNull(method.name.trim()),
          description: _orNull(method.description?.trim()),
        )
        case final way when way.name != null || way.description != null)
      way,
];

String? _orNull(String? text) => text == null || text.isEmpty ? null : text;

/// [error], a failed start, as a [SignInNeeded] when its code is
/// `authRequired`, the protocol's word that the agent needs a login;
/// otherwise [error] as it is.
Object asSignIn(StartFailed error, List<acp.AuthMethod>? methods) =>
    error.failure.code == authRequired
    ? SignInNeeded(SignIn(error.message, waysOf(methods)), error)
    : error;

/// The block's first line, from what [agent] says of its account: that
/// none is signed in, or the account it is signed in to that the request
/// still refused; nothing when it says nothing, or that it cannot tell.
/// The agent names no missing account, so chord guesses at none.
String? accountReported(String agent, AccountState? account) {
  if (account is! AccountHeard) return null;
  final status = account.status;
  if (status['state'] == 'unauthenticated') {
    return '$agent reports that no account is signed in.';
  }
  if (status['state'] != 'authenticated') return null;
  final shown = shownAccounts(status['accounts']);
  return '$agent reports ${shown.isEmpty ? 'signed in' : shown.map(accountLine).join(', ')}.';
}

/// [signIn] as a record keeps it: its words and ways, each way's parts
/// only when sent; its account is shown live and never written.
Map<String, Object?> recordedSignIn(SignIn signIn) => {
  'message': signIn.message,
  'ways': [
    for (final way in signIn.ways)
      {'name': ?way.name, 'description': ?way.description},
  ],
};

/// The sign-in a record kept, as [recordedSignIn] writes it; null where
/// [value] is not one.
SignIn? recordSignIn(Object? value) {
  if (value case {
    'message': final String message,
    'ways': final List<Object?> ways,
  }) {
    final read = <SignInWay>[];
    for (final way in ways) {
      if (way is! Map) return null;
      final (name, description) = (way['name'], way['description']);
      if (name is! String? || description is! String?) return null;
      read.add((name: name, description: description));
    }
    return SignIn(message, read);
  }
  return null;
}

/// [error] with what the agent said of its account then, when it is a
/// [SignInNeeded] and the agent advertises `auth.status`.
Object withAccount(Object error, AccountState account) =>
    error is SignInNeeded && account is! AccountNone
    ? SignInNeeded(
        SignIn(error.signIn.message, error.signIn.ways, account: account),
        error.cause,
      )
    : error;

/// The sign-in [error] or the error it wraps says is needed, if any.
SignIn? signInOf(Object error) => switch (error) {
  SignInNeeded(:final signIn) => signIn,
  ResumeError(:final cause?) => signInOf(cause),
  _ => null,
};

/// chord's own line, the way on: the sign-in is the agent's, outside chord.
String wayOn(String agent) =>
    "chord does not sign agents in. Sign in with $agent's own CLI in a "
    'terminal, or set its API key where it offers one.';

/// The line before the ways [agent] offers, by how many there are.
String offersLine(String agent, int count) =>
    '$agent offers ${count == 1 ? 'this sign-in' : 'these sign-ins'}:';

/// A way in as plain text: its name, then its description in brackets.
String _wayWords(SignInWay way) => way.name != null && way.description != null
    ? '${way.name} (${way.description})'
    : way.name ?? way.description ?? '';

/// What follows a start failure's own line where only plain text goes, as
/// on `-p`'s stderr: the ways [agent] offers, if any, and the way on.
List<String> signInLines(String agent, SignIn signIn) => [
  if (signIn.ways.isNotEmpty)
    '$agent offers: ${signIn.ways.map(_wayWords).join(', ')}',
  wayOn(agent),
];

/// What chord tells a parent of a child that needs a login: the ways it
/// offers, and who signs it in.
String signInNote(String agent, SignIn signIn) =>
    '${signIn.ways.isEmpty ? '' : ' It offers: ${signIn.ways.map(_wayWords).join(', ')}.'}'
    " chord does not sign agents in: the person signs in with $agent's own "
    'CLI in a terminal, or sets its API key where it offers one.';
