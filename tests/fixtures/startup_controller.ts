/** Owns only the fixture CLI child; tmux pane state is not its exit receipt. */
import { spawn } from 'node:child_process';
import { renameSync, writeFileSync } from 'node:fs';

const [receipt, ownership, executable, ...args] = process.argv.slice(2);

if (!receipt || !ownership || !executable) {
  throw new Error('Expected receipt, ownership and target command');
}

const target = spawn(executable, args, { stdio: 'inherit' });
let error: string | null = null;
let stopping: ReturnType<typeof setTimeout> | undefined;
const save = (path: string, value: unknown) => {
  const pending = `${path}.pending`;

  writeFileSync(pending, JSON.stringify(value));
  renameSync(pending, path);
};

const stop = () => {
  target.kill('SIGTERM');

  stopping ??= setTimeout(() => target.kill('SIGKILL'), 1_000);
};

target.once('error', (failure) => {
  error = String(failure);

  save(`${receipt}.error`, { error, controllerPid: process.pid });
});

target.once('exit', (code, signal) => {
  clearTimeout(stopping);
  save(receipt, {
    targetPid: target.pid,
    controllerPid: process.pid,
    code,
    signal,
    error,
  });

  process.exitCode = code ?? 1;
});

process.on('SIGTERM', stop);
process.on('SIGINT', stop);
process.on('SIGHUP', stop);

try {
  save(ownership, { targetPid: target.pid, controllerPid: process.pid });
} catch (failure) {
  stop();

  process.stderr.write(`${String(failure)}\n`);

  process.exitCode = 1;
}
