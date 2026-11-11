/**
 * The fake MCP server on stdio, for riff's tests: `ok`, `badname`, `crash`
 * (says why on stderr and exits before it answers) or `hang` (never
 * answers). When `PID_FILE` is set, it writes its pid there, so a test can
 * see it gone; `CALLS_FILE` gets a line per call of `save_note`; with
 * `BLOCK_FILE`, a call publishes the server's pid there and never answers.
 */
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { appendFileSync, renameSync, writeFileSync } from 'node:fs';
import process from 'node:process';
import { fakeMcpServer, type FakeMcpMode } from './fake_mcp.ts';

const mode = process.argv[2] ?? 'ok';
const pidFile = process.env['PID_FILE'];
const callsFile = process.env['CALLS_FILE'];
const blockFile = process.env['BLOCK_FILE'];

const calls = async (title: string) => {
  if (callsFile !== undefined) {
    appendFileSync(callsFile, `${title}\n`);
  }

  if (blockFile !== undefined) {
    // Published whole, so the test never reads half a file.
    writeFileSync(`${blockFile}.tmp`, String(process.pid));
    renameSync(`${blockFile}.tmp`, blockFile);
    await new Promise<never>(() => {});
  }
};

if (pidFile !== undefined) {
  writeFileSync(pidFile, String(process.pid));
}

if (mode === 'crash') {
  process.stderr.write('starting notes\nnotes: no database at ./notes.db\n');
  process.exit(3);
}

if (mode === 'hang') {
  // Reads nothing and stays until it is ended.
  setInterval(() => {}, 60_000);
} else {
  await fakeMcpServer('notes', mode as FakeMcpMode, calls).connect(
    new StdioServerTransport(),
  );
}
