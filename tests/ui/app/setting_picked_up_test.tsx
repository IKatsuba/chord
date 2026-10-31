import { describe, expect, test } from 'bun:test';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { serveChord } from '../../../src/server/server.ts';
import { settingPickedUp } from '../../../src/ui/app/setting_picked_up.ts';
import type { WindowedState } from '../../../src/ui/app/state.ts';
import { agentItems } from '../../../src/ui/prompt/commands.ts';
import { send, until, withWindow } from './render.tsx';

const listed = [
  { name: 'claude', title: 'Claude', start: 'ready', runner: undefined },
  { name: 'codex', title: 'Codex', start: 'ready', runner: undefined },
] as never;
const place = { runtimes: ['claude', 'codex'], listed };

describe('settingPickedUp', () => {
  test("a theme takes the theme command's change, a removed one the default", () => {
    expect(settingPickedUp(['theme'], { set: 'light' }, place)).toStrictEqual([
      { type: 'theme_chosen', theme: 'light' },
    ]);
    expect(settingPickedUp(['theme'], { remove: true }, place)).toStrictEqual([
      { type: 'theme_chosen', theme: 'auto' },
    ]);
  });

  test("an editor mode takes the vim command's change, a removed one off", () => {
    expect(
      settingPickedUp(['editorMode'], { set: 'vim' }, place),
    ).toStrictEqual([{ type: 'vim_toggled', on: true }]);
    expect(
      settingPickedUp(['editorMode'], { set: 'normal' }, place),
    ).toStrictEqual([{ type: 'vim_toggled', on: false }]);
    expect(
      settingPickedUp(['editorMode'], { remove: true }, place),
    ).toStrictEqual([{ type: 'vim_toggled', on: false }]);
  });

  test('offered agents set what /new lists, a removed one the whole catalog', () => {
    expect(
      settingPickedUp(['offeredAgents'], { set: ['codex'] }, place),
    ).toStrictEqual([
      {
        type: 'agents_offered',
        agents: agentItems(['claude', 'codex'], listed, ['codex']),
      },
    ]);
    expect(
      settingPickedUp(['offeredAgents'], { remove: true }, place),
    ).toStrictEqual([
      {
        type: 'agents_offered',
        agents: agentItems(['claude', 'codex'], listed, undefined),
      },
    ]);
  });

  test.each([
    [['mouse'], { set: false }],
    [['copyOnSelect'], { set: false }],
    [['agent'], { set: 'codex' }],
    [['preferredNotifChannel'], { set: 'bell' }],
    [['agents', 'codex', 'model'], { set: 'm' }],
    [['teamSelection', 'intent'], { set: 'economy' }],
    [['theme', 'deeper'], { set: 'dark' }],
  ])('%j changes nothing in the running window', (path, change) => {
    expect(settingPickedUp(path, change, place)).toStrictEqual([]);
  });
});

describe('the running window takes up a saved setting', () => {
  const configHome = (text: string) => (dir: string) => {
    const home = join(dir, 'config');

    mkdirSync(join(home, 'chord'), { recursive: true });
    writeFileSync(join(home, 'chord', 'settings.json'), text);

    return home;
  };

  /** Plays `prompt`, answers the box yes and returns the window's state. */
  async function saved(
    prompt: string,
    options: Parameters<typeof withWindow>[1],
    look: (state: WindowedState, frame: string) => void,
    settled: (state: WindowedState) => boolean,
    question: string,
  ) {
    const server = serveChord();
    let latest: WindowedState | undefined;

    try {
      await withWindow(
        async (window) => {
          await send(window, prompt);
          await window.shows(question);
          await window.press('1');
          await window.shows('Saved to ');
          await until('the window took it up', () => settled(latest!));
          look(latest!, window.frame());
        },
        {
          columns: 120,
          rows: 40,
          server,
          ...options,
          onState: (next) => {
            latest = next;
          },
        },
      );
    } finally {
      await server.close();
    }
  }

  test('a theme, at once, and the answer says so', async () => {
    await saved(
      'settingstheme',
      { configHome: configHome('{"theme":"dark"}') },
      (_state, frame) => expect(frame).toContain('takes effect now'),
      (state) => state.window.theme === 'light',
      'Change theme?',
    );
  });

  test('vim mode, at once', async () => {
    await saved(
      'settingsvim',
      { configHome: configHome('{}') },
      (_state, frame) => expect(frame).toContain('takes effect now'),
      (state) => state.window.vim !== undefined,
      'Set editorMode?',
    );
  });

  test('what /new lists, at once', async () => {
    await saved(
      'settingsoffered',
      {
        configHome: configHome('{}'),
        runtimes: ['fake', 'claude', 'codex'],
        listed: [
          { name: 'claude', title: 'Claude', start: 'ready' },
          { name: 'codex', title: 'Codex', start: 'ready' },
        ] as never,
      },
      (state) =>
        expect(state.window.agents?.map(({ name }) => name)).toStrictEqual([
          'claude',
        ]),
      (state) => state.window.agents?.length === 1,
      'Set offeredAgents?',
    );
  });

  test('a key the window cannot take up changes no state', async () => {
    await saved(
      'settingsagent',
      { configHome: configHome('{}') },
      (state, frame) => {
        expect(frame).toContain('takes effect at the next start');
        expect(state.window.theme).toBe('auto');
      },
      () => true,
      'Set agent?',
    );
  });
});
