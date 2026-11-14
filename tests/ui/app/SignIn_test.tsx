import { expect, test } from 'bun:test';
import stripAnsi from 'strip-ansi';
import type { Entry } from '../../../src/session/transcript/types.ts';
import { SignInBlock } from '../../../src/ui/app/SignIn.tsx';
import { TranscriptEntry } from '../../../src/ui/transcript/Transcript.tsx';
import { draw } from '../harness.tsx';

/** The rows `node` draws in an 80-column window, trailing blanks gone. */
async function rowsOf(node: React.ReactNode): Promise<string[]> {
  const drawn = await draw(node, { columns: 80, rows: 12 });
  const frame = drawn.frame();

  await drawn.unmount();

  return stripAnsi(frame)
    .split('\n')
    .map((row) => row.trimEnd())
    .filter((row) => row !== '');
}

const SIGNED_OUT = {
  message: 'Authentication required',
  ways: [],
  account: { phase: 'heard', status: { state: 'unauthenticated' } },
} as const;

test("the block's first line is what the agent says of its account, then chord's way on (CHD-629)", async () => {
  const rows = await rowsOf(<SignInBlock agent='claude' signIn={SIGNED_OUT} />);

  expect(rows[0]).toBe('  ⎿  claude reports that no account is signed in.');
  expect(rows[1]?.trim().startsWith('chord does not sign agents in.')).toBe(
    true,
  );
});

test('without an account heard, the block is as it was', async () => {
  const rows = await rowsOf(
    <SignInBlock
      agent='claude'
      signIn={{ message: 'Authentication required', ways: [] }}
    />,
  );

  expect(rows[0]?.startsWith('  ⎿  chord does not sign agents in.')).toBe(true);
});

test("a prompt refused for a login is the block in the turn error's place, headed by the agent's words", async () => {
  const entry: Entry = {
    kind: 'error',
    turnId: 't',
    message: 'Authentication required',
    code: '-32000',
    signIn: SIGNED_OUT,
  };
  const rows = await rowsOf(
    <TranscriptEntry
      entry={entry}
      turn={{ status: 'idle' }}
      agent='claude'
      expanded={false}
      width={76}
    />,
  );

  expect(rows.slice(0, 2)).toStrictEqual([
    '⏺ claude needs a sign-in: Authentication required',
    '  ⎿  claude reports that no account is signed in.',
  ]);
});
