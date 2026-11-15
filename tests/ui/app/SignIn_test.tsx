import { describe, expect, test } from 'bun:test';
import stripAnsi from 'strip-ansi';
import type { SignIn } from '../../../src/session/sign_in.ts';
import { Colours } from '../../../src/ui/app/context.ts';
import { paletteOf } from '../../../src/ui/theme/theme.ts';
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

describe('CHD-629 tester: sign-in account layout boundaries', () => {
  for (const [columns, theme] of [
    [80, 'dark'],
    [120, 'dark'],
    [80, 'light'],
  ] as const) {
    test(`long active accounts wrap without loss at ${columns} columns in ${theme}`, async () => {
      const signIn: SignIn = {
        message: 'Authentication required',
        ways: [
          {
            name: 'Fixture login',
            description: 'Run fixture login in another terminal',
          },
        ],
        account: {
          phase: 'heard',
          status: {
            state: 'authenticated',
            accounts: [
              {
                label: 'Primary plan',
                description: 'A long account description for the sign-in block',
                name: 'Fixture Person',
                email: 'long.account.for.signin@engineering.example.test',
                organization: 'Organisation of Long Account Names',
                active: true,
              },
              {
                label: 'Backup plan',
                email: 'backup@example.test',
                active: true,
              },
              { label: 'Inactive identity', active: false },
            ],
          },
        },
      };
      const drawn = await draw(
        <Colours.Provider value={paletteOf(theme, true)}>
          <TranscriptEntry
            entry={{
              kind: 'error',
              turnId: 't',
              message: signIn.message,
              code: '-32000',
              signIn,
            }}
            turn={{ status: 'idle' }}
            agent='fake'
            expanded={false}
            width={columns - 4}
          />
        </Colours.Provider>,
        { columns, rows: columns === 80 ? 24 : 40 },
      );

      try {
        const frame = stripAnsi(drawn.frame());
        const compact = frame.replace(/\s/g, '');

        expect(compact).toContain(
          'fake reports Primary plan · A long account description for the sign-in block · Fixture Person · long.account.for.signin@engineering.example.test · Organisation of Long Account Names, Backup plan · backup@example.test.'.replace(
            /\s/g,
            '',
          ),
        );
        expect(frame).not.toContain('Inactive identity');
        expect(frame).toContain('Fixture login');
        expect(compact).toContain(
          'chord does not sign agents in.'.replace(/\s/g, ''),
        );
        expect(frame.split('\n').every((row) => row.length <= columns)).toBe(
          true,
        );
      } finally {
        await drawn.unmount();
      }
    });
  }
});
