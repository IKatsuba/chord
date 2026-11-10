/** A real riff child with only QA stores/fetches, for session/window checks. */
import { join } from 'node:path';
import process from 'node:process';

process.env.CHORD_RIFF_FAKE_PROVIDER = 'http://localhost:1/v1';
process.env.CHORD_RIFF_QA = '1';
process.env.CHORD_RIFF_QA_STATE = process.argv[2] ?? 'signed-in';
process.env.CHORD_RIFF_QA_STORE = process.argv[3] ?? 'linux';
process.env.CHORD_RIFF_QA_PROVIDER = process.argv[4] ?? 'codex';
process.env.XDG_STATE_HOME = join(process.cwd(), '.fixture-state');
process.env.XDG_CONFIG_HOME = join(process.cwd(), '.fixture-config');

const { runRiffAgent } = await import('../../../src/riff/serve.ts');
const { riffAccess } = await import('../../../src/riff/qa.ts');
const access = riffAccess(process.env, () => {
  throw new Error('Real credential store selected in a QA fixture.');
});

await runRiffAgent('fixture', access);
