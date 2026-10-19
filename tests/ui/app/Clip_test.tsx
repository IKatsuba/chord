import { describe, expect, test } from 'bun:test';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import { createRef, type ReactNode, useEffect, useState } from 'react';
import { Clip } from '../../../src/ui/app/Clip.tsx';
import { TEXT } from '../../../src/ui/theme/text.ts';
import { draw } from '../harness.tsx';
import { until } from './render.tsx';
import type { BoxRenderable } from '@opentui/core';

/** What `node` draws in a terminal of `columns` × `rows`, escapes kept. */
async function drawn(node: ReactNode, columns = 20, rows = 6): Promise<string> {
  // chalk sees no terminal under test, and the harness writes no escapes
  // while it sees none.
  const level = chalk.level;

  chalk.level = 3;

  try {
    const app = await draw(node, { columns, rows });
    const frame = app.frame();

    await app.unmount();

    return frame;
  } finally {
    chalk.level = level;
  }
}

test('a clipping box laid out to no rows draws nothing of what it holds', async () => {
  const frame = await drawn(
    <box width={20} height={3}>
      <Clip flexGrow={1}>
        <text {...TEXT}>one</text>
        <text {...TEXT}>two</text>
      </Clip>
      <box flexShrink={0} height={3}>
        <text {...TEXT}>panel</text>
      </box>
    </box>,
    20,
    3,
  );

  expect(stripAnsi(frame).split('\n')).toStrictEqual(['panel']);
});

/** A clipping box above a panel that grows from two rows to three. */
function Squeezed() {
  const [tall, setTall] = useState(false);

  useEffect(() => {
    const timer = setTimeout(() => setTall(true), 50);

    return () => clearTimeout(timer);
  }, []);

  return (
    <box width={20} height={3}>
      <Clip flexGrow={1} flexShrink={1} flexBasis={0}>
        <text {...TEXT}>one-a</text>
        <text {...TEXT}>two-bb</text>
      </Clip>
      <box flexShrink={0} height={tall ? 3 : 2}>
        <text {...TEXT}>panel</text>
      </box>
    </box>
  );
}

test("a clipping box that goes from one row to none leaves nothing of what it held over what follows (the owner's Q57, CHD-158)", async () => {
  const app = await draw(<Squeezed />, { columns: 20, rows: 3 });

  try {
    // One row: something of what it holds.
    expect(stripAnsi(app.frame()).split('\n')[0]).not.toBe('panel');
    await new Promise((resolve) => setTimeout(resolve, 300));
    // None: the panel's row is the panel's alone.
    expect(stripAnsi(app.frame()).split('\n')[0]).toBe('panel');
  } finally {
    await app.unmount();
  }
});

describe('CHD-158 C6 tester: observed layout transitions and lifecycle', () => {
  test('an observed one-row transcript unmounts at zero and mounts again when space returns', async () => {
    let setPanel: (rows: number) => void = () => {};

    let mounts = 0;
    let unmounts = 0;

    function Content() {
      useEffect(() => {
        mounts++;

        return () => {
          unmounts++;
        };
      }, []);

      return <text {...TEXT}>observed transcript</text>;
    }

    function Layout() {
      const [panel, update] = useState(2);

      useEffect(() => {
        setPanel = update;
      }, []);

      return (
        <box width={20} height={3}>
          <Clip flexGrow={1} flexShrink={1} flexBasis={0}>
            <Content />
          </Clip>
          <box flexShrink={0} height={panel}>
            <text {...TEXT}>panel</text>
          </box>
        </box>
      );
    }

    const app = await draw(<Layout />, { columns: 20, rows: 3 });

    try {
      await until(
        'the initial transcript is really drawn',
        () => stripAnsi(app.frame()).split('\n')[0] === 'observed transcript',
      );
      expect(mounts).toBe(1);
      setPanel(3);
      await until(
        'the panel alone owns the first row',
        () =>
          stripAnsi(app.frame()).split('\n')[0] === 'panel' &&
          !app.mounted('observed transcript'),
      );
      expect(unmounts).toBe(1);
      setPanel(2);
      await until(
        'the transcript remounts into positive space',
        () =>
          app.mounted('observed transcript') &&
          stripAnsi(app.frame()).includes('observed transcript'),
      );
      expect(mounts).toBe(2);
      expect(unmounts).toBe(1);
    } finally {
      await app.unmount();
    }

    expect(unmounts).toBe(2);
  });

  test('zero width hides the child and restoring width remounts it', async () => {
    let setWidth: (width: number) => void = () => {};

    function Layout() {
      const [width, update] = useState(0);

      useEffect(() => {
        setWidth = update;
      }, []);

      return (
        <box width={20} height={3}>
          <Clip width={width} height={1}>
            <text {...TEXT}>width child</text>
          </Clip>
          <text {...TEXT}>footer</text>
        </box>
      );
    }

    const app = await draw(<Layout />, { columns: 20, rows: 3 });

    try {
      await until(
        'the zero-width child is unmounted',
        () =>
          !app.mounted('width child') &&
          stripAnsi(app.frame()).includes('footer'),
      );
      setWidth(20);
      await until(
        'positive width draws the child',
        () =>
          app.mounted('width child') &&
          stripAnsi(app.frame()).includes('width child'),
      );
      setWidth(0);
      await until(
        'zero width removes it again',
        () => !app.mounted('width child'),
      );
    } finally {
      await app.unmount();
    }
  });

  test('the supplied render hook receives the box and stops with unmount without a render loop', async () => {
    const ref = createRef<BoxRenderable>();
    let calls = 0;
    const receivers: BoxRenderable[] = [];
    const app = await draw(
      <Clip
        ref={ref}
        width={10}
        height={1}
        renderAfter={function (this: BoxRenderable, buffer, delta) {
          calls++;
          receivers.push(this);
          expect(buffer).toBeDefined();
          expect(typeof delta).toBe('number');
        }}
      >
        <text {...TEXT}>stable</text>
      </Clip>,
      { columns: 20, rows: 3 },
    );

    try {
      expect(stripAnsi(app.frame())).toContain('stable');
      expect(calls).toBeGreaterThan(0);
      expect(receivers.at(-1)).toBe(ref.current!);

      const before = calls;

      for (let i = 0; i < 6; i++) {
        await app.resize({ columns: 21 + (i % 2) });
      }

      expect(calls - before).toBeLessThanOrEqual(24);
    } finally {
      await app.unmount();
    }

    expect(ref.current).toBeNull();

    const closedCalls = calls;
    const replacement = await draw(<text {...TEXT}>replacement</text>, {
      columns: 20,
      rows: 3,
    });

    try {
      await replacement.resize({ columns: 21 });
      expect(calls).toBe(closedCalls);
    } finally {
      await replacement.unmount();
    }
  });
});
