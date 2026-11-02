// The scripted client for the CHD-573 library gate: raw newline-delimited
// JSON-RPC over real pipes, so what is on the wire is what it reads.
//
//   client.mjs <label> <mode-independent argv prefix…>
//
// The argv prefix starts the agent: `bun agent.mjs` or the compiled binary; a
// scenario appends its mode. Prints one JSON line per scenario to stdout.
import { spawn } from 'node:child_process';
import process from 'node:process';

const [label, ...prefix] = process.argv.slice(2);
const v1Init = {
  protocolVersion: 1,
  clientCapabilities: { fs: { readTextFile: true } },
};
const v2Init = {
  protocolVersion: 2,
  info: { name: 'client', version: '0' },
  capabilities: {},
};

class Peer {
  messages = [];
  stderr = '';
  raw = '';
  nonJson = [];
  nextId = 1;
  waiters = [];

  constructor(mode, env = {}) {
    this.startedAt = performance.now();
    this.child = spawn(prefix[0], [...prefix.slice(1), mode], {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, ...env },
    });
    this.child.stdout.on('data', (data) => this.#read(data));
    this.child.stderr.on('data', (data) => {
      this.stderr += data;
    });
    this.exited = new Promise((resolve) => {
      this.child.on('exit', (code, signal) => {
        resolve({
          code,
          signal,
          ms: Math.round(performance.now() - this.startedAt),
        });
      });
    });
    this.child.stdin.on('error', () => {});
  }

  #read(data) {
    this.raw += data;

    let at;

    while ((at = this.raw.indexOf('\n')) >= 0) {
      const line = this.raw.slice(0, at);

      this.raw = this.raw.slice(at + 1);

      try {
        this.messages.push(JSON.parse(line));
      } catch {
        this.nonJson.push(line);
      }
    }

    this.waiters = this.waiters.filter(({ test, resolve }) => {
      const found = this.messages.find(test);

      if (found) {
        resolve(found);
      }

      return !found;
    });
  }

  until(test, ms = 5000) {
    const found = this.messages.find(test);

    if (found) {
      return Promise.resolve(found);
    }

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('timeout')), ms);

      this.waiters.push({
        test,
        resolve: (message) => {
          clearTimeout(timer);
          resolve(message);
        },
      });
    });
  }

  write(message) {
    this.child.stdin.write(`${JSON.stringify(message)}\n`);
  }

  notify(method, params) {
    this.write({ jsonrpc: '2.0', method, params });
  }

  /** Sends a request and returns the promise of its answer. */
  request(method, params, ms) {
    const id = this.nextId++;

    this.write({ jsonrpc: '2.0', id, method, params });

    return this.until((m) => m.id === id && !m.method, ms);
  }

  events() {
    return this.stderr
      .split('\n')
      .filter(Boolean)
      .flatMap((line) => {
        try {
          return [JSON.parse(line)];
        } catch {
          return [{ raw: line.slice(0, 200) }];
        }
      });
  }

  /** The last words: EOF already sent or a signal; kills past `ms`. */
  async end(ms = 3000) {
    const outcome = await Promise.race([
      this.exited,
      new Promise((resolve) => setTimeout(() => resolve('STILL RUNNING'), ms)),
    ]);

    if (outcome === 'STILL RUNNING') {
      this.child.kill('SIGKILL');
      await this.exited;
    }

    return outcome;
  }
}

const prompt = (sessionId, text, more = {}) => ({
  sessionId,
  prompt: [{ type: 'text', text }],
  ...more,
});

async function open(mode, env) {
  const peer = new Peer(mode, env);

  await peer.request('initialize', v1Init);

  const { result } = await peer.request('session/new', {
    cwd: '/tmp',
    mcpServers: [],
  });

  return { peer, sessionId: result.sessionId };
}

/** The scenarios, each an isolated process. */
const scenarios = {
  async 'initialize+new+prompt with streamed updates (v1)'() {
    const { peer, sessionId } = await open('v1');
    const answer = await peer.request(
      'session/prompt',
      prompt(sessionId, 'stream:5'),
    );
    const chunks = peer.messages.filter((m) => m.method === 'session/update');
    const orderOk =
      peer.messages.findIndex((m) => m === answer) >
      peer.messages.findIndex((m) => m === chunks.at(-1));

    peer.child.stdin.end();

    return {
      answer: answer.result,
      chunks: chunks.length,
      updatesBeforeAnswer: orderOk,
      exit: await peer.end(),
      nonJson: peer.nonJson,
    };
  },

  async 'permission round trip (v1)'() {
    const { peer, sessionId } = await open('v1');
    const turn = peer.request('session/prompt', prompt(sessionId, 'permission'));
    const asked = await peer.until(
      (m) => m.method === 'session/request_permission',
    );

    peer.write({
      jsonrpc: '2.0',
      id: asked.id,
      result: { outcome: { outcome: 'selected', optionId: 'yes' } },
    });

    const answer = await turn;

    peer.child.stdin.end();

    const exit = await peer.end();

    return {
      asked: { id: asked.id, options: asked.params.options.length },
      answer: answer.result,
      said: peer.messages.filter((m) => m.method === 'session/update').length,
      exit,
    };
  },

  async 'session/cancel with a permission pending (v1)'() {
    const { peer, sessionId } = await open('v1');
    const turn = peer.request('session/prompt', prompt(sessionId, 'permission'));
    const asked = await peer.until(
      (m) => m.method === 'session/request_permission',
    );

    peer.notify('session/cancel', { sessionId });

    const cancelRequest = await peer.until(
      (m) => m.method === '$/cancel_request',
    );

    // As the protocol has it: the client answers `cancelled` to the request.
    peer.write({
      jsonrpc: '2.0',
      id: asked.id,
      result: { outcome: { outcome: 'cancelled' } },
    });

    const answer = await turn;

    peer.child.stdin.end();

    return {
      cancelRequest: cancelRequest.params,
      answer: answer.result,
      exit: await peer.end(),
      events: peer.events().filter((e) => /permission|cancel/.test(e.ev)),
    };
  },

  async 'session/cancel with a client that never answers the permission (v1)'() {
    const { peer, sessionId } = await open('v1');
    const turn = peer
      .request('session/prompt', prompt(sessionId, 'permission'), 1000)
      .catch(() => 'no answer in 1s');

    await peer.until((m) => m.method === 'session/request_permission');
    peer.notify('session/cancel', { sessionId });

    const answer = await turn;

    peer.child.stdin.end();

    return { answer, exit: await peer.end() };
  },

  async 'prompt and session/cancel in one write: order kept (v1)'() {
    const { peer, sessionId } = await open('v1');
    const sent = [];

    for (let i = 0; i < 20; i++) {
      const id = 1000 + i;

      peer.child.stdin.write(
        `${JSON.stringify({
          jsonrpc: '2.0',
          id,
          method: 'session/prompt',
          params: prompt(sessionId, 'hang'),
        })}\n${JSON.stringify({
          jsonrpc: '2.0',
          method: 'session/cancel',
          params: { sessionId },
        })}\n`,
      );
      sent.push(
        await peer
          .until((m) => m.id === id, 1000)
          .then((m) => m.result?.stopReason ?? 'error', () => 'hung'),
      );

      if (sent.at(-1) === 'hung') {
        break;
      }
    }

    peer.child.stdin.end();

    return {
      tries: sent.length,
      hung: sent.filter((each) => each === 'hung').length,
      exit: await peer.end(),
    };
  },

  async '$/cancel_request for a running prompt (v1)'() {
    const { peer, sessionId } = await open('v1');
    const id = peer.nextId;
    const turn = peer.request('session/prompt', prompt(sessionId, 'hang'));

    await new Promise((resolve) => setTimeout(resolve, 100));
    peer.notify('$/cancel_request', { requestId: id });

    const answer = await turn;

    peer.child.stdin.end();

    return {
      answer: answer.result ?? answer.error,
      exit: await peer.end(),
      events: peer.events().filter((e) => /signal|hang/.test(e.ev)),
    };
  },

  async 'stdin EOF idle: explicit exit (v1)'() {
    const { peer } = await open('v1');

    peer.child.stdin.end();

    const exit = await peer.end();

    return { exit, events: peer.events().filter((e) => /closed|exit/.test(e.ev)) };
  },

  async 'stdin EOF idle: natural exit (v1)'() {
    const { peer } = await open('v1', { TRIAL_EXIT: 'natural' });

    peer.child.stdin.end();

    const exit = await peer.end();

    return { exit, events: peer.events().filter((e) => /closed|exit/.test(e.ev)) };
  },

  async 'stdin EOF with a prompt running and a permission pending (v1)'() {
    const { peer, sessionId } = await open('v1');

    peer.write({
      jsonrpc: '2.0',
      id: 99,
      method: 'session/prompt',
      params: prompt(sessionId, 'permission'),
    });
    await peer.until((m) => m.method === 'session/request_permission');
    peer.child.stdin.end();

    const exit = await peer.end();

    return {
      answered: peer.messages.some((m) => m.id === 99),
      exit,
      events: peer
        .events()
        .filter((e) => /permission|signal|closed|exit/.test(e.ev)),
    };
  },

  async 'SIGTERM with a hanging prompt: the turn is answered first (v1)'() {
    const { peer, sessionId } = await open('v1');
    const turn = peer.request('session/prompt', prompt(sessionId, 'hang'));

    await new Promise((resolve) => setTimeout(resolve, 100));
    peer.child.kill('SIGTERM');

    const answer = await turn.catch(() => 'no answer');
    const exit = await peer.end();

    return {
      answer: answer.result ?? answer,
      exit,
      events: peer.events().filter((e) => /SIG|close|exit|hang/.test(e.ev)),
    };
  },

  async 'SIGTERM with a permission pending (v1)'() {
    const { peer, sessionId } = await open('v1');
    const turn = peer.request('session/prompt', prompt(sessionId, 'permission'));

    await peer.until((m) => m.method === 'session/request_permission');
    peer.child.kill('SIGTERM');

    const answer = await turn.catch(() => 'no answer');
    const exit = await peer.end();

    return {
      answer: answer.result ?? answer,
      cancelSent: peer.messages.some((m) => m.method === '$/cancel_request'),
      exit,
      events: peer.events().filter((e) => /SIG|permission|exit/.test(e.ev)),
    };
  },

  async 'extension request and notification; unknown method (v1)'() {
    const { peer } = await open('v1');
    const pong = await peer.request('_chord/ping', { hello: 1 });
    const unknown = await peer.request('_chord/absent', {});

    peer.notify('_chord/note', { note: 1 });
    peer.notify('_chord/absent-note', { note: 2 });
    await new Promise((resolve) => setTimeout(resolve, 100));
    peer.child.stdin.end();

    return {
      pong: pong.result,
      unknown: unknown.error,
      exit: await peer.end(),
      events: peer.events().filter((e) => /_chord/.test(e.ev)),
      stillNotJson: peer.nonJson,
    };
  },

  async 'unknown fields and _meta in; an unknown update kind out (v1)'() {
    const { peer, sessionId } = await open('v1');
    const answer = await peer.request(
      'session/prompt',
      prompt(sessionId, 'unknown-update', {
        _meta: { 'chord/x': 1 },
        unknownField: true,
      }),
    );

    peer.child.stdin.end();

    return {
      answer: answer.result,
      onWire: peer.messages.filter((m) => m.method === 'session/update'),
      exit: await peer.end(),
      events: peer.events().filter((e) => /session\/prompt|unknown/.test(e.ev)),
    };
  },

  async 'a handler that throws, and garbage on the line (v1)'() {
    const { peer, sessionId } = await open('v1');
    const threw = await peer.request('session/prompt', prompt(sessionId, 'throw'));

    peer.child.stdin.write('not json\n');
    peer.child.stdin.write('[1,2]\n');

    const invalid = await peer.until((m) => m.error && m.id === null);
    const alive = await peer.request('session/prompt', prompt(sessionId, 'stream:1'));

    peer.child.stdin.end();

    return {
      threw: threw.error,
      invalid: invalid.error.code,
      aliveAfter: alive.result,
      exit: await peer.end(),
    };
  },

  async 'a request before initialize (v1, router)'() {
    const plain = new Peer('v1');
    const routed = new Peer('router');
    const params = { cwd: '/tmp', mcpServers: [] };
    const answers = {
      plain: await plain.request('session/new', params),
      routed: await routed.request('session/new', params),
    };

    plain.child.stdin.end();
    routed.child.stdin.end();
    await Promise.all([plain.end(), routed.end()]);

    return {
      plain: answers.plain.error ?? answers.plain.result,
      routed: answers.routed.error ?? answers.routed.result,
    };
  },

  async 'negotiation matrix'() {
    const table = [];
    const asks = [
      ['0', { ...v1Init, protocolVersion: 0 }],
      ['1', v1Init],
      ['2 (v2 shape)', v2Init],
      ['3 (v2 shape)', { ...v2Init, protocolVersion: 3 }],
      ['2 (v1 shape)', { ...v1Init, protocolVersion: 2 }],
      ['not a number', { ...v1Init, protocolVersion: 'x' }],
    ];

    for (const mode of ['v1', 'router-v1', 'router-v2', 'router']) {
      for (const [name, params] of asks) {
        const peer = new Peer(mode);
        const answer = await peer
          .request('initialize', params, 2000)
          .catch(() => ({ error: 'no answer' }));

        peer.child.stdin.end();
        await peer.end();
        table.push({
          mode,
          asked: name,
          answered:
            answer.result?.protocolVersion ??
            answer.error?.code ??
            answer.error,
          agentSaw: peer.events().find((e) => e.ev === 'initialize')?.asked,
        });
      }
    }

    return table;
  },

  async 'v2 turn: prompt answered, then state_update (router)'() {
    const peer = new Peer('router');

    await peer.request('initialize', v2Init);

    const { result } = await peer.request('session/new', { cwd: '/tmp' });
    const answer = await peer.request(
      'session/prompt',
      prompt(result.sessionId, 'stream:3'),
    );
    const idle = await peer.until(
      (m) => m.params?.update?.sessionUpdate === 'state_update'
        && m.params.update.state === 'idle',
    );
    const updates = peer.messages
      .filter((m) => m.method === 'session/update')
      .map((m) => m.params.update.state ?? m.params.update.sessionUpdate);

    peer.child.stdin.end();

    return {
      answer: answer.result,
      stopReason: idle.params.update.stopReason,
      updates,
      exit: await peer.end(),
    };
  },

  async 'v2 permission and cancel (router)'() {
    const peer = new Peer('router');

    await peer.request('initialize', v2Init);

    const { result } = await peer.request('session/new', { cwd: '/tmp' });
    const { sessionId } = result;

    await peer.request('session/prompt', prompt(sessionId, 'permission'));

    const asked = await peer.until(
      (m) => m.method === 'session/request_permission',
    );

    peer.write({
      jsonrpc: '2.0',
      id: asked.id,
      result: { outcome: { outcome: 'selected', optionId: 'yes' } },
    });
    await peer.until(
      (m) => m.params?.update?.state === 'idle',
    );

    const before = peer.messages.length;

    await peer.request('session/prompt', prompt(sessionId, 'hang'));
    peer.notify('session/cancel', { sessionId });

    const idle = await peer.until(
      (m) =>
        m.params?.update?.state === 'idle' &&
        peer.messages.indexOf(m) >= before,
    );

    peer.child.stdin.end();

    return {
      permission: asked.params.title,
      cancelled: idle.params.update.stopReason,
      exit: await peer.end(),
    };
  },

  async 'a v1 method on a v2 connection (router)'() {
    const peer = new Peer('router');

    await peer.request('initialize', v2Init);

    const load = await peer.request('session/load', { sessionId: 's', cwd: '/tmp', mcpServers: [] });

    peer.child.stdin.end();
    await peer.end();

    return { load: load.error ?? load.result };
  },

  async 'stdout: a client that stops reading while the agent floods, awaited (v1)'() {
    const { peer, sessionId } = await open('v1');

    peer.child.stdout.pause();
    peer.write({
      jsonrpc: '2.0',
      id: 50,
      method: 'session/prompt',
      params: prompt(sessionId, `flood:${64 * 1024 * 1024}`),
    });
    await new Promise((resolve) => setTimeout(resolve, 3000));

    const during = peer.events().filter((e) => /flood/.test(e.ev)).at(-1);

    peer.child.stdout.resume();

    const answer = await peer.until((m) => m.id === 50, 30_000);

    peer.child.stdin.end();

    return {
      lastEventWhileStalled: during ?? 'no flood.progress yet: writes were held',
      answer: answer.result,
      exit: await peer.end(),
      lastEvent: peer.events().filter((e) => /flood/.test(e.ev)).at(-1),
    };
  },

  async 'stdout: a client that stops reading, unawaited sends (v1)'() {
    const { peer, sessionId } = await open('v1');

    peer.child.stdout.pause();
    peer.write({
      jsonrpc: '2.0',
      id: 50,
      method: 'session/prompt',
      params: prompt(sessionId, `flood-unawaited:${256 * 1024 * 1024}`),
    });
    await new Promise((resolve) => setTimeout(resolve, 4000));

    const events = peer.events().filter((e) => /flood/.test(e.ev));

    peer.child.kill('SIGKILL');
    await peer.exited;

    return { lastEvent: events.at(-1), stoppedOnKill: true };
  },

  async 'stdout closed by the client: the next write (v1)'() {
    const { peer, sessionId } = await open('v1');

    peer.child.stdout.destroy();
    peer.write({
      jsonrpc: '2.0',
      id: 60,
      method: 'session/prompt',
      params: prompt(sessionId, 'stream:50'),
    });

    const exit = await peer.end();

    return {
      exit,
      events: peer.events().filter((e) => /closed|exit|signal/.test(e.ev)),
    };
  },

  async 'a line over 32 MiB in (v1)'() {
    const { peer } = await open('v1');
    const big = `{"jsonrpc":"2.0","method":"_chord/note","params":"${'x'.repeat(33 * 1024 * 1024)}"}\n`;

    peer.child.stdin.write(big);

    const exit = await peer.end(5000);

    return {
      exit,
      events: peer.events().filter((e) => /closed|exit/.test(e.ev)),
    };
  },

  async 'console.log in a handler reaches stdout (v1)'() {
    const { peer, sessionId } = await open('v1');

    await peer.request('session/prompt', prompt(sessionId, 'console'));
    peer.child.stdin.end();
    await peer.end();

    return { nonJsonOnStdout: peer.nonJson };
  },
};

const only = process.env.TRIAL_ONLY;

for (const [name, scenario] of Object.entries(scenarios)) {
  if (only !== undefined && !name.includes(only)) {
    continue;
  }

  try {
    const result = await Promise.race([
      scenario(),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('scenario timed out')), 60_000),
      ),
    ]);

    console.log(JSON.stringify({ target: label, scenario: name, result }));
  } catch (error) {
    console.log(
      JSON.stringify({ target: label, scenario: name, failed: error.message }),
    );
  }
}

process.exit(0);
