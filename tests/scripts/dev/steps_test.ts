import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import {
  type FoundPackage,
  lint,
  packages,
  run,
  spawnStep,
  type StepContext,
  StepsError,
} from '../../../scripts/dev/steps.ts';

// Scratch roots whose steps files are plain objects: discovery imports
// them as `bun dev` does, and nothing they name runs a real tool unless a
// test spawns it.

let root: string;

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'chord-steps-'));
});

afterEach(() => {
  rmSync(root, { recursive: true, force: true });
});

function write(path: string, text: string): void {
  mkdirSync(dirname(join(root, path)), { recursive: true });
  writeFileSync(join(root, path), text);
}

const PUBLISH = "{ name: 'publish', npm: ['@chorded/x'], tag: 'v{version}' }";
const STAGE = "{ name: 'build', about: 'b', run: async () => {} }";

/** A package at `folder` named `name`, its release list as written. */
function pkg(
  folder: string,
  name: string,
  release = `[${STAGE}, ${PUBLISH}]`,
  extra: Record<string, unknown> = {},
): void {
  write(
    join(folder, 'package.json'),
    JSON.stringify({ name, version: '1.0.0', ...extra }),
  );
  write(
    join(folder, 'steps.ts'),
    `export default { checks: [], lint: ['eslint'], release: ${release} };\n`,
  );
}

async function refusal(): Promise<string> {
  try {
    await packages(root);
  } catch (error) {
    expect(error).toBeInstanceOf(StepsError);

    return (error as Error).message;
  }

  throw new Error('packages(root) found no fault');
}

describe('discovery', () => {
  test('the root alone is chord, by its npm name without the scope', async () => {
    pkg('.', '@chorded/chord');

    const found = await packages(root);

    expect(found.map(({ name, folder }) => ({ name, folder }))).toEqual([
      { name: 'chord', folder: '.' },
    ]);
    expect(found[0]?.steps.lint).toEqual(['eslint']);
  });

  test("the root, then its workspaces' packages in order", async () => {
    pkg('.', '@chorded/chord', undefined, { workspaces: ['packages/*'] });
    pkg('packages/b-acp', '@chorded/b-acp');
    pkg('packages/a-acp', '@chorded/a-acp');

    expect((await packages(root)).map((each) => each.folder)).toEqual([
      '.',
      'packages/a-acp',
      'packages/b-acp',
    ]);
  });

  test('a package without steps.ts is named by its folder', async () => {
    pkg('.', '@chorded/chord', undefined, { workspaces: ['packages/*'] });
    write('packages/a/package.json', '{"name":"@chorded/a"}');

    expect(await refusal()).toBe('packages/a: no steps.ts');
  });

  test('a name outside the scope is refused', async () => {
    pkg('.', '@chorded/chord', undefined, { workspaces: ['packages/*'] });
    pkg('packages/a', 'a-acp');

    expect(await refusal()).toBe(
      'packages/a: its package.json names "a-acp", which is not in the @chorded/ scope',
    );
  });

  test('two packages of one name are refused', async () => {
    pkg('.', '@chorded/chord', undefined, { workspaces: ['packages/*'] });
    pkg('packages/a', '@chorded/chord');

    expect(await refusal()).toBe("packages/a: @chorded/chord is also .'s name");
  });

  test.each([
    ['no publish', `[${STAGE}]`, 'its release has no publish stage'],
    [
      'two publishes',
      `[${PUBLISH}, ${PUBLISH}]`,
      'its release has two publish stages',
    ],
    [
      'publish not last',
      `[${PUBLISH}, ${STAGE}]`,
      'publish is not the last stage of its release',
    ],
    [
      'two stages of one name',
      `[${STAGE}, ${STAGE}, ${PUBLISH}]`,
      'its release has two stages named "build"',
    ],
  ])('a release list with %s is refused', async (_, release, problem) => {
    pkg('.', '@chorded/chord', undefined, { workspaces: ['packages/*'] });
    pkg('packages/a', '@chorded/a', release);

    expect(await refusal()).toBe(`packages/a/steps.ts: ${problem}`);
  });

  test.each([
    ['no default export', 'export const steps = {};', 'the export: '],
    ['a null default', 'export default null;', 'the export: '],
    ['no release', 'export default { checks: [], lint: [] };', 'release: '],
    [
      'a stage without its run',
      "export default { checks: [], lint: [], release: [{ name: 'build', about: 'b' }] };",
      'release.0: ',
    ],
  ])('a steps file with %s is named by its file', async (_, text, where) => {
    pkg('.', '@chorded/chord', undefined, { workspaces: ['packages/*'] });
    pkg('packages/a', '@chorded/a');
    write('packages/a/steps.ts', `${text}\n`);

    expect(await refusal()).toStartWith(
      `packages/a/steps.ts: its default export is not a package's steps: ${where}`,
    );
  });

  test('a steps file that does not load is named', async () => {
    pkg('.', '@chorded/chord');
    write('steps.ts', "throw new Error('broken on purpose');\n");

    expect(await refusal()).toBe('steps.ts: broken on purpose');
  });
});

/** A found package of `checks`, and a context recording what it spawns. */
function fixture(checks: FoundPackage['steps']['checks']) {
  const spawned: string[][] = [];
  const said: string[] = [];
  const statuses = new Map<string, number>();
  const context: StepContext = {
    root: '/scratch',
    env: { HERE: 'yes' },
    spawn: (argv, options) => {
      spawned.push([...argv]);
      expect(options).toEqual({ cwd: '/scratch', env: { HERE: 'yes' } });

      return Promise.resolve(statuses.get(argv[0] ?? '') ?? 0);
    },
    output: (line) => void said.push(line),
  };
  const found: FoundPackage = {
    name: 'a-acp',
    folder: 'packages/a-acp',
    steps: { checks, lint: ['eslint', '--config', 'c.ts'], release: [] },
  };

  return { context, found, spawned, said, statuses };
}

describe('the runner', () => {
  const checks = [
    { name: 'types', static: true, run: ['types'] },
    { name: 'format', static: true, run: ['format'] },
    { name: 'tests', run: ['tests'] },
  ];

  test('runs every check in order from the root', async () => {
    const at = fixture(checks);

    expect(await run(at.found, at.context)).toBe(0);
    expect(at.spawned).toEqual([['types'], ['format'], ['tests']]);
    expect(at.said).toEqual([]);
  });

  test('--static runs only the static checks', async () => {
    const at = fixture(checks);

    expect(await run(at.found, at.context, { static: true })).toBe(0);
    expect(at.spawned).toEqual([['types'], ['format']]);
  });

  test('stops at the first failure, naming the package and the step', async () => {
    const at = fixture(checks);

    at.statuses.set('format', 3);

    expect(await run(at.found, at.context)).toBe(3);
    expect(at.spawned).toEqual([['types'], ['format']]);
    expect(at.said).toEqual(['quality a-acp: format failed with status 3']);
  });

  test('a function step gets the context and answers its status', async () => {
    let given: StepContext | undefined;
    const at = fixture([
      {
        name: 'smoke',
        run: (context) => {
          given = context;

          return Promise.resolve(7);
        },
      },
      { name: 'after', run: ['after'] },
    ]);

    expect(await run(at.found, at.context)).toBe(7);
    expect(given).toBe(at.context);
    expect(at.spawned).toEqual([]);
    expect(at.said).toEqual(['quality a-acp: smoke failed with status 7']);
  });

  test("lint runs the package's argv with the arguments after it", async () => {
    const at = fixture([]);

    at.statuses.set('eslint', 2);

    expect(await lint(at.found, ['--fix', ''], at.context)).toBe(2);
    expect(at.spawned).toEqual([['eslint', '--config', 'c.ts', '--fix', '']]);
  });

  test('a step killed by a signal answers 128 + its number', async () => {
    const options = { cwd: root, env: process.env };

    expect(await spawnStep(['sh', '-c', 'kill -TERM $$'], options)).toBe(143);
    expect(await spawnStep(['sh', '-c', 'exit 4'], options)).toBe(4);
  });
});

test("a type error in a package's tooling fails its quality, never chord's", async () => {
  const bun = JSON.stringify(process.execPath);

  write(
    'package.json',
    '{"name":"@chorded/chord","workspaces":["packages/*"]}',
  );
  write(
    'tsconfig.json',
    '{"compilerOptions":{"strict":true},"include":["chord.ts"]}',
  );
  write('chord.ts', 'export const fine: number = 1;\n');
  write(
    'steps.ts',
    `export default { checks: [{ name: 'types', static: true, run: [${bun}, 'check'] }], lint: [], release: [${PUBLISH}] };\n`,
  );
  write('packages/acp/package.json', '{"name":"@chorded/acp"}');
  write(
    'packages/acp/tsconfig.tools.json',
    '{"compilerOptions":{"strict":true},"include":["scripts/"]}',
  );
  write(
    'packages/acp/scripts/tools.ts',
    "export const broken: number = 'x';\n",
  );
  write(
    'packages/acp/steps.ts',
    `export default { checks: [{ name: 'tooling types', static: true, run: [${bun}, 'check', '-p', 'packages/acp/tsconfig.tools.json'] }], lint: [], release: [${PUBLISH}] };\n`,
  );

  const said: string[] = [];
  const context: StepContext = {
    root,
    env: process.env,
    // Quiet: the checker's report is not this test's output.
    spawn: ([command, ...args], { cwd, env }) =>
      Promise.resolve(
        spawnSync(command ?? '', args, { cwd, env, stdio: 'ignore' }).status ??
          1,
      ),
    output: (line) => void said.push(line),
  };
  const [chord, acp] = await packages(root);

  expect(await run(chord!, context)).toBe(0);
  expect(await run(acp!, context)).not.toBe(0);
  expect(said).toEqual([
    expect.stringMatching(/^quality acp: tooling types failed with status/),
  ]);
});
