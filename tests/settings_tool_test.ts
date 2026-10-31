import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import {
  mkdir,
  mkdtemp,
  readFile,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  changeWord,
  classifySetting,
  notSavedLine,
  plannedSetting,
  readSettingsTool,
  saveFailure,
  settingRefusal,
  type SettingsWhere,
} from '../src/settings_tool.ts';
import { settingsRows } from '../src/ui/transcript/tools/settings_row.ts';

const known = ['claude', 'codex', 'my.agent'];
const set = (value: unknown) => ({ set: value });
const remove = { remove: true } as const;

describe('CHD-568 U2 tester: validation boundaries', () => {
  test('a malformed list is refused before any unknown agent is considered', () => {
    const offered = ['unknown-first', null, 'codex'];

    expect(settingRefusal(['offeredAgents'], set(offered), known)).toStartWith(
      'offeredAgents cannot be ["unknown-first",null,"codex"]: ',
    );
    expect(offered).toEqual(['unknown-first', null, 'codex']);
    expect(
      settingRefusal(
        ['offeredAgents'],
        set(['codex', 'unknown-second']),
        known,
      ),
    ).toBe(
      'chord knows no agent named "unknown-second"; list_agents names every one',
    );
  });

  test('known own agent names may resemble object methods or contain terminal controls', () => {
    const names = ['toString', 'hasOwnProperty', 'agent.\u009b\u202e'];

    for (const name of names) {
      expect(
        settingRefusal(['agents', name, 'model'], set('external-model'), names),
      ).toBeUndefined();
      expect(settingRefusal(['agent'], set(name), names)).toBeUndefined();
      expect(
        settingRefusal(['teamSelection', 'prefer', 'agent'], set(name), names),
      ).toBeUndefined();
    }

    const refused = settingRefusal(
      ['agents', names[2]!, 'effort'],
      set('external-effort'),
      [],
    );

    expect(refused).toContain('agent.\\u009b\\u202e');
    expect(refused).not.toMatch(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u);
  });

  test('forbidden keys stay unknown even below hand-edit branches', () => {
    for (const key of ['__proto__', 'constructor', 'prototype']) {
      for (const path of [
        ['mcpServers', 'server', 'env', key],
        ['agents', 'codex', 'command', key],
        ['teamSelection', 'constraints', 'models', key],
      ]) {
        expect(classifySetting(path)).toEqual({ kind: 'unknown' });
        expect(settingRefusal(path, remove, known)).toStartWith('No setting ');
        expect(settingRefusal(path, set(null), known)).toStartWith(
          'No setting ',
        );
      }
    }
  });

  test('null resets only the nullable preference, and removal accepts an unknown effort owner', () => {
    expect(
      settingRefusal(['teamSelection', 'prefer', 'model'], set(null), []),
    ).toBeUndefined();

    for (const path of [
      ['agents', 'codex', 'model'],
      ['agents', 'codex', 'effort'],
      ['teamSelection', 'prefer', 'agent'],
      ['teamSelection', 'intent'],
    ]) {
      expect(settingRefusal(path, set(null), known)).toContain(
        'cannot be null:',
      );
    }

    expect(
      settingRefusal(['agents', 'gone.agent', 'effort'], remove, []),
    ).toBeUndefined();
    expect(
      settingRefusal(['agents', 'codex', 'model'], set('unknown.model'), known),
    ).toBeUndefined();
  });
});

describe('classifySetting', () => {
  test.each([
    [['theme'], true, 'now'],
    [['editorMode'], true, 'now'],
    [['mouse'], true, 'next start'],
    [['copyOnSelect'], true, 'next start'],
    [['offeredAgents'], true, 'now'],
    [['preferredNotifChannel'], false, 'next start'],
    [['agent'], false, 'next start'],
    [['agents', 'codex', 'model'], false, 'next start'],
    [['agents', 'codex', 'effort'], false, 'next start'],
    [['teamSelection', 'intent'], false, 'now'],
    [['teamSelection', 'prefer', 'agent'], false, 'now'],
    [['teamSelection', 'prefer', 'model'], false, 'now'],
  ])('%j is writable', (path, userOnly, takesEffect) => {
    expect(classifySetting(path)).toMatchObject({
      kind: 'leaf',
      userOnly,
      takesEffect,
    });
  });

  test.each([
    [['agents', 'codex', 'command']],
    [['agents', 'codex', 'command', '0']],
    [['agents', 'codex', 'permissionMode']],
    [['agents', 'codex', 'mcpServers']],
    [['mcpServers']],
    [['mcpServers', 'linear']],
    [['mcpServers', 'linear', 'env', 'TOKEN']],
    [['teamSelection', 'constraints']],
    [['teamSelection', 'constraints', 'agents']],
    [['teamSelection', 'constraints', 'models', 'codex']],
  ])('%j stays a hand edit', (path) => {
    expect(classifySetting(path)).toStrictEqual({ kind: 'hand' });
  });

  test.each([
    [['nope']],
    [['theme', 'deeper']],
    [['toString']],
    [['agents', 'codex', 'modle']],
    [['agents', 'codex', 'model', 'deeper']],
    [['agents', 'codex', 'toString']],
    [['teamSelection', 'nope']],
    [['teamSelection', 'intent', 'deeper']],
    [['teamSelection', 'prefer', 'nope']],
    [['teamSelection', 'prefer', 'toString']],
    [['teamSelection', 'prefer', 'model', 'deeper']],
    [['__proto__']],
    [['constructor']],
    [['prototype']],
    [['agents', '__proto__', 'model']],
    [['agents', 'constructor', 'model']],
    [['theme', '__proto__']],
    [[]],
  ])('%j is no setting', (path) => {
    expect(classifySetting(path)).toStrictEqual({ kind: 'unknown' });
  });
});

describe('settingRefusal', () => {
  test.each<[string[], string]>([
    [['agents', 'claude', 'modle'], 'No setting agents.claude.modle'],
    [['__proto__'], 'No setting __proto__'],
    [['agents', 'my.agent', 'x'], 'No setting agents."my.agent".x'],
    [
      ['agents', 'claude', 'command'],
      'chord does not write agents.claude.command; edit the settings file by hand',
    ],
    [
      ['mcpServers', 'x'],
      'chord does not write mcpServers.x; edit the settings file by hand',
    ],
    [
      ['agents', 'codex'],
      'agents.codex is not one setting; name agents.codex.model or agents.codex.effort',
    ],
    [
      ['agents'],
      'agents is not one setting; name agents.<name>.model or agents.<name>.effort',
    ],
    [
      ['teamSelection'],
      'teamSelection is not one setting; name teamSelection.intent, teamSelection.prefer.agent or teamSelection.prefer.model',
    ],
    [
      ['teamSelection', 'prefer'],
      'teamSelection.prefer is not one setting; name teamSelection.prefer.agent or teamSelection.prefer.model',
    ],
  ])('%j is refused on set and remove alike', (path, line) => {
    expect(settingRefusal(path, set('x'), known)).toBe(line);
    expect(settingRefusal(path, remove, known)).toBe(line);
  });

  test('the path is checked before the value', () => {
    expect(settingRefusal(['nope'], set(undefined), [])).toBe(
      'No setting nope',
    );
  });

  test.each<[string[], unknown, string]>([
    [
      ['editorMode'],
      'emacs',
      'editorMode cannot be "emacs": Invalid option: expected one of "normal"|"vim"',
    ],
    [
      ['mouse'],
      'yes',
      'mouse cannot be "yes": Invalid input: expected boolean, received string',
    ],
    [
      ['agent'],
      '',
      'agent cannot be "": Too small: expected string to have >=1 characters',
    ],
    [
      ['offeredAgents'],
      ['claude', 3],
      'offeredAgents cannot be ["claude",3]: expected a list of one or more agent names',
    ],
    [
      ['offeredAgents'],
      [],
      'offeredAgents cannot be []: expected a list of one or more agent names',
    ],
    [
      ['agents', 'claude', 'model'],
      null,
      'agents.claude.model cannot be null: Invalid input: expected string, received null',
    ],
  ])('%j with %j is refused by its own schema', (path, value, line) => {
    expect(settingRefusal(path, set(value), known)).toBe(line);
  });

  test('a value left out is refused, not written as nothing', () => {
    expect(settingRefusal(['theme'], set(undefined), known)).toStartWith(
      'theme cannot be left out: ',
    );
    expect(
      settingRefusal(
        ['teamSelection', 'prefer', 'model'],
        set(undefined),
        known,
      ),
    ).toStartWith('teamSelection.prefer.model cannot be left out: ');
  });

  test('a value that holds a control reads escaped in the refusal', () => {
    expect(settingRefusal(['theme'], set('\u009b31m'), known)).toStartWith(
      'theme cannot be "\\u009b31m": ',
    );
  });

  test.each<[string[], unknown]>([
    [['theme'], 'dark'],
    [['editorMode'], 'vim'],
    [['mouse'], false],
    [['copyOnSelect'], true],
    [['offeredAgents'], ['claude', 'codex']],
    [['preferredNotifChannel'], 'bell'],
    [['agent'], 'claude'],
    [['agents', 'my.agent', 'model'], 'any-id-at-all'],
    [['agents', 'codex', 'effort'], 'unheard-of'],
    [['teamSelection', 'intent'], 'economy'],
    [['teamSelection', 'prefer', 'agent'], 'codex'],
    [['teamSelection', 'prefer', 'model'], 'any-id'],
    [['teamSelection', 'prefer', 'model'], null],
  ])('%j takes %j', (path, value) => {
    expect(settingRefusal(path, set(value), known)).toBeUndefined();
  });

  test.each<[string[], unknown, string]>([
    [['agents', 'nope', 'model'], 'm', 'nope'],
    [['agent'], 'nope', 'nope'],
    [['offeredAgents'], ['claude', 'nope', 'other'], 'nope'],
    [['teamSelection', 'prefer', 'agent'], 'nope', 'nope'],
    [['agents', 'a"b', 'effort'], 'm', 'a\\"b'],
  ])('%j with %j names an agent chord lacks', (path, value, name) => {
    expect(settingRefusal(path, set(value), known)).toBe(
      `chord knows no agent named "${name}"; list_agents names every one`,
    );
  });

  test('the schema is checked before the names', () => {
    expect(
      settingRefusal(['agents', 'nope', 'model'], set(''), known),
    ).toStartWith('agents.nope.model cannot be "": ');
  });

  test('a remove checks no name and no value', () => {
    for (const path of [
      ['agents', 'stale', 'model'],
      ['agent'],
      ['offeredAgents'],
      ['theme'],
    ]) {
      expect(settingRefusal(path, remove, known)).toBeUndefined();
    }
  });

  test('a file refusal ends with what the writer said', () => {
    expect(
      notSavedLine('~/.config/chord/settings.json', 'it is not valid JSON'),
    ).toBe('~/.config/chord/settings.json was not saved: it is not valid JSON');
  });
});

describe('CHD-568 U3 tester: checked fresh reads', () => {
  test('repeated reads observe repairs and removal without writing either file', async () => {
    const root = await mkdtemp(join(tmpdir(), 'chord-settings-tester-read-'));
    const where: SettingsWhere = {
      home: root,
      configHome: join(root, '.config'),
      cwd: join(root, 'work'),
    };
    const user = join(where.configHome!, 'chord', 'settings.json');
    const project = join(where.cwd, '.chord', 'settings.json');
    const rawUser = '{ "agent":"claude", "theme":"dark" }';
    const rawProject = '{ "agent":"codex" }';

    try {
      await mkdir(join(user, '..'), { recursive: true });
      await mkdir(join(project, '..'), { recursive: true });
      await writeFile(user, rawUser);
      await writeFile(project, rawProject);

      const first = await readSettingsTool(where, ['agent']);

      expect(first).toMatchObject({
        answer: { user: 'claude', project: 'codex', effective: 'codex' },
      });
      expect(await readFile(user, 'utf8')).toBe(rawUser);
      expect(await readFile(project, 'utf8')).toBe(rawProject);
      await writeFile(project, '{"mcpServers":{"x":{"env":secret-fresh}}}');

      const broken = await readSettingsTool(where, ['agent']);

      expect(broken).toMatchObject({
        answer: { user: 'claude', effective: 'claude' },
      });
      expect(JSON.stringify(broken)).not.toContain('secret-fresh');
      expect(JSON.stringify(broken)).toContain('not valid JSON; ignored');

      await rm(project);

      const removed = await readSettingsTool(where, ['agent']);

      expect(removed).toMatchObject({
        answer: { user: 'claude', effective: 'claude', problems: [] },
      });
      expect(await readFile(user, 'utf8')).toBe(rawUser);
    } finally {
      await rm(root, { recursive: true });
    }
  });
});

describe('planning a settings change (CHD-568)', () => {
  /** A home and project under a temporary root, with the files given. */
  async function placed(
    files: { user?: string; project?: string },
    run: (where: SettingsWhere, userFile: string) => Promise<void>,
  ) {
    const root = await mkdtemp(join(tmpdir(), 'chord-settings-plan-'));
    const home = join(root, 'home');
    const where = {
      home,
      configHome: join(home, '.config'),
      cwd: join(root, 'work'),
    };
    const userFile = join(where.configHome, 'chord', 'settings.json');

    try {
      await mkdir(join(where.configHome, 'chord'), { recursive: true });
      await mkdir(join(where.cwd, '.chord'), { recursive: true });

      if (files.user !== undefined) {
        await writeFile(userFile, files.user);
      }

      if (files.project !== undefined) {
        await writeFile(
          join(where.cwd, '.chord', 'settings.json'),
          files.project,
        );
      }

      await run(where, userFile);
    } finally {
      await rm(root, { recursive: true });
    }
  }

  const shownFile = `~${join('/', '.config', 'chord', 'settings.json')}`;

  test('a set on an unset key, on a held key, and a remove', async () => {
    await placed(
      { user: '{"agents":{"fake":{"model":"old"}}}' },
      async (where, file) => {
        const unset = await plannedSetting(
          where,
          ['theme'],
          set('dark'),
          known,
        );

        expect(unset).toStrictEqual({
          file,
          answer: {
            path: ['theme'],
            after: 'dark',
            file: shownFile,
            takesEffect: 'now',
          },
        });

        const path = ['agents', 'claude', 'model'];
        const fresh = await plannedSetting(where, path, set('m'), known);

        expect('answer' in fresh && fresh.answer.takesEffect).toBe(
          'next start',
        );

        const held = await plannedSetting(
          where,
          ['agents', 'fake', 'model'],
          set('new'),
          ['fake'],
        );

        expect('answer' in held && held.answer).toMatchObject({
          before: 'old',
          after: 'new',
        });
        expect('answer' in held && changeWord(held.answer)).toBe('change');

        const gone = await plannedSetting(
          where,
          ['agents', 'fake', 'model'],
          remove,
          [],
        );

        expect('answer' in gone && gone.answer).toMatchObject({
          before: 'old',
        });
        expect('answer' in gone && 'after' in gone.answer).toBe(false);
        expect('answer' in gone && changeWord(gone.answer)).toBe('remove');
      },
    );
  });

  test('the same value and a remove of an absent key do nothing', async () => {
    await placed({ user: '{"theme":"dark"}' }, async (where) => {
      expect(
        await plannedSetting(where, ['theme'], set('dark'), known),
      ).toMatchObject({ answer: { saved: false, unchanged: true } });
      expect(
        await plannedSetting(where, ['mouse'], remove, known),
      ).toMatchObject({ answer: { saved: false, unchanged: true } });
    });
  });

  test('null is a value, not an absent key', async () => {
    const path = ['teamSelection', 'prefer', 'model'];

    await placed(
      { user: '{"teamSelection":{"prefer":{"model":null}}}' },
      async (where) => {
        expect(
          await plannedSetting(where, path, set(null), known),
        ).toMatchObject({ answer: { unchanged: true, before: null } });

        const changed = await plannedSetting(where, path, set('m'), known);

        expect('answer' in changed && changed.answer.unchanged).toBeUndefined();

        const gone = await plannedSetting(where, path, remove, known);

        expect('answer' in gone && gone.answer.unchanged).toBeUndefined();
      },
    );
  });

  test('a refusal comes first, then no home, then the file, then its parent', async () => {
    await placed({ user: '{ broken' }, async (where) => {
      expect(
        await plannedSetting(where, ['nope'], set(1), known),
      ).toStrictEqual({ error: 'No setting nope' });
      expect(
        await plannedSetting(
          { ...where, configHome: undefined },
          ['theme'],
          set('dark'),
          known,
        ),
      ).toStrictEqual({
        error: 'No settings file without a home directory; nothing was saved',
      });
      expect(
        await plannedSetting(where, ['theme'], set('dark'), known),
      ).toStrictEqual({
        error: `${shownFile} was not saved: it is not valid JSON`,
      });
    });

    await placed({ user: '["a list"]' }, async (where) => {
      expect(
        await plannedSetting(where, ['theme'], remove, known),
      ).toStrictEqual({
        error: `${shownFile} was not saved: it is not a JSON object`,
      });
    });

    await placed({ user: '{"agents":3}' }, async (where) => {
      for (const change of [set('m'), remove]) {
        expect(
          await plannedSetting(
            where,
            ['agents', 'claude', 'model'],
            change,
            known,
          ),
        ).toStrictEqual({
          error: `${shownFile} was not saved: its agents is not an object; edit it by hand`,
        });
      }
    });
  });

  test('a file that cannot be read names no home', async () => {
    await placed({}, async (where, file) => {
      await mkdir(file);

      const planned = await plannedSetting(
        where,
        ['theme'],
        set('dark'),
        known,
      );

      assert('error' in planned);
      expect(planned.error).toStartWith(`${shownFile} was not saved: `);
      expect(planned.error).not.toContain(where.home!);
    });
  });

  test('a project holding a kind B key shadows it, changed or unchanged', async () => {
    const shadowedBy = join('.chord', 'settings.json');

    await placed(
      {
        user: '{"agent":"claude"}',
        project: '{"agent":"codex","teamSelection":{"prefer":{"model":null}}}',
      },
      async (where) => {
        expect(
          await plannedSetting(where, ['agent'], set('codex'), known),
        ).toMatchObject({ answer: { shadowedBy } });
        expect(
          await plannedSetting(where, ['agent'], set('claude'), known),
        ).toMatchObject({ answer: { unchanged: true, shadowedBy } });
        expect(
          await plannedSetting(
            where,
            ['teamSelection', 'prefer', 'model'],
            set('m'),
            known,
          ),
        ).toMatchObject({ answer: { shadowedBy } });
      },
    );
  });

  test("nothing shadows a user-only key, or a value the project's check dropped", async () => {
    await placed({ project: '{"theme":"dark","agent":3}' }, async (where) => {
      const theme = await plannedSetting(where, ['theme'], set('light'), known);
      const agent = await plannedSetting(where, ['agent'], set('codex'), known);

      expect('answer' in theme && 'shadowedBy' in theme.answer).toBe(false);
      expect('answer' in agent && 'shadowedBy' in agent.answer).toBe(false);
    });
  });

  test('a save that fails says the file, without the home', () => {
    const error = new Error("EACCES: permission denied, open '/h/o/me/x.json'");

    expect(saveFailure('~/x.json', error, '/h/o/me')).toBe(
      "~/x.json was not saved: EACCES: permission denied, open '~/x.json'",
    );
  });
});

describe('a read answers only from what the schema checked (CHD-568)', () => {
  const CANARY = 'canary-value-9f';
  const CANARY_KEY = 'canaryKey9f';

  /** A home and a project under a temporary root, with the files given. */
  async function placed(
    files: {
      user?: string;
      project?: string;
      plant?: (place: { cwd: string; root: string }) => Promise<void>;
    },
    run: (where: SettingsWhere) => Promise<void>,
  ) {
    const root = await mkdtemp(join(tmpdir(), 'chord-settings-checked-'));
    const home = join(root, 'home');
    const where = {
      home,
      configHome: join(home, '.config'),
      cwd: join(root, 'work'),
    };

    try {
      await mkdir(join(where.configHome, 'chord'), { recursive: true });
      await mkdir(join(where.cwd, '.chord'), { recursive: true });

      if (files.user !== undefined) {
        await writeFile(
          join(where.configHome, 'chord', 'settings.json'),
          files.user,
        );
      }

      if (files.project !== undefined) {
        await writeFile(
          join(where.cwd, '.chord', 'settings.json'),
          files.project,
        );
      }

      await files.plant?.({ cwd: where.cwd, root });
      await run(where);
    } finally {
      await rm(root, { recursive: true });
    }
  }

  async function read(where: SettingsWhere, path?: readonly string[]) {
    const result = await readSettingsTool(where, path);

    assert(!('error' in result));

    return result;
  }

  /** Everything a read or a change gives: the answer, then its rows. */
  function everything(input: unknown, answer: unknown, files?: unknown) {
    const call = {
      tool: 'settings' as const,
      input,
      answer,
      ...(files === undefined
        ? {}
        : { settingsFiles: files as { user: string; project: string } }),
    };

    return JSON.stringify([
      answer,
      files,
      settingsRows(call, false, 80),
      settingsRows(call, true, 80),
    ]);
  }

  /** Reads every key, one key and one change, each checked for the canaries. */
  async function nothingShows(where: SettingsWhere) {
    const whole = await read(where);
    const key = await read(where, ['agent']);
    const planned = await plannedSetting(where, ['agent'], set('codex'), known);

    assert('answer' in planned);

    for (const said of [
      everything({ action: 'read' }, whole.answer, whole.files),
      everything({ action: 'read', path: ['agent'] }, key.answer, key.files),
      everything(
        { action: 'set', path: ['agent'], value: 'codex' },
        planned.answer,
      ),
    ]) {
      expect(said).not.toContain(CANARY);
      expect(said).not.toContain(CANARY_KEY);
    }

    return whole;
  }

  const unknowns = JSON.stringify({
    [CANARY_KEY]: CANARY,
    other: { [CANARY_KEY]: [CANARY] },
    agents: { fake: { [CANARY_KEY]: CANARY, model: 'm' } },
    teamSelection: { [CANARY_KEY]: CANARY },
    agent: 'kept',
  });

  test('a link to a file of unknown keys and values shows none of them', async () => {
    await placed(
      {
        plant: async ({ cwd, root }) => {
          const target = join(root, 'target.json');

          await writeFile(target, unknowns);
          await symlink(target, join(cwd, '.chord', 'settings.json'));
        },
      },
      async (where) => {
        const { answer } = await nothingShows(where);

        // A start follows links, so this is an ordinary read of what is checked.
        expect(answer.project).toMatchObject({ agent: 'kept' });
        expect(answer.effective).toMatchObject({ agent: 'kept' });
        expect(answer.problems.map(({ message }) => message)).toContain(
          '4 keys ignored',
        );
      },
    );
  });

  test('a broken file with a canary token shows no parser word', async () => {
    const broken = `{"agent":${CANARY}}`;

    await placed({ project: broken }, async (where) => {
      const { answer, files } = await nothingShows(where);

      expect(answer.project).toBeNull();
      expect(answer.problems).toStrictEqual([
        {
          file: join('.chord', 'settings.json'),
          message: 'not valid JSON; ignored',
        },
      ]);
      expect(files.project).toEndWith(' · not valid JSON');
    });
  });

  test('wrong-typed values under real keys show neither value', async () => {
    const wrong = JSON.stringify({
      theme: CANARY,
      mouse: CANARY,
      agent: 7,
      preferredNotifChannel: CANARY,
    });

    await placed({ user: wrong }, async (where) => {
      const { answer } = await nothingShows(where);

      expect(answer.user).toStrictEqual({});
      expect(answer.problems).toStrictEqual([
        {
          file: `~${join('/', '.config', 'chord', 'settings.json')}`,
          message: '4 keys ignored',
        },
      ]);
    });
  });

  test('a write over a bad value reads not set, in the answer and on the row', async () => {
    await placed({ user: JSON.stringify({ theme: CANARY }) }, async (where) => {
      const planned = await plannedSetting(
        where,
        ['theme'],
        set('light'),
        known,
      );

      assert('answer' in planned);
      expect('before' in planned.answer).toBe(false);
      expect(
        everything(
          { action: 'set', path: ['theme'], value: 'light' },
          planned.answer,
        ),
      ).not.toContain(CANARY);

      const removed = await plannedSetting(where, ['theme'], remove, known);

      assert('answer' in removed);
      expect(removed.answer.unchanged).toBe(true);
      expect(JSON.stringify(removed)).not.toContain(CANARY);
    });
  });

  test('a server keeps only its shape: token and Env are gone with their values', async () => {
    const server = JSON.stringify({
      mcpServers: {
        local: {
          command: CANARY,
          args: [CANARY],
          env: { TOKEN: CANARY },
          Env: { TOKEN: CANARY },
          token: CANARY,
        },
        remote: {
          type: 'http',
          url: 'https://example.test/x',
          headers: { Auth: CANARY },
          token: CANARY,
        },
        broken: { token: CANARY },
        text: CANARY,
      },
    });

    await placed({ user: server, project: server }, async (where) => {
      const { answer } = await read(where);
      const shown = {
        mcpServers: {
          local: {
            command: '***',
            args: ['***'],
            env: { TOKEN: '***' },
          },
          remote: {
            type: 'http',
            url: '***',
            headers: { Auth: '***' },
          },
        },
      };

      expect(JSON.stringify(answer)).not.toContain(CANARY);
      expect(answer.user).toStrictEqual(shown);
      expect(answer.project).toStrictEqual(shown);
      expect(answer.effective).toStrictEqual(shown);
      // A server's own shape is not a settings problem.
      expect(answer.problems).toStrictEqual([]);
    });
  });

  test('a file that cannot be used is null, one with all its keys dropped is empty, and a key in either is not set', async () => {
    await placed({ user: '{ broken' }, async (where) => {
      expect((await read(where)).answer.user).toBeNull();
      expect((await read(where, ['agent'])).answer.user).toBeUndefined();
    });

    await placed({ user: '{"nope":1}' }, async (where) => {
      expect((await read(where)).answer.user).toStrictEqual({});
      expect((await read(where, ['agent'])).answer.user).toBeUndefined();
    });

    await placed({ user: '{}' }, async (where) => {
      expect((await read(where)).answer.user).toStrictEqual({});
    });
  });

  test('a path reads what is masked, and below a leaf is not set', async () => {
    const server = JSON.stringify({
      mcpServers: { x: { command: CANARY, env: { TOKEN: CANARY } } },
      agents: {
        url: { model: 'm', mcpServers: false },
        a: { command: CANARY },
      },
    });

    await placed({ user: server }, async (where) => {
      const at = async (...path: string[]) =>
        (await read(where, path)).answer.user;

      expect(await at('mcpServers', 'x', 'env', 'TOKEN')).toBe('***');
      expect(
        await at('mcpServers', 'x', 'env', 'TOKEN', 'more'),
      ).toBeUndefined();
      expect(await at('agents', 'a', 'command')).toBe('***');
      // An agent merely named url is masked whole.
      expect(await at('agents', 'url')).toStrictEqual({
        model: '***',
        mcpServers: '***',
      });
    });
  });

  test('a boolean agents.<name>.mcpServers stays', async () => {
    await placed(
      { user: '{"agents":{"a":{"mcpServers":false,"model":"m"}}}' },
      async (where) => {
        expect((await read(where)).answer.user).toStrictEqual({
          agents: { a: { mcpServers: false, model: 'm' } },
        });
      },
    );
  });

  test('a project key only the user may set is counted, naming nothing', async () => {
    await placed(
      { project: JSON.stringify({ theme: 'dark', mouse: false }) },
      async (where) => {
        const { answer } = await read(where);

        expect(answer.project).toStrictEqual({});
        expect(answer.problems).toStrictEqual([
          {
            file: join('.chord', 'settings.json'),
            message: "2 keys only the user's file may set; ignored",
          },
        ]);
      },
    );
  });

  test('one key ignored, and a path read carries the whole list', async () => {
    await placed({ user: '{"nope":1,"agent":"a"}' }, async (where) => {
      const { answer } = await read(where, ['agent']);

      expect(answer.user).toBe('a');
      expect(answer.problems.map(({ message }) => message)).toStrictEqual([
        '1 key ignored',
      ]);
    });
  });

  test('absent, not an object, unreadable, no home and a name no key has', async () => {
    await placed({}, async (where) => {
      const { answer, files } = await read(where);

      expect(answer.user).toBeNull();
      expect(answer.project).toBeNull();
      expect(answer.effective).toStrictEqual({});
      expect(answer.problems).toStrictEqual([]);
      expect(files.user).toEndWith(' · not there');
    });

    await placed({ project: '["x"]' }, async (where) => {
      const { answer, files } = await read(where);

      expect(answer.project).toBeNull();
      expect(answer.problems[0]?.message).toBe('not a JSON object; ignored');
      expect(files.project).toEndWith(' · not a JSON object');
    });

    await placed({}, async (where) => {
      await mkdir(join(where.configHome!, 'chord', 'settings.json'));

      const { answer, files } = await read(where);

      expect(answer.user).toBeNull();
      expect(answer.problems[0]?.message).toBe('cannot be read; ignored');
      expect(JSON.stringify(answer)).not.toContain(where.home!);
      expect(files.user).toEndWith(' · cannot be read');
    });

    await placed({ project: '{"agent":"a"}' }, async (where) => {
      const { answer, files } = await read({
        ...where,
        configHome: undefined,
        home: undefined,
      });

      expect(answer.user).toBeNull();
      expect(answer.effective).toStrictEqual({ agent: 'a' });
      expect(files.user).toBe('no home directory');
    });

    await placed({}, async (where) => {
      expect(await readSettingsTool(where, ['__proto__'])).toStrictEqual({
        error: 'No setting __proto__',
      });
    });
  });

  test('with HOME unset, no answer names the home', async () => {
    // Under the home but absent, so nothing reads a real settings file.
    const configHome = join(homedir(), '.chord-test-absent-config');

    await placed({ project: '{"theme":"dark"}' }, async (where) => {
      const { answer, files } = await read({
        ...where,
        configHome,
        home: undefined,
      });

      expect(JSON.stringify({ answer, files })).not.toContain(homedir());
      expect(files.user).toStartWith('~');
    });
  });

  test('the project shadows from its checked layer alone', async () => {
    const shadowedBy = join('.chord', 'settings.json');

    await placed(
      { project: '{"agent":"codex"}', user: '{"agent":"claude"}' },
      async (where) => {
        expect(
          await plannedSetting(where, ['agent'], set('fake'), [
            'fake',
            ...known,
          ]),
        ).toMatchObject({ answer: { shadowedBy } });
      },
    );
    await placed({ project: '{"agent":7,"theme":"dark"}' }, async (where) => {
      for (const path of [['agent'], ['theme']]) {
        const planned = await plannedSetting(
          where,
          path,
          set(path[0] === 'agent' ? 'codex' : 'light'),
          known,
        );

        assert('answer' in planned);
        expect('shadowedBy' in planned.answer).toBe(false);
      }
    });
  });
});

describe('CHD-568 U9 tester: checked plans and linked reads', () => {
  async function fixture(
    run: (where: SettingsWhere, user: string, project: string) => Promise<void>,
  ) {
    const root = await mkdtemp(join(tmpdir(), 'chord-settings-u7-tester-'));
    const where: SettingsWhere = {
      home: root,
      configHome: join(root, '.config'),
      cwd: join(root, 'work'),
    };
    const user = join(where.configHome!, 'chord', 'settings.json');
    const project = join(where.cwd, '.chord', 'settings.json');

    try {
      await mkdir(join(user, '..'), { recursive: true });
      await mkdir(join(project, '..'), { recursive: true });
      await run(where, user, project);
    } finally {
      await rm(root, { recursive: true });
    }
  }

  test('a malformed leaf is absent from a set plan and unchanged on removal', async () => {
    await fixture(async (where, user) => {
      const before = {
        env: { LIST: ['env-canary', { nested: 'env-canary' }] },
        command: ['command-canary'],
        mcpServers: { token: 'mcp-canary' },
        keep: 3,
      };
      const text = JSON.stringify({ agents: { claude: { model: before } } });

      await writeFile(user, text);

      for (const change of [set('new-model'), remove]) {
        const result = await plannedSetting(
          where,
          ['agents', 'claude', 'model'],
          change,
          known,
        );

        assert('answer' in result);
        expect(result.answer.before).toBeUndefined();

        if ('remove' in change) {
          expect(result.answer.unchanged).toBe(true);
        } else {
          expect(result.answer.after).toBe('new-model');
        }

        expect(JSON.stringify(result)).not.toContain('canary');
        expect(await readFile(user, 'utf8')).toBe(text);
      }
    });
  });

  test('linked unknown fields and server tokens stay out of every answer and row', async () => {
    await fixture(async (where, user, project) => {
      const target = join(where.home!, 'checked-target.json');
      const text = JSON.stringify({
        UNKNOWN_KEY_CANARY: 'UNKNOWN_VALUE_CANARY',
        agents: { worker: { model: 'kept', FIELD_CANARY: 'AGENT_CANARY' } },
        teamSelection: { intent: 'economy', FIELD_CANARY: 'TEAM_CANARY' },
        mcpServers: {
          linear: {
            command: 'COMMAND_CANARY',
            args: ['ARGS_CANARY'],
            env: { TOKEN: 'ENV_CANARY' },
            token: 'TOKEN_CANARY',
            Env: { TOKEN: 'WRONG_CASE_CANARY' },
          },
          invalid: { token: 'INVALID_SERVER_CANARY' },
        },
      });

      await writeFile(user, '{"agent":"claude"}');
      await writeFile(target, text);
      await symlink(target, project);

      for (const path of [
        [],
        ['mcpServers'],
        ['mcpServers', 'linear', 'token'],
        ['mcpServers', 'linear', 'env', 'TOKEN'],
        ['agents', 'worker'],
      ]) {
        const result = await readSettingsTool(where, path);

        assert('answer' in result);
        expect(JSON.stringify(result)).not.toContain('CANARY');

        for (const width of [80, 120]) {
          for (const expanded of [false, true]) {
            const rows = settingsRows(
              {
                tool: 'settings',
                input: { action: 'read', path },
                answer: result.answer,
                settingsFiles: result.files,
              },
              expanded,
              width,
            );

            expect(JSON.stringify(rows)).not.toContain('CANARY');
          }
        }
      }

      expect(await readFile(target, 'utf8')).toBe(text);
      expect(await readFile(user, 'utf8')).toBe('{"agent":"claude"}');
    });
  });

  test('two broken layers expose only fixed parse words, including a linked project', async () => {
    await fixture(async (where, user, project) => {
      const target = join(where.home!, 'broken-target.json');

      await writeFile(user, '{"theme":USER_BROKEN_CANARY}');
      await writeFile(target, '{"KEY_CANARY":PROJECT_BROKEN_CANARY}');
      await symlink(target, project);

      for (const path of [[], ['theme']]) {
        const result = await readSettingsTool(where, path);

        assert('answer' in result);
        expect(result.answer.problems.map(({ message }) => message)).toEqual([
          'not valid JSON; ignored',
          'not valid JSON; ignored',
        ]);
        expect(JSON.stringify(result)).not.toContain('CANARY');

        for (const expanded of [false, true]) {
          expect(
            JSON.stringify(
              settingsRows(
                {
                  tool: 'settings',
                  input: { action: 'read', path },
                  answer: result.answer,
                  settingsFiles: result.files,
                },
                expanded,
                80,
              ),
            ),
          ).not.toContain('CANARY');
        }
      }
    });
  });

  test('completed reads follow a link, then observe a regular file and dangling replacement', async () => {
    await fixture(async (where, user, project) => {
      const target = join(where.home!, 'target.json');

      await writeFile(user, '{"agent":"claude"}');
      await writeFile(target, '{"agent":"codex","linked-canary":1,"theme":3}');
      await symlink(target, project);

      const linked = await readSettingsTool(where, ['agent']);

      assert('answer' in linked);
      expect(linked.answer.project).toBe('codex');
      expect(linked.answer.effective).toBe('codex');
      expect(JSON.stringify(linked)).not.toContain('linked-canary');
      expect(linked.answer.problems).toHaveLength(1);

      await rm(project);
      await writeFile(project, '{"agent":"claude"}');

      const regular = await readSettingsTool(where, ['agent']);

      assert('answer' in regular);
      expect(regular.answer.project).toBe('claude');
      expect(regular.answer.effective).toBe('claude');
      expect(regular.answer.problems).toEqual([]);

      await rm(project);
      await symlink(join(where.home!, 'absent-target'), project);

      const dangling = await readSettingsTool(where, ['agent']);

      assert('answer' in dangling);
      expect(dangling.answer.project).toBeUndefined();
      expect(dangling.answer.effective).toBe('claude');
      expect(dangling.files.project).toEndWith(' · not there');
      expect(dangling.answer.problems).toEqual([]);
    });
  });
});
