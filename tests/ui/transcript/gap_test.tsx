import { describe, expect, test } from 'bun:test';
import type { ScrollBoxRenderable } from '@opentui/core';
import type { ReactNode } from 'react';
import { BlockGap, useGap } from '../../../src/ui/transcript/gap.ts';
import { draw } from '../harness.tsx';

/** `node` in OpenTUI's scrollbox `rows` tall: the lines it counts. */
async function counted(node: ReactNode, rows: number): Promise<number> {
  let box: ScrollBoxRenderable | null = null;
  const drawn = await draw(
    <box flexDirection='column' width={30}>
      <scrollbox
        ref={(each: ScrollBoxRenderable | null) => {
          box = each;
        }}
        height={rows}
        flexShrink={0}
        verticalScrollbarOptions={{ visible: false }}
      >
        {node}
      </scrollbox>
    </box>,
    { columns: 30, rows: 12 },
  );

  try {
    await new Promise((resolve) => setTimeout(resolve, 50));

    return (box as ScrollBoxRenderable | null)?.scrollHeight ?? 0;
  } finally {
    await drawn.unmount();
  }
}

const lines = (count: number) =>
  Array.from({ length: count }, (_, index) => (
    <text key={index}>{`line ${index}`}</text>
  ));
const row = (key: number) => (
  <box key={key} flexDirection='row' flexShrink={0}>
    <text>{`row ${key}`}</text>
  </box>
);

describe('opentui#1739: a scrollbox one row tall misses a margin, and padding over a box', () => {
  // When these fail, the OpenTUI pinned counts them: BlockGap and the
  // detail's provider go (docs/decisions.md).
  test('a row of margin over three lines reads one row; at two rows, its four', async () => {
    const margined = () => (
      <box marginTop={1} flexShrink={0}>
        {lines(3)}
      </box>
    );

    expect(await counted(margined(), 1)).toBe(1);
    expect(await counted(margined(), 2)).toBe(4);
  });

  test('a row of padding over a box reads one row, not its two', async () => {
    expect(
      await counted(
        <box paddingTop={1} flexShrink={0}>
          {row(0)}
        </box>,
        1,
      ),
    ).toBe(1);
  });
});

test('a row of its own before each block is counted at every height (CHD-487)', async () => {
  const blocks = () =>
    [0, 1, 2].map((key) => (
      <box key={key} flexShrink={0}>
        <box height={1} flexShrink={0} />
        {row(key)}
      </box>
    ));

  for (const rows of [1, 2, 3]) {
    expect(await counted(<>{blocks()}</>, rows)).toBe(6);
  }
});

test('a block is spaced by a margin, and by a row of its own where a scrollbox asks for it (CHD-487)', async () => {
  const seen: { props: unknown; spacer: boolean }[] = [];

  function Block() {
    const gap = useGap();

    seen.push({ props: gap.props, spacer: gap.spacer !== null });

    return <text>block</text>;
  }

  const drawn = await draw(
    <box>
      <Block />
      <BlockGap.Provider value='row'>
        <Block />
      </BlockGap.Provider>
    </box>,
  );

  await drawn.unmount();
  expect(seen.slice(0, 2)).toStrictEqual([
    { props: { marginTop: 1 }, spacer: false },
    { props: {}, spacer: true },
  ]);
});
