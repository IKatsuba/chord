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
  maskedSettings,
  notSavedLine,
  plannedSetting,
  readSettingsTool,
  saveFailure,
  type SettingsRead,
  settingRefusal,
  type SettingsWhere,
} from '../src/settings_tool.ts';

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

describe('CHD-568 U3 tester: masked fresh reads', () => {
  test('masking preserves hostile own key names without changing the raw object', () => {
    const raw: unknown = JSON.parse(
      '{"mcpServers":{"__proto__":{"env":{"__proto__":"secret-a","constructor":["secret-b"]},"headers":null},"toString":[[{"headers":{"Auth":{"deep":"secret-c"}}}]]}}',
    );
    const before = JSON.stringify(raw);
    const masked = maskedSettings(raw);

    expect(masked).toEqual(
      JSON.parse(
        '{"mcpServers":{"__proto__":{"env":{"__proto__":"***","constructor":["***"]},"headers":"***"},"toString":"***"}}',
      ),
    );
    expect(JSON.stringify(masked)).not.toContain('secret-');
    expect(JSON.stringify(raw)).toBe(before);
  });

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
      expect(JSON.stringify(broken)).toContain(
        'not valid JSON; the file is ignored',
      );

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

describe('reading settings (CHD-568)', () => {
  /** A home under a temporary root, with the files given written in it. */
  async function placed(
    files: { user?: string; project?: string },
    run: (where: SettingsWhere) => Promise<void>,
  ) {
    const root = await mkdtemp(join(tmpdir(), 'chord-settings-read-'));
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

      await run(where);
    } finally {
      await rm(root, { recursive: true });
    }
  }

  async function read(
    where: SettingsWhere,
    path?: readonly string[],
  ): Promise<{
    answer: SettingsRead;
    files: { user: string; project: string };
  }> {
    const result = await readSettingsTool(where, path);

    if ('error' in result) {
      throw new Error(result.error);
    }

    return result;
  }

  const SECRET = 'secret123';
  const servers = {
    linear: {
      url: SECRET,
      args: ['--flag', SECRET],
      env: { TOKEN: SECRET, LIST: [SECRET], DEEP: { A: SECRET } },
      headers: { Authorization: SECRET },
    },
    wrong: { env: SECRET, headers: [SECRET] },
    listed: [{ env: { TOKEN: SECRET } }],
    bare: SECRET.length,
  };

  test('every key reads as written, masked in all three, the rest whole', async () => {
    const user = JSON.stringify({
      theme: 'dark',
      unknownKey: 1,
      mcpServers: servers,
      agents: { codex: { command: SECRET, mcpServers: false } },
    });

    await placed({ user }, async (where) => {
      const { answer, files } = await read(where);
      const said = JSON.stringify(answer);

      expect(said).not.toContain(SECRET);
      expect(answer.project).toBeNull();
      expect(answer.user).toMatchObject({
        theme: 'dark',
        unknownKey: 1,
        agents: { codex: { command: '***', mcpServers: false } },
        mcpServers: {
          linear: {
            url: '***',
            args: ['***', '***'],
            env: { TOKEN: '***', LIST: ['***'], DEEP: { A: '***' } },
            headers: { Authorization: '***' },
          },
          wrong: { env: '***', headers: ['***'] },
          listed: '***',
          bare: '***',
        },
      });
      expect(answer.effective).toMatchObject({
        theme: 'dark',
        mcpServers: { linear: { env: { TOKEN: '***' } } },
      });
      expect(files).toStrictEqual({
        user: `~${join('/', '.config', 'chord', 'settings.json')} · 4 keys`,
        project: `${join('.chord', 'settings.json')} · not there`,
      });
    });
  });

  test('a project file is masked too and wins in effective', async () => {
    await placed(
      {
        user: '{"agent":"claude"}',
        project: JSON.stringify({
          agent: 'codex',
          mcpServers: { x: { env: { T: SECRET } } },
        }),
      },
      async (where) => {
        const { answer } = await read(where);

        expect(JSON.stringify(answer)).not.toContain(SECRET);
        expect(answer.user).toStrictEqual({ agent: 'claude' });
        expect(answer.project).toStrictEqual({
          agent: 'codex',
          mcpServers: { x: { env: { T: '***' } } },
        });
        expect(answer.effective).toMatchObject({ agent: 'codex' });
      },
    );
  });

  test('a path walks what is masked, one path deeper being not set', async () => {
    await placed(
      { user: JSON.stringify({ mcpServers: servers }) },
      async (where) => {
        const key = ['mcpServers', 'linear', 'env', 'TOKEN'];

        expect((await read(where, key)).answer).toStrictEqual({
          user: '***',
          project: undefined,
          effective: '***',
          problems: [],
        });

        const deeper = await read(where, [...key, 'more']);

        expect(deeper.answer.user).toBeUndefined();
        expect(deeper.answer.effective).toBeUndefined();

        const under = await read(where, [
          'mcpServers',
          'linear',
          'env',
          'DEEP',
          'A',
        ]);

        expect(under.answer.user).toBe('***');
        expect(JSON.stringify(under)).not.toContain(SECRET);
      },
    );
  });

  test('an unknown key reads, and a name that can be no key is refused', async () => {
    await placed({ user: '{"nope":{"deep":1}}' }, async (where) => {
      const { answer } = await read(where, ['nope', 'deep']);

      expect(answer.user).toBe(1);
      expect(answer.effective).toBeUndefined();
      expect(await readSettingsTool(where, ['__proto__'])).toStrictEqual({
        error: 'No setting __proto__',
      });
      expect(await readSettingsTool(where, ['a', 'constructor'])).toStrictEqual(
        {
          error: 'No setting a.constructor',
        },
      );
    });
  });

  test("a broken file with a secret drops the parser's words", async () => {
    // Bun's parser quotes the token it choked on.
    const user = `{"mcpServers":{"x":{"env":{"T":${SECRET}}}}}`;

    await placed({ user }, async (where) => {
      const { answer, files } = await read(where);

      expect(JSON.stringify(answer)).not.toContain(SECRET);
      expect(answer.user).toBeNull();
      expect(answer.problems).toStrictEqual([
        {
          file: `~${join('/', '.config', 'chord', 'settings.json')}`,
          message: 'not valid JSON; the file is ignored',
        },
      ]);
      expect(files.user).toEndWith(' · not valid JSON');
    });
  });

  test('a file that is no object reads null, and says so', async () => {
    await placed({ project: '["x"]' }, async (where) => {
      const { answer, files } = await read(where);

      expect(answer.project).toBeNull();
      expect(answer.problems.map(({ message }) => message)).toStrictEqual([
        'not a JSON object; the file is ignored',
      ]);
      expect(files.project).toEndWith(' · not a JSON object');
    });
  });

  test('no home reads the project alone and says so', async () => {
    await placed({ project: '{"agent":"codex"}' }, async (where) => {
      const { answer, files } = await read({
        ...where,
        configHome: undefined,
        home: undefined,
      });

      expect(answer.user).toBeNull();
      expect(answer.effective).toStrictEqual({ agent: 'codex' });
      expect(files.user).toBe('no home directory');
    });
  });

  test('a file that cannot be read names no path in its problem', async () => {
    await placed({}, async (where) => {
      // A directory where the file goes: read fails, and not as absent.
      await mkdir(join(where.configHome!, 'chord', 'settings.json'));

      const { answer, files } = await read(where);

      expect(answer.user).toBeNull();
      expect(answer.problems).toStrictEqual([
        {
          file: `~${join('/', '.config', 'chord', 'settings.json')}`,
          message: 'cannot be read; the file is ignored',
        },
      ]);
      expect(files.user).toEndWith(' · cannot be read');
    });
  });

  test("a path keeps its key's problems and those of a whole file", async () => {
    await placed(
      {
        user: '{"theme":3,"mouse":"no"}',
        project: '{ broken',
      },
      async (where) => {
        const keys = (answer: SettingsRead) =>
          answer.problems.map(({ message }) => message);

        expect(keys((await read(where)).answer)).toHaveLength(3);

        const theme = keys((await read(where, ['theme'])).answer);

        expect(theme).toHaveLength(2);
        expect(theme[0]).toContain('"theme"');
        expect(theme[1]).toBe('not valid JSON; the file is ignored');
        expect(keys((await read(where, ['agent'])).answer)).toStrictEqual([
          'not valid JSON; the file is ignored',
        ]);
      },
    );
  });

  test('an mcpServers no server can be read from fails closed, in every view', async () => {
    const listed = JSON.stringify({
      mcpServers: [
        { env: { TOKEN: SECRET }, headers: { Authorization: SECRET } },
        [{ env: SECRET, headers: [SECRET] }],
      ],
    });

    await placed({ user: listed, project: listed }, async (where) => {
      const { answer } = await read(where);
      const server = {
        env: { TOKEN: '***' },
        headers: { Authorization: '***' },
      };
      const masked = {
        mcpServers: [server, '***'],
      };

      expect(JSON.stringify(answer)).not.toContain(SECRET);
      expect(answer.user).toStrictEqual(masked);
      expect(answer.project).toStrictEqual(masked);
    });

    await placed(
      { user: JSON.stringify({ mcpServers: SECRET }) },
      async (where) => {
        const { answer } = await read(where);

        expect(JSON.stringify(answer)).not.toContain(SECRET);
        expect(answer.user).toStrictEqual({ mcpServers: '***' });
      },
    );
  });

  test('with HOME unset, no answer names the home the config was found under', async () => {
    // Under the home but absent, so nothing reads a real settings file.
    const configHome = join(homedir(), '.chord-test-absent-config');
    const file = join(
      '/',
      '.chord-test-absent-config',
      'chord',
      'settings.json',
    );

    await placed({ project: '{"theme":"dark"}' }, async (where) => {
      const { answer, files } = await read({
        ...where,
        configHome,
        home: undefined,
      });

      expect(JSON.stringify({ answer, files })).not.toContain(homedir());
      expect(files.user).toBe(`~${file} · not there`);
      expect(answer.problems.map(({ message }) => message)).toStrictEqual([
        `"theme" is read only from ~${file}, ignored`,
      ]);
    });
  });

  test('a broken user file and a scoped project key name no home', async () => {
    await placed(
      { user: '{ broken', project: '{"theme":"dark"}' },
      async (where) => {
        const { answer, files } = await read(where);

        expect(JSON.stringify({ answer, files })).not.toContain(where.home!);
        expect(answer.problems.map(({ file }) => file)).toContain(
          `~${join('/', '.config', 'chord', 'settings.json')}`,
        );
      },
    );
  });

  test('maskedSettings leaves a settings with nothing to mask as it is', () => {
    for (const value of [null, 3, ['x'], { theme: 'dark' }]) {
      expect(maskedSettings(value)).toStrictEqual(value);
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

describe('masking goes by key name (CHD-568)', () => {
  const S = 'secret123';

  test.each(['env', 'headers', 'command', 'args', 'url'])(
    '%s is masked wherever it stands, its shape kept',
    (key) => {
      const given = {
        [key]: S,
        agents: { a: { [key]: [S, { deep: S }] } },
        mcpServers: { x: { [key]: { one: S, two: [S] } } },
        odd: [{ nested: { [key]: 3 } }],
        keep: 'kept',
      };

      expect(maskedSettings(given)).toStrictEqual({
        [key]: '***',
        agents: { a: { [key]: ['***', { deep: '***' }] } },
        mcpServers: { x: { [key]: { one: '***', two: ['***'] } } },
        odd: [{ nested: { [key]: '***' } }],
        keep: 'kept',
      });
    },
  );

  test('a name standing where a key would be masks whole, and null is a leaf', () => {
    expect(
      maskedSettings({
        mcpServers: { url: { type: 'http', name: S } },
        env: null,
      }),
    ).toStrictEqual({
      mcpServers: { url: { type: '***', name: '***' } },
      env: '***',
    });
  });

  test('a server of the wrong shape reads whole, in a map or a list', () => {
    expect(
      maskedSettings({
        mcpServers: {
          text: S,
          number: 3,
          empty: null,
          list: [S],
          real: { type: 'http', token: 'as-written' },
        },
      }),
    ).toStrictEqual({
      mcpServers: {
        text: '***',
        number: '***',
        empty: '***',
        list: '***',
        real: { type: 'http', token: 'as-written' },
      },
    });
    expect(
      maskedSettings({ mcpServers: [S, 3, null, [S], { type: 'http' }] }),
    ).toStrictEqual({
      mcpServers: ['***', '***', '***', '***', { type: 'http' }],
    });
    expect(maskedSettings({ mcpServers: null })).toStrictEqual({
      mcpServers: '***',
    });
  });

  test('a path into a server of the wrong shape is not set', async () => {
    const root = await mkdtemp(join(tmpdir(), 'chord-settings-server-'));
    const where = {
      home: root,
      configHome: root,
      cwd: join(root, 'work'),
    };

    try {
      await mkdir(join(root, 'chord'));
      await writeFile(
        join(root, 'chord', 'settings.json'),
        JSON.stringify({ mcpServers: { x: S, list: [{ token: S }] } }),
      );

      const whole = await readSettingsTool(where);
      const inside = await readSettingsTool(where, ['mcpServers', 'list', '0']);

      expect(JSON.stringify(whole)).not.toContain(S);
      assert(!('error' in inside));
      expect(inside.answer.user).toBeUndefined();
    } finally {
      await rm(root, { recursive: true });
    }
  });

  test('an agents.<name>.mcpServers that is no boolean reads whole', () => {
    for (const held of [S, 3, null, [S], { deep: S }]) {
      expect(
        maskedSettings({ agents: { a: { mcpServers: held, model: 'm' } } }),
      ).toStrictEqual({ agents: { a: { mcpServers: '***', model: 'm' } } });
    }
  });

  test('a key named mcpServers below the top reads whole unless a boolean, whatever holds it', () => {
    expect(
      maskedSettings({
        agents: { a: [{ mcpServers: S }], b: { deep: { mcpServers: [S] } } },
        odd: [{ nested: { mcpServers: { x: S } } }],
        kept: [{ mcpServers: false }],
      }),
    ).toStrictEqual({
      agents: {
        a: [{ mcpServers: '***' }],
        b: { deep: { mcpServers: '***' } },
      },
      odd: [{ nested: { mcpServers: '***' } }],
      kept: [{ mcpServers: false }],
    });
  });

  test('a path below such a key is not set', async () => {
    const root = await mkdtemp(join(tmpdir(), 'chord-settings-below-'));
    const where = { home: root, configHome: root, cwd: join(root, 'work') };

    try {
      await mkdir(join(root, 'chord'));
      await writeFile(
        join(root, 'chord', 'settings.json'),
        JSON.stringify({ agents: { a: { mcpServers: { token: S } } } }),
      );

      const below = await readSettingsTool(where, [
        'agents',
        'a',
        'mcpServers',
        'token',
      ]);

      assert(!('error' in below));
      expect(below.answer.user).toBeUndefined();
      expect(JSON.stringify(below)).not.toContain(S);
    } finally {
      await rm(root, { recursive: true });
    }
  });

  test('a list of agents masks the same, in a read of every key', async () => {
    const root = await mkdtemp(join(tmpdir(), 'chord-settings-agents-'));
    const where = { home: root, configHome: root, cwd: join(root, 'work') };

    try {
      await mkdir(join(root, 'chord'));
      await writeFile(
        join(root, 'chord', 'settings.json'),
        JSON.stringify({
          agents: [{ mcpServers: S }, { mcpServers: true }, S],
        }),
      );

      const read = await readSettingsTool(where);

      assert(!('error' in read));
      expect(read.answer.user).toStrictEqual({
        agents: [{ mcpServers: '***' }, { mcpServers: true }, S],
      });
    } finally {
      await rm(root, { recursive: true });
    }
  });

  test('a boolean agents.<name>.mcpServers stays', () => {
    expect(
      maskedSettings({ agents: { a: { mcpServers: false, model: 'm' } } }),
    ).toStrictEqual({ agents: { a: { mcpServers: false, model: 'm' } } });
  });

  test("a file's own __proto__ key stays a key, and masks under it", () => {
    const masked = maskedSettings(
      JSON.parse(`{"__proto__":{"env":"${S}"}}`),
    ) as object;

    expect(JSON.stringify(masked)).toBe('{"__proto__":{"env":"***"}}');
    expect(({} as Record<string, unknown>)['env']).toBeUndefined();
  });
});

describe('a linked project file (CHD-568)', () => {
  const CANARY = 'linked-canary-value';
  const shownFile = join('.chord', 'settings.json');
  const words = (name: string) =>
    `${name} is a symbolic link, so it was not read: project and effective omit it. A start still follows the link`;

  /** A project with `plant` run in it, and a target holding the canary. */
  async function linked(
    plant: (place: { cwd: string; target: string }) => Promise<void>,
    run: (where: SettingsWhere) => Promise<void>,
    user = '{"theme":"dark"}',
  ) {
    const root = await mkdtemp(join(tmpdir(), 'chord-settings-linked-'));
    const home = join(root, 'home');
    const cwd = join(root, 'work');
    const target = join(root, 'target.json');
    const where = { home, configHome: join(home, '.config'), cwd };

    try {
      await mkdir(join(where.configHome, 'chord'), { recursive: true });
      await mkdir(cwd);
      await writeFile(join(where.configHome, 'chord', 'settings.json'), user);
      await writeFile(
        target,
        JSON.stringify({ agent: CANARY, theme: 'light', nope: CANARY }),
      );
      await plant({ cwd, target });
      await run(where);
    } finally {
      await rm(root, { recursive: true });
    }
  }

  async function reads(where: SettingsWhere, path?: readonly string[]) {
    const result = await readSettingsTool(where, path);

    assert(!('error' in result));

    return result;
  }

  const fileLink = async ({ cwd, target }: { cwd: string; target: string }) => {
    await mkdir(join(cwd, '.chord'));
    await symlink(target, join(cwd, '.chord', 'settings.json'));
  };

  test('a link at the file reads null, says so, and shows nothing of its target', async () => {
    await linked(fileLink, async (where) => {
      const { answer, files } = await reads(where);

      expect(JSON.stringify({ answer, files })).not.toContain(CANARY);
      expect(answer.project).toBeNull();
      expect(answer.user).toStrictEqual({ theme: 'dark' });
      expect(answer.effective).toStrictEqual({ theme: 'dark' });
      expect(answer.problems).toStrictEqual([
        { file: shownFile, message: words(shownFile) },
      ]);
      expect(files).toMatchObject({
        project: `${shownFile} · a symbolic link, not read`,
        projectLinked: true,
      });
    });
  });

  test('a link at .chord names .chord', async () => {
    await linked(
      async ({ cwd, target }) => {
        const elsewhere = join(cwd, '..', 'elsewhere');

        await mkdir(elsewhere);
        await writeFile(
          join(elsewhere, 'settings.json'),
          await readFile(target),
        );
        await symlink(elsewhere, join(cwd, '.chord'));
      },
      async (where) => {
        const { answer } = await reads(where);

        expect(JSON.stringify(answer)).not.toContain(CANARY);
        expect(answer.problems).toStrictEqual([
          { file: shownFile, message: words('.chord') },
        ]);
      },
    );
  });

  test('a dangling link is a link, not an absent file', async () => {
    await linked(
      async ({ cwd }) => {
        await mkdir(join(cwd, '.chord'));
        await symlink(
          join(cwd, 'nothing-there'),
          join(cwd, '.chord', 'settings.json'),
        );
      },
      async (where) => {
        const { answer, files } = await reads(where);

        expect(answer.project).toBeNull();
        expect(answer.problems[0]?.message).toBe(words(shownFile));
        expect(files.projectLinked).toBe(true);
      },
    );
  });

  test('a working directory under a link is not refused', async () => {
    await linked(
      async ({ cwd }) => {
        await mkdir(join(cwd, '.chord'));
        await writeFile(
          join(cwd, '.chord', 'settings.json'),
          '{"agent":"codex"}',
        );
        await symlink(cwd, join(cwd, '..', 'linked-work'));
      },
      async (where) => {
        const { answer, files } = await reads({
          ...where,
          cwd: join(where.cwd, '..', 'linked-work'),
        });

        expect(answer.project).toStrictEqual({ agent: 'codex' });
        expect(answer.problems).toStrictEqual([]);
        expect(files.projectLinked).toBeUndefined();
      },
    );
  });

  test('an absent file stays null with no problem', async () => {
    await linked(
      () => Promise.resolve(),
      async (where) => {
        const { answer, files } = await reads(where);

        expect(answer.project).toBeNull();
        expect(answer.problems).toStrictEqual([]);
        expect(files.projectLinked).toBeUndefined();
      },
    );
  });

  test('a path read reads null for it, and keeps the problem', async () => {
    await linked(fileLink, async (where) => {
      const { answer, files } = await reads(where, ['agent']);

      expect(answer.project).toBeNull();
      expect(answer.user).toBeUndefined();
      expect(answer.effective).toBeUndefined();
      expect(answer.problems).toHaveLength(1);
      expect(files.projectLinked).toBe(true);
    });
  });

  test("the user's own problems still come, the linked file's none", async () => {
    await linked(
      fileLink,
      async (where) => {
        const { answer } = await reads(where);

        expect(answer.problems.map(({ message }) => message)).toStrictEqual([
          'not valid JSON; the file is ignored',
          words(shownFile),
        ]);
        expect(answer.effective).toStrictEqual({});
      },
      '{ broken',
    );
  });

  test('a user file that is a link is read', async () => {
    await linked(
      () => Promise.resolve(),
      async (where) => {
        const file = join(where.configHome!, 'chord', 'settings.json');
        const real = join(where.configHome!, 'real.json');

        await writeFile(real, '{"theme":"light"}');
        await rm(file);
        await symlink(real, file);

        const { answer } = await reads(where);

        expect(answer.user).toStrictEqual({ theme: 'light' });
        expect(answer.problems).toStrictEqual([]);
      },
    );
  });

  test('no home with a linked file leaves effective empty', async () => {
    await linked(fileLink, async (where) => {
      const { answer, files } = await reads({
        ...where,
        configHome: undefined,
        home: undefined,
      });

      expect(answer.effective).toStrictEqual({});
      expect(files.user).toBe('no home directory');
    });
  });

  test('a write still says a linked file shadows a key, and no value', async () => {
    await linked(fileLink, async (where) => {
      const planned = await plannedSetting(
        where,
        ['agent'],
        set('codex'),
        known,
      );

      assert('answer' in planned);
      expect(planned.answer.shadowedBy).toBe(shownFile);
      expect(JSON.stringify(planned)).not.toContain(CANARY);
    });
  });
});

describe('CHD-568 U7 tester: masked plans and completed link transitions', () => {
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

  test('set and remove plans mask a malformed leaf by its full path and preserve file bytes', async () => {
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
        expect(result.answer.before).toEqual({
          env: { LIST: ['***', { nested: '***' }] },
          command: ['***'],
          mcpServers: '***',
          keep: 3,
        });
        expect(JSON.stringify(result)).not.toContain('canary');
        expect(await readFile(user, 'utf8')).toBe(text);
      }
    });
  });

  test('later completed reads distinguish a removed link, regular file and dangling replacement', async () => {
    await fixture(async (where, user, project) => {
      const target = join(where.home!, 'target.json');

      await writeFile(user, '{"agent":"claude"}');
      await writeFile(target, '{"agent":"linked-canary","theme":3}');
      await symlink(target, project);

      const linked = await readSettingsTool(where, ['agent']);

      assert('answer' in linked);
      expect(linked.answer.project).toBeNull();
      expect(linked.answer.effective).toBe('claude');
      expect(JSON.stringify(linked)).not.toContain('linked-canary');
      expect(linked.answer.problems).toHaveLength(1);

      await rm(project);
      await writeFile(project, '{"agent":"codex"}');

      const regular = await readSettingsTool(where, ['agent']);

      assert('answer' in regular);
      expect(regular.answer.project).toBe('codex');
      expect(regular.answer.effective).toBe('codex');
      expect(regular.answer.problems).toEqual([]);
      expect(regular.files.projectLinked).toBeUndefined();

      await rm(project);
      await symlink(join(where.home!, 'absent-target'), project);

      const dangling = await readSettingsTool(where, ['agent']);

      assert('answer' in dangling);
      expect(dangling.answer.project).toBeNull();
      expect(dangling.answer.effective).toBe('claude');
      expect(dangling.files.projectLinked).toBe(true);
      expect(dangling.answer.problems).toHaveLength(1);
    });
  });
});
