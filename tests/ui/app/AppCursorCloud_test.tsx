/**
 * cursor-cloud as the window draws it with nothing of its own (CHD-622):
 * its first message before any prompt, its sign-in, and a request it
 * cannot answer, each through what chord already draws for any agent.
 */
import { expect, test } from 'bun:test';
import { openSession } from '../../../src/session/session.ts';
import { SignInBlock } from '../../../src/ui/app/SignIn.tsx';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { draw } from '../harness.tsx';
import { ready, send, until, withWindow } from './render.tsx';

const LINK =
  'https://cursor.com/agents/bc-5e1f0a7c-2d4b-4e8a-9c1f-7b2e6d3a9f10';
const FIRST = `Cursor cloud agent on github.com/acme/web, starting from branch login-page on origin. It runs in Cursor's cloud, not on this machine, pushes its work to a branch of its own, and keeps running if chord closes.  \n${LINK}`;
const COMMAND =
  'Run `npx -y @chorded/cursor-cloud-acp@0.1.0 login` in a terminal, or set CURSOR_API_KEY';

for (const columns of [80, 120]) {
  test(`a message before the first prompt draws as the agent's text and starts no turn at ${columns} columns`, async () => {
    await withWindow(
      async (window) => {
        await ready(window);
        await until('the first message', () =>
          window
            .frame()
            .replace(/\s+/g, ' ')
            .includes('keeps running if chord closes.'),
        );

        const frame = window.frame();

        expect(frame).toContain('⏺ Cursor cloud agent on github.com/acme/web');
        // The link on a row of its own, whole, as the design draws it.
        expect(frame.split('\n').map((row) => row.trim())).toContain(LINK);
        expect(frame).not.toContain('Working…');
      },
      {
        columns,
        rows: 30,
        agent: 'cursor-cloud',
        agentCommand: fakeAgentCommand(undefined, '--first-message', FIRST),
      },
    );
  });
}

test("a start refused signed out shows cursor-cloud's one way in, its versioned command, and chord's way on", async () => {
  let frame = '';

  await withWindow(
    async (window) => {
      await ready(window);
      await send(window, '/new cursor-cloud');
      await until('the sign-in block', () =>
        window.frame().replace(/\s+/g, ' ').includes('where it offers one.'),
      );

      frame = window.frame().replace(/\s+/g, ' ');
    },
    {
      columns: 120,
      rows: 30,
      runtimes: ['fake', 'cursor-cloud'],
      openWith: (options) =>
        openSession(
          options.agent === 'cursor-cloud'
            ? {
                ...options,
                agentCommand: fakeAgentCommand(
                  undefined,
                  '--auth-required',
                  'cloud',
                ),
              }
            : options,
        ),
    },
  );

  expect(frame).toContain(
    `⏺ cursor-cloud did not start: Not signed in to Cursor. ⎿ cursor-cloud offers this sign-in: Cursor login · ${COMMAND} chord does not sign agents in. Sign in with cursor-cloud's own CLI in a terminal, or set its API key where it offers one.`,
  );
});

test('the sign-in block names the version this chord pins, then the command for that version', async () => {
  const drawn = await draw(
    <box>
      <SignInBlock
        agent='cursor-cloud'
        signIn={{
          message: 'Not signed in to Cursor.',
          ways: [{ name: 'Cursor login', description: COMMAND }],
        }}
        pinned='@chorded/cursor-cloud-acp@0.1.0'
      />
    </box>,
    { columns: 120, rows: 12 },
  );

  try {
    expect(drawn.frame().replace(/\s+/g, ' ').trim()).toBe(
      `⎿ chord ran @chorded/cursor-cloud-acp@0.1.0, the version this chord pins. cursor-cloud offers this sign-in: Cursor login · ${COMMAND} chord does not sign agents in. Sign in with cursor-cloud's own CLI in a terminal, or set its API key where it offers one.`,
    );
  } finally {
    await drawn.unmount();
  }
});

test('a request Cursor waits on draws as a line, the turn running until Esc', async () => {
  await withWindow(
    async (window) => {
      await ready(window);
      await send(window, 'cloudrequest');
      await until('the request line', () =>
        window.frame().replace(/\s+/g, ' ').includes('Esc stops the run.'),
      );

      expect(window.frame().replace(/\s+/g, ' ')).toContain(
        "⏺ Cursor's agent is waiting for input or approval (request r-81c2). This adapter cannot answer it; Esc stops the run.",
      );
      expect(window.frame()).toContain('Working…');
      await window.press('\u001b');
      await until(
        'the turn stopped',
        () => !window.frame().includes('Working…'),
      );
    },
    { columns: 120, rows: 30, agent: 'cursor-cloud' },
  );
});
