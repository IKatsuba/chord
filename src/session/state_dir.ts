import { join } from 'node:path';
import { xdgState } from 'xdg-basedir';

/**
 * Where chord keeps its state: the session records under `records/`. The
 * window records 0.54.0 to 0.57.0 wrote under `windows/` are left alone (Q179).
 */
export function chordStateDir(): string {
  if (!xdgState) {
    throw new Error("No home directory to keep chord's state in.");
  }

  return join(xdgState, 'chord');
}
