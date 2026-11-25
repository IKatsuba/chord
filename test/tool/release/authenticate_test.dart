import 'package:test/test.dart';

import '../../../tool/release/authenticate.dart';
import '../../../tool/release/runner.dart';
import 'fixtures/recording_runner.dart';

Matcher dies(String text) =>
    throwsA(isA<ReleaseError>().having((e) => e.message, 'message', text));

/// npm answering each whoami in turn from [whoami], and login with [login].
RecordingRunner npm(List<int?> whoami, {int? login = 0}) {
  var asked = 0;
  return RecordingRunner(
    (argv) => switch (argv) {
      ['npm', 'whoami'] => Ran(whoami[asked++]),
      ['npm', 'login'] => Ran(login),
      _ => throw StateError('unexpected $argv'),
    },
  );
}

void main() {
  late List<String> said;
  setUp(() => said = []);

  for (final tty in [true, false]) {
    test(
      'a successful identity check continues, terminal or not ($tty)',
      () async {
        final runner = npm([0]);
        await authenticate(runner, tty: tty, out: said.add);
        expect(runner.argvs, [
          ['npm', 'whoami'],
        ]);
        expect(said, isEmpty);
      },
    );
  }

  test(
    'a failed identity check without a terminal never starts login',
    () async {
      final runner = npm([1]);
      await expectLater(
        authenticate(runner, tty: false, out: said.add),
        dies(
          'npm login needs stdin and stdout on a terminal; rerun this release '
          'in a terminal.',
        ),
      );
      expect(runner.argvs, [
        ['npm', 'whoami'],
      ]);
    },
  );

  test('on a terminal, login runs once with the terminal, then the check '
      'again', () async {
    final runner = npm([1, 0]);
    await authenticate(runner, tty: true, out: said.add);
    expect(runner.argvs, [
      ['npm', 'whoami'],
      ['npm', 'login'],
      ['npm', 'whoami'],
    ]);
    expect(runner.calls[1].loud, isTrue);
    expect(said, [
      'npm whoami failed; npm login will use this terminal and may open a '
          'browser.',
      'npm may save credentials and registry settings, including during a '
          'dry run.',
    ]);
  });

  for (final login in [2, 130, null]) {
    test('a login that fails or is cancelled ($login) stops', () async {
      final runner = npm([1], login: login);
      await expectLater(
        authenticate(runner, tty: true, out: said.add),
        dies('npm login did not complete; release stopped'),
      );
      expect(runner.argvs.last, ['npm', 'login']);
    });
  }

  test(
    'successful login still requires a successful identity recheck',
    () async {
      await expectLater(
        authenticate(npm([1, 1]), tty: true, out: said.add),
        dies('npm whoami still failed after login; release stopped'),
      );
    },
  );

  group('tester: authentication interruption boundaries', () {
    test('a signalled identity check without a terminal never logs in', () async {
      final runner = npm([null]);
      await expectLater(
        authenticate(runner, tty: false, out: said.add),
        dies(
          'npm login needs stdin and stdout on a terminal; rerun this release in a terminal.',
        ),
      );
      expect(runner.argvs, [
        ['npm', 'whoami'],
      ]);
      expect(said, isEmpty);
    });
  });
}
