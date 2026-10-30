import { expect, test } from 'bun:test';
import {
  overlayRoom,
  overlayRule,
  framedRows,
} from '../../../src/ui/prompt/overlay.ts';

test('the layer over the transcript may take every row above its edge, and none above the window (CHD-545)', () => {
  expect(overlayRoom(19)).toBe(19);
  expect(overlayRoom(0)).toBe(0);
  expect(overlayRoom(-2)).toBe(0);
  expect(overlayRoom(7.6)).toBe(7);
});

test("a frameless list's rule runs the width it is given (CHD-545)", () => {
  expect(overlayRule(4)).toBe('────');
  expect(overlayRule(0)).toBe('');
  expect(overlayRule(-1)).toBe('');
});

test("a framed picker's list keeps its own limit until its frame and hint would leave the room, and goes where not one row fits (CHD-545)", () => {
  // Seven rows around the list: frame, title, description, two gaps, hint.
  expect(framedRows(6, 19, 2)).toBe(6);
  expect(framedRows(6, 13, 2)).toBe(6);
  expect(framedRows(6, 12, 2)).toBe(5);
  expect(framedRows(6, 8, 1)).toBe(1);
  // A row for one of two, and one to count the other: nine.
  expect(framedRows(6, 8, 2)).toBe(0);
  expect(framedRows(6, 7, 2)).toBe(0);
  expect(framedRows(6, 3, 2)).toBe(0);
});

test('hidden choices take the row that counts them, and a wrapped description its rows (CHD-545)', () => {
  // Ten choices in six rows: the count row is the eighth around them.
  expect(framedRows(6, 19, 10)).toBe(6);
  expect(framedRows(6, 12, 10)).toBe(4);
  // As many choices as rows: none hidden, no count row.
  expect(framedRows(6, 12, 5)).toBe(5);
  expect(framedRows(6, 12, 2, 2)).toBe(3);
  expect(framedRows(3, 9, 10)).toBe(1);
});
