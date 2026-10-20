import { describe, expect, spyOn, test } from 'bun:test';
import stripAnsi from 'strip-ansi';
import { CRASH_HINT } from '../../../src/ui/app/crash.ts';
import { quietCaught } from '../../../src/ui/app/caught.ts';
import { CrashBoundary } from '../../../src/ui/app/Crash.tsx';
import { draw } from '../harness.tsx';
import { until } from './render.tsx';

const broke = new Error('the window broke while drawing');

function Throws(): never {
  throw broke;
}

/** The crash screen over a tree that throws, and what it handed on to quit. */
async function crashed(columns = 80, rows = 24) {
  const quits: unknown[] = [];
  // React writes the caught error to stderr itself, as it does in chord.
  const logged = spyOn(console, 'error').mockImplementation(() => {});

  const drawn = await draw(
    <CrashBoundary quit={(error) => quits.push(error)}>
      <Throws />
    </CrashBoundary>,
    { columns, rows },
  );

  logged.mockRestore();

  return { drawn, quits };
}

test('a tree that throws while drawing shows the crash screen: the error, its frames, then the hint (CHD-468)', async () => {
  const { drawn } = await crashed();

  try {
    const lines = stripAnsi(drawn.frame()).split('\n');

    expect(lines[0]).toBe('');
    expect(lines[1]).toBe('  Error: the window broke while drawing');
    expect(lines[2]).toMatch(/^ {6}at /);
    expect(lines.at(-1)).toBe(`  ${CRASH_HINT}`);
    expect(lines.at(-2)).toBe('');
  } finally {
    await drawn.unmount();
  }
});

test('a key on the crash screen hands the error to quit, once; a paste does not (CHD-468)', async () => {
  const { drawn, quits } = await crashed();

  try {
    await drawn.paste('pasted');
    expect(quits).toStrictEqual([]);
    await drawn.write('q');
    expect(quits).toStrictEqual([broke]);
  } finally {
    await drawn.unmount();
  }
});

test('the crash screen lays out again on a resize (CHD-468)', async () => {
  const { drawn } = await crashed(80, 24);

  try {
    await drawn.resize({ columns: 30, rows: 3 });

    const lines = stripAnsi(drawn.frame()).split('\n');

    expect(lines).toHaveLength(3);
    expect(lines.at(-1)).toBe('  any key to quit · chord pri…');
  } finally {
    await drawn.unmount();
  }
});

describe('CHD-468 tester: crash-screen keys and resize recovery', () => {
  for (const [name, bytes] of [
    ['Enter', '\r'],
    ['Esc', '\x1b'],
    ['Tab', '\t'],
    ['Backspace', '\x7f'],
    ['Up', '\x1b[A'],
    ['F1', '\x1bOP'],
    ['Ctrl+C', '\x03'],
    ['Ctrl+D', '\x04'],
    ['Alt+q', '\x1bq'],
    ['Cmd+q', '\x1b[113;9u'],
  ] as const) {
    test(`${name} hands the original error to quit at 80 columns`, async () => {
      const { drawn, quits } = await crashed();

      try {
        await drawn.write(bytes);
        await until('the crash key to quit', () => quits.length === 1);
        expect(quits).toStrictEqual([broke]);
      } finally {
        await drawn.unmount();
      }
    });
  }

  test('modifier-only keys, pointer input and pasted text leave the error readable', async () => {
    const { drawn, quits } = await crashed();

    try {
      const before = drawn.frame();

      for (const bytes of [
        '\x1b[57441;2u',
        '\x1b[57442;5u',
        '\x1b[57443;3u',
        '\x1b[57444;9u',
        '\x1b[<0;3;3M',
        '\x1b[<0;3;3m',
        '\x1b[<64;3;3M',
      ]) {
        await drawn.write(bytes);
      }

      await drawn.paste('q\n\x03');
      expect(quits).toStrictEqual([]);
      expect(drawn.frame()).toBe(before);
      await drawn.write('q');
      await until(
        'a real key after ignored input to quit',
        () => quits.length === 1,
      );
      expect(quits).toStrictEqual([broke]);
    } finally {
      await drawn.unmount();
    }
  });

  test('shrinking to the hint alone and growing back restores the original frame', async () => {
    const { drawn, quits } = await crashed(120, 40);

    try {
      const before = drawn.frame();

      await drawn.resize({ columns: 30, rows: 1 });
      await until('only the crash hint to fit', () =>
        stripAnsi(drawn.frame()).startsWith('  any key to quit'),
      );
      expect(stripAnsi(drawn.frame()).split('\n')).toHaveLength(1);
      await drawn.resize({ columns: 80, rows: 24 });
      await until('the narrow crash message to return', () =>
        drawn.frame().includes('the window broke while drawing'),
      );
      await drawn.resize({ columns: 120, rows: 40 });
      await until(
        'the original crash frame to return',
        () => drawn.frame() === before,
      );
      expect(quits).toStrictEqual([]);
    } finally {
      await drawn.unmount();
    }
  });
});

test("with chord's console.error in place before the root, React's log of the caught error never comes out (CHD-468)", async () => {
  const original = console.error;
  const reached: unknown[][] = [];

  console.error = quietCaught((...data) => reached.push(data));

  try {
    const drawn = await draw(
      <CrashBoundary quit={() => {}}>
        <Throws />
      </CrashBoundary>,
    );

    try {
      expect(stripAnsi(drawn.frame())).toContain(CRASH_HINT);
      expect(reached.some((data) => data[0] === broke)).toBeFalse();
    } finally {
      await drawn.unmount();
    }
  } finally {
    console.error = original;
  }
});
