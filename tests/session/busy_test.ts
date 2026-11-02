import { expect, test } from 'bun:test';
import { busyOf } from '../../src/session/busy.ts';
import {
  emptyTranscript,
  type TurnState,
} from '../../src/session/transcript/types.ts';

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
