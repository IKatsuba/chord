/**
 * The fake agent's flags and the environment variables beside them, read once
 * at start. Here rather than in `main.ts` because the scenarios read them too,
 * and `main.ts` imports the scenarios.
 */
import process from 'node:process';

/** The flags after the script, as the runtime was given them. */
export const ARGS = process.argv.slice(2);

export const RESUME_ONLY = ARGS.includes('--resume-only');

export const NO_USAGE =
  ARGS.includes('--no-usage') || process.env.CHORD_FAKE_NO_USAGE === '1';

export const TOKENS_ONLY =
  ARGS.includes('--tokens-only') || process.env.CHORD_FAKE_TOKENS_ONLY === '1';

export const NO_IMAGES =
  ARGS.includes('--no-images') || process.env.CHORD_FAKE_NO_IMAGES === '1';

export const NO_HTTP =
  ARGS.includes('--no-http') || process.env.CHORD_FAKE_NO_HTTP === '1';

export const NO_CONFIG =
  ARGS.includes('--no-config') || process.env.CHORD_FAKE_NO_CONFIG === '1';

export const NO_MODES =
  ARGS.includes('--no-modes') || process.env.CHORD_FAKE_NO_MODES === '1';

const HANGS = ['start', 'config', 'turn'] as const;

function hangStep(): (typeof HANGS)[number] | undefined {
  const flag = ARGS.indexOf('--hang');
  const chosen = flag >= 0 ? ARGS[flag + 1] : process.env.CHORD_FAKE_HANG;

  if (chosen === undefined) {
    return undefined;
  }

  if (!HANGS.includes(chosen as (typeof HANGS)[number])) {
    throw new Error(`unknown step to hang at "${chosen}"`);
  }

  return chosen as (typeof HANGS)[number];
}

export const HANG = hangStep();

export const PLAN_CAPABILITY_ONLY =
  ARGS.includes('--plan-capability-only') ||
  process.env.CHORD_FAKE_PLAN_CAPABILITY_ONLY === '1';

export const SILENT_SET_MODE =
  ARGS.includes('--silent-set-mode') ||
  process.env.CHORD_FAKE_SILENT_SET_MODE === '1';

const STEERINGS = ['claude', 'codex'] as const;

function steeringAdapter(): (typeof STEERINGS)[number] | undefined {
  const flag = ARGS.indexOf('--steering');
  const chosen = flag >= 0 ? ARGS[flag + 1] : process.env.CHORD_FAKE_STEERING;

  if (chosen === undefined) {
    return undefined;
  }

  if (!STEERINGS.includes(chosen as (typeof STEERINGS)[number])) {
    throw new Error(`unknown adapter to steer as "${chosen}"`);
  }

  return chosen as (typeof STEERINGS)[number];
}

/**
 * The adapter whose `_session/steering` the fake answers as, `claude` or
 * `codex`; none by default, when it neither advertises nor takes it.
 */
export const STEERING = steeringAdapter();

/**
 * A steer lands only once the turn playing has ended, as one sent just as a
 * turn ends does: Claude's adapter then refuses it, Codex's starts a turn of
 * its own with it.
 */
export const STEER_LATE =
  ARGS.includes('--steer-late') || process.env.CHORD_FAKE_STEER_LATE === '1';

export const REFUSE_CONFIG =
  ARGS.includes('--refuse-config') ||
  process.env.CHORD_FAKE_REFUSE_CONFIG === '1';

/**
 * Long enough that chunks arrive as separate events, short enough to keep
 * tests fast. `--step-ms <ms>` or `CHORD_FAKE_STEP_MS` sets it, and every
 * scenario's pace with it.
 */
export const STEP_MS = Number(
  (ARGS.includes('--step-ms')
    ? ARGS[ARGS.indexOf('--step-ms') + 1]
    : undefined) ??
    process.env.CHORD_FAKE_STEP_MS ??
    '5',
);
