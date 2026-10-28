/** Completion rows retain their library scrolling and full-width content. */
import { expect, test } from 'bun:test';
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

test('zero rows hide completion paint and one row restores the selected file', async () => {
  let room: boolean | undefined;
  const selected = 'abcdefghijklmnopqrstuvwxyz';
  const screen = await draw(
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
        onRoom={(next) => {
          room = next;
        }}
      />
      <box height={5} flexShrink={0}>
        <text>pinned</text>
      </box>
    </box>,
    { columns: 30, rows: 5 },
  );

  try {
    await until(
      'zero completion room',
      () => room === false && !screen.frame().includes(selected),
    );
    expect(screen.mounted(selected)).toBe(false);
    await screen.resize({ rows: 6 });
    await until(
      'one completion row',
      () => room === true && screen.mounted(selected),
    );
    expect(screen.frame().split('\n')[0]).toBe(`  ${selected}`);
    expect(screen.frame().split('\n')[1]).toContain('pinned');
    await screen.resize({ rows: 5 });
    await until(
      'zero completion paint again',
      () => room === false && !screen.mounted(selected),
    );
    expect(screen.frame().split('\n')[0]).toContain('pinned');
  } finally {
    await screen.unmount();
  }
});
