import { expect, test } from 'bun:test';
import { resumeMessage } from '../../../src/session/sessions.ts';
import {
  emptyTranscript,
  type TurnState,
} from '../../../src/session/transcript/types.ts';
import {
  agentCloseArmedLine,
  busyOf,
  ctrlCArmedLine,
  teamCloseArmedLine,
} from '../../../src/ui/app/closing.ts';
import {
  initialAppState,
  reduceWindowed,
  windowed,
} from '../../../src/ui/app/state.ts';

const working: TurnState = { status: 'working', turnId: 't', since: 0 };

test('a session is busy while asked, queued or working, the person first', () => {
  const session = (turn: TurnState, queued = 0, asking = false) => ({
    transcript: {
      ...emptyTranscript,
      turn,
      ...(asking
        ? {
            asking: [{} as (typeof emptyTranscript.asking)[number]],
          }
        : {}),
    },
    queue: Array.from({ length: queued }, (_, i) => ({
      turnId: `q${i}`,
      text: `${i}`,
    })),
  });

  expect(busyOf(session({ status: 'idle' }))).toStrictEqual(undefined);
  expect(
    busyOf({
      transcript: {
        ...emptyTranscript,
        entries: [
          {
            kind: 'shell',
            turnId: 's',
            run: {
              command: 'sleep 60',
              stdout: '',
              stderr: '',
              running: true,
            },
          },
        ],
      },
      queue: [],
    }),
  ).toStrictEqual({ kind: 'working' });
  expect(busyOf(session(working))).toStrictEqual({ kind: 'working' });
  expect(busyOf(session(working, 2))).toStrictEqual({
    kind: 'queued',
    count: 2,
  });
  expect(busyOf(session(working, 2, true))).toStrictEqual({ kind: 'input' });
  expect(
    busyOf(
      session(
        { ...working, status: 'awaiting_permission', permissions: [] },
        2,
      ),
    ),
  ).toStrictEqual({ kind: 'permission' });
});

test('ctrl+c asks once more before quitting, counting nothing', () => {
  expect(ctrlCArmedLine()).toStrictEqual('Press ctrl+c again to quit');
});

test('one resume command for each session, in tab order', () => {
  expect(resumeMessage([])).toStrictEqual(undefined);
  expect(
    resumeMessage([{ agent: 'fake', sessionId: 'a', cwd: '/work' }]),
  ).toStrictEqual('Resume this session with:\nchord fake --resume a');
  expect(
    resumeMessage(
      [
        { agent: 'fake', sessionId: 'a', cwd: '/work' },
        { agent: 'claude', sessionId: 'b', cwd: '/work' },
      ],
      { agent: 'fake', agentCommand: 'run fake' },
    ),
  ).toStrictEqual(
    'Resume these sessions with:\n' +
      "chord fake --agent-command 'run fake' --resume a\n" +
      'chord claude --resume b',
  );
});

test('an armed quit takes the place of a note of the sessions for good', () => {
  const noted = reduceWindowed(windowed(initialAppState, 1), {
    type: 'sessions_noted',
    message: 'Nothing waits on you',
  });
  const expired = reduceWindowed(
    reduceWindowed(noted, { type: 'quit_armed' }),
    { type: 'quit_disarmed' },
  );

  expect(expired.window.sessionsNote).toStrictEqual(undefined);
});

test('the armed close line of a child or a team says what closing would stop', () => {
  expect(agentCloseArmedLine('parser', { kind: 'working' }, 'x')).toStrictEqual(
    'parser is working · x again to stop it and close',
  );
  expect(
    agentCloseArmedLine('docs', { kind: 'permission' }, 'x'),
  ).toStrictEqual(
    'docs waits for your permission · x again to stop it and close',
  );
  expect(
    agentCloseArmedLine('parser', { kind: 'queued', count: 2 }, 'x'),
  ).toStrictEqual('parser has 2 prompts queued · x again to stop it and close');
  expect(teamCloseArmedLine('bugfix', 3, 'x')).toStrictEqual(
    'bugfix and its 3 members are working · x again to stop them and close',
  );
  expect(teamCloseArmedLine('bugfix', 1, 'x')).toStrictEqual(
    'bugfix and its member are working · x again to stop them and close',
  );
});
