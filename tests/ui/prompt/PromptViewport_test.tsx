/**
 * Completion rows keep their library scrolling and full-width content, in
 * the room the layer they float in tells them (CHD-545, Q315).
 */
import { expect, test } from 'bun:test';
import { useState } from 'react';
import { CommandList, FileList } from '../../../src/ui/prompt/Prompt.tsx';
import { draw } from '../harness.tsx';
import { until } from '../app/render.tsx';

for (const room of [3, 1]) {
  for (const kind of ['commands', 'files'] as const) {
    test(`${kind} reveals its highlight in ${room} rows`, async () => {
      const screen = await draw(
        <box width={30} height={room + 5}>
          {kind === 'commands' ? (
            <CommandList
              menu={{
                items: Array.from({ length: 6 }, (_, i) => ({
                  name: `choice${i}`,
                  owner: 'agent' as const,
                })),
                highlighted: 5,
                top: 0,
              }}
              rows={6}
              room={room}
              width={30}
            />
          ) : (
            <FileList
              finder={{
                mention: { query: '', line: 0, column: 0 },
                files: Array.from({ length: 6 }, (_, i) => `choice${i}`),
                highlighted: 5,
                top: 0,
                pending: false,
                searching: false,
              }}
              rows={6}
              room={room}
            />
          )}
          <box height={5} flexShrink={0}>
            <text>pinned</text>
          </box>
        </box>,
        { columns: 30, rows: room + 5 },
      );

      try {
        await until('highlight revealed', () =>
          screen.frame().includes('choice5'),
        );
        expect(screen.frame().split('\n')[room]).toContain('pinned');
      } finally {
        await screen.unmount();
      }
    });
  }
}

test('zero rows hide completion paint, and room again restores the selected file however long it was hidden', async () => {
  let room: boolean | undefined;
  const selected = 'abcdefghijklmnopqrstuvwxyz';
  let setRoom: (rows: number) => void = () => {};

  const Held = () => {
    const [rows, set] = useState(0);

    setRoom = set;

    return list(rows);
  };

  const list = (rows: number) => (
    <box width='100%' height='100%'>
      <FileList
        finder={{
          mention: { query: '', line: 0, column: 0 },
          files: ['first', selected],
          highlighted: 1,
          top: 0,
          pending: false,
          searching: false,
        }}
        rows={6}
        room={rows}
        onRoom={(next) => {
          room = next;
        }}
      />
      <box height={5} flexShrink={0}>
        <text>pinned</text>
      </box>
    </box>
  );
  const screen = await draw(<Held />, { columns: 30, rows: 6 });

  try {
    await until(
      'zero completion room',
      () => room === false && !screen.frame().includes(selected),
    );
    expect(screen.mounted(selected)).toBe(false);
    setRoom(1);
    // The frame, not the tree: a row is mounted a frame before it is drawn.
    await until(
      'one completion row',
      () =>
        room === true &&
        screen.frame().split('\n')[0] === `  ${selected}` &&
        screen.frame().split('\n')[1]!.includes('pinned'),
    );
    setRoom(0);
    await until(
      'zero completion paint again',
      () =>
        room === false &&
        !screen.mounted(selected) &&
        screen.frame().split('\n')[0]!.includes('pinned'),
    );
    setRoom(6);
    await until(
      'the whole list back',
      () =>
        room === true &&
        screen.frame().includes('first') &&
        screen.frame().includes(selected),
    );
  } finally {
    await screen.unmount();
  }
});
