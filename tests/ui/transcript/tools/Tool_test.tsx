import { describe, expect, test } from 'bun:test';
import chalk from 'chalk';
import { draw } from '../../harness.tsx';
import stringWidth from 'string-width';
import stripAnsi from 'strip-ansi';
import type {
  ToolCall,
  TurnState,
} from '../../../../src/session/transcript/types.ts';
import { ChordServerName } from '../../../../src/ui/app/context.ts';
import { TranscriptEntry } from '../../../../src/ui/transcript/Transcript.tsx';
import {
  asked,
  CTRL_O,
  END,
  send,
  until,
  withWindow,
} from '../../app/render.tsx';
import { NOTES_COMMAND } from '../../../fixtures/headlines.ts';
import {
  LONG_DIFF,
  LONG_JSON,
  LONG_STDOUT,
  LONG_TERMINAL,
} from '../../../fixtures/fake_agent/scenarios/tools.ts';
import { readFile } from 'node:fs/promises';
import { serveChord } from '../../../../src/server/server.ts';
import { join } from 'node:path';

test("a call whose result came only as rawOutput draws it: a string, a shell's output and its failure, an object's JSON (CHD-440)", () =>
  withWindow(
    async (window) => {
      await send(window, 'rawoutputs');
      await window.shows('Ran them.');

      const frame = window.frame();

      expect(frame).toContain('⎿  Thu Oct 22 12:00:00 UTC 2026');
      expect(frame).toContain('⎿  ok 1');
      expect(frame).toContain('   ok 2');
      // Failed, by its exit code, in words as any failed call is.
      expect(frame).toContain('⎿  Error: src/a.ts:3 unused x');
      expect(frame).toContain('⎿  const x = 1;');
      expect(frame).toContain('⎿  built 3 targets');
      expect(frame).toContain('⎿  {');
      expect(frame).toContain('"files": [');
    },
    { rows: 60 },
  ));

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

test("a command's line wider than the screen is wrapped, not cut", () =>
  withWindow(
    async (window) => {
      await send(window, 'shell');
      await window.shows('Exit code 1');
      await window.press(CTRL_O);
      await window.shows('running 3 tests');

      const lines = window.frame().split('\n');
      const at = lines.findIndex((line) => line.includes('Task te'));

      // Wrapped at its words, as every result is (CHD-422).
      expect(
        lines.slice(at, at + 3).map((line) => line.trimEnd()),
      ).toStrictEqual([
        '   ⎿  Task test deno',
        '      test',
        '      running 3 tests',
      ]);

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

      // No server is named chord's here, so the title reads as any MCP call's.
      expect(frame).toContain('⏺ chord - spawn_task (MCP)');
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

test('a command of many lines is drawn whole and leaves the transcript under it in reach', async () => {
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

  // The headline is whole either way; ctrl+o does not change it.
  for (const expanded of [false, true]) {
    const frame = await shown(expanded);

    expect(frame).toContain('  ## 39. A decision');
    expect(frame).toContain('  EOF)');
    expect(frame).toContain('the reply after them');
  }
});

/** The rows of `frame` from the one holding `from` to the one holding `to`. */
function rowsBetween(frame: string, from: string, to: string): string[] {
  const lines = frame.split('\n').map((line) => line.trimEnd());
  const start = lines.findIndex((line) => line.includes(from));
  const end = lines.findIndex(
    (line, index) => index >= start && line.includes(to),
  );

  return lines.slice(start, end + 1);
}

for (const [columns, rows] of [
  [80, 24],
  [120, 40],
] as const) {
  test(`a long command's headline wraps under its name, the ⎿ under its last row, at ${columns}×${rows}`, () =>
    withWindow(
      async (window) => {
        await send(window, 'longcommand');
        await window.shows('Done.');

        // The design's mocks, docs/design/evidence/CHD-393/mock/.
        expect(
          rowsBetween(stripAnsi(window.frame()), '⏺ Bash(echo', '⎿'),
        ).toStrictEqual(
          columns === 80
            ? [
                ' ⏺ Bash(echo "This morning the weather started out cool and misty with a thin',
                '   layer of fog rolling over the hills, but by noon the sun had burned through',
                '   the clouds, the temperature climbed steadily, a light breeze came in from',
                '   the west, and forecasters warned that scattered thunderstorms could arrive',
                '   late in the evening" | tr a-z A-Z | wc -c)',
                '   ⎿  309',
              ]
            : [
                ' ⏺ Bash(echo "This morning the weather started out cool and misty with a thin layer of fog rolling over the hills, but',
                '   by noon the sun had burned through the clouds, the temperature climbed steadily, a light breeze came in from the',
                '   west, and forecasters warned that scattered thunderstorms could arrive late in the evening" | tr a-z A-Z | wc -c)',
                '   ⎿  309',
              ],
        );
      },
      { columns, rows },
    ));

  test(`a heredoc's every line is drawn, an empty one too, at ${columns}×${rows}`, () =>
    withWindow(
      async (window) => {
        await send(window, 'heredoc');
        await window.shows('Done.');

        const [first, ...rest] = NOTES_COMMAND.split('\n');
        const drawn = [
          ` ⏺ Bash(${first}`,
          ...rest.map((line, index) =>
            `   ${line}${index === rest.length - 1 ? ')' : ''}`.trimEnd(),
          ),
          '   ⎿        10 notes.md',
        ];

        expect(
          rowsBetween(stripAnsi(window.frame()), '⏺ Bash(cat', '⎿'),
        ).toStrictEqual(drawn);
      },
      { columns, rows },
    ));
}

test('a command of 300 lines is drawn whole, its output and the reply under it', () =>
  withWindow(
    async (window) => {
      await send(window, 'headlines');
      await window.shows('Four calls with long headlines.');

      expect(
        rowsBetween(stripAnsi(window.frame()), 'line 297 of', 'Four calls'),
      ).toStrictEqual([
        '   line 297 of the long command',
        '   line 298 of the long command',
        '   EOF)',
        '   ⎿  (no output)',
        '',
        ' ⏺ Four calls with long headlines.',
      ]);
    },
    { columns: 80, rows: 24 },
  ));

for (const [columns, rows] of [
  [80, 24],
  [120, 40],
] as const) {
  test(`an MCP call's arguments wrap under its name as the design's mock does, at ${columns}×${rows}`, () =>
    withWindow(
      async (window) => {
        await send(window, 'mcpnote');
        await window.shows('Done.');

        const mock = (
          await readFile(
            join(
              import.meta.dir,
              `../../../../docs/design/evidence/CHD-393/mock/mcp-after-${columns}x${rows}.txt`,
            ),
            'utf8',
          )
        ).split('\n');
        const from = (lines: string[]) => {
          const start = lines.findIndex((line) =>
            line.includes('⏺ notes - save_note'),
          );
          const end = lines.findIndex(
            (line, index) => index > start && line.includes('⎿'),
          );

          // The headline's rows; the ⎿ line under it is cut as it always was.
          return lines.slice(start, end).map((line) => line.trimEnd());
        };

        expect(from(stripAnsi(window.frame()).split('\n'))).toStrictEqual(
          from(mock),
        );
      },
      { columns, rows },
    ));
}

for (const [columns, rows] of [
  [80, 24],
  [120, 40],
] as const) {
  test(`Codex's MCP call draws the same rows as Claude's, the design's mock (CHD-419), at ${columns}×${rows}`, () =>
    withWindow(
      async (window) => {
        await send(window, 'codexmcpnote');
        await window.shows('Done.');

        const mock = (
          await readFile(
            join(
              import.meta.dir,
              `../../../../docs/design/evidence/CHD-393/mock/mcp-after-${columns}x${rows}.txt`,
            ),
            'utf8',
          )
        ).split('\n');
        const from = (lines: string[]) => {
          const start = lines.findIndex((line) =>
            line.includes('⏺ notes - save_note'),
          );
          const end = lines.findIndex(
            (line, index) => index > start && line.includes('⎿'),
          );

          // The headline's rows; the ⎿ line under it is cut as it always was.
          return lines.slice(start, end).map((line) => line.trimEnd());
        };

        expect(from(stripAnsi(window.frame()).split('\n'))).toStrictEqual(
          from(mock),
        );
      },
      { columns, rows },
    ));
}

describe('CHD-1 tester: original question result visibility', () => {
  for (const columns of [80, 120]) {
    test(`expanded question result restores every original line at ${columns} columns`, async () => {
      const result =
        'User has answered your questions: "Which language should helper scripts use?"="Python", "Which checks should run before a commit?"="Types, Tests". You can now continue with the user\'s answers in mind.';
      const continuation = [
        'Language: Python',
        'Checks: Types, Tests',
        'Note: keep portable',
        'Answers complete',
      ];
      const entry = {
        kind: 'tool' as const,
        turnId: 't',
        call: {
          id: 'ask-1',
          title: 'Asking for your input',
          status: 'completed' as const,
          asked: true as const,
          content: [
            {
              type: 'content' as const,
              content: {
                type: 'text' as const,
                text: [result, ...continuation].join('\n'),
              },
            },
          ],
        },
      };
      const turn: TurnState = { status: 'idle' };

      for (const expanded of [false, true]) {
        const rendered = await draw(
          <TranscriptEntry
            entry={entry}
            turn={turn}
            agent='fake'
            expanded={expanded}
            width={columns - 2}
          />,
          { columns, rows: 24 },
        );

        try {
          const frame = stripAnsi(rendered.frame());

          if (expanded) {
            // Existing tool lines stay cut at the terminal width, even expanded.
            expect(frame).toContain('User has answered your questions');

            for (const line of continuation) {
              expect(frame).toContain(line);
            }
          } else {
            expect(frame).not.toContain('User has answered');
            expect(frame).not.toContain('Types, Tests');
          }
        } finally {
          await rendered.unmount();
        }
      }
    });
  }
});

describe('CHD-393 tester: long headline navigation', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`every numbered line remains reachable with paging at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await send(window, 'headlines');
          await window.shows('Four calls with long headlines.');
          await until(
            'the headline turn to finish',
            () => !window.frame().includes('Working'),
          );

          const tail = rowsBetween(
            stripAnsi(window.frame()),
            'line 298 of',
            'Four calls',
          );

          await window.press(CTRL_O);
          expect(
            rowsBetween(stripAnsi(window.frame()), 'line 298 of', 'Four calls'),
          ).toEqual(tail);
          await window.press(CTRL_O);
          await window.press('\x1b[H');
          await window.shows('› headlines');

          const seen = new Set<number>();

          for (let page = 0; page < 40; page++) {
            const frame = window.frame();

            for (const match of frame.matchAll(
              /line (\d+) of the long command/g,
            )) {
              seen.add(Number(match[1]));
            }

            if (frame.includes('Four calls with long headlines.')) {
              break;
            }

            await window.press('\x1b[6~');
          }

          expect([...seen].sort((a, b) => a - b)).toEqual(
            Array.from({ length: 298 }, (_, index) => index + 1),
          );
          await window.press(END);
          await window.shows('EOF)');
          await window.shows('Four calls with long headlines.');
        },
        { columns, rows },
      ));
  }
});

describe('CHD-415 tester: MCP context and view changes', () => {
  test('a chord-2 context distinguishes own and external calls before rawInput arrives', async () => {
    const drawn = await draw(
      <ChordServerName.Provider value='chord-2'>
        {['chord', 'chord-2'].map((server) => (
          <TranscriptEntry
            key={server}
            entry={{
              kind: 'tool',
              turnId: 't',
              call: {
                id: server,
                title: `mcp__${server}__monitor`,
                status: 'completed',
              },
            }}
            turn={{ status: 'idle' }}
            agent='fake'
            expanded={false}
            width={76}
          />
        ))}
      </ChordServerName.Provider>,
      { columns: 80, rows: 12 },
    );

    try {
      const frame = stripAnsi(drawn.frame());

      expect(frame).toContain('⏺ chord - monitor (MCP)');
      expect(frame).toContain('⏺ Monitor');
      expect(frame).not.toContain('chord-2 - monitor');
      expect(frame).not.toContain('undefined');
    } finally {
      await drawn.unmount();
    }
  });

  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`MCP arguments survive verbose toggle and resize from ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await send(window, 'mcpnote');
          await window.shows('Done.');
          await until(
            'the MCP turn to finish',
            () => !window.frame().includes('Working'),
          );

          const before = rowsBetween(
            stripAnsi(window.frame()),
            '⏺ notes - save_note',
            '⎿',
          ).slice(0, -1);

          await window.press(CTRL_O);
          expect(
            rowsBetween(
              stripAnsi(window.frame()),
              '⏺ notes - save_note',
              '⎿',
            ).slice(0, -1),
          ).toEqual(before);
          await window.resize({ columns: columns === 80 ? 120 : 80, rows: 40 });

          const after = rowsBetween(
            stripAnsi(window.frame()),
            '⏺ notes - save_note',
            '⎿',
          ).slice(0, -1);
          const joined = (lines: string[]) =>
            lines.map((line) => line.trim()).join(' ');

          expect(joined(after)).toBe(joined(before));
          expect(joined(after)).toEndWith(
            '["ui-test","tool-rendering","mcp","terminal","claude-code"])',
          );
          expect(after.length).not.toBe(before.length);
        },
        { columns, rows },
      ));
  }
});

/** The words of `text`, each as it would be read on screen. */
function wordsOf(text: string): string[] {
  return text.split(/\s+/).filter((word) => word !== '');
}

for (const columns of [80, 120]) {
  test(`every result longer than a row is wrapped whole at ${columns} columns, never cut or folded`, () =>
    withWindow(
      async (window) => {
        await send(window, 'longresults');
        await window.shows('Four long results.');

        const frame = window.frame();
        // The rows as read, the gutters and the wrapping left out.
        const read = frame.replace(/\s+/g, ' ');

        expect(!frame.includes('...'), frame).toBeTruthy();
        expect(!frame.includes('to expand'), frame).toBeTruthy();

        for (const text of [
          LONG_JSON,
          LONG_STDOUT,
          LONG_DIFF.newText,
          LONG_TERMINAL,
        ]) {
          for (const word of wordsOf(text)) {
            expect(read.includes(word), `${word} is missing`).toBeTruthy();
          }
        }

        for (const line of frame.split('\n')) {
          expect(stringWidth(line) <= columns, line).toBeTruthy();
        }
      },
      { columns, rows: 60 },
    ));
}

for (const columns of [80, 120]) {
  test(`a proposed team's roles wrap in their column and its body is drawn whole at ${columns} columns`, async () => {
    // propose_team is chord's, and its team names claude and codex.
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await send(window, 'propose');
          await window.shows('Save team bugfix?');

          const frame = window.frame();
          const read = frame.replace(/\s+/g, ' ');

          expect(!frame.includes('to expand'), frame).toBeTruthy();

          for (const role of [
            'Splits the job, says who edits which files, reports to main',
            'Writes the failing test, then proves the fix',
            'Writes the fix, in the files the lead names',
            'Reads the diff and edits nothing',
          ]) {
            for (const word of wordsOf(role)) {
              expect(read.includes(word), `${word} is missing`).toBeTruthy();
            }
          }

          // The body's last line, which a fold left out.
          expect(read).toContain('make, when the job is done');
        },
        { columns, rows: 120, server, runtimes: ['fake', 'claude', 'codex'] },
      );
    } finally {
      await server.close();
    }
  });
}

test("a proposed change's body diff wraps its long lines under their code, never clipped, at 80 columns", async () => {
  const server = serveChord();
  const bugfix = await readFile(
    new URL('../../../fixtures/teams/fake/bugfix.md', import.meta.url),
    'utf8',
  );

  try {
    await withWindow(
      async (window) => {
        await send(window, 'propose');
        await window.shows('Replace team bugfix?');

        const read = window.frame().replace(/\s+/g, ' ');

        expect(read).toContain("bugfix.md's body · 10 additions, 6 removals");
        // A line wider than the row, whole under its number and sign.
        expect(read).toContain(
          '5 + 3. coder fixes the code so that test passes. It edits only the files the lead named for it, and never `tests/`.',
        );
      },
      {
        columns: 80,
        rows: 120,
        server,
        runtimes: ['fake', 'claude', 'codex'],
        teams: { bugfix },
      },
    );
  } finally {
    await server.close();
  }
});

test("chord's calls the agent cut off say after their body that they did nothing, wrapped at 80 columns", async () => {
  // Read as chord's own by the name the session gave chord's server.
  const server = serveChord();

  try {
    await withWindow(
      async (window) => {
        await send(window, 'cutcalls');
        await window.shows('I have stopped.');

        const read = window.frame().replace(/\s+/g, ' ');

        expect(read).toContain(
          '→ to @main ⎿ CHD-393: the owner has a question on Q8',
        );
        expect(read).toContain(
          'Not delivered: cut off before it reached chord. chord tells the agent at its next turn.',
        );
        expect(read).toContain(
          'Cut off before it reached chord, so it did nothing. chord tells the agent at its next turn.',
        );
        expect(read).not.toContain('Error calling tool');
      },
      { columns: 80, rows: 50, server },
    );
  } finally {
    await server.close();
  }
});

describe('CHD-422 tester: wrapped source-line exceptions', () => {
  for (const columns of [80, 120]) {
    test(`Read keeps the first three source lines and terminal the last three at ${columns} columns`, async () => {
      const source = Array.from(
        { length: 4 },
        (_, index) =>
          `source-${index + 1} ${'one two three four five six seven eight '.repeat(5)}tail-${index + 1}`,
      );
      const calls: ToolCall[] = [
        {
          id: 'read',
          title: 'Read notes.txt',
          kind: 'read',
          status: 'completed',
          content: [
            {
              type: 'content',
              content: { type: 'text', text: source.join('\n') },
            },
          ],
        },
        {
          id: 'terminal',
          title: '`test`',
          kind: 'execute',
          status: 'failed',
          terminals: [
            {
              id: 'term',
              output: source.join('\n'),
              exited: true,
              exitCode: 2,
            },
          ],
        },
      ];

      for (const call of calls) {
        for (const expanded of [false, true]) {
          const drawn = await draw(
            <TranscriptEntry
              entry={{ kind: 'tool', turnId: 't', call }}
              turn={{ status: 'idle' }}
              agent='fake'
              expanded={expanded}
              width={columns}
            />,
            { columns, rows: 60 },
          );

          try {
            const shown = stripAnsi(drawn.frame());
            const read = shown.replace(/\s+/g, ' ');
            const kept = expanded
              ? source
              : call.id === 'read'
                ? source.slice(0, 3)
                : source.slice(-3);

            for (const line of kept) {
              expect(read).toContain(line);
            }

            expect(shown).not.toContain('...');
            expect(
              shown.split('\n').every((row) => stringWidth(row) <= columns),
            ).toBe(true);

            if (expanded) {
              expect(shown).not.toContain('to expand');
            } else {
              expect(shown).toContain('… +1 line (ctrl+o to expand)');
              expect(shown).not.toContain(
                call.id === 'read' ? 'tail-4' : 'source-1',
              );
            }

            if (call.id === 'terminal') {
              expect(shown).toContain('Exit code 2');
            }
          } finally {
            await drawn.unmount();
          }
        }
      }
    });
  }
});

test('a call the person is asked about waits, whatever its status, until answered', async () => {
  const shown = async (status: string, asked: boolean) => {
    const drawn = await draw(
      <TranscriptEntry
        entry={{
          kind: 'tool',
          turnId: 't',
          call: { id: 'c', title: 'Run ./deploy.sh', kind: 'execute', status },
        }}
        turn={{
          status: 'awaiting_permission',
          turnId: 't',
          since: 0,
          permissions: asked ? [{ id: 'p', toolCallId: 'c', options: [] }] : [],
        }}
        agent='fake'
        expanded={false}
        width={80}
      />,
    );
    const frame = stripAnsi(drawn.frame());

    await drawn.unmount();

    return frame;
  };

  // The marker takes the same tone as the line under it.
  expect(await shown('in_progress', true)).toStrictEqual(
    await shown('pending', false),
  );
  expect(await shown('in_progress', true)).toContain('⎿  Waiting…');
  expect(await shown('in_progress', false)).toContain('⎿  Running…');
});

test("a command waits while asked, mid-run as Codex's adapter asks and first as Claude's", () =>
  withWindow(async (window) => {
    await send(window, 'bashask');
    await asked(window);

    let frame = window.frame();

    expect(frame).toContain('⏺ Run(./deploy.sh)');
    expect(frame).toMatch(/⎿ {2}Waiting…\n\s+building…\n\s+built in 1\.2s/);
    expect(!frame.includes('Running…'), "Codex's asked call runs").toBeTruthy();
    await window.press('1');
    await window.shows('deployed');
    await window.shows('⏺ Bash(git push)');
    await asked(window);

    frame = window.frame();

    expect(frame).toMatch(/Bash\(git push\)\n\s+⎿ {2}Waiting…/);
    await window.press('1');
    await window.shows('Codex: ran; Claude: ran.');
    expect(window.frame()).toContain('pushed');
  }));

describe('CHD-404 tester: denied commands at terminal sizes', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`denial preserves earlier output and clears waiting at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await send(window, 'bashask');
          await asked(window);
          expect(window.frame()).toContain('Waiting…');
          expect(window.frame()).toContain('built in 1.2s');
          await window.press('3');
          await window.shows('Bash(git push)');
          await asked(window);
          await window.press('3');
          await window.shows('Codex: denied; Claude: denied.');

          const frame = window.frame();

          expect(frame).toContain('not deployed');
          expect(frame).toContain('built in 1.2s');
          expect(frame).toContain('Exit code 1');
          expect(frame).toContain('Failed');
          expect(frame).not.toContain('Waiting…');
          expect(frame).not.toContain('Running…');
          expect(
            frame.split('\n').every((row) => stringWidth(row) <= columns),
          ).toBe(true);
        },
        { columns, rows },
      ));
  }
});

describe('CHD-404 tester: cancelling an open command permission', () => {
  test('cancelling clears the permission and a later turn has no stale Waiting line', () =>
    withWindow(async (window) => {
      await send(window, 'bashask');
      await asked(window);
      await window.session()!.cancel();
      await until(
        'the permission turn to end',
        () => !window.frame().includes('Waiting…'),
      );
      expect(window.frame()).not.toContain('Waiting…');
      await send(window, 'hello');
      await window.shows('Hello');
      expect(window.frame()).not.toContain('Waiting…');
    }));
});
