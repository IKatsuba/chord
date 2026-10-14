import { join } from 'node:path';
import { xdgState } from 'xdg-basedir';

/**
 * Where chord keeps its state: the session records under `records/`, the
 * window records under `windows/`.
 */
export function chordStateDir(): string {
  if (!xdgState) {
    throw new Error("No home directory to keep chord's state in.");
  }

  return join(xdgState, 'chord');
}
