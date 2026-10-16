/**
 * Loaded ahead of every test file (bunfig.toml): chalk's colour off, as it
 * is when stdout is not a terminal, so a test reads the same frame in CI and
 * in a person's terminal. A test that checks colour sets the level itself.
 */
import chalk from 'chalk';

chalk.level = 0;

// bun test --parallel run from a terminal sets FORCE_COLOR=1 for its
// workers, and every process a test starts inherits it, so Bun's
// console.error there paints what a test reads off stderr red.
delete process.env['FORCE_COLOR'];
