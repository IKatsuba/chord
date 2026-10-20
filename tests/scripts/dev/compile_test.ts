import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Fragment as ReactFragment, isValidElement } from 'react';
import { buildOptions } from '../../../scripts/dev/compile.ts';
import { Fragment, jsxDEV } from '../../../scripts/dev/jsx_dev_runtime.ts';

const FIXTURE = fileURLToPath(
  new URL('../../fixtures/boundary/main.tsx', import.meta.url),
);

test("built as the binary is, OpenTUI's ErrorBoundary paints the error rather than throwing jsxDEV (CHD-468)", async () => {
  const out = await mkdtemp(join(tmpdir(), 'chord-boundary-'));

  try {
    const built = await Bun.build({ ...buildOptions(FIXTURE), outdir: out });

    expect(built.success).toBe(true);

    // From its own directory, where the bundle looks for OpenTUI's library.
    const run = spawnSync(process.execPath, [join(out, 'main.js')], {
      cwd: out,
      encoding: 'utf8',
    });

    expect(run.stderr).not.toContain('jsxDEV');
    expect(run.stdout).toContain('Error: the boundary caught this');
    // chord's own crash screen, drawn the same way.
    expect(run.stdout).toContain('any key to quit');
    expect(run.status).toBe(0);
  } finally {
    await rm(out, { recursive: true });
  }
}, 60_000);

describe('CHD-468 tester: production JSX shim element semantics', () => {
  test('Fragment is the React runtime fragment', () => {
    expect(Fragment).toBe(ReactFragment);
  });

  for (const isStaticChildren of [false, true]) {
    for (const key of [undefined, 'row', 0]) {
      test(`preserves props and children with static=${isStaticChildren} and key=${String(key)}`, () => {
        const child = jsxDEV('span', { children: 'child' }, 'child', false);
        const children = isStaticChildren
          ? [child, jsxDEV('span', { children: 'next' }, 'next', false)]
          : child;
        const props = { title: 'parent', children };
        const element = jsxDEV('div', props, key, isStaticChildren);

        assert(isValidElement<typeof props>(element));
        expect(element.type).toBe('div');
        expect(element.key).toBe(key === undefined ? null : String(key));
        expect(element.props.title).toBe('parent');
        expect(element.props.children).toBe(children);
      });
    }
  }
});
