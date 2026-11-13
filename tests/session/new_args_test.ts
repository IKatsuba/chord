import { describe, expect, test } from 'bun:test';

import { newArgs, NO_NAME, NOT_NAME } from '../../src/session/new_args.ts';

describe('newArgs', () => {
  test.each([
    ['', {}],
    ['  ', {}],
    ['codex', { agent: 'codex' }],
    ['--name scout', { name: 'scout' }],
    ['codex --name scout', { agent: 'codex', name: 'scout' }],
    ['codex --name  the scout  ', { agent: 'codex', name: 'the scout' }],
    ['--name codex --name', { name: 'codex --name' }],
    ['--namex', { agent: '--namex' }],
  ])('%j reads as %j', (typed, read) => {
    expect(newArgs(typed)).toEqual(read);
  });

  test.each(['--name', '--name   ', 'codex --name'])(
    '%j is refused for want of a name',
    (typed) => {
      expect(newArgs(typed)).toEqual({ problem: NO_NAME });
    },
  );

  test.each(['codex scout', 'codex --name=scout', 'codex --other scout'])(
    '%j is refused for a word that is not --name',
    (typed) => {
      expect(newArgs(typed)).toEqual({ problem: NOT_NAME });
    },
  );
});
