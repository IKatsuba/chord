/**
 * CTUI-35 trial runner: starts the Dart server (through `dart run` and as a
 * `dart compile exe` binary in a scratch directory outside the repository)
 * and the TypeScript one (bun; ts/server.ts is copied into the scratch
 * directory beside a node_modules symlink to ../chord/node_modules, because
 * bun resolves ESM bare imports from the script's directory, ignores
 * NODE_PATH for them, and would otherwise auto-install a fresh SDK),
 * sends each the same request sequence, and writes normalised results to
 * results/{dart,dart_exe,ts}.json and the differences to results/diff.md.
 *
 *   deno run --allow-run --allow-read --allow-write --allow-env --allow-net \
 *     --allow-sys run.ts
 *
 * CHORD_SOURCE selects the chord checkout (default: ../chord beside the
 * repository root); CHORD_BUN selects bun (default: bun on PATH).
 */
import { dirname, fromFileUrl, join, resolve } from 'jsr:@std/path@1';

const here = dirname(fromFileUrl(import.meta.url));
const repoRoot = resolve(here, '../../../../..');
const chord = Deno.env.get('CHORD_SOURCE') ?? resolve(repoRoot, '../chord');
const bun = Deno.env.get('CHORD_BUN') ?? 'bun';
const PROTOCOL = '2025-11-25';

// ---------------------------------------------------------------- relabel

const scratch = await Deno.makeTempDir({ prefix: 'mcp_trial_' });
const secrets: [string, string][] = [];

{
  const add = (value: string | undefined, label: string) => {
    if (value && value.length > 1) secrets.push([value, label]);
  };
  add(await Deno.realPath(scratch).catch(() => undefined), '<scratch>');
  add(scratch, '<scratch>');
  add(await Deno.realPath(chord).catch(() => undefined), '../chord');
  add(chord, '../chord');
  add(await Deno.realPath(here).catch(() => undefined), '.');
  add(here, '.');
  add(Deno.env.get('HOME'), '<home>');
  add(Deno.env.get('USER'), '<user>');
  add(Deno.hostname(), '<host>');
  // Longest first, so a path is replaced before a part of it.
  secrets.sort((a, b) => b[0].length - a[0].length);
}

function relabel(text: string): string {
  for (const [value, label] of secrets) text = text.split(value).join(label);
  // Any other system scratch path left in a captured output.
  for (const root of ['private', 'tmp', 'var/folders']) {
    text = text.replace(new RegExp(`/${root}/[^\\s"']*`, 'g'), '<scratch>');
  }
  return text;
}

// ---------------------------------------------------------------- servers

interface Running {
  readonly url: string;
  readonly tokens: { main: string; task: string };
  revoke(token: string): Promise<void>;
  stop(): Promise<string>;
}

async function start(
  command: string,
  args: string[],
  options: { cwd: string; env?: Record<string, string> },
): Promise<Running> {
  const child = new Deno.Command(command, {
    args,
    cwd: options.cwd,
    env: options.env,
    stdin: 'piped',
    stdout: 'piped',
    stderr: 'piped',
  }).spawn();
  const writer = child.stdin.getWriter();
  const decoder = new TextDecoder();
  let stderr = '';
  let stdoutRest = '';
  const waiters: { token: string; resolve: () => void }[] = [];

  void (async () => {
    for await (const chunk of child.stderr) {
      stderr += decoder.decode(chunk);
      for (const waiter of [...waiters]) {
        if (stderr.includes(`revoked ${waiter.token}`)) {
          waiters.splice(waiters.indexOf(waiter), 1);
          waiter.resolve();
        }
      }
    }
  })();

  const reader = child.stdout.getReader();
  let first: { url: string; tokens: { main: string; task: string } } | undefined;
  const extra: string[] = [];
  const deadline = Date.now() + 120_000;

  while (first === undefined) {
    if (Date.now() > deadline) throw new Error(`${command}: no URL line`);
    const { value, done } = await reader.read();
    if (done) throw new Error(`${command} exited: ${relabel(stderr)}`);
    stdoutRest += decoder.decode(value);
    let newline: number;
    while (first === undefined && (newline = stdoutRest.indexOf('\n')) >= 0) {
      const line = stdoutRest.slice(0, newline);
      stdoutRest = stdoutRest.slice(newline + 1);
      try {
        const parsed = JSON.parse(line);
        if (typeof parsed?.url === 'string') first = parsed;
        else extra.push(line);
      } catch {
        // `dart run` may print its build progress before the program runs.
        extra.push(line);
      }
    }
  }
  void (async () => {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      stdoutRest += decoder.decode(value);
    }
  })();

  return {
    url: first.url,
    tokens: first.tokens,
    revoke: async (token) => {
      const acknowledged = new Promise<void>((resolve) =>
        waiters.push({ token, resolve }),
      );
      await writer.write(new TextEncoder().encode(`revoke ${token}\n`));
      await acknowledged;
    },
    stop: async () => {
      await writer.close().catch(() => {});
      const timer = setTimeout(() => child.kill('SIGKILL'), 10_000);
      await child.status;
      clearTimeout(timer);
      const tokens = first!.tokens;
      let log = stderr
        .split(tokens.main).join('<token-main>')
        .split(tokens.task).join('<token-task>');
      if (extra.length > 0) log = `[stdout before the URL line]\n${extra.join('\n')}\n[stderr]\n${log}`;
      if (stdoutRest.trim() !== '') log += `\n[stdout after the URL line]\n${stdoutRest}`;
      return relabel(log);
    },
  };
}

// ---------------------------------------------------------------- requests

const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;

class Names {
  readonly map = new Map<string, string>();
  sessions = 0;
  others = 0;

  constructor(tokens: { main: string; task: string }) {
    this.map.set(tokens.main, '<token-main>');
    this.map.set(tokens.task, '<token-task>');
  }

  session(id: string): string {
    if (!this.map.has(id)) this.map.set(id, `<session-${++this.sessions}>`);
    return this.map.get(id)!;
  }

  text(value: string): string {
    for (const [raw, label] of this.map) value = value.split(raw).join(label);
    return value.replace(UUID, (found) => {
      if (!this.map.has(found)) this.map.set(found, `<uuid-${++this.others}>`);
      return this.map.get(found)!;
    });
  }

  deep(value: unknown): unknown {
    if (typeof value === 'string') return this.text(value);
    if (Array.isArray(value)) return value.map((item) => this.deep(item));
    if (value !== null && typeof value === 'object') {
      return Object.fromEntries(
        Object.entries(value).map(([key, item]) => [key, this.deep(item)]),
      );
    }
    return value;
  }
}

interface Ask {
  readonly method?: string;
  readonly token?: string | null;
  readonly session?: string;
  readonly body?: unknown;
  /** Sent as is when a string. */
  readonly raw?: string;
  readonly accept?: string | null;
  readonly contentType?: string | null;
  readonly protocolVersion?: string | null;
  /** Read only the head, for a GET stream that stays open. */
  readonly headOnly?: boolean;
}

const KEPT_HEADERS = [
  'content-type',
  'mcp-session-id',
  'mcp-protocol-version',
  'allow',
  'cache-control',
  'www-authenticate',
];

function parseSse(text: string): unknown[] {
  const events: unknown[] = [];
  for (const block of text.split(/\r?\n\r?\n/)) {
    if (block.trim() === '') continue;
    const event: Record<string, unknown> = {};
    const data: string[] = [];
    for (const line of block.split(/\r?\n/)) {
      const colon = line.indexOf(':');
      const field = colon < 0 ? line : line.slice(0, colon);
      const value = colon < 0 ? '' : line.slice(colon + 1).replace(/^ /, '');
      if (field === 'data') data.push(value);
      else if (field !== '') event[field] = value;
    }
    if (data.length > 0) {
      const joined = data.join('\n');
      try {
        event.data = JSON.parse(joined);
      } catch {
        event.data = joined;
      }
    }
    events.push(event);
  }
  return events;
}

async function send(
  running: Running,
  names: Names,
  ask: Ask,
): Promise<{ result: Record<string, unknown>; session?: string }> {
  const headers = new Headers();
  const token = ask.token === undefined ? running.tokens.main : ask.token;
  if (token !== null) headers.set('authorization', `Bearer ${token}`);
  const accept =
    ask.accept === undefined ? 'application/json, text/event-stream' : ask.accept;
  if (accept !== null) headers.set('accept', accept);
  const method = ask.method ?? 'POST';
  const hasBody = ask.raw !== undefined || ask.body !== undefined;
  const contentType =
    ask.contentType === undefined ? 'application/json' : ask.contentType;
  if (hasBody && contentType !== null) headers.set('content-type', contentType);
  if (ask.session !== undefined) {
    headers.set('mcp-session-id', ask.session);
    const version =
      ask.protocolVersion === undefined ? PROTOCOL : ask.protocolVersion;
    if (version !== null) headers.set('mcp-protocol-version', version);
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 5000);
  const result: Record<string, unknown> = {};
  let session: string | undefined;
  try {
    const response = await fetch(running.url, {
      method,
      headers,
      body: hasBody ? (ask.raw ?? JSON.stringify(ask.body)) : undefined,
      signal: controller.signal,
    });
    result.status = response.status;
    const kept: Record<string, string> = {};
    for (const name of KEPT_HEADERS) {
      const value = response.headers.get(name);
      if (value === null) continue;
      if (name === 'mcp-session-id') {
        session = value;
        kept[name] = names.session(value);
      } else {
        kept[name] = names.text(value);
      }
    }
    result.headers = kept;
    const type = response.headers.get('content-type') ?? '';
    if (ask.headOnly) {
      await response.body?.cancel();
      result.body = '<not read: stream left open>';
    } else {
      const text = await response.text();
      if (text === '') result.body = null;
      else if (type.includes('text/event-stream')) {
        result.sse = names.deep(parseSse(text));
      } else {
        try {
          result.body = names.deep(JSON.parse(text));
        } catch {
          result.body = names.text(text);
        }
      }
    }
  } catch (error) {
    result.failure = error instanceof DOMException && error.name === 'AbortError'
      ? 'no complete answer within 5 s'
      : String(error);
  } finally {
    clearTimeout(timer);
  }
  return { result, session };
}

function initialize(id: number) {
  return {
    jsonrpc: '2.0',
    id,
    method: 'initialize',
    params: {
      protocolVersion: PROTOCOL,
      capabilities: {},
      clientInfo: { name: 'trial', version: '1.0.0' },
    },
  };
}

const initialized = { jsonrpc: '2.0', method: 'notifications/initialized' };

function call(id: number, name: string, args?: unknown) {
  return {
    jsonrpc: '2.0',
    id,
    method: 'tools/call',
    params: args === undefined ? { name } : { name, arguments: args },
  };
}

async function sequence(running: Running): Promise<Record<string, unknown>> {
  const names = new Names(running.tokens);
  const out: Record<string, unknown> = {};
  const { main, task } = running.tokens;
  const run = async (name: string, ask: Ask) => {
    const { result, session } = await send(running, names, ask);
    out[name] = { request: describe(ask, names), ...result };
    return session;
  };

  await run('01 no token', { token: null, body: initialize(1) });
  await run('02 wrong token', { token: 'not-a-token', body: initialize(1) });
  await run('03 non-initialize without session id', {
    body: { jsonrpc: '2.0', id: 1, method: 'tools/list' },
  });
  await run('04 malformed JSON without session id', { raw: '{"jsonrpc": "2.0",' });
  await run('05 initialize with Accept: application/json only', {
    accept: 'application/json',
    body: initialize(1),
  });
  await run('06 initialize with Content-Type: text/plain', {
    contentType: 'text/plain',
    body: initialize(1),
  });
  await run('07 GET without session id', { method: 'GET', accept: 'text/event-stream' });
  const s1 = (await run('08 initialize (main)', { body: initialize(1) }))!;
  await run('09 notifications/initialized (main)', { session: s1, body: initialized });
  await run('10 ping', { session: s1, body: { jsonrpc: '2.0', id: 2, method: 'ping' } });
  await run('11 unknown session id', {
    session: '00000000-0000-4000-8000-000000000000',
    body: { jsonrpc: '2.0', id: 3, method: 'tools/list' },
  });
  await run('12 session with another token', {
    token: task,
    session: s1,
    body: { jsonrpc: '2.0', id: 3, method: 'tools/list' },
  });
  await run('13 tools/list (main)', {
    session: s1,
    body: { jsonrpc: '2.0', id: 4, method: 'tools/list' },
  });
  const s2 = (await run('14 initialize (task)', { token: task, body: initialize(1) }))!;
  await run('15 notifications/initialized (task)', {
    token: task,
    session: s2,
    body: initialized,
  });
  await run('16 tools/list (task)', {
    token: task,
    session: s2,
    body: { jsonrpc: '2.0', id: 2, method: 'tools/list' },
  });
  await run('17 tools/call send_message (main)', {
    session: s1,
    body: call(5, 'send_message', { to: 'parser', text: 'hello' }),
  });
  await run('18 tools/call close_agent gone (refusal)', {
    session: s1,
    body: call(6, 'close_agent', { to: 'gone' }),
  });
  await run('19 tools/call close_agent parser', {
    session: s1,
    body: call(7, 'close_agent', { to: 'parser' }),
  });
  await run('20 tools/call clear_agent parser', {
    session: s1,
    body: call(8, 'clear_agent', { to: 'parser' }),
  });
  await run('21 tools/call send_message (task)', {
    token: task,
    session: s2,
    body: call(3, 'send_message', { text: 'hello' }),
  });
  await run('22 task calls close_agent (not in role)', {
    token: task,
    session: s2,
    body: call(4, 'close_agent', { to: 'parser' }),
  });
  await run('23 missing required argument', {
    session: s1,
    body: call(9, 'send_message', { to: 'parser' }),
  });
  await run('24 no arguments at all', { session: s1, body: call(10, 'close_agent') });
  await run('25 wrong argument type (to: 5)', {
    session: s1,
    body: call(11, 'close_agent', { to: 5 }),
  });
  await run('26 extra unknown argument', {
    session: s1,
    body: call(12, 'close_agent', { to: 'parser', extra: 1 }),
  });
  await run('27 unknown tool name', {
    session: s1,
    body: call(13, 'no_such_tool', {}),
  });
  await run('28 unknown method', {
    session: s1,
    body: { jsonrpc: '2.0', id: 14, method: 'no/such_method' },
  });
  await run('29 malformed JSON with session id', {
    session: s1,
    raw: '{"jsonrpc": "2.0",',
  });
  await run('30 wrong Accept with session id', {
    session: s1,
    accept: 'application/json',
    body: { jsonrpc: '2.0', id: 15, method: 'tools/list' },
  });
  await run('31 no Accept header with session id', {
    session: s1,
    accept: null,
    body: { jsonrpc: '2.0', id: 16, method: 'tools/list' },
  });
  await run('32 unsupported MCP-Protocol-Version header', {
    session: s1,
    protocolVersion: '1999-01-01',
    body: { jsonrpc: '2.0', id: 17, method: 'tools/list' },
  });
  await run('33 no MCP-Protocol-Version header', {
    session: s1,
    protocolVersion: null,
    body: { jsonrpc: '2.0', id: 18, method: 'ping' },
  });
  await run('34 JSON-RPC batch', {
    session: s1,
    body: [
      { jsonrpc: '2.0', id: 19, method: 'ping' },
      { jsonrpc: '2.0', id: 20, method: 'tools/list' },
    ],
  });
  await run('35 re-initialize on an open session', {
    session: s1,
    body: initialize(21),
  });
  await run('36 invalid JSON-RPC (no jsonrpc field)', {
    session: s1,
    body: { id: 22, method: 'ping' },
  });
  await run('37 GET stream on session', {
    session: s1,
    method: 'GET',
    accept: 'text/event-stream',
    headOnly: true,
  });
  await run('38 PUT on session', { session: s1, method: 'PUT', raw: '{}' });
  await run('39 DELETE session', { session: s1, method: 'DELETE' });
  await run('40 reuse deleted session', {
    session: s1,
    body: { jsonrpc: '2.0', id: 23, method: 'ping' },
  });
  const s3 = (await run('41 initialize (main, to revoke)', { body: initialize(1) }))!;
  await run('42 notifications/initialized (main, to revoke)', {
    session: s3,
    body: initialized,
  });
  await running.revoke(main);
  out['43 revoke main token'] = { request: 'trial stdin: revoke <token-main>' };
  await run('44 call on a revoked token session', {
    session: s3,
    body: call(2, 'send_message', { to: 'parser', text: 'hello' }),
  });
  await run('45 initialize with a revoked token', { body: initialize(1) });
  await run('46 task session survives the main revocation', {
    token: task,
    session: s2,
    body: { jsonrpc: '2.0', id: 5, method: 'ping' },
  });
  return out;
}

function describe(ask: Ask, names: Names): Record<string, unknown> {
  const request: Record<string, unknown> = { method: ask.method ?? 'POST' };
  if (ask.token === null) request.authorization = '(none)';
  else if (ask.token !== undefined) request.authorization = `Bearer ${names.text(ask.token)}`;
  else request.authorization = 'Bearer <token-main>';
  if (ask.session !== undefined) request.session = names.text(ask.session);
  if (ask.accept !== undefined) request.accept = ask.accept ?? '(none)';
  if (ask.contentType !== undefined) request.contentType = ask.contentType;
  if (ask.protocolVersion !== undefined) {
    request.protocolVersion = ask.protocolVersion ?? '(none)';
  }
  if (ask.raw !== undefined) request.raw = ask.raw;
  if (ask.body !== undefined) request.body = names.deep(ask.body);
  return request;
}

// ---------------------------------------------------------------- diff

function paths(a: unknown, b: unknown, at: string, out: string[]): void {
  const same = JSON.stringify(a) === JSON.stringify(b);
  if (same) return;
  const objects =
    a !== null && b !== null && typeof a === 'object' && typeof b === 'object' &&
    Array.isArray(a) === Array.isArray(b);
  if (!objects) {
    out.push(`- \`${at || '(root)'}\`: Dart \`${JSON.stringify(a)}\`, TS \`${JSON.stringify(b)}\``);
    return;
  }
  const ka = Object.keys(a as object);
  const kb = Object.keys(b as object);
  const keys = [...new Set([...ka, ...kb])];
  for (const key of keys) {
    const va = (a as Record<string, unknown>)[key];
    const vb = (b as Record<string, unknown>)[key];
    const next = at === '' ? key : `${at}.${key}`;
    if (!(key in (a as object))) out.push(`- \`${next}\`: absent in Dart, TS \`${JSON.stringify(vb)}\``);
    else if (!(key in (b as object))) out.push(`- \`${next}\`: Dart \`${JSON.stringify(va)}\`, absent in TS`);
    else paths(va, vb, next, out);
  }
  // Same members, different order: key order is visible on the wire.
  if (!Array.isArray(a) && ka.join() !== kb.join() && ka.length === kb.length &&
    ka.every((k) => kb.includes(k))) {
    out.push(`- \`${at || '(root)'}\` key order: Dart \`${ka.join(', ')}\`, TS \`${kb.join(', ')}\``);
  }
}

function diffReport(
  dart: Record<string, unknown>,
  ts: Record<string, unknown>,
  exe: Record<string, unknown>,
): string {
  const lines = [
    '# Dart (mcp_dart 2.4.4) against TS (@modelcontextprotocol/sdk 1.32.2)',
    '',
    'Generated by run.ts from results/dart.json and results/ts.json. Each case lists every differing JSON path; a case not listed answered identically.',
    '',
  ];
  const sameExe = JSON.stringify(dart) === JSON.stringify(exe);
  lines.push(
    sameExe
      ? 'The compiled binary (results/dart_exe.json) answered exactly as `dart run` did.'
      : 'The compiled binary (results/dart_exe.json) answered differently from `dart run`; see the last section.',
    '',
  );
  const identical: string[] = [];
  for (const name of Object.keys(dart)) {
    const out: string[] = [];
    const a = { ...(dart[name] as object) } as Record<string, unknown>;
    const b = { ...(ts[name] as object) } as Record<string, unknown>;
    delete a.request;
    delete b.request;
    paths(a, b, '', out);
    if (out.length === 0) identical.push(name);
    else lines.push(`## ${name}`, '', ...out, '');
  }
  lines.push('## Identical', '', ...identical.map((name) => `- ${name}`), '');
  if (!sameExe) {
    lines.push('## dart run against the compiled binary', '');
    for (const name of Object.keys(dart)) {
      const out: string[] = [];
      paths(dart[name], exe[name], '', out);
      if (out.length > 0) lines.push(`### ${name}`, '', ...out, '');
    }
  }
  return lines.join('\n');
}

// ---------------------------------------------------------------- main

const results = join(here, 'results');
await Deno.mkdir(results, { recursive: true });

async function trial(label: string, starting: () => Promise<Running>) {
  const running = await starting();
  let out: Record<string, unknown>;
  try {
    out = await sequence(running);
  } finally {
    const log = await running.stop();
    await Deno.writeTextFile(join(results, `${label}.stderr.txt`), log);
  }
  const json = relabel(JSON.stringify(out, null, 2)) + '\n';
  await Deno.writeTextFile(join(results, `${label}.json`), json);
  return JSON.parse(json) as Record<string, unknown>;
}

try {
  const dartDir = join(here, 'dart');
  const get = await new Deno.Command('dart', { args: ['pub', 'get'], cwd: dartDir }).output();
  if (!get.success) throw new Error(new TextDecoder().decode(get.stderr));

  const dart = await trial('dart', () =>
    start('dart', ['run', 'bin/server.dart'], { cwd: dartDir }));

  const exe = join(scratch, 'server');
  const compiled = await new Deno.Command('dart', {
    args: ['compile', 'exe', 'bin/server.dart', '-o', exe],
    cwd: dartDir,
  }).output();
  if (!compiled.success) throw new Error(new TextDecoder().decode(compiled.stderr));
  const dartExe = await trial('dart_exe', () => start(exe, [], { cwd: dartDir }));

  const tsDir = join(scratch, 'ts_server');
  await Deno.mkdir(tsDir);
  await Deno.copyFile(join(here, 'ts', 'server.ts'), join(tsDir, 'server.ts'));
  await Deno.symlink(join(chord, 'node_modules'), join(tsDir, 'node_modules'));
  const ts = await trial('ts', () =>
    start(bun, ['--no-install', 'server.ts'], { cwd: tsDir }));

  await Deno.writeTextFile(join(results, 'diff.md'), relabel(diffReport(dart, ts, dartExe)));
  console.log('wrote results/dart.json, results/dart_exe.json, results/ts.json, results/diff.md');
} finally {
  await Deno.remove(scratch, { recursive: true });
  // pub writes absolute pub-cache paths there; dart pub get makes it again.
  await Deno.remove(join(here, 'dart', '.dart_tool'), { recursive: true }).catch(() => {});
}
