#!/usr/bin/env node
// Fake the public npm launcher's unchanged spawn/inherit/signal/exit contract.
// The provider binary is a test fixture; no installed provider is reached.
import { spawn } from 'node:child_process';
import process from 'node:process';

const child = spawn(
  process.env.CHORD_FAKE_RESOURCE_NATIVE,
  process.argv.slice(2),
  {
    stdio: 'inherit',
    env: process.env,
  },
);

for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
  process.on(signal, () => child.kill(signal));
}

child.on('error', () => process.exit(1));
child.on('exit', (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
  } else {
    process.exit(code ?? 1);
  }
});
