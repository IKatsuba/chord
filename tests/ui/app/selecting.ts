/** Helpers the selection tests share: where text is, and a clipboard. */
import assert from 'node:assert/strict';
import type { ClipboardWriteResult } from '@opentui/core';
import stripAnsi from 'strip-ansi';
import type { Copy } from '../../../src/ui/app/selection.ts';
import { copiedStub, left, type Window } from './render.tsx';

/** Where `text` is on screen: its first cell and its last, 0-based. */
export function cellsOf(window: Window, text: string) {
  const rows = stripAnsi(window.frame()).split('\n');
  const y = rows.findIndex((row) => row.includes(text));

  assert(y >= 0, `"${text}" is not on screen`);

  const x = rows[y]!.indexOf(text);

  return { x, y, end: x + text.length - 1 };
}

/** A drag over `text`, on one row, from its first cell to its last. */
export async function dragOver(window: Window, text: string): Promise<void> {
  const { x, y, end } = cellsOf(window, text);

  await window.press(left(x, y, 'down'));
  await window.press(left(end, y, 'drag'));
  await window.press(left(end, y, 'up'));
}

export const REPLY = 'This reply came in chunks.';

export const NOT_ATTEMPTED = {
  status: 'not-attempted',
  capability: 'unknown',
} as const;

/** A clipboard that answers each copy with the next of `answers`, kept. */
export function clipboard(...answers: (() => Promise<ClipboardWriteResult>)[]) {
  const copies: { text: string; signal: AbortSignal }[] = [];
  const copy: Copy = (text, signal) => {
    copies.push({ text, signal });

    return (answers.shift() ?? (() => copiedStub(text, signal)))();
  };

  return { copies, copy };
}

export const answered = (result: ClipboardWriteResult) => () =>
  Promise.resolve(result);
