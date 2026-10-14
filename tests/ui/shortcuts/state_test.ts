import { expect, test } from 'bun:test';
import { reduceApp } from '../../../src/ui/app/state.ts';
import { ready } from '../app/states.ts';

test('/help opens the shortcuts, and stays open when they are', () => {
  const open = reduceApp(ready, { type: 'help_opened' });

  expect(open.help).toStrictEqual(true);
  expect(reduceApp(open, { type: 'help_opened' })).toStrictEqual(open);
});
