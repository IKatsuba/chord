import { expect, test } from 'bun:test';
import type { EarlierSession } from '../../../src/session/sessions.ts';
import {
  type AppAction,
  initialAppState,
  keyCommand,
  reduceApp,
  resumeRefusal,
} from '../../../src/ui/app/state.ts';
import {
  configOption,
  configPickerShown,
  mcpShown,
  modelPickerShown,
  resumeChoices,
  resumePickerShown,
  sessionsPickerShown,
  shownTheme,
  themePickerShown,
} from '../../../src/ui/pickers/state.ts';
import { after, busy, ctrl, escape, ready } from '../app/states.ts';

test('/model opens the picker, and Esc or a pick closes it', () => {
  const open = reduceApp(ready, { type: 'model_picker_opened' });

  expect(open.modelPicker).toStrictEqual(true);
  expect(modelPickerShown(open)).toStrictEqual(true);
  expect(reduceApp(open, { type: 'model_picker_opened' })).toStrictEqual(open);
  expect(keyCommand('', { ctrl: false, escape: true }, open, '')).toStrictEqual(
    'close_model_picker',
  );
  expect(
    reduceApp(open, { type: 'model_picker_closed' }).modelPicker,
  ).toStrictEqual(false);
  // Quitting or a new session puts it away too.
  expect(reduceApp(open, { type: 'closing' }).modelPicker).toStrictEqual(false);
  expect(reduceApp(open, { type: 'cleared' }).modelPicker).toStrictEqual(false);
});

test('Esc closes the picker before it interrupts the turn under it', () => {
  const busy = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'prompt', turnId: 't1', text: 'hi', at: 0 },
    { type: 'model_picker_opened' },
  );

  expect(keyCommand('', { ctrl: false, escape: true }, busy, '')).toStrictEqual(
    'close_model_picker',
  );
  expect(
    keyCommand(
      '',
      { ctrl: false, escape: true },
      reduceApp(busy, { type: 'model_picker_closed' }),
      '',
    ),
  ).toStrictEqual('interrupt');
});

test('a permission asked takes the place of the picker until answered', () => {
  const asked = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'prompt', turnId: 't1', text: 'hi', at: 0 },
    { type: 'model_picker_opened' },
    {
      type: 'permission_requested',
      turnId: 't1',
      permission: { id: 'p1', options: [] },
    },
  );

  expect(modelPickerShown(asked)).toStrictEqual(false);
  expect(
    keyCommand('', { ctrl: false, escape: true }, asked, ''),
  ).toStrictEqual('reject_permission');
  expect(
    modelPickerShown(
      reduceApp(asked, {
        type: 'permission_settled',
        turnId: 't1',
        id: 'p1',
        answer: { type: 'rejected' },
      }),
    ),
  ).toStrictEqual(true);
});

test('the picker waits for the session to be up', () => {
  const early = reduceApp(initialAppState, { type: 'model_picker_opened' });

  expect(modelPickerShown(early)).toStrictEqual(false);
  expect(
    modelPickerShown(
      reduceApp(early, { type: 'connected', sessionId: 'session-1' }),
    ),
  ).toStrictEqual(true);
});

const EARLIER = [
  {
    resume: { sessionId: 'session-0', cwd: '/work' },
    lastUsedAt: '2026-10-01T00:00:00.000Z',
    prompt: 'hi',
  },
];

/** `/resume` asked as `asked`, and its read finding `sessions`. */
function listed(
  sessions: readonly EarlierSession[],
  asked = 'r1',
): AppAction[] {
  return [
    { type: 'resume_asked', asked },
    {
      type: 'resume_listed',
      asked,
      sessions,
      cwd: '/work',
      otherwise: 'None here.',
    },
  ];
}

test('/resume opens the session picker, and Esc or a pick closes it', () => {
  const open = listed(EARLIER).reduce(reduceApp, ready);

  expect(open.resumePicker).toStrictEqual({
    sessions: EARLIER,
    cwd: '/work',
    everywhere: false,
  });
  expect(resumePickerShown(open)).toStrictEqual(true);
  expect(keyCommand('', escape, open, '')).toStrictEqual('close_resume_picker');

  const closed = reduceApp(open, { type: 'resume_picker_closed' });

  expect(resumePickerShown(closed)).toStrictEqual(false);
  expect('resumePicker' in closed).toStrictEqual(false);
  expect(reduceApp(closed, { type: 'resume_picker_closed' })).toStrictEqual(
    closed,
  );
  // Quitting or the session it resumes puts it away too.
  expect(resumePickerShown(reduceApp(open, { type: 'closing' }))).toStrictEqual(
    false,
  );
  expect(resumePickerShown(reduceApp(open, { type: 'cleared' }))).toStrictEqual(
    false,
  );
});

test("ctrl+a switches /resume between this directory's sessions and every one's", () => {
  const there = {
    resume: { sessionId: 'session-9', cwd: '/other' },
    lastUsedAt: '2026-10-02T00:00:00.000Z',
    prompt: 'over there',
  };
  const open = listed([there, ...EARLIER]).reduce(reduceApp, ready);

  expect(resumeChoices(open.resumePicker!)).toStrictEqual(EARLIER);
  expect(keyCommand('a', ctrl, open, '')).toStrictEqual('toggle_resume_scope');

  const wide = reduceApp(open, { type: 'resume_scope_toggled' });

  expect(resumeChoices(wide.resumePicker!)).toStrictEqual([there, ...EARLIER]);
  expect(
    reduceApp(wide, { type: 'resume_scope_toggled' }).resumePicker,
  ).toStrictEqual(open.resumePicker);
  // Without the picker, ctrl+a is the prompt's, and the toggle does nothing.
  expect(keyCommand('a', ctrl, ready, '')).toStrictEqual(undefined);
  expect(reduceApp(ready, { type: 'resume_scope_toggled' })).toStrictEqual(
    ready,
  );
});

test('/resume opens on this directory even with none here, to reach the others', () => {
  const there = {
    resume: { sessionId: 'session-9', cwd: '/other' },
    lastUsedAt: '2026-10-02T00:00:00.000Z',
    prompt: 'over there',
  };
  const open = listed([there]).reduce(reduceApp, ready);

  expect(resumePickerShown(open)).toStrictEqual(true);
  expect(resumeChoices(open.resumePicker!)).toStrictEqual([]);
});

test('the session picker opens over a session that failed to start', () => {
  const failed = after(
    { type: 'connect_failed', message: 'no' },
    ...listed(EARLIER),
  );

  expect(resumePickerShown(failed)).toStrictEqual(true);
});

test('/resume with nothing found says so instead of opening', () => {
  const none = listed([]).reduce(reduceApp, ready);

  expect(resumePickerShown(none)).toStrictEqual(false);
  expect('resumeAsked' in none).toStrictEqual(false);
  expect(none.transcript.entries.at(-1)).toStrictEqual({
    kind: 'report',
    turnId: 'r1',
    command: 'resume',
    rows: [{ text: 'None here.' }],
  });
});

test('a list read after the turn started is refused, not opened', () => {
  const [ask, list] = listed(EARLIER);
  const late = [
    ask!,
    {
      type: 'prompt',
      turnId: 't1',
      text: 'hi',
      at: 0,
    } as const,
    list!,
  ].reduce(reduceApp, ready);

  expect(resumePickerShown(late)).toStrictEqual(false);
  expect(late.transcript.entries.at(-1)).toStrictEqual({
    kind: 'report',
    turnId: 'r1',
    command: 'resume',
    rows: [{ text: resumeRefusal(busy)! }],
  });
});

test('a list read after /clear, quitting or a newer /resume opens nothing', () => {
  const [ask, list] = listed(EARLIER);

  for (const between of [{ type: 'cleared' }, { type: 'closing' }] as const) {
    const stale = [ask!, between, list!].reduce(reduceApp, ready);

    expect(stale).toStrictEqual(reduceApp(reduceApp(ready, ask!), between));
  }

  const newer = [ask!, ...listed(EARLIER, 'r2')].reduce(reduceApp, ready);

  expect(reduceApp(newer, list!)).toStrictEqual(newer);
  // Nor does a list that was never asked for.
  expect(reduceApp(ready, list!)).toStrictEqual(ready);
});

test('/resume is refused while a turn runs, in a sentence', () => {
  expect(resumeRefusal(ready)).toStrictEqual(undefined);
  expect(resumeRefusal(busy)).toStrictEqual(
    'A turn is running. Wait for it to end, or press Esc to interrupt it, ' +
      'then /resume.',
  );
});

const OPTIONS: AppAction = {
  type: 'options',
  options: [
    {
      id: 'effort',
      name: 'Effort',
      values: [
        { value: 'low', name: 'Low' },
        { value: 'high', name: 'High' },
      ],
      current: 'low',
    },
  ],
};

test('/config opens on the options, Enter on one lists its values', () => {
  const open = after({ type: 'connected', sessionId: 'session-1' }, OPTIONS, {
    type: 'config_picker_opened',
  });

  expect(configPickerShown(open)).toStrictEqual(true);
  expect(configOption(open)).toStrictEqual(undefined);

  const values = reduceApp(open, {
    type: 'config_option_opened',
    id: 'effort',
  });

  expect(configOption(values)?.id).toStrictEqual('effort');
  // An option the agent no longer offers falls back to the list.
  expect(
    configOption(reduceApp(values, { type: 'options', options: [] })),
  ).toStrictEqual(undefined);
  // Nothing opens an option on a picker that is shut.
  expect(
    reduceApp(ready, { type: 'config_option_opened', id: 'effort' }),
  ).toStrictEqual(ready);
});

test('Esc backs /config out one level, and a pick closes it', () => {
  const values = after(
    { type: 'connected', sessionId: 'session-1' },
    OPTIONS,
    { type: 'config_picker_opened' },
    { type: 'config_option_opened', id: 'effort' },
  );

  expect(keyCommand('', escape, values, '')).toStrictEqual(
    'close_config_picker',
  );

  const options = reduceApp(values, { type: 'config_picker_back' });

  // The options open on the one Esc came back from.
  expect(options.configPicker).toStrictEqual({ from: 'effort' });
  expect(keyCommand('', escape, options, '')).toStrictEqual(
    'close_config_picker',
  );

  const shut = reduceApp(options, { type: 'config_picker_back' });

  expect('configPicker' in shut).toStrictEqual(false);
  expect(reduceApp(shut, { type: 'config_picker_back' })).toStrictEqual(shut);
  expect(
    'configPicker' in reduceApp(values, { type: 'config_picker_closed' }),
  ).toStrictEqual(false);
  // Quitting or a new session puts it away too.
  expect(
    'configPicker' in reduceApp(values, { type: 'closing' }),
  ).toStrictEqual(false);
  expect(
    'configPicker' in reduceApp(values, { type: 'cleared' }),
  ).toStrictEqual(false);
});

test('the /config picker waits for the session and gives way to a permission', () => {
  const opened = reduceApp(initialAppState, { type: 'config_picker_opened' });

  expect(configPickerShown(opened)).toStrictEqual(false);
  expect(
    configPickerShown(
      reduceApp(opened, { type: 'connected', sessionId: 'session-1' }),
    ),
  ).toStrictEqual(true);

  const asked = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'prompt', turnId: 't1', text: 'hi', at: 0 },
    { type: 'config_picker_opened' },
    {
      type: 'permission_requested',
      turnId: 't1',
      permission: { id: 'p1', options: [] },
    },
  );

  expect(configPickerShown(asked)).toStrictEqual(false);
  expect(keyCommand('', escape, asked, '')).toStrictEqual('reject_permission');
  // ctrl+r is not the search's while the picker holds the keys.
  expect(
    keyCommand(
      'r',
      ctrl,
      reduceApp(ready, { type: 'config_picker_opened' }),
      '',
    ),
  ).toStrictEqual(undefined);
});

test('/theme previews the highlighted theme, Esc brings the old one back', () => {
  const open = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'theme_picker_opened' },
  );

  expect(themePickerShown(open)).toStrictEqual(true);
  expect(shownTheme(open)).toStrictEqual('auto');

  const previewing = reduceApp(open, {
    type: 'theme_previewed',
    theme: 'light',
  });

  expect(shownTheme(previewing)).toStrictEqual('light');
  expect(previewing.theme, 'nothing kept yet').toStrictEqual('auto');
  expect(keyCommand('', escape, previewing, '')).toStrictEqual(
    'close_theme_picker',
  );

  const back = reduceApp(previewing, { type: 'theme_picker_closed' });

  expect(themePickerShown(back)).toStrictEqual(false);
  expect(shownTheme(back)).toStrictEqual('auto');
  // A preview with the picker shut changes nothing.
  expect(
    reduceApp(back, { type: 'theme_previewed', theme: 'dark' }),
  ).toStrictEqual(back);
});

test('Enter keeps the theme, and /clear and a permission do not lose it', () => {
  const kept = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'theme_picker_opened' },
    { type: 'theme_previewed', theme: 'light-ansi' },
    { type: 'theme_chosen', theme: 'light-ansi' },
  );

  expect(themePickerShown(kept)).toStrictEqual(false);
  expect(shownTheme(kept)).toStrictEqual('light-ansi');
  expect(reduceApp(kept, { type: 'cleared' }).theme).toStrictEqual(
    'light-ansi',
  );

  // A permission asked over the picker hides it, and its preview with it.
  const asked = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'theme_picker_opened' },
    { type: 'theme_previewed', theme: 'light' },
    { type: 'prompt', turnId: 't1', text: 'hi', at: 0 },
    {
      type: 'permission_requested',
      turnId: 't1',
      permission: { id: 'p1', options: [] },
    },
  );

  expect(themePickerShown(asked)).toStrictEqual(false);
  expect(shownTheme(asked)).toStrictEqual('auto');

  // The window may open it before the session is up; quitting shuts it.
  const early = after({ type: 'theme_picker_opened' });

  expect(themePickerShown(early)).toStrictEqual(true);
  expect('themePicker' in reduceApp(early, { type: 'closing' })).toStrictEqual(
    false,
  );
});

test('/mcp opens its list, takes the keys, and Esc or closing shuts it', () => {
  const open = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'mcp_opened' },
  );

  expect(mcpShown(open)).toStrictEqual(true);
  expect(keyCommand('', escape, open, '')).toStrictEqual('close_mcp');
  // Its keys are the list's: ctrl+g leaves the draft where it is.
  expect(
    keyCommand('g', { ctrl: true, escape: false }, open, ''),
  ).toStrictEqual(undefined);
  expect(mcpShown(reduceApp(open, { type: 'mcp_closed' }))).toStrictEqual(
    false,
  );
  expect(mcpShown(reduceApp(open, { type: 'closing' }))).toStrictEqual(false);
});

test('ctrl+x w opens the sessions picker in place of any other, and Esc closes it', () => {
  const theming = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'theme_picker_opened' },
    { type: 'theme_previewed', theme: 'light' },
  );
  const open = reduceApp(theming, { type: 'sessions_picker_opened' });

  expect(sessionsPickerShown(open)).toStrictEqual(true);
  expect(themePickerShown(open)).toStrictEqual(false);
  // The theme previewed goes with its picker.
  expect(shownTheme(open)).toStrictEqual(theming.theme);
  expect(keyCommand('', escape, open, '')).toStrictEqual(
    'close_sessions_picker',
  );

  const closed = reduceApp(open, { type: 'sessions_picker_closed' });

  expect(sessionsPickerShown(closed)).toStrictEqual(false);
  expect('sessionsPicker' in closed).toStrictEqual(false);
  expect(
    sessionsPickerShown(reduceApp(open, { type: 'closing' })),
  ).toStrictEqual(false);
});

test('the sessions picker stands in front of a permission: Esc closes it, not the permission', () => {
  const open = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'prompt', turnId: 't1', text: 'hi', at: 0 },
    {
      type: 'permission_requested',
      turnId: 't1',
      permission: { id: 'p1', title: 'Write notes.txt', options: [] },
    },
    { type: 'sessions_picker_opened' },
  );

  expect(sessionsPickerShown(open)).toStrictEqual(true);
  expect(keyCommand('', escape, open, '')).toStrictEqual(
    'close_sessions_picker',
  );
  expect(
    keyCommand(
      '',
      escape,
      reduceApp(open, { type: 'sessions_picker_closed' }),
      '',
    ),
  ).toStrictEqual('reject_permission');
});
