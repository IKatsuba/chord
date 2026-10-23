/**
 * A start that fails as the window draws it: the step, the agent's own
 * words, the ways in it offers and chord's way on (CHD-435, CHD-454).
 */
import { describe, expect, test } from 'bun:test';
import { SignInBlock } from '../../../src/ui/app/SignIn.tsx';
import { StartFailureBlock } from '../../../src/ui/app/StartFailure.tsx';
import { TRACEBACK_ERROR } from '../../fixtures/fake_agent/options.ts';
import { draw } from '../harness.tsx';
import { failedFrame, failedFrameShowing } from './start_failure.tsx';

for (const columns of [80, 120]) {
  test(`a start the agent refuses for want of a login hangs its ways in and chord's way on under the failure at ${columns} columns (CHD-435)`, async () => {
    const frame = await failedFrame(columns, '--auth-required', 'methods');
    const rows = frame.split('\n');

    expect(frame.replace(/\s+/g, ' ')).toContain(
      "⏺ codex did not start: Authentication required: run `fake login` from your terminal, or set FAKE_API_KEY ⎿ codex offers these sign-ins: Log in with the fake · Run `fake login` in the terminal Log in with SSO chord does not sign agents in. Sign in with codex's own CLI in a terminal, or set its API key where it offers one.",
    );
    // Each way in sits two in under the block's text.
    expect(
      rows.find((row) => row.includes('Log in with SSO'))?.indexOf('Log'),
    ).toStrictEqual(
      (rows.find((row) => row.includes('codex offers'))?.indexOf('codex') ??
        0) + 2,
    );
  });
}

test("a start that needs a login, its agent offering no ways in, says chord's way on alone (CHD-435)", async () => {
  const read = (await failedFrame(120, '--auth-required', 'bare')).replace(
    /\s+/g,
    ' ',
  );

  expect(read).toContain(
    "⏺ codex did not start: Authentication required ⎿ chord does not sign agents in. Sign in with codex's own CLI in a terminal, or set its API key where it offers one.",
  );
  expect(read).not.toContain('offers this');
});

for (const columns of [80, 120]) {
  test(`an agent that exits before initialize says so with its code and hangs the end of its stderr under it at ${columns} columns (CHD-454)`, async () => {
    const frame = await failedFrameShowing(
      columns,
      TRACEBACK_ERROR,
      '--start-fails',
      'traceback',
    );
    const read = frame.replace(/\s+/g, ' ');

    expect(read).toContain(
      '⏺ codex did not start: it exited with code 1 before answering initialize. ⎿ The end of its stderr: … +116 lines from .module_58 import run',
    );
    expect(read).toContain(`from .module_60 import run ${TRACEBACK_ERROR}`);

    // The tail sits two in under the block's text, and keeps its own indent.
    const rows = frame.split('\n');
    const heading = rows.find((row) => row.includes('The end of its stderr:'))!;
    const frame58 = rows.find((row) =>
      row.includes('from .module_58 import run'),
    )!;

    expect(frame58.indexOf('from')).toBe(heading.indexOf('The') + 2 + 4);
  });
}

test('an agent that serves no ACP sessions, or one that refuses its session another way, says which (CHD-454)', async () => {
  expect(
    (
      await failedFrameShowing(
        120,
        'not at this version.',
        '--start-fails',
        'notacp',
      )
    ).replace(/\s+/g, ' '),
  ).toContain(
    '⏺ codex did not start: it does not serve ACP sessions: not an ACP agent, or not at this version.',
  );

  // Its message may break after a `.` (Q157): read with no whitespace.
  const alias = (
    await failedFrameShowing(120, 'entry)', '--start-fails', 'alias')
  ).replace(/\s+/g, '');

  expect(alias).toContain(
    '⏺codexdidnotstart:itrefusedsession/new:session/newrequires`agentAlias`(aliasofaconfigured[agents.<alias>]entry)',
  );
  // Not zeroclaw: no way on chord knows.
  expect(alias).not.toContain('Set a default agent');
  expect(alias).not.toContain('⎿');
});

describe('the block under a start failure, by what chord knows (CHD-454)', () => {
  const block = async (node: React.ReactNode) => {
    const drawn = await draw(<box>{node}</box>, { columns: 80, rows: 12 });

    try {
      return drawn.frame().replace(/\s+/g, ' ').trim();
    } finally {
      await drawn.unmount();
    }
  };

  test("a registry agent's names the pin chord ran, a sign-in's first", async () => {
    expect(
      await block(
        <StartFailureBlock
          agent='agoragentic-acp'
          failure={{
            step: 'session/new',
            code: -32601,
            pinned: 'agoragentic-mcp@1.3.0',
          }}
        />,
      ),
    ).toBe(
      '⎿ chord ran agoragentic-mcp@1.3.0, the version the ACP Registry names.',
    );
    expect(
      await block(
        <SignInBlock
          agent='qoder'
          signIn={{ message: 'Authentication required', ways: [] }}
          pinned='@qoder-ai/qodercli@0.2.14'
        />,
      ),
    ).toBe(
      "⎿ chord ran @qoder-ai/qodercli@0.2.14, the version the ACP Registry names. chord does not sign agents in. Sign in with qoder's own CLI in a terminal, or set its API key where it offers one.",
    );
  });

  test("zeroclaw's -32602 says how to set a default agent, and nothing else of it does", async () => {
    const way =
      'Set a default agent: [acp] default_agent = "<alias>" in ZeroClaw\'s config, or start it with zeroclaw acp --agent <alias>.';

    expect(
      await block(
        <StartFailureBlock
          agent='zeroclaw'
          failure={{ step: 'session/new', code: -32602 }}
        />,
      ),
    ).toBe(`⎿ ${way}`);
    expect(
      await block(
        <StartFailureBlock
          agent='zeroclaw'
          failure={{ step: 'session/new', code: -32601 }}
        />,
      ),
    ).toBe('');
  });
});
