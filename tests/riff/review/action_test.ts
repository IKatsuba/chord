import { expect, test } from 'bun:test';
import { reviewAction } from '../../../src/riff/review/action.ts';

test('review actions use resolved paths, shell cwd and jsdiff line counts', () => {
  expect(
    reviewAction({ tool: 'shell', command: 'pwd' }, '/real/project'),
  ).toEqual({
    tool: 'shell',
    command: 'pwd',
    cwd: '/real/project',
  });
  expect(
    reviewAction({ tool: 'read', real: '/real/file' }, '/project'),
  ).toEqual({ tool: 'read', real: '/real/file' });
  expect(
    reviewAction({ tool: 'write', real: '/real/file' }, '/project', {
      path: '/link/file',
      real: '/real/file',
      hash: 'hash',
      oldText: 'one\ntwo\n',
      newText: 'one\nthree\nfour\n',
      patch: 'complete diff',
      content: [],
    }),
  ).toEqual({
    tool: 'write',
    real: '/real/file',
    existed: true,
    additions: 2,
    deletions: 1,
    diff: 'complete diff',
  });
  expect(reviewAction({ tool: 'list' }, '/project')).toBeUndefined();
});
