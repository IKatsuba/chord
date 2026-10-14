import { expect, test } from 'bun:test';
import {
  editedQuery,
  emptySearch,
  foundPieces,
  matched,
  queryPattern,
  type Search,
  searched,
  searchedOlder,
  searchLabel,
} from '../../../src/ui/prompt/search.ts';

const PROMPTS = [
  'fix the login bug in auth.ts',
  'explain the auth flow',
  '!echo auth ok',
  'explain the auth flow',
  'what is next',
];

function typed(query: string): Search {
  return searched(emptySearch, PROMPTS, query);
}

test('a query finds the newest prompt that contains it', () => {
  expect(matched(typed('auth'), PROMPTS)).toStrictEqual(
    'explain the auth flow',
  );
  // A prompt sent twice counts where it was sent last.
  expect(typed('auth').match).toStrictEqual(3);
  expect(matched(typed('next'), PROMPTS)).toStrictEqual('what is next');
  // Plain substring, case and all, as in Claude Code.
  expect(typed('AUTH').match).toStrictEqual(undefined);
});

test('an empty query finds nothing, and the box keeps the draft', () => {
  expect(typed('')).toStrictEqual(emptySearch);
  expect(matched(emptySearch, PROMPTS)).toStrictEqual(undefined);
  expect(searchedOlder(emptySearch, PROMPTS)).toStrictEqual(emptySearch);
});

test('ctrl+r steps to older matches, past a repeat already shown', () => {
  const first = typed('auth');
  const second = searchedOlder(first, PROMPTS);
  const third = searchedOlder(second, PROMPTS);

  expect(matched(second, PROMPTS)).toStrictEqual('!echo auth ok');
  // The earlier `explain the auth flow` is the one already seen.
  expect(matched(third, PROMPTS)).toStrictEqual('fix the login bug in auth.ts');
  expect(third.failed).toStrictEqual(false);
});

test('past the oldest match the search fails and keeps what it found', () => {
  const oldest = searchedOlder(searchedOlder(typed('auth'), PROMPTS), PROMPTS);
  const past = searchedOlder(oldest, PROMPTS);

  expect(past.failed).toStrictEqual(true);
  expect(past.match).toStrictEqual(oldest.match);
  expect(searchLabel(past)).toStrictEqual('no matching prompt:');
  expect(searchedOlder(past, PROMPTS)).toStrictEqual(past);
});

test('typing on starts from the newest again; a miss keeps the last match', () => {
  const stepped = searchedOlder(typed('auth'), PROMPTS);
  const narrowed = searched(stepped, PROMPTS, 'auth f');
  const missed = searched(narrowed, PROMPTS, 'auth fz');

  expect(matched(narrowed, PROMPTS)).toStrictEqual('explain the auth flow');
  expect(missed.failed).toStrictEqual(true);
  expect(missed.match).toStrictEqual(narrowed.match);
  expect(searchLabel(narrowed)).toStrictEqual('search prompts:');
  // Deleting back to a query that matches finds again.
  expect(searched(missed, PROMPTS, 'auth f').failed).toStrictEqual(false);
  // Deleting it all leaves the draft.
  expect(searched(missed, PROMPTS, '')).toStrictEqual(emptySearch);
});

test('a command is found by its ! too', () => {
  expect(matched(typed('!'), PROMPTS)).toStrictEqual('!echo auth ok');
  expect(searched(emptySearch, [], 'x').failed).toStrictEqual(true);
});

test('keys edit the query; ctrl chords and control characters do not', () => {
  const plain = { ctrl: false };

  expect(editedQuery('au', 't', plain)).toStrictEqual('aut');
  expect(
    editedQuery('aut', '', { ctrl: false, backspace: true }),
  ).toStrictEqual('au');
  expect(editedQuery('a😀', '', { ctrl: false, delete: true })).toStrictEqual(
    'a',
  );
  expect(editedQuery('', '', { ctrl: false, backspace: true })).toStrictEqual(
    '',
  );
  expect(editedQuery('au', 'r', { ctrl: true })).toStrictEqual(undefined);
  expect(editedQuery('au', 'b', { ctrl: false, meta: true })).toStrictEqual(
    undefined,
  );
  expect(editedQuery('au', '\t', plain)).toStrictEqual(undefined);
  expect(editedQuery('', 'one\ntwo', plain)).toStrictEqual('one');
});

test('the match is marked wherever the query is, taken literally', () => {
  expect(queryPattern('')).toStrictEqual(undefined);
  expect('a.b axb a.b'.match(queryPattern('a.b')!)).toStrictEqual([
    'a.b',
    'a.b',
  ]);
});

test('the text is split where the query is, found or not, nothing measured', () => {
  expect(foundPieces('fix auth', '')).toStrictEqual([
    { text: 'fix auth', found: false },
  ]);
  expect(foundPieces('auth or auth', 'auth')).toStrictEqual([
    { text: 'auth', found: true },
    { text: ' or ', found: false },
    { text: 'auth', found: true },
  ]);
  expect(foundPieces('say 👩‍💻\tauth.', 'auth')).toStrictEqual([
    { text: 'say 👩‍💻\t', found: false },
    { text: 'auth', found: true },
    { text: '.', found: false },
  ]);
  expect(foundPieces('', 'auth')).toStrictEqual([{ text: '', found: false }]);
});

test('ctrl+r steps over a prompt the box cannot hold (CHD-323)', () => {
  const prompts = ['auth one', 'auth\u000cbad', 'auth two'];
  const found = searched(emptySearch, prompts, 'auth');

  expect(found.match).toStrictEqual(2);
  expect(searchedOlder(found, prompts).match).toStrictEqual(0);
  expect(searched(emptySearch, prompts, 'bad').failed).toStrictEqual(true);
});
