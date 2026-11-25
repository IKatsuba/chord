import 'package:chord/session/auth_status.dart';
import 'package:test/test.dart';

AccountState fold(List<AccountEvent> events) =>
    events.fold<AccountState>(noAccount, foldAccount);

const signedIn = {
  'state': 'authenticated',
  'accounts': [
    {'label': 'Claude Max', 'email': 'name@example.com', 'active': true},
  ],
};

Map<String, Object?>? heard(AccountState state) =>
    state is AccountHeard ? state.status : null;

void main() {
  test('none until asked, pending once asked, and the last status heard', () {
    expect(fold([]), isA<AccountNone>());
    expect(fold([const AccountAsked()]), isA<AccountPending>());
    expect(
      heard(
        fold([
          const AccountAsked(),
          const AccountStatus(signedIn),
          const AccountStatus({'state': 'unauthenticated'}),
        ]),
      ),
      {'state': 'unauthenticated'},
    );
  });

  test('a push after a failed request is heard; a request failing after a '
      'push keeps the push', () {
    expect(
      heard(
        fold([
          const AccountAsked(),
          const AccountAskFailed(),
          const AccountStatus(signedIn),
        ]),
      ),
      signedIn,
    );
    expect(
      heard(
        fold([
          const AccountAsked(),
          const AccountStatus(signedIn),
          const AccountAskFailed(),
        ]),
      ),
      signedIn,
    );
    expect(
      fold([const AccountAsked(), const AccountAskFailed()]),
      isA<AccountFailed>(),
    );
  });

  test('a state word the schema leaves open reads unknown, the rest kept', () {
    expect(
      heard(
        fold([
          const AccountStatus({'state': 'expired', 'accounts': <Object?>[]}),
        ]),
      ),
      {'state': 'unknown', 'accounts': <Object?>[]},
    );
    expect(
      heard(
        fold([
          const AccountStatus({'state': 'not_required'}),
        ]),
      ),
      {'state': 'not_required'},
    );
  });

  test('asking again once heard keeps what was heard', () {
    final state = fold([const AccountStatus(signedIn), const AccountAsked()]);
    expect(heard(state), signedIn);
  });
}
