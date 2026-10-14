import { expect, test } from 'bun:test';
import {
  pointed,
  type Pointer,
  type Pointing,
  selectHint,
} from '../../../src/ui/app/drag.ts';

const event = (type: string, x: number, y: number, button = 0): Pointing => ({
  type,
  button,
  x,
  y,
});

/** Whether each event in turn ended a drag. */
function play(events: readonly Pointing[]): boolean[] {
  let pointer: Pointer = {};

  return events.map((each) => {
    const read = pointed(pointer, each);

    pointer = read.pointer;

    return read.dragged;
  });
}

test('the hint names the terminal own modifier', () => {
  expect(selectHint({ termProgram: 'iTerm.app', tmux: false })).toStrictEqual(
    'option + drag to select text',
  );
  expect(
    selectHint({ termProgram: 'tmux', lcTerminal: 'iTerm2', tmux: true }),
  ).toStrictEqual('option + drag to select text');
  expect(
    selectHint({ termProgram: 'Apple_Terminal', tmux: false }),
  ).toStrictEqual('fn + drag to select text');

  for (const termProgram of ['WezTerm', 'ghostty', 'vscode', undefined]) {
    expect(selectHint({ termProgram, tmux: false })).toStrictEqual(
      'shift + drag to select text',
    );
  }
});

test('clicks, moves, the wheel and other buttons are no drag', () => {
  expect(
    play([
      event('scroll', 1, 1),
      event('down', 4, 4),
      event('up', 4, 4),
      event('down', 4, 4, 2),
      event('up', 9, 9, 2),
      event('move', 5, 5),
      event('over', 6, 6),
    ]),
  ).toStrictEqual(Array(7).fill(false));
});

test('the left button let go on another cell is a drag', () => {
  expect(
    play([
      event('down', 4, 4),
      event('drag', 5, 4),
      event('up', 9, 4),
      // OpenTUI's second hearing of the same release, with no press left.
      event('up', 9, 4),
      event('down', 1, 1),
      event('up', 1, 2),
    ]),
  ).toStrictEqual([false, false, true, false, false, true]);
});
