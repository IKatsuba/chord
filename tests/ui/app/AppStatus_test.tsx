/**
 * What the window tells the terminal and its tabs: work, done and idle, the
 * record's title, blocked requests, and which agent a picked child names.
 */
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openSession, type Session } from '../../../src/session/session.ts';
import { serveChord } from '../../../src/server/server.ts';
import { fakeAgentCommand, gatedCommand } from '../../fixtures/fake.ts';
import {
  asked,
  DOWN,
  CTRL_G,
  ESC,
  inputAsked,
  promptRow,
  ready,
  send,
  statusReports,
  until,
  UP,
  type Window,
  withWindow,
} from './render.tsx';

/** The last program status the terminal was told, its fields as written. */
function lastStatus(
  log: readonly string[],
): Record<string, string> | undefined {
  return statusReports(log).at(-1);
}

test("the terminal hears chord work, then done with the notification's words, then idle at the next key (CHD-382)", () => {
  const log: string[] = [];

  return withWindow(
    async (window) => {
      await ready(window);
      await until(
        'idle to be reported',
        () => lastStatus(log)?.state === 'idle',
      );
      expect(lastStatus(log)).toStrictEqual({ state: 'idle', app: 'chord' });
      await send(window, 'slow');
      await until(
        'working to be reported',
        () => lastStatus(log)?.state === 'working',
      );
      await until(
        'done to be reported',
        () => lastStatus(log)?.state === 'done',
      );
      // Named by its first prompt from then on (CHD-491).
      expect(lastStatus(log)).toStrictEqual({
        state: 'done',
        app: 'chord',
        title: 'slow',
        msg: 'fake is waiting for your input',
      });

      const sent = statusReports(log).length;

      await window.type('x');
      await until(
        'idle to be reported',
        () => lastStatus(log)?.state === 'idle',
      );
      // Each change once: a draw that changes nothing reports nothing.
      expect(statusReports(log).slice(sent)).toStrictEqual([
        { state: 'idle', app: 'chord', title: 'slow' },
      ]);
    },
    { log },
  );
});

test("the record's title is the agent's own title for the main session once it gives one, and follows it as it changes (CHD-491, Q119)", () => {
  const log: string[] = [];

  return withWindow(
    async (window) => {
      await ready(window);
      await send(window, 'text');
      await window.shows('came in chunks.');
      // None from the agent yet: the first prompt.
      await until('the title', () => lastStatus(log)?.title === 'text');
      // One name a prompt, so each is drawn and told before the next.
      await send(window, 'titledlook');
      await window.shows('Looking.');
      await until(
        "the agent's title",
        () => lastStatus(log)?.title === 'Look at the parser',
      );
      await send(window, 'titledfix');
      await window.shows('Renamed.');
      await until(
        'its new title',
        () => lastStatus(log)?.title === 'Fix the parser',
      );
    },
    { log },
  );
});

test("the record's title is the main session's first prompt, a child picked and prompted leaving it so (CHD-491)", async () => {
  const log: string[] = [];
  const server = serveChord();
  const admit = server.admit.bind(server);
  let main: Parameters<typeof admit>[0] | undefined;

  server.admit = (caller) => {
    if (caller.role === 'person') {
      main = caller;
    }

    return admit(caller);
  };

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        expect(lastStatus(log)?.title).toStrictEqual(undefined);
        await send(window, 'text');
        await window.shows('came in chunks.');
        await until('the title', () => lastStatus(log)?.title === 'text');

        if (main === undefined) {
          throw new Error('main was not admitted');
        }

        await main.window.open(main.key, {
          agent: 'fake',
          name: 'helper',
          prompt: 'steps',
        });
        await window.shows('helper');
        await window.press(DOWN);
        await window.press(DOWN);
        await window.press('\r');
        await window.shows('╭─ helper ─');
        // Its first prompt answered and the box taking keys, or a prompt
        // typed under load waits in the box unsent.
        await window.shows('150 steps read.');
        // The status line's hint, above the agents list.
        await window.shows('? for shortcuts');
        await send(window, 'slow');
        await until(
          'working to be reported',
          () => lastStatus(log)?.state === 'working',
        );
        expect(
          statusReports(log).every(
            (report) => report.title === undefined || report.title === 'text',
          ),
        ).toBeTruthy();
        expect(lastStatus(log)?.title).toStrictEqual('text');
      },
      { log, server },
    );
  } finally {
    await server.close();
  }
});

test('a permission is reported blocked with its kind and words, and the answer goes back to work (CHD-382)', () => {
  const log: string[] = [];

  return withWindow(
    async (window) => {
      await ready(window);
      await send(window, 'permission');
      await asked(window);
      expect(lastStatus(log)).toStrictEqual({
        state: 'blocked',
        kind: 'permission',
        app: 'chord',
        title: 'permission',
        msg: 'fake needs your permission: Write notes.txt',
      });
      await window.press('1');
      await until(
        'done to be reported',
        () => lastStatus(log)?.state === 'done',
      );
    },
    { log },
  );
});

test("ctrl+g clears chord's status for the editor and reports it again once back (CHD-382)", () => {
  const log: string[] = [];

  return withWindow(
    async (window) => {
      await ready(window);
      await window.press(CTRL_G);
      await window.shows('from the editor');

      const editor = log.findIndex((chunk) => chunk.startsWith('editor: '));
      const reports = (chunks: readonly string[]) => statusReports(chunks);

      expect(reports(log.slice(0, editor)).at(-1)).toStrictEqual({
        state: 'clear',
      });
      expect(reports(log.slice(editor))).toStrictEqual([
        { state: 'idle', app: 'chord' },
      ]);
    },
    {
      log,
      editor: (draft) => {
        log.push(`editor: ${draft}`);

        return Promise.resolve({ text: 'from the editor' });
      },
    },
  );
});

describe("a picked child on another runtime is named by its own agent, not the tab's (CHD-488)", () => {
  /**
   * Opens `foreign`, a codex child of main on the fake tab, its agent
   * started by `codex` and given `prompt`, and picks it.
   */
  async function onChild(
    codex: readonly string[],
    prompt: string,
    body: (window: Window) => Promise<void>,
    options: Parameters<typeof withWindow>[1] = {},
  ): Promise<void> {
    const server = serveChord();
    const admit = server.admit.bind(server);
    let main: Parameters<typeof admit>[0] | undefined;
    const command = fakeAgentCommand();

    server.admit = (caller) => {
      if (caller.role === 'person') {
        main = caller;
      }

      return admit(caller);
    };

    try {
      await withWindow(
        async (window) => {
          await ready(window);

          if (main === undefined) {
            throw new Error('main was not admitted');
          }

          await main.window.open(main.key, {
            agent: 'codex',
            name: 'foreign',
            prompt,
          });
          await window.shows('foreign');
          await window.press(DOWN);
          await window.press(DOWN);
          await window.press('\r');
          await window.shows('╭─ foreign ─');
          await body(window);
        },
        {
          ...options,
          server,
          runtimes: ['fake', 'codex'],
          agentCommand: command,
          startupOf: (agent) => ({
            agentCommand: agent === 'codex' ? [...codex] : command,
          }),
        },
      );
    } finally {
      await server.close();
    }
  }

  test('the status line says the child is starting by its own agent', async () => {
    // The child's agent starts only once the gate is there.
    const gates = await mkdtemp(join(tmpdir(), 'chord-gate-'));
    const gate = join(gates, 'open');

    try {
      await onChild(
        gatedCommand(gate, fakeAgentCommand()),
        'text',
        async (window) => {
          await window.shows('Starting codex…');
          expect(window.frame()).not.toContain('Starting fake…');
          await writeFile(gate, '');
        },
      );
    } finally {
      await rm(gates, { recursive: true, force: true });
    }
  });

  test('a child whose agent did not start says so by its own agent', () =>
    onChild(['sh', '-c', 'exit 1'], 'text', async (window) => {
      await window.shows('codex did not start:');
      expect(window.frame()).not.toContain('fake did not start');
    }));

  test("a form's record names the child's agent as who asked", () =>
    onChild(fakeAgentCommand(), 'text', async (window) => {
      await window.shows('came in chunks.');
      await send(window, 'form');
      await inputAsked(window, 'foreign asks for input');
      await window.press(ESC);
      await window.shows('codex asked');
      expect(window.frame()).not.toContain('fake asked');
    }));

  test("/model and /config name the child's agent", () =>
    onChild(fakeAgentCommand(), 'text', async (window) => {
      await window.type('/model');
      await window.press('\r');
      await until('the model picker', () =>
        /codex offers no models|Switch codex's model/.test(window.frame()),
      );
      expect(window.frame()).not.toMatch(/fake offers|Switch fake's/);
      await window.press(ESC);
      await window.type('/config');
      await window.press('\r');
      await until('the settings picker', () =>
        /codex has no settings|Change codex's settings/.test(window.frame()),
      );
      expect(window.frame()).not.toMatch(/fake has no settings|Change fake's/);
    }));

  test("ctrl+v's refusal names the child's agent", () =>
    onChild(
      fakeAgentCommand(undefined, '--no-images'),
      'text',
      async (window) => {
        await window.shows('came in chunks.');
        await window.press('\x16');
        await window.shows('codex does not take images');
        expect(window.frame()).not.toContain('fake does not take images');
      },
      { clipboard: () => Promise.resolve({ failed: 'not read' }) },
    ));
});

describe('CHD-488 tester: agent identity follows the selected conversation', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`returning to the parent restores its identity at ${columns}×${rows}`, async () => {
      const server = serveChord();
      const admit = server.admit.bind(server);
      let main: Parameters<typeof admit>[0] | undefined;
      const command = fakeAgentCommand();
      const gates = await mkdtemp(join(tmpdir(), 'chord-identity-'));
      const gate = join(gates, 'open');
      let clipboardReads = 0;

      server.admit = (caller) => {
        if (caller.role === 'person') {
          main = caller;
        }

        return admit(caller);
      };

      try {
        await withWindow(
          async (window) => {
            await ready(window);

            if (main === undefined) {
              throw new Error('main was not admitted');
            }

            await main.window.open(main.key, {
              agent: 'codex',
              name: 'delayed-child',
              prompt: 'text',
            });
            await window.shows('delayed-child');
            await window.press(DOWN);
            await window.press(DOWN);
            await window.press('\r');
            await window.shows('Starting codex…');
            await window.press('\x16');
            await window.shows('codex has not started yet');
            expect(clipboardReads).toBe(0);
            expect(window.frame()).not.toContain('fake has not started yet');
            await window.press(DOWN);
            await window.press(UP);
            await window.press('\r');
            await until(
              'the parent is shown again',
              () => !window.frame().includes('╭─ delayed-child ─'),
            );
            await send(window, '/model');
            await window.shows("Switch fake's model");
            expect(window.frame()).not.toContain("Switch codex's model");
            await window.press(ESC);
            await window.press(DOWN);
            await window.press(DOWN);
            await window.press('\r');
            await window.shows('Starting codex…');
            await writeFile(gate, '');
            await window.shows('came in chunks.');
            await window.press('\x16');
            await window.shows('codex does not take images');
            expect(window.frame()).not.toContain('fake does not take images');
            expect(clipboardReads).toBe(0);
          },
          {
            server,
            columns,
            rows,
            runtimes: ['fake', 'codex'],
            agentCommand: command,
            startupOf: (agent) => ({
              agentCommand:
                agent === 'codex'
                  ? gatedCommand(
                      gate,
                      fakeAgentCommand(undefined, '--no-images'),
                    )
                  : command,
            }),
            clipboard: () => {
              clipboardReads += 1;

              return Promise.resolve({ failed: 'unexpected clipboard read' });
            },
          },
        );
      } finally {
        await rm(gates, { recursive: true, force: true });
        await server.close();
      }
    });
  }
});

describe('CHD-491 tester: the main session title on the actual OSC wire', () => {
  /** Encoded title fields, from the bytes OpenTUI actually wrote. */
  const wireTitles = (log: readonly string[]) => {
    // eslint-disable-next-line no-control-regex
    const records = /\x1b\]7501;[^\x07\x1b]*?title=([^:\x07\x1b]*)/g;

    return [...log.join('').matchAll(records)].map((match) => match[1]!);
  };

  for (const columns of [80, 120]) {
    const rows = columns === 80 ? 24 : 40;

    test(`unnamed, first prompt, clear, resume and fresh name at ${columns} columns`, async () => {
      const log: string[] = [];

      await withWindow(
        async (window) => {
          await ready(window);
          await until(
            'initial idle record',
            () => lastStatus(log)?.state === 'idle',
          );
          expect(lastStatus(log)?.title).toBeUndefined();
          expect(wireTitles(log)).toStrictEqual([]);
          await send(window, 'First main session');
          await window.shows('came in chunks.');
          await until(
            'first prompt title',
            () => lastStatus(log)?.title === 'First main session',
          );
          await send(window, 'A later prompt');
          await window.shows('came in chunks.');
          expect(lastStatus(log)?.title).toBe('First main session');
          await send(window, '/clear');
          await until(
            'clear omits old title',
            () => lastStatus(log)?.title === undefined,
          );
          await ready(window);
          await send(window, '/resume');
          await window.shows('Resume a session');
          await window.shows('First main session');
          await window.press('\r');
          await until(
            'resumed title restored',
            () => lastStatus(log)?.title === 'First main session',
          );
          expect(wireTitles(log)).toContain(
            Buffer.from('First main session').toString('base64'),
          );
          await send(window, '/clear');
          await until(
            'resumed title cleared',
            () => lastStatus(log)?.title === undefined,
          );
          await ready(window);
          await send(window, 'Replacement main session');
          await until(
            'replacement title',
            () => lastStatus(log)?.title === 'Replacement main session',
          );
        },
        { log, columns, rows },
      );
    });

    for (const [label, prompt, expected] of [
      ['two-byte exact', 'é'.repeat(96), 'é'.repeat(96)],
      ['two-byte overflow', 'é'.repeat(97), 'é'.repeat(96)],
      ['three-byte exact', '語'.repeat(64), '語'.repeat(64)],
      ['three-byte overflow', '語'.repeat(65), '語'.repeat(64)],
      ['joined emoji exact', 'a'.repeat(181) + '👩‍💻', 'a'.repeat(181) + '👩‍💻'],
      ['joined emoji crosses', 'a'.repeat(182) + '👩‍💻', 'a'.repeat(182)],
      ['combining exact', 'é'.repeat(64), 'é'.repeat(64)],
      ['combining crosses', 'a'.repeat(190) + 'é', 'a'.repeat(190)],
    ] as const) {
      test(`${label} fits both byte bounds on the wire at ${columns} columns`, async () => {
        const log: string[] = [];

        await withWindow(
          async (window) => {
            await ready(window);
            await window.paste(prompt);
            await until(
              'pasted name in prompt',
              () => promptRow(window)?.includes(prompt.slice(0, 20)) ?? false,
            );
            await window.press('\r');
            await until(
              'bounded title emitted',
              () => lastStatus(log)?.title === expected,
            );

            const titles = wireTitles(log);
            const encoded = Buffer.from(expected).toString('base64');

            expect(titles.length).toBeGreaterThan(0);
            expect(titles.every((title) => title === encoded)).toBe(true);

            for (const title of titles) {
              const decoded = Buffer.from(title, 'base64');

              expect(title.length).toBeLessThanOrEqual(256);
              expect(decoded.length).toBeLessThanOrEqual(192);
              expect(decoded.toString('utf8')).toBe(expected);
              expect(decoded.toString('utf8')).not.toContain('\ufffd');
            }
          },
          { log, columns, rows },
        );
      });
    }
  }

  test('a picked child cannot name an unnamed main session', async () => {
    const server = serveChord();
    const admit = server.admit.bind(server);
    let main: Parameters<typeof admit>[0] | undefined;
    const log: string[] = [];

    server.admit = (caller) => {
      if (caller.role === 'person') {
        main = caller;
      }

      return admit(caller);
    };

    try {
      await withWindow(
        async (window) => {
          await ready(window);

          if (main === undefined) {
            throw new Error('main was not admitted');
          }

          await main.window.open(main.key, {
            agent: 'fake',
            name: 'helper',
            prompt: 'text',
          });
          await window.shows('helper');
          await window.press(DOWN);
          await window.press(DOWN);
          await window.press('\r');
          await window.shows('╭─ helper ─');
          // Opening draws the box before the initial turn hands it the keys.
          await window.shows('came in chunks.');
          await window.shows('? for shortcuts');
          await send(window, 'slow');
          await until(
            'child working',
            () => lastStatus(log)?.state === 'working',
          );
          await window.shows('esc to interrupt');
          expect(lastStatus(log)?.title).toBeUndefined();
          expect(wireTitles(log)).toStrictEqual([]);
          await window.press(ESC);
          await window.shows('Interrupted by user');
          await window.press(DOWN);
          await window.press(UP);
          await window.shows('❯ main ');
          await window.press('\r');
          await until(
            'main prompt taking keys',
            () =>
              !window.frame().includes('╭─ helper ─') &&
              window.frame().includes('? for shortcuts'),
          );
          await send(window, 'Main owns the title');
          await until(
            'main gets its title',
            () => lastStatus(log)?.title === 'Main owns the title',
          ).catch((error: Error) => {
            throw new Error(`${error.message}; the screen:\n${window.frame()}`);
          });
        },
        { log, server, columns: 80, rows: 24 },
      );
    } finally {
      await server.close();
    }
  });
});

describe('CHD-491 U2 tester: agent titles on the actual wire', () => {
  for (const columns of [80, 120]) {
    test(`own updates, byte-safe changes, null fallback, clear and resume at ${columns} columns`, async () => {
      const log: string[] = [];
      let publish: Parameters<Session['subscribe']>[0] | undefined;
      const title = (value?: string | null, parent?: string) => {
        assert(publish);
        publish(
          {
            sessionUpdate: 'session_info_update',
            ...(value === undefined ? {} : { title: value }),
          },
          parent,
        );
      };

      await withWindow(
        async (window) => {
          await ready(window);

          const oldPublish = publish;

          title('Agent title before prompt');
          await until(
            'agent title with no prompt',
            () => lastStatus(log)?.title === 'Agent title before prompt',
          );
          await send(window, 'Fallback main title');
          await window.shows('came in chunks.');
          title();
          title('');
          title(' \t\n ');
          title('Nested title', 'nested');
          expect(lastStatus(log)?.title).toBe('Agent title before prompt');

          for (const [value, expected] of [
            ['Line\nTitle\tValue', 'Line Title Value'],
            ['語'.repeat(64), '語'.repeat(64)],
            ['語'.repeat(65), '語'.repeat(64)],
            ['a'.repeat(181) + '👩‍💻', 'a'.repeat(181) + '👩‍💻'],
            ['a'.repeat(182) + '👩‍💻', 'a'.repeat(182)],
            ['é'.repeat(64), 'é'.repeat(64)],
          ] as const) {
            title(value);
            await until(
              'updated bounded title',
              () => lastStatus(log)?.title === expected,
            );

            // These are actual OSC fields, not only the decoded helper result.
            const fields = [
              ...log.join('').matchAll(
                // eslint-disable-next-line no-control-regex
                /\x1b\]7501;[^\x07\x1b]*?title=([^:\x07\x1b]*)/g,
              ),
            ].map((match) => match[1]!);

            expect(fields).toContain(Buffer.from(expected).toString('base64'));
            expect(
              fields.every(
                (field) =>
                  field.length <= 256 &&
                  Buffer.from(field, 'base64').length <= 192,
              ),
            ).toBe(true);
          }

          title(null);
          await until(
            'null returns first prompt',
            () => lastStatus(log)?.title === 'Fallback main title',
          );
          title('Persisted own title');
          await until(
            'last own title',
            () => lastStatus(log)?.title === 'Persisted own title',
          );
          await send(window, '/clear');
          await until(
            'clear drops both names',
            () => lastStatus(log)?.title === undefined,
          );
          assert(oldPublish);
          oldPublish({
            sessionUpdate: 'session_info_update',
            title: 'Retired title',
          });
          await ready(window);
          expect(lastStatus(log)?.title).toBeUndefined();
          await send(window, '/resume');
          await window.shows('Resume a session');
          await window.shows('Persisted own title');
          await window.press('\r');
          await until(
            'last own title restored on resume',
            () => lastStatus(log)?.title === 'Persisted own title',
          );
        },
        {
          log,
          columns,
          rows: columns === 80 ? 24 : 40,
          agentCommand: fakeAgentCommand(undefined, '--resume-only'),
          openWith: async (options) => {
            const session = await openSession(options);
            const subscribe = session.subscribe.bind(session);

            session.subscribe = (listener) => {
              publish = listener;

              return subscribe(listener);
            };

            return session;
          },
        },
      );
    });
  }

  test('a picked child agent title never replaces the main title or names an unnamed main', async () => {
    const server = serveChord();
    const admit = server.admit.bind(server);
    let main: Parameters<typeof admit>[0] | undefined;
    const log: string[] = [];

    server.admit = (caller) => {
      if (caller.role === 'person') {
        main = caller;
      }

      return admit(caller);
    };

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          assert(main);
          await main.window.open(main.key, {
            agent: 'fake',
            name: 'helper',
            prompt: 'retitled',
          });
          await window.press(DOWN);
          await window.press(DOWN);
          await window.press('\r');
          await window.shows('╭─ helper ─');
          await window.shows('Renamed.');
          expect(lastStatus(log)?.title).toBeUndefined();
          await window.press(DOWN);
          await window.press(UP);
          await window.press('\r');
          await send(window, 'titled');
          await until(
            'main agent title',
            () => lastStatus(log)?.title === 'Fix the tokenizer',
          );
          await window.press(DOWN);
          await window.press(DOWN);
          await window.press('\r');
          await window.shows('╭─ helper ─');
          await send(window, 'retitled');
          await until(
            'child ends its turn',
            () => lastStatus(log)?.state === 'done',
          );
          expect(lastStatus(log)?.title).toBe('Fix the tokenizer');
          expect(
            statusReports(log).some(
              (report) => report.title === 'Fix the parser',
            ),
          ).toBe(false);
        },
        { log, server, columns: 80, rows: 24 },
      );
    } finally {
      await server.close();
    }
  });
});

test("a resumed session whose past has its agent's exit never tells the terminal main exited, with no key pressed (CHD-510)", () => {
  const log: string[] = [];

  return withWindow(
    async (window) => {
      await ready(window);
      await send(window, 'text');
      await window.shows('This reply came in chunks.');
      await send(window, '/clear');
      await ready(window);
      await send(window, '/resume');
      await window.shows('Resume a session');

      const sent = statusReports(log).length;

      await window.press('\r');
      await window.shows('resumed · ');
      await ready(window);
      await until(
        'the resumed title to be reported',
        () => lastStatus(log)?.title === 'text',
      );
      expect(
        statusReports(log)
          .slice(sent)
          .filter((status) => status.state === 'error'),
      ).toStrictEqual([]);
      expect(lastStatus(log)?.state).not.toBe('error');
    },
    { log },
  );
});
