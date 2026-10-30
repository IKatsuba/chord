import { describe, expect, test } from 'bun:test';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  classifySetting,
  maskedSettings,
  notSavedLine,
  readSettingsTool,
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
      url: 'https://mcp.example/linear',
      args: ['--flag'],
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
      agents: { codex: { command: 'codex-acp --key=visible' } },
    });

    await placed({ user }, async (where) => {
      const { answer, files } = await read(where);
      const said = JSON.stringify(answer);

      expect(said).not.toContain(SECRET);
      expect(answer.project).toBeNull();
      expect(answer.user).toMatchObject({
        theme: 'dark',
        unknownKey: 1,
        agents: { codex: { command: 'codex-acp --key=visible' } },
        mcpServers: {
          linear: {
            url: 'https://mcp.example/linear',
            args: ['--flag'],
            env: { TOKEN: '***', LIST: '***', DEEP: '***' },
            headers: { Authorization: '***' },
          },
          wrong: { env: '***', headers: '***' },
          listed: [{ env: { TOKEN: '***' } }],
          bare: 9,
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

        expect(under.answer.user).toBeUndefined();
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
        mcpServers: [server, [{ env: '***', headers: '***' }]],
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
