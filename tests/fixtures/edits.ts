/** The texts the fake agent's `edit` and `rewrite` scenarios edit. */
export const EDIT_OLD = [
  'export function greet(name: string): string {',
  '  return "hello " + name;',
  '}',
  '',
].join('\n');

export const EDIT_NEW = [
  '/** Greets someone by name. */',
  'export function greet(name: string): string {',
  '  return `hello, ${name}`;',
  '}',
  '',
].join('\n');

/** Sixty rows of a table, so one edit to it runs to several hunks. */
const TABLE = Array.from(
  { length: 60 },
  (_, row) => `  { id: ${row + 1}, name: 'row ${row + 1}' },`,
);

export const REWRITE_OLD = ['export const table = [', ...TABLE, '];', ''].join(
  '\n',
);

export const REWRITE_NEW = [
  'export const table = [',
  ...TABLE.slice(0, 4),
  ...TABLE.slice(4, 12).map((line) => line.replace('row', 'entry')),
  ...TABLE.slice(12, 30),
  `  { id: 31, name: 'a row whose name runs well past the edge of a narrow terminal window' },`,
  ...TABLE.slice(31, 50),
  ...TABLE.slice(52),
  '];',
  '',
].join('\n');
