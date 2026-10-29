import { expect, test } from 'bun:test';
import {
  layoutRows,
  overlayRoom,
  overlayRule,
  pickerRows,
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

test("a framed picker's list keeps its own limit until its frame and hint would leave the room, and one row at least (CHD-545)", () => {
  expect(pickerRows(6, 19)).toBe(6);
  expect(pickerRows(6, 12)).toBe(6);
  expect(pickerRows(6, 10)).toBe(4);
  expect(pickerRows(6, 3)).toBe(1);
});

test('a picker laid out by the window is told its height until the layer has less (CHD-545)', () => {
  expect(layoutRows(19, 24)).toBe(24);
  expect(layoutRows(35, 40)).toBe(40);
  expect(layoutRows(12, 24)).toBe(17);
});
