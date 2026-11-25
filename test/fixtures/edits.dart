// The texts the fake agent's `edit` and `rewrite` scenarios edit, as the
// original's tests/fixtures/edits.ts has them.

/// `edit`'s file before.
const editOld =
    'export function greet(name: string): string {\n'
    '  return "hello " + name;\n'
    '}\n';

/// `edit`'s file after.
const editNew =
    '/** Greets someone by name. */\n'
    'export function greet(name: string): string {\n'
    r'  return `hello, ${name}`;'
    '\n'
    '}\n';

/// Sixty rows of a table, so one edit to it runs to several hunks.
final List<String> _table = [
  for (var row = 0; row < 60; row++)
    "  { id: ${row + 1}, name: 'row ${row + 1}' },",
];

/// `rewrite`'s file before.
final String rewriteOld = [
  'export const table = [',
  ..._table,
  '];',
  '',
].join('\n');

/// `rewrite`'s file after.
final String rewriteNew = [
  'export const table = [',
  ..._table.sublist(0, 4),
  for (final line in _table.sublist(4, 12)) line.replaceFirst('row', 'entry'),
  ..._table.sublist(12, 30),
  "  { id: 31, name: 'a row whose name runs well past the edge of a narrow "
      "terminal window' },",
  ..._table.sublist(31, 50),
  ..._table.sublist(52),
  '];',
  '',
].join('\n');
