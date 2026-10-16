/**
 * Notarises the signed macOS chords as one zip with the team-wide App Store
 * Connect key in the login keychain, keeps Apple's log beside the build
 * whatever the verdict, stops unless Accepted, then checks that each binary
 * is one Apple's log lists a ticket for, by its cdhash, so what is packed is
 * what was notarised. Not codesign's =notarized requirement: it asks this
 * Mac's view of Apple's ticket service, which can say no for minutes after
 * Apple accepted and the ticket is online (seen at 0.54.0, about 8 minutes).
 * spctl is no check either: `spctl -a -t exec` rejects any bare Mach-O as
 * "does not seem to be an app". A bare Mach-O cannot be stapled; Gatekeeper
 * looks the ticket up online on a quarantined copy.
 */
import {
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join } from 'node:path';
import { die, type Release, run, said } from './lib.ts';

/** The notarytool profile in the login keychain that holds the team's key. */
export const PROFILE = 'roost-notary';

export async function notarise(
  release: Release,
  out: string,
  binaries: readonly string[],
): Promise<void> {
  mkdirSync(out, { recursive: true });

  const zip = join(out, 'chord.zip');
  const staging = mkdtempSync(join(tmpdir(), 'chord-notarise-'));

  try {
    mkdirSync(join(staging, 'chord'));

    for (const binary of binaries) {
      copyFileSync(
        join(release.root, binary),
        join(staging, 'chord', `${basename(dirname(binary))}-chord`),
      );
    }

    run(release, 'ditto', [
      '-c',
      '-k',
      '--norsrc',
      '--noextattr',
      '--keepParent',
      join(staging, 'chord'),
      zip,
    ]);
  } finally {
    rmSync(staging, { recursive: true, force: true });
  }

  // The result is kept, and Apple's log fetched, before any verdict is
  // judged. The JSON result is stdout alone; notarytool's diagnostics are
  // kept apart.
  const submit = run(release, 'xcrun', [
    'notarytool',
    'submit',
    zip,
    '--keychain-profile',
    PROFILE,
    '--wait',
    '--output-format',
    'json',
  ]);
  const result = said(submit.stdout);

  writeFileSync(join(out, 'notarytool-submit.stderr'), submit.stderr);
  writeFileSync(join(out, 'notarytool.json'), `${result}\n`);

  const { id: submission, status } = fields(result);

  if (submission !== '') {
    for (let attempt = 1; ; attempt++) {
      const fetched = run(release, 'xcrun', [
        'notarytool',
        'log',
        submission,
        '--keychain-profile',
        PROFILE,
        join(out, 'notarytool-log.json'),
      ]);

      if (fetched.status === 0) {
        break;
      }

      if (attempt === 3) {
        die(
          `the notarisation log of ${submission} could not be fetched: ${said(fetched.stdout + fetched.stderr)}`,
        );
      }

      await release.sleep(10_000);
    }
  }

  if (submit.status !== 0) {
    die(
      `notarytool submit exited ${submit.status ?? 'without a status'}: ${result} ${said(submit.stderr)}`,
    );
  }

  if (status !== 'Accepted') {
    die(`notarisation of ${zip} ended ${status}: ${result}`);
  }

  const tickets = cdhashes(join(out, 'notarytool-log.json'));

  for (const binary of binaries) {
    const shown = run(release, 'codesign', ['-dvvv', binary]);
    const cdhash =
      /^CDHash=(.*)$/m.exec(shown.stdout + shown.stderr)?.[1] ?? '';

    if (cdhash === '') {
      die(`the cdhash of ${binary} could not be read`);
    }

    if (!tickets.includes(`"cdhash":"${cdhash}"`)) {
      die(
        `Apple's log has no ticket for ${binary} (cdhash ${cdhash}); it lists: ${tickets.join('\n')}`,
      );
    }

    release.out(`notarised ${binary}: ${cdhash}`);
  }
}

/** notarytool's submission id and status, empty where it gave none. */
function fields(result: string): { id: string; status: string } {
  try {
    const parsed = JSON.parse(result) as { id?: unknown; status?: unknown };

    return {
      id: typeof parsed.id === 'string' ? parsed.id : '',
      status: typeof parsed.status === 'string' ? parsed.status : '',
    };
  } catch {
    return { id: '', status: '' };
  }
}

/** The cdhashes Apple's log has a ticket for, each as `"cdhash":"…"`. */
function cdhashes(log: string): string[] {
  try {
    const parsed = JSON.parse(readFileSync(log, 'utf8')) as {
      ticketContents?: { cdhash?: unknown }[];
    };

    return (parsed.ticketContents ?? []).flatMap(({ cdhash }) =>
      typeof cdhash === 'string' && /^[0-9a-f]*$/.test(cdhash)
        ? [`"cdhash":"${cdhash}"`]
        : [],
    );
  } catch {
    return [];
  }
}
