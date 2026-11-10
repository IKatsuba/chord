/** Fixture programs for direct execution; never an agent or resource provider. */
import { spawn } from 'node:child_process';
import process from 'node:process';

if (import.meta.main) {
  const mode = process.argv[2];

  if (mode === 'descendant') {
    const child = spawn('/bin/sleep', ['60'], { stdio: 'ignore' });

    process.on('SIGTERM', () => {});

    process.stdout.write(`${child.pid}\n`);
    setInterval(() => {}, 1000);
  } else if (mode === 'output') {
    process.stdout.write('x'.repeat(Number(process.argv[3])));
  } else if (mode === 'stderr') {
    process.stderr.write('x'.repeat(Number(process.argv[3])));
  } else if (mode === 'environment') {
    process.stdout.write(JSON.stringify(process.env));
  }
}
