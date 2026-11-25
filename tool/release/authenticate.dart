/// Mandatory npm identity preparation, after the eligibility guards and
/// before release work, as the original's
/// `scripts/dev/release/authenticate.ts`: npm owns the terminal, the
/// browser and the credential writes; recovery is tried once.
library;

import 'runner.dart';

/// Checks `npm whoami`, and on a terminal ([tty]) runs `npm login` once
/// and checks again; [out] says what npm is about to do.
Future<void> authenticate(
  ReleaseRunner runner, {
  required bool tty,
  required void Function(String line) out,
}) async {
  if ((await runner.run('npm', ['whoami'])).status == 0) return;
  if (!tty) {
    die(
      'npm login needs stdin and stdout on a terminal; rerun this release in '
      'a terminal.',
    );
  }
  out(
    'npm whoami failed; npm login will use this terminal and may open a '
    'browser.',
  );
  out(
    'npm may save credentials and registry settings, including during a '
    'dry run.',
  );
  if ((await runner.run('npm', ['login'], loud: true)).status != 0) {
    die('npm login did not complete; release stopped');
  }
  if ((await runner.run('npm', ['whoami'])).status != 0) {
    die('npm whoami still failed after login; release stopped');
  }
}
