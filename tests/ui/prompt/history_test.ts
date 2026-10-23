import { expect, test } from 'bun:test';
import {
  emptyHistory,
  type History,
  left,
  newer,
  older,
  recalledImages,
  recorded,
  recordedWith,
  walking,
} from '../../../src/ui/prompt/history.ts';

const sent = ['first', 'second'].reduce(recorded, emptyHistory);

test('a sent prompt is kept once, after the ones before it', () => {
  expect(sent.prompts).toStrictEqual(['first', 'second']);
  expect(recorded(sent, 'second').prompts).toStrictEqual(['first', 'second']);
  expect(recorded(sent, 'first').prompts).toStrictEqual([
    'first',
    'second',
    'first',
  ]);
});

test('↑ walks back to the oldest prompt and stops there', () => {
  const one = older(sent, '');
  const two = one && older(one.history, one.text);

  expect(one?.text).toStrictEqual('second');
  expect(two?.text).toStrictEqual('first');
  expect(two && older(two.history, two.text)).toStrictEqual(undefined);
  expect(older(emptyHistory, 'draft')).toStrictEqual(undefined);
});

test('↓ walks forward and then gives back the draft ↑ left', () => {
  const back = older(sent, 'half typed')!;
  const further = older(back.history, back.text)!;
  const forward = newer(further.history)!;
  const home = newer(forward.history)!;

  expect(forward.text).toStrictEqual('second');
  expect(home.text).toStrictEqual('half typed');
  expect(home.history.index).toStrictEqual(undefined);
  // Off the walk ↓ has nowhere to go.
  expect(newer(home.history)).toStrictEqual(undefined);
  expect(newer(sent)).toStrictEqual(undefined);
});

test("↑ walks an agent's kept drafts, newest first, before the prompts sent, and ↓ back to the box (U10)", () => {
  const kept = ['set aside first', 'set aside last'];
  const one = older(sent, 'typing', kept)!;
  const two = older(one.history, one.text, kept)!;
  const three = older(two.history, two.text, kept)!;

  expect([one, two, three].map(({ text, kept }) => [text, kept])).toStrictEqual(
    [
      ['set aside last', 1],
      ['set aside first', 0],
      ['second', undefined],
    ],
  );

  const back = newer(three.history, kept)!;
  const home = newer(newer(back.history, kept)!.history, kept)!;

  expect([back.text, back.kept]).toStrictEqual(['set aside first', 0]);
  expect(home.text).toStrictEqual('typing');
  expect(home.history.index).toStrictEqual(undefined);
  // A walk begun among one agent's drafts stands at the box on an agent
  // with fewer.
  expect(older(one.history, '', [])?.text).toStrictEqual('second');
  expect(newer(one.history, [])?.history.index).toStrictEqual(undefined);
});

test('sending ends the walk', () => {
  const back = older(sent, 'draft')!;
  const after: History = recorded(back.history, 'third');

  expect(after.index).toStrictEqual(undefined);
  expect(after.draft).toStrictEqual('');
  expect(older(after, '')?.text).toStrictEqual('third');
});

test('the arrows are history’s only while a recalled prompt is untouched', () => {
  const back = older(sent, '')!;

  expect(walking(sent, '')).toStrictEqual(false);
  expect(walking(back.history, back.text)).toStrictEqual(true);
  expect(walking(back.history, `${back.text}!`)).toStrictEqual(false);
});

test('a prompt taken some other way ends the walk without sending', () => {
  const back = older(sent, 'draft')!;
  const after = left(back.history);

  expect(after.index).toStrictEqual(undefined);
  expect(after.prompts).toStrictEqual(sent.prompts);
  expect(older(after, '')?.text).toStrictEqual('second');
  expect(left(sent)).toStrictEqual(sent);
});

test('a recalled prompt brings back the images it sent', () => {
  const image = { id: 1, mediaType: 'image/png', data: 'AAAA', bytes: 3 };
  const sent = recordedWith(emptyHistory, 'look at [Image #1]', [image]);

  expect(recalledImages(sent, 'look at [Image #1]')).toStrictEqual([image]);
  expect(recalledImages(sent, 'something else')).toStrictEqual([]);
  // Sent again without them, it brings none.
  expect(
    recalledImages(recorded(sent, 'look at [Image #1]'), 'look at [Image #1]'),
  ).toStrictEqual([]);
});

test('↑ and ↓ bring back a prompt with a control character as it was sent', () => {
  const kept = ['first', 'with\u000cform feed', 'last'].reduce(
    recorded,
    emptyHistory,
  );
  const last = older(kept, 'draft')!;
  const middle = older(last.history, last.text)!;

  expect(middle.text).toStrictEqual('with\u000cform feed');
  expect(older(middle.history, middle.text)?.text).toStrictEqual('first');
  expect(newer(middle.history)?.text).toStrictEqual('last');
});
