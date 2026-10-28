/** Real fake-ACP caller records with admitted attempts and no prompt/tool event. */
import assert from 'node:assert/strict';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { serveChord } from '../../src/server/server.ts';
import { openSession } from '../../src/session/session.ts';
import { withWindow, ready } from '../ui/app/render.tsx';
import { fakeAgentCommand } from './fake.ts';

export async function selectedReceiptFixture(
  directory: string,
  stateDir: string,
): Promise<void> {
  const server = serveChord();
  const admit = server.admit.bind(server);
  let token: string | undefined;
  let opens = 0;

  server.admit = (caller) => {
    const admitted = admit(caller);

    if (caller.role === 'person') {
      token = admitted.token;
    }

    return admitted;
  };

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        assert(token !== undefined);

        const client = new Client({
          name: 'chord-receipt-fixture',
          version: '0.0.0',
        });
        const transport = new StreamableHTTPClientTransport(
          new URL(server.url),
          { requestInit: { headers: { Authorization: `Bearer ${token}` } } },
        );

        await client.connect(transport as Parameters<Client['connect']>[0]);

        try {
          for (let index = 0; index < 2; index++) {
            const result = await client.callTool({
              name: 'run_team',
              arguments: {
                team: 'fixture',
                job: `Actual admitted attempt ${index + 1}; its first job is never delivered.`,
                selection: {
                  reason:
                    'Preserve every role instruction and exact permission requirement. Capacity is unknown; external work may be missing. '
                      .repeat(3)
                      .trim(),
                },
              },
            });

            assert(
              result.isError === true && result.structuredContent !== undefined,
            );
          }
        } finally {
          await client.close();
        }
      },
      {
        server,
        stateDir,
        runtimes: ['fake'],
        agentCommand: fakeAgentCommand(),
        startupOf: () => ({ agentCommand: fakeAgentCommand() }),
        teams: {
          fixture: `---\ndescription: Receipt-only admitted attempts\nlead:\n  agent: fake\nmembers:\n  - name: reviewer\n    role: Review\n    agent: fake\n    instructions: Keep the review permissions.\n---\nPreserve every instruction.\n`,
        },
        openWith: (args) =>
          ++opens === 1
            ? openSession({ ...args, cwd: directory })
            : Promise.reject(new Error('fake initialization refusal')),
      },
    );
  } finally {
    await server.close();
  }
}
