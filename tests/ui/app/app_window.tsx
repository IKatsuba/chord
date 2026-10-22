/**
 * The steps the window's tests share: `App_test.tsx` and the files split
 * from it (CHD-501).
 */
import { type Window } from './render.tsx';

export const OSC9 = {
  channel: 'osc9',
  env: { termProgram: 'iTerm.app', tmux: false },
} as const;

/** The writes to stdout that carry `bytes`. */
export function writes(window: Window, bytes: string): number {
  return window.written().filter((written) => written.startsWith(bytes)).length;
}

/** The rows `/name` reported, from its line to the end of its block. */
export async function reported(window: Window, name: string): Promise<string> {
  await window.type(name);
  await window.press('\r');
  await window.shows(`› ${name}`);

  const lines = window.frame().split('\n');
  const at = lines.findLastIndex((line) => line.includes(`› ${name}`));
  const block = lines.slice(at + 1);
  const end = block.findIndex((line) => line.trim() === '');

  return block.slice(0, end < 0 ? undefined : end).join('\n');
}
