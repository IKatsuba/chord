import { expect, test } from 'bun:test';
import { settingPickedUp } from '../../src/session/setting_picked_up.ts';

test('a theme is the one saved, a removed one the default', () => {
  expect(settingPickedUp(['theme'], { set: 'light' })).toStrictEqual({
    key: 'theme',
    theme: 'light',
  });
  expect(settingPickedUp(['theme'], { remove: true })).toStrictEqual({
    key: 'theme',
    theme: 'auto',
  });
});

test('vim is on only for a saved vim mode', () => {
  expect(settingPickedUp(['editorMode'], { set: 'vim' })).toStrictEqual({
    key: 'editorMode',
    vim: true,
  });
  expect(settingPickedUp(['editorMode'], { set: 'normal' })).toStrictEqual({
    key: 'editorMode',
    vim: false,
  });
  expect(settingPickedUp(['editorMode'], { remove: true })).toStrictEqual({
    key: 'editorMode',
    vim: false,
  });
});

test('offered agents are the names saved, none when removed', () => {
  expect(settingPickedUp(['offeredAgents'], { set: ['codex'] })).toStrictEqual({
    key: 'offeredAgents',
    offered: ['codex'],
  });
  expect(settingPickedUp(['offeredAgents'], { remove: true })).toStrictEqual({
    key: 'offeredAgents',
    offered: undefined,
  });
});

test.each([
  [['mouse'], { set: false }],
  [['agents', 'codex', 'model'], { set: 'm' }],
  [['theme', 'deeper'], { set: 'dark' }],
])('%j is no change to a running process', (path, change) => {
  expect(settingPickedUp(path, change)).toBe(undefined);
});
