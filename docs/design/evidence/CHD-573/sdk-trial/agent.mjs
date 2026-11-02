// A minimal ACP agent on the SDK's agent({ name }), for the CHD-573 library
// gate. Not chord: no model, no agent below it. `.mjs` because tracked TS has
// to be type-checked by `bun check` (scripts/dev/covered.ts).
//
//   agent.mjs v1            AgentApp from the unstable v1 entrypoint
//   agent.mjs router        AgentProtocolRouter with v1 and v2
//   agent.mjs router-v1     the router with v1 alone
//   agent.mjs router-v2     the router with v2 alone
//
// TRIAL_EXIT=natural leaves the process to end by itself once the connection
// closes; otherwise it calls process.exit. Events go to stderr as JSON lines:
// stdout carries ACP only.
import process from 'node:process';
import { Readable, Writable } from 'node:stream';
import * as v1 from '@agentclientprotocol/sdk/unstable';
import * as v2 from '@agentclientprotocol/sdk/experimental/v2/unstable';

const mode = process.argv[2] ?? 'v1';
const explicitExit = process.env.TRIAL_EXIT !== 'natural';
const started = performance.now();
const say = (ev, more = {}) =>
  process.stderr.write(
    `${JSON.stringify({ ms: Math.round(performance.now() - started), ev, ...more })}\n`,
  );

/** The turns running now, so SIGTERM can answer them before it closes. */
const turns = new Map();

function wait(signal, ms) {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);

    signal.addEventListener('abort', () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

function newTurn(sessionId, signal) {
  const cancel = new AbortController();
  const turn = { cancel, stop: Promise.withResolvers() };

  signal.addEventListener('abort', () => {
    say('prompt.signal.abort', {
      sessionId,
      reason: String(signal.reason?.message ?? signal.reason),
    });
    cancel.abort(signal.reason);
  });
  turns.set(sessionId, turn);

  return turn;
}

function textOf(prompt) {
  return prompt.map((block) => block.text ?? '').join('');
}

/** Sends `total` bytes of chunks, awaited or not, and says how it went. */
async function flood(client, sessionId, total, awaited, chunk) {
  const piece = 'x'.repeat(64 * 1024);
  let sent = 0;
  let lastSaid = 0;
  const firstAt = performance.now();
  const pending = [];

  while (sent < total) {
    const notified = client
      .notify('session/update', { sessionId, update: chunk(piece) })
      .catch((error) => say('flood.notify.failed', { message: error.message }));

    if (awaited) {
      await notified;
    } else {
      pending.push(notified);
    }

    sent += piece.length;

    if (sent - lastSaid >= 8 * 1024 * 1024) {
      lastSaid = sent;
      say('flood.progress', {
        sent,
        rssMiB: Math.round(process.memoryUsage().rss / 1048576),
        ms: Math.round(performance.now() - firstAt),
      });
    }
  }

  say('flood.queued', {
    sent,
    rssMiB: Math.round(process.memoryUsage().rss / 1048576),
  });
  await Promise.all(pending);
  say('flood.done', {
    sent,
    ms: Math.round(performance.now() - firstAt),
    rssMiB: Math.round(process.memoryUsage().rss / 1048576),
  });

  if (process.env.TRIAL_EXIT_AFTER_FLOOD === '1') {
    process.exit(0);
  }
}

function v1App() {
  let sessions = 0;
  const update = (client, sessionId, text) =>
    client.notify('session/update', {
      sessionId,
      update: {
        sessionUpdate: 'agent_message_chunk',
        content: { type: 'text', text },
      },
    });

  return v1
    .agent({ name: 'chd-573-trial-v1' })
    .onRequest('initialize', ({ params }) => {
      say('initialize', {
        api: 'v1',
        asked: params.protocolVersion,
        clientCapabilities: params.clientCapabilities,
      });

      return {
        protocolVersion: 1,
        agentCapabilities: { _meta: { 'chord/trial': { version: 1 } } },
        agentInfo: { name: 'trial', version: '0.0.0' },
        _meta: { 'chord/trial': { version: 1 } },
      };
    })
    .onRequest('session/new', ({ params }) => {
      say('session/new', { meta: params._meta, cwd: typeof params.cwd });

      return { sessionId: `s${++sessions}` };
    })
    .onNotification('session/cancel', ({ params }) => {
      say('session/cancel', { sessionId: params.sessionId });
      turns.get(params.sessionId)?.cancel.abort('session/cancel');
    })
    .onRequest('session/prompt', async ({ params, client, signal }) => {
      const { sessionId } = params;
      const [what, arg] = textOf(params.prompt).split(':');
      const turn = newTurn(sessionId, signal);

      say('session/prompt', {
        what,
        meta: params._meta,
        unknownKept: 'unknownField' in params,
      });

      try {
        if (what === 'stream') {
          for (let i = 0; i < Number(arg); i++) {
            await update(client, sessionId, `chunk ${i}\n`);
          }
        }

        if (what === 'unknown-update') {
          await client
            .notify('session/update', {
              sessionId,
              update: { sessionUpdate: '_chord/custom', anything: 1 },
              _meta: { 'chord/filled': ['x'] },
            })
            .then(
              () => say('unknown-update.sent'),
              (error) => say('unknown-update.refused', { message: error.message }),
            );
        }

        if (what === 'permission') {
          const answer = await client
            .request(
              'session/request_permission',
              {
                sessionId,
                toolCall: { toolCallId: 't1', title: 'Trial tool' },
                options: [
                  { optionId: 'yes', name: 'Allow', kind: 'allow_once' },
                  { optionId: 'no', name: 'Reject', kind: 'reject_once' },
                ],
              },
              { cancellationSignal: turn.cancel.signal },
            )
            .then(
              (response) => {
                say('permission.answered', { response });

                return response;
              },
              (error) => {
                say('permission.rejected', {
                  name: error.name,
                  code: error.code,
                  message: error.message,
                });

                return { outcome: { outcome: 'cancelled' } };
              },
            );

          if (turn.cancel.signal.aborted) {
            return { stopReason: 'cancelled' };
          }

          await update(client, sessionId, `answered ${answer.outcome.outcome}`);
        }

        if (what === 'hang') {
          await wait(turn.cancel.signal, 3_600_000);

          if (turn.cancel.signal.aborted) {
            say('hang.released', { closed: signal.aborted });

            return { stopReason: 'cancelled' };
          }
        }

        if (what === 'flood' || what === 'flood-unawaited') {
          await flood(client, sessionId, Number(arg), what === 'flood', (text) => ({
            sessionUpdate: 'agent_message_chunk',
            content: { type: 'text', text },
          }));
        }

        if (what === 'flood-unique') {
          // Each chunk its own string, so what the SDK retains costs memory.
          for (let sent = 0; sent < Number(arg); sent += 64 * 1024) {
            void client
              .notify('session/update', {
                sessionId,
                update: {
                  sessionUpdate: 'agent_message_chunk',
                  content: {
                    type: 'text',
                    text: `${sent}`.padEnd(64 * 1024, String(sent % 10)),
                  },
                },
              })
              .catch(() => {});
          }

          say('flood.queued', {
            rssMiB: Math.round(process.memoryUsage().rss / 1048576),
          });
        }

        if (what === 'stderr-flood') {
          const piece = 'y'.repeat(64 * 1024);

          for (let sent = 0; sent < Number(arg); sent += piece.length) {
            process.stderr.write(piece);
          }

          await update(client, sessionId, 'stderr written');
        }

        if (what === 'console') {
          console.log('a console.log from a handler');
        }

        if (what === 'throw') {
          throw new Error('handler threw');
        }

        return { stopReason: 'end_turn' };
      } finally {
        turns.delete(sessionId);
      }
    })
    .onRequest(
      '_chord/ping',
      (params) => params ?? {},
      ({ params }) => ({ pong: params }),
    )
    .onNotification(
      '_chord/note',
      (params) => params ?? {},
      ({ params }) => say('_chord/note', { params }),
    );
}

function v2App() {
  let sessions = 0;
  let messages = 0;

  return v2
    .agent({ name: 'chd-573-trial-v2' })
    .onRequest('initialize', ({ params }) => {
      say('initialize', {
        api: 'v2',
        asked: params.protocolVersion,
        client: params.info,
      });

      return {
        protocolVersion: 2,
        info: { name: 'trial', version: '0.0.0' },
        capabilities: {},
      };
    })
    .onRequest('session/new', () => ({ sessionId: `s${++sessions}` }))
    .onNotification('session/cancel', ({ params }) => {
      say('session/cancel', { sessionId: params.sessionId });
      turns.get(params.sessionId)?.cancel.abort('session/cancel');
    })
    .onRequest('session/prompt', ({ params, client, signal }) => {
      const { sessionId } = params;
      const [what, arg] = textOf(params.prompt).split(':');
      const messageId = `m${++messages}`;
      const turn = newTurn(`${sessionId}`, signal);
      const send = (update) =>
        client.notify('session/update', { sessionId, update });
      const idle = (stopReason) =>
        send({ sessionUpdate: 'state_update', state: 'idle', stopReason });

      // v2 answers the prompt once it is in the conversation; the turn goes on
      // after that answer, and ends in a state_update.
      void (async () => {
        await send({ sessionUpdate: 'state_update', state: 'running' });

        try {
          if (what === 'stream') {
            for (let i = 0; i < Number(arg); i++) {
              await send({
                sessionUpdate: 'agent_message_chunk',
                messageId: `${messageId}-a`,
                content: { type: 'text', text: `chunk ${i}\n` },
              });
            }
          }

          if (what === 'permission') {
            const answer = await client.request(
              'session/request_permission',
              {
                sessionId,
                title: 'Trial tool',
                options: [
                  { optionId: 'yes', name: 'Allow', kind: 'allow_once' },
                  { optionId: 'no', name: 'Reject', kind: 'reject_once' },
                ],
              },
              { cancellationSignal: turn.cancel.signal },
            );

            say('permission.answered', { response: answer });
          }

          if (what === 'hang') {
            await wait(turn.cancel.signal, 3_600_000);
          }

          await idle(turn.cancel.signal.aborted ? 'cancelled' : 'end_turn');
          say('v2.turn.idle');
        } catch (error) {
          say('v2.turn.failed', { message: error.message });
        } finally {
          turns.delete(`${sessionId}`);
        }
      })();

      void arg;

      return { messageId };
    });
}

/**
 * TRIAL_STDOUT picks how stdout becomes a WritableStream: Node's adapter as
 * src/ would use it (code outside src/platform/ calls node: built-ins), a write
 * whose promise waits on the stream's callback, as src/acp/process.ts does for
 * an agent's stdin, or Bun's own writer on fd 1.
 */
function stdoutStream() {
  const how = process.env.TRIAL_STDOUT ?? 'toweb';

  if (how === 'callback') {
    return new WritableStream({
      write: (chunk) =>
        new Promise((resolve, reject) => {
          process.stdout.write(chunk, (error) =>
            error ? reject(error) : resolve(),
          );
        }),
    });
  }

  if (how === 'bun') {
    return new WritableStream({
      write: async (chunk) => {
        await Bun.write(Bun.stdout, chunk);
      },
    });
  }

  return Writable.toWeb(process.stdout);
}

const stream = v1.ndJsonStream(stdoutStream(), Readable.toWeb(process.stdin));
const connector =
  mode === 'v1'
    ? v1App()
    : mode === 'router-v1'
      ? v2.agentProtocolRouter().withV1(v1App())
      : mode === 'router-v2'
        ? v2.agentProtocolRouter().withV2(v2App())
        : v2.agentProtocolRouter().withV1(v1App()).withV2(v2App());
const connection = connector.connect(stream);

say('connected', {
  mode,
  closeable: typeof connection.close,
  signal: connection.signal !== undefined,
});

process.on('SIGTERM', async () => {
  say('SIGTERM', { running: turns.size });

  for (const turn of turns.values()) {
    turn.cancel.abort('SIGTERM');
  }

  // A turn answers `cancelled`, and that write goes out before the close.
  await new Promise((resolve) => setTimeout(resolve, 50));
  connection.close?.();
  say('after.close');
  process.exit(0);
});

process.on('exit', (code) => say('exit', { code }));

if (process.env.TRIAL_STDIN_WATCH === '1') {
  // Node's own view of stdin, beneath the web stream the SDK reads.
  process.stdin.on('end', () => say('stdin.end'));
  process.stdin.on('close', () => say('stdin.close'));

  if (process.env.TRIAL_LEAVE_ON_END === '1') {
    // A second observer of EOF: the way out starts from it, whatever the SDK
    // read loop is doing. Nothing is hidden from the SDK.
    process.stdin.on('end', () => {
      say('leave.from.stdin');
      connection.close?.();
      process.exit(0);
    });
  }
}

if (process.env.TRIAL_TICK === '1') {
  setInterval(() => {
    say('tick', { rssMiB: Math.round(process.memoryUsage().rss / 1048576) });
  }, 250);
}

connection.closed.then(() => {
  say('closed', { reason: String(connection.signal?.reason?.message) });

  if (explicitExit) {
    process.exit(0);
  }
});
