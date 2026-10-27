/** Scripted public Codex peer; tests never start an installed provider. */
import split from 'split2';
import process from 'node:process';
import { spawn } from 'node:child_process';
import { writeFileSync, appendFileSync } from 'node:fs';

declare const RESOURCE_FIXTURE_COMPILED: boolean;

if (process.argv.includes('--resource-descendant')) {
  process.on('SIGTERM', () => {});

  setInterval(() => {}, 1000);

  await new Promise(() => {});
}

if (process.argv.includes('--version')) {
  process.stdout.write('codex-cli 0.163.0\n');
  process.exit(0);
}

const args = process.argv.slice(2);

if (args[0] === 'app-server') {
  args.shift();
}

const scenario =
  process.env.CHORD_FAKE_RESOURCE_SCENARIO ?? args[0] ?? 'normal';
const record = process.env.CHORD_FAKE_RESOURCE_RECORD ?? args[1];

if (record !== undefined) {
  writeFileSync(record, JSON.stringify({ pid: process.pid }) + '\n');
}

if (scenario === 'stubborn') {
  process.on('SIGTERM', () => {
    if (record !== undefined) {
      appendFileSync(
        record,
        JSON.stringify({ signal: 'SIGTERM', ignored: true }) + '\n',
      );
    }
  });

  const compiled =
    typeof RESOURCE_FIXTURE_COMPILED !== 'undefined' &&
    RESOURCE_FIXTURE_COMPILED;
  const child = spawn(
    process.execPath,
    [
      ...(compiled
        ? []
        : [new URL('./resource_provider.ts', import.meta.url).pathname]),
      '--resource-descendant',
    ],
    { stdio: 'ignore' },
  );

  if (record !== undefined) {
    appendFileSync(record, JSON.stringify({ descendant: child.pid }) + '\n');
  }
}

if (scenario === 'term') {
  process.on('SIGTERM', () => {
    if (record !== undefined) {
      appendFileSync(record, JSON.stringify({ signal: 'SIGTERM' }) + '\n');
    }

    process.exit(0);
  });
}

process.stdin.pipe(split()).on('data', (line: string) => {
  const request = JSON.parse(line) as {
    id?: number;
    method: string;
    params?: unknown;
  };

  if (record !== undefined) {
    appendFileSync(
      record,
      JSON.stringify({ method: request.method, params: request.params }) + '\n',
    );
  }

  if (request.id === undefined) {
    return;
  }

  if (scenario === 'crash') {
    process.exit(3);
  }

  if (
    scenario === 'timeout' ||
    scenario === 'stubborn' ||
    scenario === 'term'
  ) {
    return;
  }

  const window = {
    usedPercent: 12.345,
    windowDurationMins: 60,
    resetsAt: null,
  };
  const bucket = {
    primary: window,
    secondary: null,
    credits: null,
    planType: null,
    limitId: null,
    limitName: null,
  };
  const result =
    request.method === 'initialize'
      ? { userAgent: 'fake' }
      : request.method === 'account/read'
        ? {
            account: {
              type: scenario === 'api-account' ? 'apiKey' : 'chatgpt',
              email: 'excluded@example.test',
              planType: 'pro',
            },
            requiresOpenaiAuth: false,
          }
        : {
            rateLimits: bucket,
            rateLimitsByLimitId: { one: bucket, two: bucket },
          };

  process.stdout.write(JSON.stringify({ id: request.id, result }) + '\n');
});

process.stdin.on('end', () => {
  if (scenario !== 'stubborn' && scenario !== 'term') {
    process.exit(0);
  }
});

if (scenario === 'stubborn' || scenario === 'timeout' || scenario === 'term') {
  setInterval(() => {}, 1000);
}
