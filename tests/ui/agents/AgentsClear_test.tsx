/**
 * clear_agent: a parent clears a child it opened, which keeps its id and
 * name in a fresh session that knows nothing of earlier turns (CHD-476).
 */
import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { serveChord } from '../../../src/server/server.ts';
import type { Caller } from '../../../src/server/tools.ts';
import {
  DOWN,
  ready,
  send,
  until,
  UP,
  type Window,
  withWindow,
} from '../app/render.tsx';
import { count, withAgents } from './agents_window.tsx';
import { withTeams } from './teams_window.tsx';
import { PIXEL_BYTES, PIXEL_PNG } from '../../fixtures/images.ts';
import { RECEIVED } from '../prompt/prompt_window.tsx';

/** Picks `name` in the list under the prompt and shows it. */
async function pick(window: Window, name: string) {
  await window.press(DOWN);
  await until(`${name} picked in the list`, async () => {
    if (new RegExp(`❯ (└─ )?${name} `).test(window.frame())) {
      return true;
    }

    await window.press(DOWN);

    return false;
  });

  await window.press('\r');
  await window.shows(`╭─ ${name} `);
}

test('main clears its working child: the queued message is not delivered and said so, the next is its first, an unknown name is refused, and main is told nothing more', () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agentcost');
    await window.shows('Open(parser)');
    await until('parser at work', () =>
      /^ {4}parser .*✻/m.test(window.frame()),
    );
    await send(window, 'agentclear');
    await window.shows('parser was cleared.');

    expect(window.frame()).toContain('Clear(parser)');
    expect(window.frame()).toMatch(/Fresh session · id \w+/);
    expect(window.frame()).toContain(
      '1 queued message from main was not delivered.',
    );
    expect(window.frame()).toContain('Clear(nobody)');
    expect(window.frame()).not.toContain('The person cleared');
    expect(count(window, '    parser ')).toBe(1);

    // Its view has the message sent after the clear and its answer, and
    // nothing of the work before it.
    await pick(window, 'parser');
    await window.shows('This reply came in chunks.');

    expect(window.frame()).not.toContain('Queued before the clear.');
    await window.press(DOWN);
    await window.press(UP);
  }));

test("a lead clears its member: the member's next message carries the team's part again, as a first one does", () =>
  withTeams(async (window) => {
    await ready(window);
    await send(window, '/team run bugfix leadclear');
    await window.shows('└─ tester ');
    await pick(window, 'bugfix');
    await window.shows('tester was cleared.');

    expect(window.frame()).toContain('Clear(tester)');
    await pick(window, 'tester');
    await window.shows('The team part from bugfix reached this session.');
  }));

test('the old session of a cleared child reaches no one once it is let go, even as it still runs', () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agentlate');
    await window.shows('Open(parser)');
    await until('parser at work', () =>
      /^ {4}parser .*✻/m.test(window.frame()),
    );
    await send(window, 'agentclearonly');
    await window.shows('parser was cleared.');
    // Another round trip of main's, by which the old turn has tried.
    await send(window, 'text');
    await window.shows('This reply came in chunks.');

    expect(window.frame()).not.toContain('Late from the old session.');
  }));

test('two clears at once: one is refused, and a message sent meanwhile goes once to the fresh session, as its first', () =>
  withTeams(async (window) => {
    await ready(window);
    await send(window, '/team run bugfix leadclearrace');
    await window.shows('└─ tester ');
    await pick(window, 'bugfix');
    await window.shows('tester was cleared once.');

    expect(window.frame()).toContain(
      'Could not clear tester: it is being cleared already',
    );
    expect(window.frame()).toMatch(/Fresh session · id \w+/);
    await pick(window, 'tester');
    await window.shows('The team part from bugfix reached this session.');

    expect(
      count(window, 'The team part from bugfix reached this session.'),
    ).toBe(1);
  }));

test("the person's first message to a member its lead cleared carries the team's part, as a first one does", () =>
  withTeams(async (window) => {
    await ready(window);
    await send(window, '/team run bugfix leadclearonly');
    await window.shows('└─ tester ');
    await pick(window, 'bugfix');
    await window.shows('tester was cleared.');
    await pick(window, 'tester');
    await send(window, 'teampartof');
    await window.shows('The team part from the person reached this session.');
  }));

/** A window on the fake, and main's caller as chord's server admitted it. */
async function withMain(body: (window: Window, main: Caller) => Promise<void>) {
  const server = serveChord();
  const admit = server.admit.bind(server);
  let main: Caller | undefined;

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
        assert(main?.launch);
        await body(window, main);
      },
      { server, runtimes: ['fake'], columns: 120, rows: 40 },
    );
  } finally {
    await server.close();
  }
}

/** `main` as it would speak once its session has been let go meanwhile. */
function lettingGo(main: Caller): { caller: Caller; letGo: () => void } {
  let live = true;

  assert(main.launch);

  const { signal } = main.launch;

  return {
    caller: { ...main, launch: { valid: () => live, signal } },
    letGo: () => {
      live = false;
    },
  };
}

test('a spawn_task or open_agent whose session is let go while it waits starts nothing', () =>
  withMain(async (window, main) => {
    const spawning = lettingGo(main);
    const spawned = main.window.spawn(spawning.caller, {
      agent: 'fake',
      prompt: 'text',
    });

    spawning.letGo();

    expect(await spawned).toStrictEqual({
      error: 'Your session was cleared or closed; nothing more goes from it',
    });

    const opening = lettingGo(main);
    const opened = main.window.open(
      main.key,
      { agent: 'fake', prompt: 'text', name: 'late' },
      opening.caller,
    );

    opening.letGo();

    expect(await opened).toStrictEqual({
      error: 'Your session was cleared or closed; nothing more goes from it',
    });
    expect(window.frame()).not.toContain('late');
  }));

test('a child closed while it restarts says the message sent meanwhile was not delivered', () =>
  withMain(async (window, main) => {
    const opened = await main.window.open(main.key, {
      agent: 'fake',
      prompt: 'text',
      name: 'parser',
    });

    expect(opened).toHaveProperty('id');
    // Up and done with its first prompt, so nothing of that is waiting.
    await until('parser replied', () =>
      /^ {4}parser .*✓ new reply/m.test(window.frame()),
    );

    const clearing = main.window.clear(main, 'parser');
    const told = main.window.tell(
      main,
      'parser',
      'During the restart.',
      () => {},
    );

    main.window.close(main, 'parser');

    expect(told).toMatchObject({ delivered: 'queued' });
    expect(await clearing).toStrictEqual({
      error:
        'Could not clear parser: it was closed. 1 queued message from main was not delivered.',
    });
  }));

test("the person's /clear on a working child: its turn goes, their queued prompt comes back into the box, and its view starts over", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agentcost');
    await window.shows('Open(parser)');
    await until('parser at work', () =>
      /^ {4}parser .*✻/m.test(window.frame()),
    );
    await pick(window, 'parser');
    await window.shows('Working until stopped.');
    await send(window, 'Later.');
    await window.shows('› Later.');
    await send(window, '/clear');
    await until(
      "parser's view empty",
      () => !window.frame().includes('Working until stopped.'),
    );
    await until('the queued prompt back in the box', () =>
      window.frame().includes('│ › Later.'),
    );

    expect(window.frame()).toContain('╭─ parser ');
    expect(window.frame()).toMatch(/^ {4}parser .*◦ idle/m);
  }));

test("main's clear_agent puts the person's queued prompt for the child back into the child's box, whatever is in front", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agentcost');
    await window.shows('Open(parser)');
    await until('parser at work', () =>
      /^ {4}parser .*✻/m.test(window.frame()),
    );
    await pick(window, 'parser');
    await window.shows('Working until stopped.');
    await send(window, 'Later.');
    await window.shows('› Later.');
    await window.press(DOWN);
    await until('main picked in the list', async () => {
      if (window.frame().includes('  ❯ main ')) {
        return true;
      }

      await window.press(UP);

      return false;
    });

    await window.press('\r');
    await until('main in view', () => !/╭─ \S/.test(window.frame()));
    await send(window, 'agentclearonly');
    await window.shows('parser was cleared.');
    await pick(window, 'parser');
    await until('the queued prompt back in its box', () =>
      window.frame().includes('│ › Later.'),
    );
  }));

for (const columns of [80, 120]) {
  test(`a queued prompt's image comes back with it after /clear and goes when it is sent again, at ${columns} columns`, async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'agentcost');
          await window.shows('Open(parser)');
          await until('parser at work', () =>
            /^ {4}parser .*✻/m.test(window.frame()),
          );
          await pick(window, 'parser');
          await window.shows('Working until stopped.');

          // Typed key by key: pasted, the path would be read at once.
          for (const key of 'see /shots/a.png') {
            await window.press(key);
          }

          await window.press('\r');
          await window.shows('› see [Image #1]');
          await send(window, '/clear');
          await until('the queued prompt back in its box', () =>
            window.frame().includes('│ › see [Image #1]'),
          );
          // Enter sends once the fresh session is up; before, it waits.
          await until('sent to the fresh session', async () => {
            if (!window.frame().includes('│ › see [Image #1]')) {
              return true;
            }

            await window.press('\r');

            return false;
          });

          await window.shows(RECEIVED);
        },
        {
          server,
          runtimes: ['fake'],
          columns,
          rows: columns === 80 ? 24 : 40,
          readImage: () =>
            Promise.resolve({
              mediaType: 'image/png',
              data: PIXEL_PNG,
              bytes: PIXEL_BYTES.length,
            }),
        },
      );
    } finally {
      await server.close();
    }
  });
}
