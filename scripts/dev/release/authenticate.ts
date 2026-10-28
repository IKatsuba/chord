/** Mandatory npm identity preparation, after eligibility guards and before release work. */
import { die, npm, type Release } from './lib.ts';

/** npm owns the terminal, browser and credential writes; recovery is attempted once. */
export function authenticate(release: Release): void {
  if (npm(release, ['whoami']).status === 0) {
    return;
  }

  if (!release.tty) {
    die(
      'npm login needs stdin and stdout on a terminal; rerun this release in a terminal.',
    );
  }

  release.out(
    'npm whoami failed; npm login will use this terminal and may open a browser.',
  );
  release.out(
    'npm may save credentials and registry settings, including during a dry run.',
  );

  if (npm(release, ['login'], { stdio: 'inherit' }).status !== 0) {
    die('npm login did not complete; release stopped');
  }

  if (npm(release, ['whoami']).status !== 0) {
    die('npm whoami still failed after login; release stopped');
  }
}
