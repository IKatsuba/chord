import { expect, test } from 'bun:test';
import { formatModule } from '../../scripts/format.ts';

test('generated modules use the native formatter with the repository config', () => {
  expect(formatModule('export const value = "hi"')).toBe(
    "export const value = 'hi';\n",
  );
});

test('invalid generated TypeScript fails instead of returning partial output', () => {
  expect(() => formatModule('export const =')).toThrow('bun fmt failed');
});
