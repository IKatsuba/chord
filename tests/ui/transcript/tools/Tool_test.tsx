import { expect, test } from 'bun:test';
import chalk from 'chalk';
import { draw } from '../../harness.tsx';
import stringWidth from 'string-width';
import stripAnsi from 'strip-ansi';
import type { TurnState } from '../../../../src/session/transcript/types.ts';
import { TranscriptEntry } from '../../../../src/ui/transcript/Transcript.tsx';
import { CTRL_O, send, withWindow } from '../../app/render.tsx';

test('tool calls draw their status, their output and a failure', () =>
  withWindow(async (window) => {
    await send(window, 'calls');
    // The read before it runs for a moment too, so wait for the long command
    // rather than for the first call that runs.
    await window.shows('⏺ Bash(deno test --allow-read');
    expect(window.frame()).toContain('Running…');
    await window.shows('Two calls worked, one failed.');

    const frame = window.frame();

    expect(frame).toContain('⏺ Read(src/main.tsx)');
    expect(frame).toContain("⎿  import { Command } from '@cliffy/command';");
    expect(frame).toContain('… +4 lines (ctrl+o to expand)');
    expect(frame).toContain('⎿  ok | 1 passed | 0 failed (12ms)');
    expect(frame).toContain('⎿  Error: File does not exist.');
    expect(
      !frame.includes('Running…'),
      'a finished call still runs',
    ).toBeTruthy();

    // Every line is cut at the window's edge; none wraps. Measured in cells,
    // since the prompt's cursor is an inverse-video escape.
    for (const line of frame.split('\n')) {
      expect(
        stringWidth(line) <= 100,
        `a line wider than the window: ${line}`,
      ).toBeTruthy();
    }

    expect(
      !frame.includes('.parse(Deno.args)'),
      'the output was not cut',
    ).toBeTruthy();
    await window.press(CTRL_O);
    await window.shows('.parse(Deno.args)');
    expect(
      !window.frame().includes('+4 lines'),
      'expanded still counts',
    ).toBeTruthy();
  }));

test("a command's output streams under its call, folded to its end", () =>
  withWindow(async (window) => {
    await send(window, 'shell');
    await window.shows('⏺ Run(deno task test)');
    // Its first piece arrives while it still runs.
    await window.shows('⎿  Task test deno test');
    expect(
      !window.frame().includes('Running…'),
      'output and Running… both',
    ).toBeTruthy();
    await window.shows('The tests failed.');

    const frame = window.frame();

    expect(frame).toContain('⎿  3/3');
    expect(frame).toContain('ok | 2 passed');
    expect(frame).toContain('FAILED | 1 failed');
    expect(frame).toContain('… +2 lines (ctrl+o to expand)');
    expect(frame).toContain('Exit code 1');
    expect(
      !frame.includes('Task test deno test'),
      'the fold kept the start',
    ).toBeTruthy();
    expect(
      !frame.includes('\x1b[32m'),
      'an escape reached the screen',
    ).toBeTruthy();
    expect(
      !frame.includes('Output in a terminal'),
      'the old line is drawn',
    ).toBeTruthy();
    await window.press(CTRL_O);
    await window.shows('⎿  Task test deno test');
    expect(window.frame()).toContain('running 3 tests');
    expect(
      !window.frame().includes('+2 lines'),
      'expanded still counts',
    ).toBeTruthy();
  }));

test('an escape split between pieces of output is never drawn half', () =>
  withWindow(async (window) => {
    await send(window, 'shell');
    await window.shows('The tests failed.');

    const frames = window.written().map((frame) => stripAnsi(frame));

    // A piece ended inside a colour's CSI, the next inside a hyperlink's OSC.
    expect(
      frames.some(
        (frame) => frame.includes('3/3') && !frame.includes('ok | 2 passed'),
      ),
      'no frame between the pieces',
    ).toBeTruthy();
    expect(
      frames.some(
        (frame) => frame.includes('ok | 2 passed') && !frame.includes('FAILED'),
      ),
      'no frame inside the hyperlink',
    ).toBeTruthy();

    for (const frame of frames) {
      expect(
        !/^\s*\[3?\s*$/m.test(frame),
        `a CSI's tail drawn:\n${frame}`,
      ).toBeTruthy();
      expect(
        !frame.includes('example.com'),
        `an OSC's tail drawn:\n${frame}`,
      ).toBeTruthy();
    }

    expect(window.frame()).toContain('FAILED | 1 failed');
  }));

test("a command's line wider than the screen is cut, not wrapped", () =>
  withWindow(
    async (window) => {
      await send(window, 'shell');
      await window.shows('Exit code 1');
      await window.press(CTRL_O);
      await window.shows('running 3 tests');

      const lines = window.frame().split('\n');
      const at = lines.findIndex((line) => line.includes('Task te'));

      // OpenTUI's cut keeps both ends of the line, `...` between them.
      expect(lines[at]?.trimEnd()).toStrictEqual('   ⎿  Task te...no test');
      expect(lines[at + 1]?.trimEnd()).toStrictEqual('      running 3 tests');

      for (const line of lines) {
        expect(
          stringWidth(line) <= 24,
          `wider than the screen: ${line}`,
        ).toBeTruthy();
      }
    },
    { columns: 24 },
  ));

test("Claude's command keeps working until its output comes whole", () =>
  withWindow(async (window) => {
    await send(window, 'bash');
    // Nothing of its output comes while it runs, so it reads as working.
    await window.shows('Running…');
    expect(
      !window.frame().includes('notes.md'),
      'output came before the end',
    ).toBeTruthy();
    await window.shows('Two files changed.');

    const frame = window.frame();

    expect(frame).toContain('⏺ Bash(git status --short)');
    // git's own leading space stays: it is a column of its status.
    expect(frame).toContain('⎿   M src/main.tsx');
    expect(frame).toContain('?? notes.md');
    expect(
      !frame.includes('Exit code'),
      'a success said its exit',
    ).toBeTruthy();
    expect(
      !frame.includes('Running…'),
      'a finished call still runs',
    ).toBeTruthy();
  }));

test('a call its turn left unfinished waits on nothing once the turn has ended', async () => {
  const shown = async (turn: TurnState, status: string) => {
    const drawn = await draw(
      <TranscriptEntry
        entry={{
          kind: 'tool',
          turnId: 'history-2',
          call: { id: 'c', title: 'mcp__chord__spawn_task', status },
        }}
        turn={turn}
        agent='fake'
        expanded={false}
        width={80}
      />,
    );
    const frame = stripAnsi(drawn.frame());

    await drawn.unmount();

    return frame;
  };

  const working = (turnId: string): TurnState => ({
    status: 'working',
    turnId,
    since: 0,
  });

  expect(await shown(working('history-2'), 'pending')).toContain('Waiting…');
  expect(await shown(working('history-2'), 'in_progress')).toContain(
    'Running…',
  );

  // A resumed past, a later turn, and a prompt that returned while a task it
  // started still asks between turns.
  for (const turn of [
    { status: 'idle' },
    working('t-3'),
    {
      status: 'awaiting_permission',
      turnId: 'history-2',
      since: 0,
      permissions: [],
      between: true,
    },
  ] satisfies TurnState[]) {
    for (const status of ['pending', 'in_progress']) {
      const frame = await shown(turn, status);

      expect(frame).toContain('⏺ Tool(mcp__chord__spawn_task)');
      expect(
        !frame.includes('Waiting…'),
        `${turn.status} still waits`,
      ).toBeTruthy();
      expect(
        !frame.includes('Running…'),
        `${turn.status} still runs`,
      ).toBeTruthy();
    }
  }
});

test("an agent's escapes in a call colour it, folded and open, the rest go", async () => {
  const level = chalk.level;

  chalk.level = 3;

  try {
    for (const expanded of [false, true]) {
      const drawn = await draw(
        <TranscriptEntry
          entry={{
            kind: 'tool',
            turnId: 't',
            call: {
              id: 'c',
              title: 'Read(\x1b[32mfile\x1b[39m)',
              status: 'completed',
              content: [
                {
                  type: 'content',
                  content: {
                    type: 'text',
                    // A coloured run and its reset; a line erase and a
                    // hyperlink, which are not SGR, leave only their text.
                    text: '\x1b[31mred\x1b[0m plain\x1b[2K \x1b]8;;https://example.com\x07link\x1b]8;;\x07',
                  },
                },
              ],
            },
          }}
          turn={{ status: 'idle' }}
          agent='fake'
          expanded={expanded}
          width={80}
        />,
        { columns: 80, rows: 8 },
      );
      const frame = drawn.frame();

      await drawn.unmount();
      expect(frame).toContain('\x1b[32mfile\x1b[0m');
      expect(frame).toContain('\x1b[31mred\x1b[0m');
      expect(stripAnsi(frame)).toContain('⏺ Read(file)');
      expect(stripAnsi(frame)).toContain('⎿  red plain link');
      expect(stripAnsi(frame)).not.toMatch(/\[\d*m|\]8;;/);
    }
  } finally {
    chalk.level = level;
  }
});

test('a command of many lines leaves the transcript under it in reach', async () => {
  const title = [
    "cat >> notes.md <<'EOF'",
    ...Array.from({ length: 40 }, (_, line) => `## ${line}. A decision`),
    'EOF',
  ].join('\n');
  const shown = async (expanded: boolean) => {
    const drawn = await draw(
      <box flexGrow={1} justifyContent='flex-end'>
        <box flexShrink={0}>
          {['a', 'b', 'c'].map((id) => (
            <TranscriptEntry
              key={id}
              entry={{
                kind: 'tool',
                turnId: 't',
                call: { id, title, kind: 'execute', status: 'completed' },
              }}
              turn={{ status: 'idle' }}
              agent='fake'
              expanded={expanded}
              width={80}
            />
          ))}
          <text>the reply after them</text>
        </box>
      </box>,
      { columns: 80, rows: 12 },
    );
    const frame = stripAnsi(drawn.frame());

    await drawn.unmount();

    return frame;
  };

  const folded = await shown(false);

  expect(folded).toContain("⏺ Bash(cat >> notes.md <<'EOF' … +41 lines)");
  expect(folded).toContain('the reply after them');

  const whole = await shown(true);

  expect(whole).toContain('  ## 39. A decision');
  expect(whole).toContain('  EOF)');
  expect(whole).toContain('the reply after them');
});
