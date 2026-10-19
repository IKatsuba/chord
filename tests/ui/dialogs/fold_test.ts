import { expect, test } from 'bun:test';
import { foldOf, moreLines } from '../../../src/ui/dialogs/fold.ts';

test('a held box fits whole where it can, else folds from the bottom under a line that counts the rest', () => {
  expect(foldOf(12, 20)).toStrictEqual({ shown: 12, more: 0 });
  expect(foldOf(12, 12)).toStrictEqual({ shown: 12, more: 0 });
  // The count takes a row of its own.
  expect(foldOf(12, 11)).toStrictEqual({ shown: 10, more: 2 });
  expect(foldOf(12, 1)).toStrictEqual({ shown: 0, more: 12 });
  expect(foldOf(12, 0)).toStrictEqual({ shown: 0, more: 12 });
  expect(moreLines(1)).toBe('… 1 more line');
  expect(moreLines(3)).toBe('… 3 more lines');
});
