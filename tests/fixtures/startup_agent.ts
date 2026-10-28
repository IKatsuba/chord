/** A fake ACP process with an explicit start log for CLI boundary checks. */
import { appendFileSync } from 'node:fs';

const log = process.env['CHORD_START_LOG'];

if (log) {
  appendFileSync(log, `${process.pid}\n`);
}

await import('./fake_agent/main.ts');
