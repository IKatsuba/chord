/**
 * Loaded ahead of every test file (bunfig.toml): fixture resources stay
 * selected in child processes, and chalk's colour is off so a test reads
 * the same frame in CI and in a person's terminal. Colour tests opt in.
 */
import chalk from 'chalk';

// Spawned test processes inherit the same fixture boundary as fake/QA runs.
process.env['CHORD_RESOURCE_FIXTURE'] = 'true';

chalk.level = 0;

// bun test --parallel run from a terminal sets FORCE_COLOR=1 for its
// workers, and every process a test starts inherits it, so Bun's
// console.error there paints what a test reads off stderr red.
delete process.env['FORCE_COLOR'];
