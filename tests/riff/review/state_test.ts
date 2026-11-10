import { expect, test } from 'bun:test';
import { ReviewHistory } from '../../../src/riff/review/state.ts';

test('review history retains user requests and only the current turn results', () => {
  const history = new ReviewHistory();

  history.prompt('first');
  history.result({ id: '1', tool: 'read', text: 'old turn' });
  history.prompt('second');
  history.prompt('current');
  history.result({ id: '2', tool: 'read', text: 'older' });
  history.result({ id: '3', tool: 'shell', text: 'newer' });

  expect(history.snapshot()).toEqual({
    requests: { current: 'current', first: 'first', recent: ['second'] },
    results: [
      { id: '3', tool: 'shell', text: 'newer' },
      { id: '2', tool: 'read', text: 'older' },
    ],
    omittedResults: 0,
  });
});

test('review history bounds retained results and counts omitted entries', () => {
  const history = new ReviewHistory();

  history.prompt('x'.repeat(10000));

  for (let i = 0; i < 100; i++) {
    history.result({ id: String(i), tool: 'read', text: 'x'.repeat(10000) });
  }

  const snapshot = history.snapshot();

  expect(snapshot.results.length).toBe(8);
  expect(snapshot.results[0]?.id).toBe('99');
  expect(snapshot.omittedResults).toBe(92);
  expect(snapshot.requests.current.length).toBe(1024);

  history.prompt('next');

  expect(history.snapshot().results).toEqual([]);
  expect(history.snapshot().omittedResults).toBe(0);
});

test('permission feedback is excluded by call identity, while admitted tool output remains', () => {
  const history = new ReviewHistory();

  history.prompt('request');
  history.permission('denied');
  history.permission('unanswered');
  history.permission('allowed');
  history.admitted('allowed');

  for (const id of ['denied', 'unanswered', 'allowed', 'ordinary']) {
    history.result({
      id,
      tool: 'read',
      text: 'same text, different authority',
    });
  }

  expect(history.snapshot().results.map(({ id }) => id)).toEqual([
    'ordinary',
    'allowed',
  ]);
});

test('empty text prompts do not grow retained request history', () => {
  const history = new ReviewHistory();

  history.prompt('first');

  for (let i = 0; i < 10000; i++) {
    history.prompt('');
  }

  expect(history.snapshot().requests).toEqual({
    current: '',
    first: 'first',
    recent: [],
  });
});
