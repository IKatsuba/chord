/**
 * The mapper on a real `Conversation` and the fake agent, below `src/ui/`.
 */
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { SessionNotification } from '@agentclientprotocol/sdk/unstable';
import {
  answeredConfig,
  configChange,
  mapUpdate,
  upstreamSession,
} from '../../src/session/upstream.ts';
import { ended, onFake } from './conversation_fake.ts';

const ENTRY = fileURLToPath(new URL('../../src/acp_agent.ts', import.meta.url));

/** Every module `entry`'s static imports reach, as bare names or file paths. */
function reached(entry: string): Set<string> {
  const seen = new Set<string>();
  const walk = (file: string) => {
    if (seen.has(file)) {
      return;
    }

    seen.add(file);

    // What is not code imports nothing.
    if (!/\.tsx?$/.test(file)) {
      return;
    }

    const loader = file.endsWith('x') ? 'tsx' : 'ts';

    for (const { path, kind } of new Bun.Transpiler({ loader }).scanImports(
      readFileSync(file, 'utf8'),
    )) {
      if (kind !== 'import-statement') {
        continue;
      }

      if (path.startsWith('.')) {
        walk(resolve(dirname(file), path));
      } else {
        seen.add(path);
      }
    }
  };

  walk(entry);

  return seen;
}

describe('below the interface', () => {
  test("acp_agent.ts's static imports reach neither OpenTUI nor React", () => {
    const names = [...reached(ENTRY)];

    expect(names.length).toBeGreaterThan(5);
    expect(
      names.filter(
        (name) =>
          name.startsWith('@opentui/') ||
          name === 'react' ||
          name.startsWith('react/'),
      ),
    ).toEqual([]);
  });
});

describe('a conversation mapped', () => {
  test('a turn goes up under the id, its config once', () =>
    onFake([], async (conversation, events) => {
      conversation.send('tools');

      await ended(events, 1);

      const session = conversation.session;

      expect(session).toBeDefined();

      if (session === undefined) {
        return;
      }

      let upstream = answeredConfig(
        upstreamSession(session.id, 'up'),
        session.agentState(),
      ).session;

      expect(
        configChange(upstream, session.agentState()).notification,
      ).toBeUndefined();

      const sent: SessionNotification[] = [];

      for (const event of events) {
        if (event.type !== 'update') {
          continue;
        }

        const mapped = mapUpdate(upstream, {}, event.update, event.subagentId);

        upstream = mapped.session;

        if (mapped.notification !== undefined) {
          sent.push(mapped.notification);
        }
      }

      expect(sent.map(({ update }) => update.sessionUpdate)).toContain(
        'tool_call',
      );
      expect(new Set(sent.map(({ sessionId }) => sessionId))).toEqual(
        new Set(['up']),
      );
    }));
});
