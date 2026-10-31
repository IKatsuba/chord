import { describe, expect, test } from 'bun:test';
import { execFileSync } from 'node:child_process';
import {
  appendFileSync,
  chmodSync,
  linkSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  renameSync,
  rmSync,
  symlinkSync,
  truncateSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  type ProjectReadSeam,
  readProjectFile,
} from '../src/project_settings.ts';
import { readSettingsTool } from '../src/settings_tool.ts';
import { settingsRows } from '../src/ui/transcript/tools/settings_row.ts';

const CANARY = 'project-read-canary';
const REAL = '{"agent":"real"}';
const REFUSED_FILE = { kind: 'refused', what: 'file' } as const;
const REFUSED_DIRECTORY = { kind: 'refused', what: 'directory' } as const;

interface Place {
  readonly root: string;
  readonly cwd: string;
  readonly directory: string;
  readonly file: string;
  /** A file outside the project holding the canary. */
  readonly target: string;
  /** A directory outside the project, its settings file holding the canary. */
  readonly elsewhere: string;
}

function placed(run: (place: Place) => void | Promise<void>) {
  return async () => {
    const root = mkdtempSync(join(tmpdir(), 'chord-project-read-'));
    const cwd = join(root, 'work');
    const directory = join(cwd, '.chord');
    const target = join(root, 'target.json');
    const elsewhere = join(root, 'elsewhere');
    const secret = JSON.stringify({ agent: CANARY, nope: CANARY, theme: 3 });

    mkdirSync(cwd);
    mkdirSync(elsewhere);
    writeFileSync(target, secret);
    writeFileSync(join(elsewhere, 'settings.json'), secret);

    try {
      await run({
        root,
        cwd,
        directory,
        file: join(directory, 'settings.json'),
        target,
        elsewhere,
      });
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  };
}

/** A real `.chord` holding a real settings file. */
function real({ directory, file }: Place) {
  mkdirSync(directory);
  writeFileSync(file, REAL);
}

/**
 * The whole answer a read gives, and the rows drawn from it, each as text a
 * canary must not be in.
 */
async function everything({ root, cwd }: Place, seam?: ProjectReadSeam) {
  const where = { home: root, configHome: join(root, 'none'), cwd };
  const read = await readSettingsTool(where, [], seam);

  if ('error' in read) {
    throw new Error(read.error);
  }

  const call = {
    tool: 'settings' as const,
    input: { action: 'read' },
    answer: read.answer,
    settingsFiles: read.files,
  };

  return {
    ...read,
    said: JSON.stringify([
      read,
      settingsRows(call, false, 80),
      settingsRows(call, true, 80),
    ]),
  };
}

describe('readProjectFile', () => {
  test(
    'a regular file is read, from one handle, and every handle closes',
    placed((place) => {
      real(place);

      const before = readdirSync('/dev/fd').length;

      expect(readProjectFile(place.cwd)).toStrictEqual({
        kind: 'read',
        text: REAL,
      });
      expect(readdirSync('/dev/fd').length).toBe(before);
    }),
  );

  test(
    'absent is no refusal, of the directory or the file',
    placed((place) => {
      expect(readProjectFile(place.cwd)).toStrictEqual({ kind: 'absent' });
      mkdirSync(place.directory);
      expect(readProjectFile(place.cwd)).toStrictEqual({ kind: 'absent' });
    }),
  );

  test(
    'a link at the file, or a dangling one, is refused',
    placed((place) => {
      mkdirSync(place.directory);
      symlinkSync(place.target, place.file);
      expect(readProjectFile(place.cwd)).toStrictEqual(REFUSED_FILE);
      unlinkSync(place.file);
      symlinkSync(join(place.root, 'nothing'), place.file);
      expect(readProjectFile(place.cwd)).toStrictEqual(REFUSED_FILE);
    }),
  );

  test(
    'a link at .chord, or a dangling one, or a file there, is refused',
    placed((place) => {
      symlinkSync(place.elsewhere, place.directory);
      expect(readProjectFile(place.cwd)).toStrictEqual(REFUSED_DIRECTORY);
      unlinkSync(place.directory);
      symlinkSync(join(place.root, 'nothing'), place.directory);
      expect(readProjectFile(place.cwd)).toStrictEqual(REFUSED_DIRECTORY);
      unlinkSync(place.directory);
      writeFileSync(place.directory, '');
      expect(readProjectFile(place.cwd)).toStrictEqual(REFUSED_DIRECTORY);
    }),
  );

  test(
    'a hard link is refused',
    placed((place) => {
      mkdirSync(place.directory);
      linkSync(place.target, place.file);
      expect(readProjectFile(place.cwd)).toStrictEqual(REFUSED_FILE);
    }),
  );

  test(
    'a FIFO is refused, and does not hang',
    placed((place) => {
      mkdirSync(place.directory);
      execFileSync('mkfifo', [place.file]);
      expect(readProjectFile(place.cwd)).toStrictEqual(REFUSED_FILE);
    }),
  );

  test(
    'a directory at the name is refused',
    placed((place) => {
      mkdirSync(place.file, { recursive: true });
      expect(readProjectFile(place.cwd)).toStrictEqual(REFUSED_FILE);
    }),
  );

  test(
    'EACCES on the file and on .chord is refused, not taken for absent',
    placed((place) => {
      real(place);

      try {
        chmodSync(place.file, 0o000);
        expect(readProjectFile(place.cwd)).toStrictEqual(REFUSED_FILE);
        chmodSync(place.file, 0o600);
        chmodSync(place.directory, 0o000);
        expect(readProjectFile(place.cwd)).toStrictEqual(REFUSED_DIRECTORY);
      } finally {
        chmodSync(place.directory, 0o700);
      }
    }),
  );

  test(
    'with no libc to reach, a project file is refused and absent stays absent',
    placed((place) => {
      const seam = { openAt: undefined };

      expect(readProjectFile(place.cwd, seam)).toStrictEqual({
        kind: 'absent',
      });
      real(place);
      expect(readProjectFile(place.cwd, seam)).toStrictEqual(REFUSED_DIRECTORY);
    }),
  );

  test(
    'a working directory under a link is not refused',
    placed((place) => {
      real(place);

      const linked = join(place.root, 'linked-work');

      symlinkSync(place.cwd, linked);
      expect(readProjectFile(linked)).toStrictEqual({
        kind: 'read',
        text: REAL,
      });
    }),
  );
});

describe('a file past the size limit', () => {
  const MIB = 1024 * 1024;

  test(
    'a sparse file over the limit is refused, and reads nothing of it',
    placed((place) => {
      mkdirSync(place.directory);
      writeFileSync(place.file, '');
      truncateSync(place.file, 1024 * MIB);
      expect(readProjectFile(place.cwd)).toStrictEqual(REFUSED_FILE);
    }),
  );

  test(
    'a file of exactly the limit is read, one byte more is refused',
    placed((place) => {
      mkdirSync(place.directory);
      writeFileSync(place.file, ' '.repeat(MIB));
      expect(readProjectFile(place.cwd)).toMatchObject({ kind: 'read' });
      writeFileSync(place.file, ' '.repeat(MIB + 1));
      expect(readProjectFile(place.cwd)).toStrictEqual(REFUSED_FILE);
    }),
  );

  test(
    'growth past the limit after the fstat is refused',
    placed((place) => {
      real(place);

      expect(
        readProjectFile(place.cwd, {
          afterStat: () => truncateSync(place.file, MIB + 1),
        }),
      ).toStrictEqual(REFUSED_FILE);
    }),
  );

  test(
    'growth that stays within the limit is read',
    placed((place) => {
      real(place);

      expect(
        readProjectFile(place.cwd, {
          afterStat: () => appendFileSync(place.file, ' '),
        }),
      ).toStrictEqual({ kind: 'read', text: `${REAL} ` });
    }),
  );

  test(
    'an oversized file is the one problem, and every handle closes',
    placed(async (place) => {
      mkdirSync(place.directory);
      writeFileSync(place.file, '');
      truncateSync(place.file, 2 * MIB);

      const before = readdirSync('/dev/fd').length;
      const { answer } = await everything(place);

      expect(answer.project).toBeNull();
      expect(answer.effective).toStrictEqual({});
      expect(answer.problems).toHaveLength(1);
      expect(readdirSync('/dev/fd').length).toBe(before);
    }),
  );
});

describe('a swap during the read', () => {
  test(
    '.chord to a link after the directory opened reads the real directory',
    placed((place) => {
      real(place);

      expect(
        readProjectFile(place.cwd, {
          afterDirectory: () => {
            renameSync(place.directory, `${place.directory}.moved`);
            symlinkSync(place.elsewhere, place.directory);
          },
        }),
      ).toStrictEqual({ kind: 'read', text: REAL });
    }),
  );

  test(
    'the file to a link after the directory opened is refused',
    placed((place) => {
      real(place);

      expect(
        readProjectFile(place.cwd, {
          afterDirectory: () => {
            unlinkSync(place.file);
            symlinkSync(place.target, place.file);
          },
        }),
      ).toStrictEqual(REFUSED_FILE);
    }),
  );

  test(
    'the file moved aside after it opened reads what was opened',
    placed((place) => {
      real(place);

      expect(
        readProjectFile(place.cwd, {
          afterFile: () => {
            renameSync(place.file, `${place.file}.moved`);
            symlinkSync(place.target, place.file);
          },
        }),
      ).toStrictEqual({ kind: 'read', text: REAL });
    }),
  );

  test(
    'the file removed after it opened has no links, and is refused',
    placed((place) => {
      real(place);

      expect(
        readProjectFile(place.cwd, {
          afterFile: () => {
            unlinkSync(place.file);
            symlinkSync(place.target, place.file);
          },
        }),
      ).toStrictEqual(REFUSED_FILE);
    }),
  );

  test(
    'a hard link made after it opened is refused',
    placed((place) => {
      real(place);

      expect(
        readProjectFile(place.cwd, {
          afterFile: () => linkSync(place.file, `${place.file}.second`),
        }),
      ).toStrictEqual(REFUSED_FILE);
    }),
  );
});

describe('nothing of a refused or swapped file reaches the answer or the row', () => {
  const plants: readonly [
    string,
    (place: Place) => void,
    ProjectReadSeam | ((place: Place) => ProjectReadSeam),
  ][] = [
    [
      'a link at the file',
      (place) => {
        mkdirSync(place.directory);
        symlinkSync(place.target, place.file);
      },
      {},
    ],
    [
      'a link at .chord',
      (place) => symlinkSync(place.elsewhere, place.directory),
      {},
    ],
    [
      'a hard link',
      (place) => {
        mkdirSync(place.directory);
        linkSync(place.target, place.file);
      },
      {},
    ],
    [
      '.chord swapped after it opened',
      real,
      (place) => ({
        afterDirectory: () => {
          renameSync(place.directory, `${place.directory}.moved`);
          symlinkSync(place.elsewhere, place.directory);
        },
      }),
    ],
    [
      'the file swapped after it opened',
      real,
      (place) => ({
        afterFile: () => {
          renameSync(place.file, `${place.file}.moved`);
          symlinkSync(place.target, place.file);
        },
      }),
    ],
  ];

  for (const [name, plant, seam] of plants) {
    test(
      name,
      placed(async (place) => {
        plant(place);

        const { said } = await everything(
          place,
          typeof seam === 'function' ? seam(place) : seam,
        );

        expect(said).not.toContain(CANARY);
      }),
    );
  }

  test(
    'a refused file is the one problem, in its words, and left out of effective',
    placed(async (place) => {
      mkdirSync(place.directory);
      symlinkSync(place.target, place.file);

      const { answer, files } = await everything(place);

      expect(answer.project).toBeNull();
      expect(answer.effective).toStrictEqual({});
      expect(answer.problems).toStrictEqual([
        {
          file: join('.chord', 'settings.json'),
          message: `${join('.chord', 'settings.json')} was not read: chord could not read it as a regular file of one link and at most 1 MiB. project and effective omit it. A start still follows links`,
        },
      ]);
      expect(files).toMatchObject({
        project: `${join('.chord', 'settings.json')} · not read`,
        projectUnread: true,
      });
    }),
  );

  test(
    'with no libc to reach, the .chord line stands',
    placed(async (place) => {
      real(place);

      const { answer } = await everything(place, { openAt: undefined });

      expect(answer.problems[0]?.message).toStartWith(
        '.chord was not read: chord could not open it as a directory without following a link.',
      );
      expect(answer.effective).toStrictEqual({});
    }),
  );

  test(
    'the one read serves project, effective and problems alike',
    placed(async (place) => {
      mkdirSync(place.directory);
      writeFileSync(place.file, '{"agent":"first","nope":1}');

      const { answer } = await everything(place, {
        afterFile: () => {
          renameSync(place.file, `${place.file}.moved`);
          writeFileSync(place.file, `{"agent":"${CANARY}"}`);
        },
      });

      expect(answer.project).toStrictEqual({ agent: 'first', nope: 1 });
      expect(answer.effective).toStrictEqual({ agent: 'first' });
      expect(answer.problems.map(({ message }) => message)).toStrictEqual([
        'unknown key "nope", ignored',
      ]);
    }),
  );
});
