/**
 * A drag in the window, which the terminal no longer selects for while
 * chord reads the mouse, and what the status line says after one: the
 * modifier that makes the terminal select past chord's reading.
 */
import type { TerminalEnv } from '../../notify.ts';

/** What the left button's press left to be read with its release. */
export interface Pointer {
  /** The cell the left button went down on, until it comes up. */
  readonly pressed?: { readonly x: number; readonly y: number };
}

/** Of OpenTUI's mouse event, what tells a drag. */
export interface Pointing {
  readonly type: string;
  /** 0 is the left button. */
  readonly button: number;
  readonly x: number;
  readonly y: number;
}

/**
 * `event` read after `pointer`: the pointer it leaves, and whether it ended
 * a drag, the left button let go on another cell than it went down on.
 * OpenTUI may hear one release twice, the second time with no press left.
 */
export function pointed(
  pointer: Pointer,
  event: Pointing,
): { pointer: Pointer; dragged: boolean } {
  if (event.button !== 0 || (event.type !== 'down' && event.type !== 'up')) {
    return { pointer, dragged: false };
  }

  if (event.type === 'down') {
    return { pointer: { pressed: { x: event.x, y: event.y } }, dragged: false };
  }

  const { pressed } = pointer;

  return {
    pointer: {},
    dragged:
      pressed !== undefined && (pressed.x !== event.x || pressed.y !== event.y),
  };
}

/**
 * What the status line says after a drag: the modifier that makes this
 * terminal select. iTerm2 names itself in `LC_TERMINAL` too, which survives
 * tmux and ssh.
 */
export function selectHint(env: TerminalEnv): string {
  if (env.termProgram === 'iTerm.app' || env.lcTerminal === 'iTerm2') {
    return 'option + drag to select text';
  }

  if (env.termProgram === 'Apple_Terminal') {
    return 'fn + drag to select text';
  }

  return 'shift + drag to select text';
}
