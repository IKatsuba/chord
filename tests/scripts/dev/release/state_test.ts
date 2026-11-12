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
  npm: ReleaseState['npm'] = {},
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
    npm: ['@chorded/one'],
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

    const all = {
      githubRelease: true,
      npm: ['@chorded/a', '@chorded/b', '@chorded/c', '@chorded/one'],
    };

    expect(left(at, selection(STAGES, all))).toStrictEqual({
      cleared: [],
      stages: [],
      publish: {
        npm: ['@chorded/b', '@chorded/c', '@chorded/one'],
        tag: true,
        draft: true,
      },
    });
    expect(
      left(
        { ...at, tag: { state: 'pushed' }, draft: { state: 'made' } },
        selection(STAGES, all),
      ).publish,
    ).toStrictEqual({
      npm: ['@chorded/b', '@chorded/c', '@chorded/one'],
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
            selection(['pack', 'publish'], {
              named: true,
              npm: ['@chorded/a', '@chorded/one'],
            }),
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

  const npm = ['@chorded/one'];

  expect(finished(at, npm, false)).toBeTrue();
  expect(finished(at, npm, true)).toBeFalse();
  expect(finished({ ...at, draft: { state: 'made' } }, npm, true)).toBeTrue();
  expect(finished({ ...at, tag: { state: 'made' } }, npm, false)).toBeFalse();
  expect(
    finished({ ...at, npm: { '@chorded/one': 'sent' } }, npm, false),
  ).toBeFalse();
  // A name the state never started is not done.
  expect(finished(at, ['@chorded/a', ...npm], false)).toBeFalse();
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

describe('tester: CHD-623 state persistence boundaries', () => {
  let root: string;

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), 'chord-state-tester-'));
  });

  afterEach(() => {
    rmSync(root, { recursive: true, force: true });
  });

  test('clearing one package preserves the other state and build outputs', () => {
    const one = state(['build'], {});
    const two = state(['pack'], {}, { package: 'two', version: '2.0.0' });

    writeState(root, one);
    writeState(root, two);
    mkdirSync(join(root, 'dist'));
    writeFileSync(join(root, 'dist', 'artifact'), 'release bytes');
    clearState(root, 'one');
    clearState(root, 'one');

    expect(readState(root, 'one')).toBeUndefined();
    expect(readState(root, 'two')).toEqual(two);
    expect(readFileSync(join(root, 'dist', 'artifact'), 'utf8')).toBe(
      'release bytes',
    );
  });

  test('an interrupted first write stays absent until a complete replacement is renamed', () => {
    const at = state(['install'], {});
    const failure = new Error('fixture interrupted rename');
    const temporary = join(root, '.release', 'one', 'state.json.tmp');

    expect(() =>
      writeState(root, at, {
        rename: (from, to) => {
          expect(from).toBe(temporary);
          expect(to).toBe(join(root, '.release', 'one', 'state.json'));
          expect(JSON.parse(readFileSync(from, 'utf8'))).toEqual(at);

          throw failure;
        },
      }),
    ).toThrow(failure);
    expect(existsSync(temporary)).toBeTrue();
    expect(readState(root, 'one')).toBeUndefined();

    writeState(root, at);

    expect(existsSync(temporary)).toBeFalse();
    expect(readState(root, 'one')).toEqual(at);
  });

  test.each([
    ['versionCommit', { versionCommit: { state: 'sent' } }],
    ['stages', { stages: { pack: { at: 'now', outputs: { artifact: 1 } } } }],
    ['npm', { npm: { '@chorded/one': true } }],
    ['draft', { draft: { state: 'pushed' } }],
  ])(
    'malformed nested %s is refused without replacing the file',
    (_, invalid) => {
      const file = join(root, '.release', 'one', 'state.json');
      const text = JSON.stringify({ ...state([], {}), ...invalid });

      mkdirSync(join(root, '.release', 'one'), { recursive: true });
      writeFileSync(file, text);

      expect(refused(() => readState(root, 'one'))).toEndWith(`; ${ABANDON}`);
      expect(readFileSync(file, 'utf8')).toBe(text);
    },
  );

  test('clearing stage progress keeps its input and unrelated output sums intact', () => {
    const at = state(
      [],
      {},
      {
        stages: {
          build: { at: 'built', outputs: { binary: 'build-sum' } },
          pack: { at: 'packed', outputs: { tarball: 'pack-sum' } },
        },
      },
    );
    const before = JSON.stringify(at);

    Object.freeze(at.stages);
    Object.freeze(at);

    const next = cleared(at, ['pack']);

    expect(next.stages).toEqual({
      build: { at: 'built', outputs: { binary: 'build-sum' } },
    });
    expect(JSON.stringify(at)).toBe(before);
    expect(next.built).toBe(at.built);
    expect(next.base).toBe(at.base);
  });
});

describe('tester: CHD-623 expected npm progress', () => {
  test('work follows the package npm order, including names the state never started', () => {
    const npm = [
      '@chorded/a',
      '@chorded/b',
      '@chorded/missing',
      '@chorded/one',
    ];
    const at = state(['pack'], {
      '@chorded/one': 'answered',
      '@chorded/b': 'sent',
      '@chorded/a': 'pending',
    });
    const before = JSON.stringify(at);

    expect(left(at, selection(['publish'], { npm })).publish?.npm).toEqual([
      '@chorded/a',
      '@chorded/b',
      '@chorded/missing',
    ]);
    expect(JSON.stringify(at)).toBe(before);
  });

  test('an empty npm map cannot finish or hide outstanding names after tagging', () => {
    const npm = ['@chorded/a', '@chorded/one'];
    const at = state(
      ['pack'],
      {},
      {
        tag: { state: 'pushed' },
        draft: { state: 'made', url: 'https://github.example/draft' },
      },
    );

    expect(finished(at, npm, false)).toBeFalse();
    expect(finished(at, npm, true)).toBeFalse();
    expect(
      left(at, selection(['publish'], { npm, githubRelease: true })).publish,
    ).toEqual({ npm, tag: false, draft: false });
  });

  test('progress diagnostics count expected names rather than unrelated entries', () => {
    const at = state(['pack'], {
      '@chorded/a': 'answered',
      '@chorded/unrelated': 'answered',
    });
    const npm = ['@chorded/a', '@chorded/one'];

    expect(
      refused(() => left(at, selection(['publish'], { npm, dryRun: true }))),
    ).toContain('npm 1 of 2');
    expect(
      finished({ ...at, tag: { state: 'pushed' } }, npm, false),
    ).toBeFalse();
  });
});
