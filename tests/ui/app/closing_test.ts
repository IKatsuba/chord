import { expect, test } from 'bun:test';
import { resumeMessage } from '../../../src/session/sessions.ts';
import {
  agentCloseArmedLine,
  ctrlCArmedLine,
  teamCloseArmedLine,
} from '../../../src/ui/app/closing.ts';
import {
  initialAppState,
  reduceWindowed,
  windowed,
} from '../../../src/ui/app/state.ts';

test('ctrl+c asks once more before quitting, counting nothing', () => {
  expect(ctrlCArmedLine()).toStrictEqual('Press ctrl+c again to quit');
});

test("the resume command of the window's session, or none, its --agent-command only for the agent it overrides", () => {
  expect(resumeMessage(undefined)).toStrictEqual(undefined);
  expect(resumeMessage({ agent: 'fake', sessionId: 'a' })).toStrictEqual(
    'Resume this session with:\nchord fake --resume a',
  );
  expect(
    resumeMessage(
      { agent: 'fake', sessionId: 'a' },
      { agent: 'fake', agentCommand: 'run fake' },
    ),
  ).toStrictEqual(
    "Resume this session with:\nchord fake --agent-command 'run fake' --resume a",
  );
  expect(
    resumeMessage(
      { agent: 'claude', sessionId: 'b' },
      { agent: 'fake', agentCommand: 'run fake' },
    ),
  ).toStrictEqual('Resume this session with:\nchord claude --resume b');
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
