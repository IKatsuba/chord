/**
 * The layer over the transcript gives its picker and list the rows they had
 * when they took the transcript's in the window's flow (CHD-545).
 */
import { expect, test } from 'bun:test';
import type { ReactNode } from 'react';
import { NoticeBox } from '../../../src/ui/pickers/Pickers.tsx';
import { Overlay } from '../../../src/ui/prompt/Overlay.tsx';
import { until } from '../app/render.tsx';
import { draw } from '../harness.tsx';

const COLUMNS = 80;

/** A box of `height` rows, each naming itself `name` and its row. */
const rowsOf = (name: string, height: number) => (
  <box flexShrink={0} flexDirection='column'>
    {Array.from({ length: height }, (_, at) => (
      <text key={at}>{`${name} ${at}`}</text>
    ))}
  </box>
);

/**
 * A window `rows` high: a transcript that gives way, then `slot`, then a
 * prompt of five rows. Both are blank, as the test renderer draws the
 * terminal's default background as no fill: what the layer covers would
 * show through it here, though not on a terminal.
 */
const window = (rows: number, slot: ReactNode) => (
  <box width={COLUMNS} height={rows} flexDirection='column'>
    <box flexGrow={1} flexShrink={1} flexBasis={0} />
    {slot}
    <box height={5} flexShrink={0} />
  </box>
);

/** The frame's lines, trailing blanks off. */
const lines = (frame: string) =>
  frame.split('\n').map((line) => line.trimEnd());

/** What `node` draws in a window `rows` high, once `ready` says it is drawn. */
async function drawn(
  node: ReactNode,
  rows: number,
  ready: (frame: string) => boolean,
): Promise<string[]> {
  const screen = await draw(node, { columns: COLUMNS, rows });

  try {
    await until('drawn', () => ready(screen.frame()));

    return lines(screen.frame());
  } finally {
    await screen.unmount();
  }
}

test("a list under a picker gets the rows the picker leaves, as origin/main's flow gave it", async () => {
  let given: number | undefined;
  // The window's flow as origin/main laid it out: the picker kept its rows,
  // the list gave way first.
  const flow = await drawn(
    window(
      14,
      <>
        {rowsOf('picker', 5)}
        <box flexShrink={1} flexBasis={8} minHeight={0} overflow='hidden'>
          {rowsOf('list', 8)}
        </box>
      </>,
    ),
    14,
    (frame) => frame.includes('list 3'),
  );
  const floating = await drawn(
    window(
      14,
      <Overlay
        columns={COLUMNS}
        picker={() => rowsOf('picker', 5)}
        list={(room) => {
          given = room;

          return rowsOf('list', Math.min(8, room));
        }}
      />,
    ),
    14,
    // Nine rows above the prompt: the picker's five, and four for the list.
    (frame) => given === 4 && frame.includes('list 3'),
  );

  expect(floating.slice(0, 9)).toEqual(flow.slice(0, 9));
  expect(floating.join('\n')).not.toContain('list 4');
});

test("dimcode's notice short of room shows the rows origin/main's flow showed of it", async () => {
  const notice = (
    <NoticeBox columns={COLUMNS} active={false} onAnswer={() => {}} />
  );

  for (const rows of [12, 16]) {
    const flow = await drawn(window(rows, notice), rows, (frame) =>
      frame.includes('╭'),
    );
    const floating = await drawn(
      window(
        rows,
        <Overlay columns={COLUMNS} picker={() => notice} list={() => null} />,
      ),
      rows,
      (frame) => frame.includes('╭'),
    );
    // The notice's rows: from its top border down to its bottom one, or to
    // the window's edge that cut it.
    const end = flow.findIndex((line) => line.startsWith('╰'));
    const shown = flow.slice(0, end === -1 ? rows : end + 1);

    expect(shown[0]).toStartWith('╭');
    expect(floating.slice(0, shown.length)).toEqual(shown);
  }
});
