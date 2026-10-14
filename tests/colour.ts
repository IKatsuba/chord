/**
 * Loaded ahead of every test file (bunfig.toml): chalk's colour off, as it
 * is when stdout is not a terminal, so a test reads the same frame in CI and
 * in a person's terminal. A test that checks colour sets the level itself.
 */
import chalk from 'chalk';

chalk.level = 0;
