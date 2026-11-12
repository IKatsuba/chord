import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ReleaseError } from '../../../../scripts/dev/release/lib.ts';
import {
  cleared,
  clearState,
  finished,
  left,
  readState,
  type ReleaseState,
  type Selection,
  writeState,
} from '../../../../scripts/dev/release/state.ts';

const STAGES = ['install', 'quality', 'build', 'pack', 'publish'];
const ABANDON = 'rm -r .release/one abandons it';

/** A state of `one` 1.2.0 with `done` stages and its npm names as given. */
function state(
  done: readonly string[] = [],
  npm: ReleaseState['npm'] = { '@chorded/one': 'pending' },
  more: Partial<ReleaseState> = {},
): ReleaseState {
  return {
    format: 1,
    package: 'one',
    version: '1.2.0',
    channel: null,
    branch: 'main',
    base: 'a'.repeat(40),
    built: 'b'.repeat(40),
    stages: Object.fromEntries(
      done.map((stage) => [
        stage,
        { at: '2026-11-12T00:00:00.000Z', outputs: {} },
      ]),
    ),
    npm,
    ...more,
  };
}

/** A selection of `selected`, nothing else given. */
function selection(
  selected: readonly string[] = STAGES,
  more: Partial<Selection> = {},
): Selection {
  return {
    stages: STAGES,
    selected,
    named: false,
    dryRun: false,
    bump: undefined,
    channel: undefined,
    githubRelease: false,
    ...more,
  };
}

function refused(run: () => unknown): string {
  try {
    run();
  } catch (error) {
    expect(error).toBeInstanceOf(ReleaseError);

    return (error as Error).message;
  }

  throw new Error('not refused');
}

describe('what is left', () => {
  test('with no options: the stages not done, then what is left of publish', () => {
    expect(left(state(['install', 'quality']), selection())).toStrictEqual({
      cleared: [],
      stages: ['build', 'pack'],
      publish: { npm: ['@chorded/one'], tag: true, draft: false },
    });
  });

  test('publish: the npm names not answered, the tag not pushed, the draft not made', () => {
    const at = state(
      ['install', 'quality', 'build', 'pack'],
      {
        '@chorded/a': 'answered',
        '@chorded/b': 'sent',
        '@chorded/one': 'pending',
      },
      { tag: { state: 'made' }, draft: { state: 'pending' } },
    );

    expect(left(at, selection(STAGES, { githubRelease: true }))).toStrictEqual({
      cleared: [],
      stages: [],
      publish: { npm: ['@chorded/b', '@chorded/one'], tag: true, draft: true },
    });
    expect(
      left(
        { ...at, tag: { state: 'pushed' }, draft: { state: 'made' } },
        selection(STAGES, { githubRelease: true }),
      ).publish,
    ).toStrictEqual({
      npm: ['@chorded/b', '@chorded/one'],
      tag: false,
      draft: false,
    });
  });

  test('--skip: those stages are not run and stay not done', () => {
    expect(
      left(state(['install']), selection(['install', 'build', 'pack'])),
    ).toStrictEqual({ cleared: [], stages: ['build', 'pack'] });
  });

  test('--to: stops after it, nothing of publish', () => {
    expect(
      left(state(['install']), selection(['install', 'quality'])),
    ).toStrictEqual({ cleared: [], stages: ['quality'] });
  });

  test('--only or --from: a done stage runs again, cleared with every done one after it', () => {
    const at = state(['install', 'quality', 'build', 'pack']);

    expect(left(at, selection(['quality'], { named: true }))).toStrictEqual({
      cleared: ['quality', 'build', 'pack'],
      stages: ['quality'],
    });
    expect(
      left(at, selection(['build', 'pack', 'publish'], { named: true })),
    ).toStrictEqual({
      cleared: ['build', 'pack'],
      stages: ['build', 'pack'],
      publish: { npm: ['@chorded/one'], tag: true, draft: false },
    });
  });

  test('an exact --bump equal to the state version is the same as none', () => {
    expect(
      left(state(['install']), selection(STAGES, { bump: '1.2.0' })),
    ).toStrictEqual(left(state(['install']), selection()));
  });

  test("the state's own channel is allowed", () => {
    const at = state([], undefined, {
      channel: 'next',
      version: '1.2.0-next.0',
    });

    expect(
      left(at, selection(STAGES, { channel: 'next' })).stages,
    ).toStrictEqual(['install', 'quality', 'build', 'pack']);
  });
});

describe('refused, naming the way out', () => {
  test('--dry-run', () => {
    expect(
      refused(() =>
        left(state(['install']), selection(STAGES, { dryRun: true })),
      ),
    ).toBe(
      `--dry-run is refused while one 1.2.0 is in progress (done: install; npm 0 of 1): \`bun dev release one\` continues it; ${ABANDON}`,
    );
  });

  test('--bump another version or a bump word', () => {
    for (const bump of ['1.3.0', 'patch']) {
      expect(
        refused(() => left(state(['install']), selection(STAGES, { bump }))),
      ).toBe(
        `--bump ${bump} is refused while one 1.2.0 is in progress (done: install; npm 0 of 1): \`bun dev release one\` continues it; ${ABANDON}`,
      );
    }
  });

  test('another channel', () => {
    expect(
      refused(() => left(state(), selection(STAGES, { channel: 'next' }))),
    ).toBe(
      `--channel next is not one 1.2.0 is in progress (done: nothing; npm 0 of 1)'s channel, none; ${ABANDON}`,
    );
  });

  test('a stage before publish run again once npm has any of it', () => {
    for (const sent of ['sent', 'answered'] as const) {
      expect(
        refused(() =>
          left(
            state(['install', 'quality', 'build', 'pack'], {
              '@chorded/a': sent,
              '@chorded/one': 'pending',
            }),
            selection(['pack', 'publish'], { named: true }),
          ),
        ),
      ).toStartWith(`pack cannot run again: npm has one 1.2.0's bytes`);
    }
  });

  test('publish without pack done', () => {
    expect(
      refused(() =>
        left(
          state(['install', 'quality', 'build']),
          selection(['publish'], { named: true }),
        ),
      ),
    ).toBe(
      `publish needs pack's output; pack is not done in one 1.2.0; ${ABANDON}`,
    );
  });
});

test('a state is finished once npm answered for all, the tag is pushed and, with a GitHub release, the draft made', () => {
  const at = state(
    [],
    { '@chorded/one': 'answered' },
    { tag: { state: 'pushed' } },
  );

  expect(finished(at, false)).toBeTrue();
  expect(finished(at, true)).toBeFalse();
  expect(finished({ ...at, draft: { state: 'made' } }, true)).toBeTrue();
  expect(finished({ ...at, tag: { state: 'made' } }, false)).toBeFalse();
  expect(
    finished({ ...at, npm: { '@chorded/one': 'sent' } }, false),
  ).toBeFalse();
});

test('cleared leaves the other done stages', () => {
  expect(
    Object.keys(
      cleared(state(['install', 'quality', 'build']), ['quality', 'build'])
        .stages,
    ),
  ).toStrictEqual(['install']);
});

describe('on disk', () => {
  let root: string;
  const file = () => join(root, '.release', 'one', 'state.json');

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), 'chord-state-'));
  });

  afterEach(() => {
    rmSync(root, { recursive: true, force: true });
  });

  test('none until written; written, read back whole; cleared, none again', () => {
    expect(readState(root, 'one')).toBeUndefined();

    const at = state(['install'], undefined, {
      versionCommit: { state: 'made', sha: 'c'.repeat(40) },
    });

    writeState(root, at);

    expect(readState(root, 'one')).toStrictEqual(at);

    clearState(root, 'one');

    expect(existsSync(join(root, '.release', 'one'))).toBeFalse();
    expect(readState(root, 'one')).toBeUndefined();
  });

  test('a write stopped before the rename leaves the old state', () => {
    writeState(root, state(['install']));

    expect(() =>
      writeState(root, state(['install', 'quality']), {
        rename: () => {
          throw new Error('killed before the rename');
        },
      }),
    ).toThrow('killed before the rename');
    expect(Object.keys(readState(root, 'one')!.stages)).toStrictEqual([
      'install',
    ]);
  });

  test('a leftover .tmp is never read, and the next write replaces it', () => {
    writeState(root, state(['install']));
    writeFileSync(`${file()}.tmp`, '{"half":');

    expect(Object.keys(readState(root, 'one')!.stages)).toStrictEqual([
      'install',
    ]);

    writeState(root, state(['install', 'quality']));

    expect(existsSync(`${file()}.tmp`)).toBeFalse();
    expect(Object.keys(readState(root, 'one')!.stages)).toStrictEqual([
      'install',
      'quality',
    ]);
  });

  test.each([
    [
      'another format, untouched',
      '{"format":2}',
      'has format 2; this release reads format 1',
    ],
    ['not JSON', '{', 'is not JSON: '],
    [
      'a missing field',
      JSON.stringify({ ...state(), built: undefined }),
      "is not a release's state: built: ",
    ],
    [
      "another package's",
      JSON.stringify({ ...state(), package: 'chord' }),
      "is chord's state, not one's",
    ],
  ])('a state that is %s is refused, naming the file', (_, text, why) => {
    mkdirSync(join(root, '.release', 'one'), { recursive: true });
    writeFileSync(file(), text);

    const message = refused(() => readState(root, 'one'));

    expect(message).toStartWith(`${file()} ${why}`);
    expect(message).toEndWith(`; ${ABANDON}`);
    expect(readFileSync(file(), 'utf8')).toBe(text);
  });
});
