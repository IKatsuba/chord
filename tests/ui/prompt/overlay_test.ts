import { expect, test } from 'bun:test';
import { overlayRoom, overlayRule } from '../../../src/ui/prompt/overlay.ts';

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
