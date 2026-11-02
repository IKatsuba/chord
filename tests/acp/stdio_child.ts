// Stands for chord's stdout under a test: real pipes, this process's own
// stdin and stdout, and what it sees of them on stderr.
import process from 'node:process';
import { Readable } from 'node:stream';
import { outputStream } from '../../src/acp/stdio.ts';

const MIB = 1024 * 1024;
const writer = outputStream(process.stdout).getWriter();

if (process.argv[2] === 'blocked') {
  // One write larger than any pipe holds, with nobody reading it.
  void writer.write(new Uint8Array(4 * MIB).fill(120)).then(() => {
    process.stderr.write('written\n');
  });

  // The loop runs on: each tick says so, while the write stays pending.
  setInterval(() => process.stderr.write('tick\n'), 5);

  const reader = (
    Readable.toWeb(process.stdin) as unknown as ReadableStream<Uint8Array>
  ).getReader();

  while (!(await reader.read()).done) {
    // Input is read to its end, which is all that is asked of it here.
  }

  process.stderr.write('eof\n');
  process.exit(0);
} else {
  await writer.write(new Uint8Array(MIB).fill(120));

  process.exit(0);
}
