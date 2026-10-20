import { expect, spyOn, test } from 'bun:test';
import stripAnsi from 'strip-ansi';
import { CRASH_HINT } from '../../../src/ui/app/crash.ts';
import { CrashBoundary } from '../../../src/ui/app/Crash.tsx';
import { draw } from '../harness.tsx';

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
