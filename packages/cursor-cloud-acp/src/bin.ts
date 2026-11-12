#!/usr/bin/env node
/**
 * The package's command. It checks Node's version before importing anything,
 * so an older Node gets one line on stderr rather than a syntax error from a
 * dependency (`@cursor/sdk` needs 22.13). Kept to syntax any Node parses.
 */
const [major = 0, minor = 0] = process.versions.node.split('.').map(Number);

if (major < 22 || (major === 22 && minor < 13)) {
  process.stderr.write(
    `cursor-cloud-acp needs Node 22.13 or newer; this is Node ${process.versions.node}.\n`,
  );
  process.exit(1);
}

// No top-level await, so a Node too old for it still parses this file and
// prints the line above.
void import('./main.ts')
  .then(({ main }) => main(process.argv.slice(2)))
  .then(
    (status) => {
      process.exitCode = status;
    },
    // One line, never a stack: an SDK error's is its minified bundle.
    (error) => {
      process.stderr.write(
        `cursor-cloud-acp: ${error instanceof Error ? error.message : String(error)}\n`,
      );

      process.exitCode = 1;
    },
  );
