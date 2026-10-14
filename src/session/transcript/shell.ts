/**
 * A bash-mode command's run, the one entry no turn asked for: started, fed
 * its output up to the limit, ended, or carried whole by a resumed session's
 * prompt.
 */
import { OUTPUT_LIMIT } from '../context.ts';
import type { ShellRun, Transcript, TranscriptAction } from './types.ts';

export function shellStarted(
  state: Transcript,
  turnId: string,
  command: string,
): Transcript {
  return {
    ...state,
    entries: [
      ...state.entries,
      {
        kind: 'shell',
        turnId,
        run: {
          command,
          stdout: '',
          stderr: '',
          running: true,
        },
      },
    ],
  };
}

export function shellReplayed(
  state: Transcript,
  turnId: string,
  run: ShellRun,
): Transcript {
  return {
    ...state,
    entries: [
      ...state.entries,
      {
        kind: 'shell',
        turnId,
        run,
      },
    ],
  };
}

export function shellOutput(
  state: Transcript,
  turnId: string,
  stream: 'stdout' | 'stderr',
  text: string,
): Transcript {
  return updateShell(state, turnId, (run) => {
    const kept = run[stream];
    const room = OUTPUT_LIMIT - kept.length;

    if (room <= 0) {
      return run.truncated ? run : { ...run, truncated: true };
    }

    return {
      ...run,
      [stream]: kept + text.slice(0, room),
      ...(text.length > room ? { truncated: true } : {}),
    };
  });
}

export function shellEnded(
  state: Transcript,
  action: Extract<TranscriptAction, { type: 'shell_ended' }>,
): Transcript {
  const { code, stopped, error } = action;

  return updateShell(state, action.turnId, (run) => ({
    ...run,
    running: false,
    ...(code === undefined ? {} : { code }),
    ...(stopped ? { stopped } : {}),
    ...(error === undefined ? {} : { error }),
  }));
}

/**
 * The run `id` changed by `change`; a run the transcript no longer has, as
 * after `/clear`, changes nothing.
 */
function updateShell(
  state: Transcript,
  id: string,
  change: (run: ShellRun) => ShellRun,
): Transcript {
  const index = state.entries.findIndex(
    (entry) => entry.kind === 'shell' && entry.turnId === id,
  );
  const entry = state.entries[index];

  if (entry?.kind !== 'shell' || !entry.run.running) {
    return state;
  }

  const entries = [...state.entries];

  entries[index] = { ...entry, run: change(entry.run) };

  return { ...state, entries };
}
