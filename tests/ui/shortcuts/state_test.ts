import { expect, test } from 'bun:test';
import { reduceApp } from '../../../src/ui/app/state.ts';
import { ready } from '../app/states.ts';

test('/help opens the shortcuts, and stays open when they are', () => {
  const open = reduceApp(ready, { type: 'help_opened' });

  expect(open.help).toStrictEqual(true);
  expect(reduceApp(open, { type: 'help_opened' })).toStrictEqual(open);
});

test('the panel says it overflows only while open, and forgets it once shut (CHD-378)', () => {
  const open = reduceApp(ready, { type: 'help_toggled' });
  const over = reduceApp(open, { type: 'panel_overflowed', overflows: true });

  expect(over.panelOverflows).toBe(true);
  expect(
    reduceApp(over, { type: 'panel_overflowed', overflows: false })
      .panelOverflows,
  ).toBeUndefined();
  expect(
    reduceApp(over, { type: 'help_toggled' }).panelOverflows,
  ).toBeUndefined();
  expect(
    reduceApp(over, { type: 'help_closed' }).panelOverflows,
  ).toBeUndefined();
  // A report from a panel already shut changes nothing.
  expect(
    reduceApp(ready, { type: 'panel_overflowed', overflows: true })
      .panelOverflows,
  ).toBeUndefined();
});
