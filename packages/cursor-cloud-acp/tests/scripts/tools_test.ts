import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdtemp, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  build,
  foreign,
  here,
  PACKED,
  serveOnce,
  tooOld,
} from '../../scripts/tools.ts';

test("foreign names a build's inputs outside the package's src/, by a path from the cwd or absolute", () => {
  const root = join(here, '..', '..');

  expect(
    foreign(
      [
        'packages/cursor-cloud-acp/src/bin.ts',
        join(here, 'src', 'main.ts'),
        'node_modules/.bun/@cursor+sdk@1.3.1/node_modules/@cursor/sdk/dist/esm/index.js',
        'packages/cursor-cloud-acp/scripts/tools.ts',
        'packages/cursor-cloud-acp/srcs/a.ts',
      ],
      root,
    ),
  ).toEqual([
    'node_modules/.bun/@cursor+sdk@1.3.1/node_modules/@cursor/sdk/dist/esm/index.js',
    'packages/cursor-cloud-acp/scripts/tools.ts',
    'packages/cursor-cloud-acp/srcs/a.ts',
  ]);
});

describe('CHD-622 tester: built Node launcher', () => {
  test('Node reports a thrown error or primitive without a stack or stdout', async () => {
    const outdir = await mkdtemp(
      join(tmpdir(), 'cursor-cloud-acp-node-error-'),
    );

    try {
      expect(await build({ output: () => undefined }, outdir)).toBe(0);
      await writeFile(join(outdir, 'package.json'), '{"type":"module"}\n');

      for (const thrown of [
        "Object.assign(new Error('fixture failure'), { stack: 'private-stack-marker' })",
        "'fixture failure'",
      ]) {
        await writeFile(
          join(outdir, 'main.js'),
          `export function main() { throw ${thrown}; }\n`,
        );

        const result = spawnSync('node', [join(outdir, 'bin.js')], {
          encoding: 'utf8',
          stdio: ['ignore', 'pipe', 'pipe'],
          timeout: 5000,
        });

        expect(result.error).toBeUndefined();
        expect(result.signal).toBeNull();
        expect(result.status).toBe(1);
        expect(result.stdout).toBe('');
        expect(result.stderr).toBe('cursor-cloud-acp: fixture failure\n');
      }
    } finally {
      await rm(outdir, { recursive: true, force: true });
    }
  });

  test('rejects old versions before loading main and forwards arguments and exit status on supported versions', async () => {
    const outdir = await mkdtemp(join(tmpdir(), 'cursor-cloud-acp-node-'));

    try {
      expect(await build({ output: () => undefined }, outdir)).toBe(0);
      await writeFile(join(outdir, 'package.json'), '{"type":"module"}\n');
      await writeFile(
        join(outdir, 'main.js'),
        'export function main(args) { process.stdout.write(JSON.stringify(args)); return 7; }\n',
      );

      for (const version of ['21.99.0', '22.12.999', '22.13.0', '23.0.0']) {
        const accepted = version === '22.13.0' || version === '23.0.0';
        const result = spawnSync(
          'node',
          [
            '--input-type=module',
            '-e',
            `Object.defineProperty(process.versions, 'node', { value: ${JSON.stringify(version)} }); process.argv = ['node', 'bin.js', 'login', 'a b', '']; await import(${JSON.stringify(pathToFileURL(join(outdir, 'bin.js')).href)});`,
          ],
          {
            encoding: 'utf8',
            stdio: ['ignore', 'pipe', 'pipe'],
            timeout: 5000,
          },
        );

        expect(result.error).toBeUndefined();
        expect(result.signal).toBeNull();
        expect(result.status).toBe(accepted ? 7 : 1);
        expect(result.stdout).toBe(accepted ? '["login","a b",""]' : '');
        expect(result.stderr).toBe(
          accepted
            ? ''
            : `cursor-cloud-acp needs Node 22.13 or newer; this is Node ${version}.\n`,
        );
      }
    } finally {
      await rm(outdir, { recursive: true, force: true });
    }
  });
});

test('a main that rejects ends the built bin.js with one line and status 1, never a stack', async () => {
  const outdir = await mkdtemp(join(tmpdir(), 'cursor-cloud-acp-reject-'));

  try {
    expect(await build({ output: () => undefined }, outdir)).toBe(0);
    await writeFile(
      join(outdir, 'main.js'),
      "export function main() { return Promise.reject(new Error('Usage limit exceeded')); }\n",
    );

    const run = spawnSync(process.execPath, [join(outdir, 'bin.js')], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    expect(run.stderr).toBe('cursor-cloud-acp: Usage limit exceeded\n');
    expect(run.stdout).toBe('');
    expect(run.status).toBe(1);
  } finally {
    await rm(outdir, { recursive: true, force: true });
  }
});

test("build writes bin.js, whose only import is main's chunk, after Node's version is checked", async () => {
  const outdir = await mkdtemp(join(tmpdir(), 'cursor-cloud-acp-build-'));
  const lines: string[] = [];

  try {
    expect(await build({ output: (line) => lines.push(line) }, outdir)).toBe(0);
    expect(lines).toEqual([]);

    const bin = await readFile(join(outdir, 'bin.js'), 'utf8');

    expect(bin.startsWith('#!/usr/bin/env node\n')).toBe(true);
    expect(bin.match(/\bimport\b[^)]*\)/g)).toEqual(['import("./main.js")']);
    expect(bin.indexOf('process.exit(1)')).toBeLessThan(bin.indexOf('import('));
    expect((await readdir(outdir)).toSorted()).toEqual(['bin.js', 'main.js']);
  } finally {
    await rm(outdir, { recursive: true, force: true });
  }
});

test("tooOld refuses a Node below 22.13, naming it as the node found past Bun's", () => {
  expect(tooOld('v22.13.0')).toBeUndefined();
  expect(tooOld('v24.1.0')).toBeUndefined();
  expect(tooOld('v22.12.0')).toBe(
    "the smoke needs Node 22.13 or newer; v22.12.0 is the first node past Bun's on PATH",
  );
});

test('the tarball holds dist, README.md, LICENSE and package.json alone, as files names them', async () => {
  const manifest = JSON.parse(
    await readFile(join(here, 'package.json'), 'utf8'),
  ) as { files: string[] };

  expect(manifest.files).toEqual(['dist', 'README.md', 'LICENSE']);
  expect(PACKED).toEqual([
    'LICENSE',
    'README.md',
    'dist/bin.js',
    'dist/main.js',
    'package.json',
  ]);
});

describe('the smoke talks to its child as a client, and leaves none behind', () => {
  /** A child that answers each request as `answer` says, run by Bun. */
  const child = async (body: string) => {
    const dir = await mkdtemp(join(tmpdir(), 'cursor-cloud-acp-child-'));
    const file = join(dir, 'child.ts');

    await writeFile(
      file,
      `process.stdout.write(\`\${JSON.stringify({ jsonrpc: '2.0', method: 'started', params: { pid: process.pid } })}\\n\`);
${body}
`,
    );

    return { dir, argv: [process.execPath, file] };
  };

  const ANSWERS = `let buffered = '';
process.stdin.setEncoding('utf8').on('data', (chunk) => {
  buffered += chunk;
  const lines = buffered.split('\\n');
  buffered = lines.pop();
  for (const line of lines) {
    const { id } = JSON.parse(line);
    process.stdout.write(\`\${JSON.stringify({ jsonrpc: '2.0', id, result: { id } })}\\n\`);
  }
});`;

  test('answers both requests, every line JSON-RPC', async () => {
    const at = await child(ANSWERS);

    try {
      expect(await serveOnce(at.argv, at.dir, process.env)).toEqual([
        { jsonrpc: '2.0', id: 1, result: { id: 1 } },
        { jsonrpc: '2.0', id: 2, result: { id: 2 } },
      ]);
    } finally {
      await rm(at.dir, { recursive: true, force: true });
    }
  });

  test('a line of JSON that is not JSON-RPC fails it', async () => {
    const at = await child(
      `process.stdout.write('{"level":"info","msg":"hi"}\\n');\n${ANSWERS}`,
    );

    try {
      await expect(serveOnce(at.argv, at.dir, process.env)).rejects.toThrow(
        'a stdout line is not JSON-RPC: {"level":"info","msg":"hi"}',
      );
    } finally {
      await rm(at.dir, { recursive: true, force: true });
    }
  });

  test('a child that never answers is killed and reaped when the bound passes', async () => {
    const at = await child(
      `await Bun.write(${JSON.stringify('PID_FILE')}, String(process.pid));\nprocess.stdin.resume();`,
    );
    const pidFile = join(at.dir, 'pid');

    await writeFile(
      at.argv[1]!,
      (await readFile(at.argv[1]!, 'utf8')).replace('PID_FILE', pidFile),
    );

    try {
      await expect(
        serveOnce(at.argv, at.dir, process.env, 1500),
      ).rejects.toThrow('the adapter did not answer initialize within 1.5 s');

      const pid = Number(await readFile(pidFile, 'utf8'));

      expect(Number.isSafeInteger(pid) && pid > 0).toBe(true);
      expect(() => process.kill(pid, 0)).toThrow(
        expect.objectContaining({ code: 'ESRCH' }),
      );
    } finally {
      await rm(at.dir, { recursive: true, force: true });
    }
  });
});

describe('the smoke takes only JSON-RPC envelopes, and all of stdout', () => {
  const lines = (...json: string[]) =>
    `${json.map((each) => `process.stdout.write(${JSON.stringify(`${each}\n`)});`).join('\n')}`;

  test.each([
    ['no method, result or error', '{"jsonrpc":"2.0"}'],
    ['an id alone', '{"jsonrpc":"2.0","id":1}'],
  ])('%s is not JSON-RPC', async (_, envelope) => {
    const dir = await mkdtemp(join(tmpdir(), 'cursor-cloud-acp-env-'));
    const file = join(dir, 'child.ts');

    await writeFile(
      file,
      `${lines(envelope)}
let buffered = '';
process.stdin.setEncoding('utf8').on('data', (chunk) => {
  buffered += chunk;
  const parts = buffered.split('\\n');
  buffered = parts.pop();
  for (const line of parts) {
    const { id } = JSON.parse(line);
    process.stdout.write(\`\${JSON.stringify({ jsonrpc: '2.0', id: id + 10, result: {} })}\\n\`);
    process.stdout.write(\`\${JSON.stringify({ jsonrpc: '2.0', id, result: {} })}\\n\`);
  }
});`,
    );

    try {
      await expect(
        serveOnce([process.execPath, file], dir, process.env),
      ).rejects.toThrow(`a stdout line is not JSON-RPC: ${envelope}`);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  test('output left without its newline when the child ends fails it', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'cursor-cloud-acp-tail-'));
    const file = join(dir, 'child.ts');

    await writeFile(
      file,
      `let buffered = '';
process.stdin.setEncoding('utf8').on('data', (chunk) => {
  buffered += chunk;
  const parts = buffered.split('\\n');
  buffered = parts.pop();
  for (const line of parts) {
    const { id } = JSON.parse(line);
    process.stdout.write(\`\${JSON.stringify({ jsonrpc: '2.0', id, result: {} })}\\n\`);
  }
});
process.stdin.on('end', () => process.stdout.write('bye'));`,
    );

    try {
      await expect(
        serveOnce([process.execPath, file], dir, process.env),
      ).rejects.toThrow('stdout ended inside a line: bye');
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
