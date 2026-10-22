import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { serveChord } from '../../../src/server/server.ts';
import { openSession } from '../../../src/session/session.ts';
import { unwrapMessage } from '../../../src/session/tasks.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  SHORT_MESSAGE,
  LONG_MESSAGE,
  PROSE_RU,
  PROSE_EN,
} from '../../fixtures/fake_agent/scenarios/agents.ts';
import { leader, send, until, withWindow } from '../app/render.tsx';

describe('CHD-501 tester: ungated agent pacing preserves delivery order', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const scenario of columns === 80
      ? ['agentsend', 'agentprose']
      : ['codexagentsend', 'codexagentprose']) {
      test(`${scenario} delivers both whole messages once and in order at ${columns} columns`, async () => {
        const server = serveChord();
        const received: string[] = [];
        let opened = 0;

        try {
          await withWindow(
            async (window) => {
              await send(window, scenario);
              await window.shows('Waiting on parser.');
              await until(
                'both messages received by the fake child',
                () => received.length === 2,
              );
              expect(received).toEqual(
                scenario.includes('prose')
                  ? [PROSE_RU, PROSE_EN]
                  : [SHORT_MESSAGE, LONG_MESSAGE],
              );
            },
            {
              server,
              runtimes: ['fake'],
              columns,
              rows,
              agentCommand: fakeAgentCommand(undefined, '--echo-messages'),
              openWith: async (options) => {
                const session = await openSession(options);
                const child = opened++ > 0;

                if (child) {
                  session.subscribe((update) => {
                    if (
                      update.sessionUpdate !== 'agent_message_chunk' ||
                      update.content.type !== 'text'
                    ) {
                      return;
                    }

                    const match = /^Received (".*")$/s.exec(
                      update.content.text,
                    );

                    if (match) {
                      const message = unwrapMessage(
                        JSON.parse(match[1]!) as string,
                      );

                      assert(message);
                      received.push(message.text);
                    }
                  });
                }

                return session;
              },
            },
          );
        } finally {
          await server.close();
        }
      });
    }

    for (const steering of [columns === 80 ? 'claude' : 'codex']) {
      test(`ungated docs message waits for its permission answer with ${steering} steering at ${columns} columns`, async () => {
        const server = serveChord();
        const trace: string[] = [];
        let opened = 0;

        try {
          await withWindow(
            async (window) => {
              await send(window, 'agentsheld');
              await window.shows('Waiting on docs.');
              await until('docs asked for permission', () =>
                trace.includes('permission'),
              );
              expect(trace).toEqual(['permission']);
              await leader(window, 'a');
              await window.shows('docs asks');
              await window.press('1');
              await until(
                'docs received the parent message after answering',
                () => trace.includes('received'),
              );
              expect(trace).toEqual(['permission', 'received']);
            },
            {
              server,
              runtimes: ['fake'],
              columns,
              rows,
              agentCommand: fakeAgentCommand(
                undefined,
                '--echo-messages',
                '--steering',
                steering,
              ),
              openWith: async (options) => {
                const session = await openSession(options);
                const child = opened++ > 0;

                if (child) {
                  session.permissions.subscribe(() => trace.push('permission'));
                  session.subscribe((update) => {
                    if (
                      update.sessionUpdate === 'agent_message_chunk' &&
                      update.content.type === 'text' &&
                      /^(Received |Read the message from main)/.test(
                        update.content.text,
                      )
                    ) {
                      trace.push('received');
                    }
                  });
                }

                return session;
              },
            },
          );
        } finally {
          await server.close();
        }
      });
    }
  }
});
