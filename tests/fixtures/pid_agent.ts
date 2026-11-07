/**
 * The fake agent, leaving its pid in the file its first argument names: its
 * process group's id, which a test spawning chord has no other way to learn.
 */
import { writeFileSync } from 'node:fs';
import process from 'node:process';

writeFileSync(process.argv[2] ?? '', String(process.pid));

await import('./fake_agent/main.ts');
