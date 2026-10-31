import { describe, expect, test } from 'bun:test';
import { readdirSync } from 'node:fs';
import {
  chmod,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  agentCommands,
  canBeSettingPath,
  homePath,
  knownAgents,
  loadSettings,
  mergeSettings,
  NO_SETTINGS_HOME,
  parseSettings,
  problemLine,
  problemNote,
  refusalLine,
  readSettingsObject,
  readTeamSelection,
  resolveStartup,
  resumedStartup,
  saveEditorMode,
  saveSettingAt,
  saveTheme,
  settingAt,
  settingParentProblem,
  settingsFiles,
  setWhere,
  shownPath,
  shownSettingPath,
  shownValue,
  startupOf,
  unknownOffered,
  unseenProblems,
} from '../src/settings.ts';
import { parse } from 'shell-quote';
import { commandLine, listedAgents } from '../src/agents.ts';
import { commandArgv } from '../src/acp/process.ts';
import { resumeCommand, resumeMessage } from '../src/session/sessions.ts';

describe('CHD-565 tester: offered settings isolation and fresh reads', () => {
  test('many invalid elements cost one key without exhausting file recovery', () => {
    for (const offeredAgents of [
      Array.from({ length: 20 }, () => null),
      ['known', { name: 'nested' }, ['another']],
      false,
      7,
    ]) {
      const parsed = parseSettings(
        'fixture.json',
        JSON.stringify({
          offeredAgents,
          agent: 'fixture',
          theme: 'light',
          agents: { fixture: { command: ['fixture', '--acp'] } },
        }),
      );

      expect(parsed.settings).toEqual({
        agent: 'fixture',
        theme: 'light',
        agents: { fixture: { command: ['fixture', '--acp'] } },
      });
      expect(parsed.problems).toHaveLength(1);
      expect(parsed.problems[0]).toMatchObject({
        file: 'fixture.json',
        kind: 'validation',
        key: ['offeredAgents'],
      });
    }
  });

  for (const userValid of [false, true]) {
    test(`a ${userValid ? 'bad' : 'valid'} project list cannot replace the user's ${userValid ? 'valid' : 'bad'} list`, () =>
      place(
        {
          user: JSON.stringify({
            offeredAgents: userValid ? ['mine', 'other'] : ['mine', null],
            theme: 'light',
          }),
          project: JSON.stringify({
            offeredAgents: userValid ? [null] : ['project-only'],
            agent: 'project-only',
          }),
        },
        async (where) => {
          const loaded = await loadSettings(where);

          expect(loaded.settings.offeredAgents).toEqual(
            userValid ? ['mine', 'other'] : undefined,
          );
          expect(loaded.settings.agent).toBe('project-only');
          expect(loaded.settings.theme).toBe('light');
          expect(loaded.problems).toHaveLength(userValid ? 1 : 2);
          expect(loaded.layers[1]?.settings.offeredAgents).toBeUndefined();
        },
      ));
  }

  test('repair, replacement and removal are observed on the next file read', () =>
    place(
      { user: JSON.stringify({ offeredAgents: [], theme: 'dark' }) },
      async (where) => {
        const [user] = settingsFiles(where);

        expect(user).toBeDefined();
        expect((await loadSettings(where)).settings).toEqual({ theme: 'dark' });

        for (const offeredAgents of [['b', 'a', 'b'], ['only']]) {
          await writeFile(
            user!,
            JSON.stringify({ offeredAgents, theme: 'dark' }),
          );

          const loaded = await loadSettings(where);

          expect(loaded.settings.offeredAgents).toEqual(offeredAgents);
          expect(loaded.problems).toEqual([]);
        }

        await writeFile(user!, JSON.stringify({ theme: 'dark' }));
        expect((await loadSettings(where)).settings).toEqual({ theme: 'dark' });
      },
    ));
});

describe('selected policy admission diagnostics', () => {
  test('invalid nested policy keeps structured paths and refuses selected admission only', async () => {
    await place(
      {
        project: JSON.stringify({
          agent: 'fake',
          teamSelection: { constraints: { agents: null } },
        }),
      },
      async (where) => {
        const loaded = await loadSettings(where);

        expect(loaded.settings.agent).toBe('fake');
        expect(loaded.problems[0]).toMatchObject({
          kind: 'validation',
          key: ['teamSelection', 'constraints', 'agents'],
        });
        expect(await readTeamSelection(where)).toEqual({
          error:
            'Team selection settings could not be validated. Correct the settings before selecting a team.',
        });
        expect(JSON.stringify(await readTeamSelection(where))).not.toContain(
          where.cwd,
        );
      },
    );
  });

  test('ordinary unrelated validation and user-only scope warnings do not block selection', async () => {
    await place(
      {
        user: JSON.stringify({
          mouse: false,
          theme: 7,
          teamSelection: { constraints: { modes: { fake: ['plan'] } } },
        }),
        project: JSON.stringify({ mouse: true }),
      },
      async (where) => {
        const loaded = await loadSettings(where);

        expect(loaded.problems.map(({ kind, key }) => ({ kind, key }))).toEqual(
          [
            { kind: 'validation', key: ['theme'] },
            { kind: 'scope', key: ['mouse'] },
          ],
        );
        expect(await readTeamSelection(where)).toEqual({
          policy: { constraints: { modes: { fake: ['plan'] } } },
        });
      },
    );
  });

  test('fresh reads use ordinary layer merge and observe changed explicit empty lists', async () => {
    await place(
      {
        user: JSON.stringify({
          teamSelection: {
            intent: 'prefer',
            prefer: { agent: 'codex', model: 'large' },
            constraints: {
              agents: ['codex', 'claude'],
              modes: { codex: ['auto'], claude: ['plan'] },
            },
          },
        }),
        project: JSON.stringify({
          teamSelection: {
            prefer: { model: null },
            constraints: { agents: ['claude'] },
          },
        }),
      },
      async (where) => {
        expect(await readTeamSelection(where)).toEqual({
          policy: {
            intent: 'prefer',
            prefer: { agent: 'codex', model: null },
            constraints: {
              agents: ['claude'],
              modes: { codex: ['auto'], claude: ['plan'] },
            },
          },
        });

        const project = settingsFiles(where)[1];

        await writeFile(
          project!,
          JSON.stringify({
            teamSelection: {
              constraints: { agents: [], modes: { claude: [] } },
            },
          }),
        );
        expect(await readTeamSelection(where)).toEqual({
          policy: {
            intent: 'prefer',
            prefer: { agent: 'codex', model: 'large' },
            constraints: { agents: [], modes: { codex: ['auto'], claude: [] } },
          },
        });
      },
    );
  });

  test('missing files mean defaults; whole-file parse/read failures refuse without fallback', async () => {
    await place({}, async (where) => {
      expect(await readTeamSelection(where)).toEqual({ policy: {} });

      const project = settingsFiles(where)[1]!;

      await mkdir(project, { recursive: true });
      expect((await loadSettings(where)).problems[0]?.kind).toBe('read');
      expect(await readTeamSelection(where)).toHaveProperty('error');
    });

    for (const project of ['not-json', 'null', '[]']) {
      await place(
        { user: '{"teamSelection":{"intent":"balanced"}}', project },
        async (where) => {
          expect((await loadSettings(where)).problems[0]?.kind).toBe('parse');
          expect(await readTeamSelection(where)).toHaveProperty('error');
        },
      );
    }
  });
});

describe('resource selection preferences', () => {
  test('strict nested fields report problems and retain explicit empty constraints', () => {
    const parsed = parseSettings(
      'settings.json',
      JSON.stringify({
        teamSelection: {
          intent: 'balanced',
          constraints: { agents: [], models: { codex: [] } },
          unknown: true,
        },
      }),
    );

    expect(parsed.problems).toHaveLength(1);
    expect(parsed.settings.teamSelection).toEqual({
      intent: 'balanced',
      constraints: { agents: [], models: { codex: [] } },
    });
  });

  test('project precedence replaces lists while merging preference fields and runtime maps', () => {
    expect(
      mergeSettings(
        {
          teamSelection: {
            intent: 'prefer',
            prefer: { agent: 'codex', model: 'large' },
            constraints: {
              agents: ['codex'],
              models: { codex: ['large'], claude: ['small'] },
              modes: { codex: ['auto'] },
            },
          },
        },
        {
          teamSelection: {
            intent: 'balanced',
            prefer: { model: null },
            constraints: {
              agents: [],
              models: { codex: [] },
              modes: { claude: ['plan'] },
            },
          },
        },
      ).teamSelection,
    ).toEqual({
      intent: 'balanced',
      prefer: { agent: 'codex', model: null },
      constraints: {
        agents: [],
        models: { codex: [], claude: ['small'] },
        modes: { codex: ['auto'], claude: ['plan'] },
      },
    });
  });
});

describe('tester: copyOnSelect settings edges', () => {
  test('invalid booleans are reported without losing valid settings', () => {
    for (const copyOnSelect of ['false', 0, null, {}, []]) {
      const { settings, problems } = parseSettings(
        'settings.json',
        JSON.stringify({ copyOnSelect, agent: 'fake' }),
      );

      expect(settings).toStrictEqual({ agent: 'fake' });
      expect(problems).toHaveLength(1);
      expect(problems[0]!.message).toContain('copyOnSelect');
    }
  });

  test('merging preserves false through absent values and later overrides', () => {
    expect(mergeSettings({ copyOnSelect: false }, {}).copyOnSelect).toBe(false);
    expect(
      mergeSettings({ copyOnSelect: true }, { copyOnSelect: false })
        .copyOnSelect,
    ).toBe(false);
    expect(
      mergeSettings({ copyOnSelect: false }, { copyOnSelect: true })
        .copyOnSelect,
    ).toBe(true);
  });

  test('saving other preferences keeps auto-copy disabled', async () => {
    await place({ user: '{ "copyOnSelect": false }' }, async (where) => {
      const [user] = settingsFiles(where);

      await saveTheme(user!, 'light');
      await saveEditorMode(user!, 'vim');

      const { settings, problems } = await loadSettings(where);

      expect(problems).toStrictEqual([]);
      expect(settings.copyOnSelect).toBe(false);
      expect(settings.theme).toBe('light');
      expect(settings.editorMode).toBe('vim');
    });
  });
});

/**
 * A config home and a project, both temporary, with the files given written
 * into them; nothing reads the home directory of whoever runs the tests.
 */
async function place(
  files: { user?: string; project?: string },
  run: (where: { configHome: string; cwd: string }) => Promise<void>,
) {
  const root = await mkdtemp(join(tmpdir(), 'chord-settings-'));
  const where = { configHome: join(root, 'config'), cwd: join(root, 'work') };
  const [user, project] = settingsFiles(where);

  try {
    for (const [file, text] of [
      [user, files.user],
      [project, files.project],
    ]) {
      if (file !== undefined && text !== undefined) {
        await mkdir(join(file, '..'), { recursive: true });
        await writeFile(file, text);
      }
    }

    await run(where);
  } finally {
    await rm(root, { recursive: true });
  }
}

test('the user file is under the config home, the project file under the directory', () => {
  expect(settingsFiles({ configHome: '/c', cwd: '/w' })).toStrictEqual([
    join('/c', 'chord', 'settings.json'),
    join('/w', '.chord', 'settings.json'),
  ]);
  expect(settingsFiles({ configHome: undefined, cwd: '/w' })).toStrictEqual([
    join('/w', '.chord', 'settings.json'),
  ]);
});

test('the project file overrides the user file, and a flag overrides both', async () => {
  await place(
    {
      user: JSON.stringify({
        agent: 'codex',
        agents: {
          fake: {
            command: 'fake --acp',
            model: 'large',
            effort: 'low',
            permissionMode: 'acceptEdits',
          },
        },
      }),
      project: JSON.stringify({
        agent: 'fake',
        agents: { fake: { effort: 'high', permissionMode: 'plan' } },
      }),
    },
    async (where) => {
      const { settings, layers, problems } = await loadSettings(where);
      const [user, project] = settingsFiles(where);

      expect(problems).toStrictEqual([]);
      // Agent by agent, key by key: the user's command and model stay.
      expect(settings).toStrictEqual({
        agent: 'fake',
        agents: {
          fake: {
            command: 'fake --acp',
            model: 'large',
            effort: 'high',
            permissionMode: 'plan',
          },
        },
      });
      // Each value says where it was set, for a refusal to point there.
      expect(resolveStartup({}, layers, 'claude')).toStrictEqual({
        agent: 'fake',
        agentCommand: 'fake --acp',
        model: { id: 'large', from: user! },
        effort: { id: 'high', from: project! },
        permissionMode: { id: 'plan', from: project! },
      });
      expect(
        resolveStartup(
          {
            permissionMode: 'default',
            model: 'small',
            effort: 'max',
            agentCommand: 'other',
          },
          layers,
          'claude',
        ),
      ).toStrictEqual({
        agent: 'fake',
        agentCommand: 'other',
        model: { id: 'small', from: '--model' },
        effort: { id: 'max', from: '--effort' },
        permissionMode: { id: 'default', from: '--permission-mode' },
      });
    },
  );
});

test("an agent named on the command line takes that agent's settings, not the default's", () => {
  const layers = [
    {
      file: 'f',
      settings: {
        agent: 'fake',
        agents: { fake: { permissionMode: 'plan' }, codex: { model: 'o3' } },
      },
    },
  ];

  expect(resolveStartup({ agent: 'codex' }, layers, 'claude')).toStrictEqual({
    agent: 'codex',
    model: { id: 'o3', from: 'f' },
  });
  expect(resolveStartup({}, [], 'claude')).toStrictEqual({ agent: 'claude' });
});

test("each agent's sessions start on its own settings, and the flags only the named agent's", () => {
  const layers = [
    {
      file: 'f',
      settings: {
        agents: {
          fake: { model: 'large' },
          fake2: {
            command: 'fake2 --acp',
            model: 'small',
            effort: 'low',
            permissionMode: 'plan',
          },
        },
      },
    },
  ];
  const invoked = resolveStartup(
    {
      agent: 'fake',
      agentCommand: 'fake --acp',
      model: 'huge',
      effort: 'max',
    },
    layers,
    'claude',
  );

  expect(startupOf('fake', invoked, layers)).toStrictEqual(invoked);
  expect(startupOf('fake2', invoked, layers)).toStrictEqual({
    agent: 'fake2',
    agentCommand: 'fake2 --acp',
    model: { id: 'small', from: 'f' },
    effort: { id: 'low', from: 'f' },
    permissionMode: { id: 'plan', from: 'f' },
  });
  expect(startupOf('codex', invoked, layers)).toStrictEqual({ agent: 'codex' });
});

test("the agents a window can open are its own, those the files give a command, then the registry's, each once", () => {
  const layers = [
    {
      file: 'f',
      settings: {
        agents: {
          fake2: { command: 'fake2 --acp' },
          claude: { command: 'my-claude' },
          codex: { model: 'o3' },
        },
      },
    },
  ];

  expect(
    knownAgents({ agent: 'fake', agentCommand: 'fake' }, layers, [
      'claude',
      'codex',
    ]),
  ).toStrictEqual(['fake', 'fake2', 'claude', 'codex']);
});

test("the settings commands are the merged files' own, by agent", () => {
  expect(
    agentCommands([
      { file: 'u', settings: { agents: { mine: { command: 'a' } } } },
      {
        file: 'p',
        settings: {
          agents: { mine: { command: 'b' }, codex: { model: 'o3' } },
        },
      },
    ]),
  ).toStrictEqual({ mine: 'b' });
});

test("a session resumed from another directory starts on that directory's settings", async () => {
  await place(
    {
      user: JSON.stringify({ agents: { fake: { model: 'large' } } }),
      project: JSON.stringify({
        agent: 'fake',
        agents: {
          fake: { command: 'fake --acp', permissionMode: 'acceptEdits' },
        },
      }),
    },
    async (here) => {
      const there = { ...here, cwd: join(here.cwd, '..', 'elsewhere') };
      const file = settingsFiles(there)[1]!;

      await mkdir(join(file, '..'), { recursive: true });
      await writeFile(
        file,
        JSON.stringify({
          agent: 'codex',
          agents: {
            fake: {
              command: 'other --acp',
              effort: 'high',
              permissionMode: 'plan',
            },
          },
          colour: 'dark',
        }),
      );

      const found = resolveStartup(
        {},
        (await loadSettings(here)).layers,
        'claude',
      );
      const loaded = await loadSettings(there);

      // The agent and command that found the session stay; the effort and
      // the mode are the resumed directory's, and the user's model still
      // counts.
      expect(resumedStartup(found, {}, loaded.layers)).toStrictEqual({
        agent: 'fake',
        agentCommand: 'fake --acp',
        model: { id: 'large', from: settingsFiles(here)[0]! },
        effort: { id: 'high', from: file },
        permissionMode: { id: 'plan', from: file },
      });
      expect(
        resumedStartup(found, { effort: 'low' }, loaded.layers).effort,
      ).toStrictEqual({ id: 'low', from: '--effort' });
      expect(
        resumedStartup(found, { permissionMode: 'default' }, loaded.layers)
          .permissionMode,
      ).toStrictEqual({ id: 'default', from: '--permission-mode' });
      expect(
        unseenProblems((await loadSettings(here)).problems, loaded.problems),
      ).toStrictEqual([
        {
          file,
          kind: 'validation',
          key: ['colour'],
          message: 'unknown key "colour", ignored',
        },
      ]);
    },
  );
});

test("the user file's problems are said once over two readings", () => {
  const user = { file: 'u', message: 'unknown key "x", ignored' };
  const project = { file: 'p', message: 'unknown key "y", ignored' };

  expect(unseenProblems([user], [{ ...user }, project])).toStrictEqual([
    project,
  ]);
});

test('a missing file is no problem, and no file at all leaves the defaults', async () => {
  await place({}, async (where) => {
    expect(await loadSettings(where)).toStrictEqual({
      settings: {},
      layers: [],
      problems: [],
    });
  });

  await place({ project: '{"agent": "fake"}' }, async (where) => {
    const [, project] = settingsFiles(where);

    expect(await loadSettings(where)).toStrictEqual({
      settings: { agent: 'fake' },
      layers: [{ file: project!, settings: { agent: 'fake' } }],
      problems: [],
    });
  });
});

test('a malformed file is named and ignored, and the other file still counts', async () => {
  await place(
    { user: '{"agent": "codex"', project: '{"agent": "fake"}' },
    async (where) => {
      const { settings, problems } = await loadSettings(where);
      const [user] = settingsFiles(where);

      expect(settings).toStrictEqual({ agent: 'fake' });
      expect(problems.length).toStrictEqual(1);
      expect(problems[0]?.file).toStrictEqual(user);
      expect(problems[0]?.message.startsWith('not valid JSON (')).toStrictEqual(
        true,
      );
      expect(
        problems[0]?.message.endsWith('); the file is ignored'),
      ).toStrictEqual(true);
    },
  );

  expect(parseSettings('f', '["agent"]')).toStrictEqual({
    settings: {},
    problems: [
      {
        file: 'f',
        kind: 'parse',
        message: 'not a JSON object; the file is ignored',
      },
    ],
  });
});

test('an unknown key is named with its file and left out, and the rest still counts', async () => {
  await place(
    {
      project: JSON.stringify({
        agent: 'fake',
        colour: 'dark',
        agents: { fake: { permissionMode: 'plan', mode: 'plan' } },
      }),
    },
    async (where) => {
      const { settings, problems } = await loadSettings(where);
      const [, project] = settingsFiles(where);

      expect(settings).toStrictEqual({
        agent: 'fake',
        agents: { fake: { permissionMode: 'plan' } },
      });
      expect(problems.map(problemLine).sort()).toStrictEqual([
        `chord: ${project}: unknown key "agents.fake.mode", ignored`,
        `chord: ${project}: unknown key "colour", ignored`,
      ]);
    },
  );
});

test('a key holding the wrong kind of value is named and left out', () => {
  const { settings, problems } = parseSettings(
    'f',
    JSON.stringify({
      agent: 3,
      agents: { fake: { model: 'large', command: '' } },
    }),
  );

  expect(settings).toStrictEqual({ agents: { fake: { model: 'large' } } });
  expect(
    problems.map((problem) => problem.message.split(':')[0]),
  ).toStrictEqual(['"agent"', '"agents.fake.command"']);
});

test('the window shows a path from the working directory, or from ~, never the home path', () => {
  const where = { cwd: join('/w', 'project'), home: '/h' };

  expect(
    shownPath(join('/w', 'project', '.chord', 'settings.json'), where),
  ).toStrictEqual(join('.chord', 'settings.json'));
  expect(
    shownPath(join('/h', '.config', 'chord', 'settings.json'), where),
  ).toStrictEqual(`~${join('/', '.config', 'chord', 'settings.json')}`);
  expect(shownPath('/etc/chord.json', where)).toStrictEqual('/etc/chord.json');
  expect(
    shownPath('/etc/chord.json', { cwd: '/w', home: undefined }),
  ).toStrictEqual('/etc/chord.json');
  expect(setWhere('--model', where)).toStrictEqual('set by --model');
  expect(
    setWhere(join('/w', 'project', '.chord', 'settings.json'), where),
  ).toStrictEqual(`set in ${join('.chord', 'settings.json')}`);
  expect(
    problemNote(
      {
        file: join('/h', '.config', 'chord', 'settings.json'),
        message: 'unknown key "colour", ignored',
      },
      where,
    ),
  ).toStrictEqual(
    `~${join(
      '/',
      '.config',
      'chord',
      'settings.json',
    )}: unknown key "colour", ignored`,
  );
});

test('an unknown notification channel is named with its file and left out', async () => {
  await place(
    {
      user: JSON.stringify({ preferredNotifChannel: 'osc9' }),
      project: JSON.stringify({
        preferredNotifChannel: 'popup',
        agent: 'fake',
      }),
    },
    async (where) => {
      const { settings, problems } = await loadSettings(where);
      const [, project] = settingsFiles(where);

      // The user's channel stands, as the project's was refused.
      expect(settings).toStrictEqual({
        preferredNotifChannel: 'osc9',
        agent: 'fake',
      });
      expect(problems.map(problemLine)).toStrictEqual([
        `chord: ${project}: "preferredNotifChannel": invalid option: expected one of "auto"|"bell"|"osc9"|"osc777"|"off", ignored`,
      ]);
    },
  );
});

test("the project file's notification channel overrides the user's", async () => {
  await place(
    {
      user: JSON.stringify({ preferredNotifChannel: 'osc9' }),
      project: JSON.stringify({ preferredNotifChannel: 'off' }),
    },
    async (where) => {
      expect((await loadSettings(where)).settings).toStrictEqual({
        preferredNotifChannel: 'off',
      });
    },
  );
});

test("the theme is read from the user's file, never the project's", async () => {
  await place(
    {
      user: '{ "theme": "light" }',
      project: '{ "theme": "dark-ansi", "agent": "codex" }',
    },
    async (where) => {
      const { settings, problems } = await loadSettings({
        ...where,
        home: join(where.configHome, '..'),
      });
      const [, project] = settingsFiles(where);

      expect(settings.theme).toStrictEqual('light');
      // Only the key is lost; the rest of the project's file still counts.
      expect(settings.agent).toStrictEqual('codex');
      expect(problems).toStrictEqual([
        {
          file: project!,
          kind: 'scope',
          key: ['theme'],
          message:
            '"theme" is read only from ~/config/chord/settings.json, ignored',
        },
      ]);
    },
  );
});

test('an unknown theme is named and chord starts on auto', () => {
  const { settings, problems } = parseSettings(
    'settings.json',
    '{ "theme": "solarized" }',
  );

  expect(settings.theme).toStrictEqual(undefined);
  expect(problems.length).toStrictEqual(1);

  for (const id of ['auto', 'dark', 'light-daltonized', 'dark-ansi']) {
    expect(problems[0]!.message.includes(`"${id}"`), id).toStrictEqual(true);
  }
});

test('saving the theme keeps every other key, in its place', async () => {
  await place(
    {
      user: '{\n  "agent": "codex",\n  "theme": "dark",\n  "x": 1\n}\n',
    },
    async (where) => {
      const [user] = settingsFiles(where);

      await saveTheme(user!, 'light');

      expect(await readFile(user!, 'utf8')).toStrictEqual(
        '{\n  "agent": "codex",\n  "theme": "light",\n  "x": 1\n}\n',
      );
      // No temporary file is left beside it.
      expect(
        [...readdirSync(join(user!, '..'), { withFileTypes: true })].map(
          ({ name }) => name,
        ),
      ).toStrictEqual(['settings.json']);
    },
  );
});

test('saving the theme makes the file and its directory', async () => {
  await place({}, async (where) => {
    const [user] = settingsFiles(where);

    await saveTheme(user!, 'dark-daltonized');

    expect(await readFile(user!, 'utf8')).toStrictEqual(
      '{\n  "theme": "dark-daltonized"\n}\n',
    );
  });
});

test('a file that is not a JSON object is never overwritten', async () => {
  for (const text of ['{ "agent": ', '[1, 2]']) {
    await place({ user: text }, async (where) => {
      const [user] = settingsFiles(where);

      const refused = saveTheme(user!, 'light');

      await expect(refused).rejects.toThrow(Error);
      await expect(refused).rejects.toThrow(
        text.startsWith('[') ? 'not a JSON object' : 'not valid JSON',
      );
      expect(await readFile(user!, 'utf8')).toStrictEqual(text);
    });
  }
});

test('/vim is kept as the editor mode, every other key in its place', async () => {
  await place(
    {
      user: '{\n  "theme": "dark",\n  "x": 1\n}\n',
    },
    async (where) => {
      const [user] = settingsFiles(where);

      await saveEditorMode(user!, 'vim');

      expect(await readFile(user!, 'utf8')).toStrictEqual(
        '{\n  "theme": "dark",\n  "x": 1,\n  "editorMode": "vim"\n}\n',
      );
      expect((await loadSettings(where)).settings.editorMode).toStrictEqual(
        'vim',
      );

      await saveEditorMode(user!, 'normal');

      expect((await loadSettings(where)).settings.editorMode).toStrictEqual(
        'normal',
      );
    },
  );
});

test("the editor mode is read from the user's file, never the project's", async () => {
  await place(
    {
      user: '{ "theme": "light" }',
      project: '{ "editorMode": "vim", "agent": "codex" }',
    },
    async (where) => {
      const { settings, problems } = await loadSettings({
        ...where,
        home: join(where.configHome, '..'),
      });
      const [, project] = settingsFiles(where);

      expect(settings.editorMode).toStrictEqual(undefined);
      expect(settings.agent).toStrictEqual('codex');
      expect(problems).toStrictEqual([
        {
          file: project!,
          kind: 'scope',
          key: ['editorMode'],
          message:
            '"editorMode" is read only from ~/config/chord/settings.json, ignored',
        },
      ]);
    },
  );
});

test("the mouse is read from the user's file, never the project's", async () => {
  await place(
    {
      user: '{ "mouse": false }',
      project: '{ "mouse": true }',
    },
    async (where) => {
      const { settings, problems } = await loadSettings({
        ...where,
        home: join(where.configHome, '..'),
      });
      const [, project] = settingsFiles(where);

      expect(settings.mouse).toStrictEqual(false);
      expect(problems).toStrictEqual([
        {
          file: project!,
          kind: 'scope',
          key: ['mouse'],
          message:
            '"mouse" is read only from ~/config/chord/settings.json, ignored',
        },
      ]);
    },
  );
});

test("copyOnSelect is read from the user's file, never the project's", async () => {
  await place(
    {
      user: '{ "copyOnSelect": false }',
      project: '{ "copyOnSelect": true }',
    },
    async (where) => {
      const { settings, problems } = await loadSettings({
        ...where,
        home: join(where.configHome, '..'),
      });
      const [, project] = settingsFiles(where);

      expect(settings.copyOnSelect).toStrictEqual(false);
      expect(problems).toStrictEqual([
        {
          file: project!,
          kind: 'scope',
          key: ['copyOnSelect'],
          message:
            '"copyOnSelect" is read only from ~/config/chord/settings.json, ignored',
        },
      ]);
    },
  );
});

test("a project's copyOnSelect alone leaves it unset, so a copy on release", async () => {
  await place({ project: '{ "copyOnSelect": false }' }, async (where) => {
    const { settings, problems } = await loadSettings(where);

    expect(settings.copyOnSelect).toStrictEqual(undefined);
    expect(problems.length).toStrictEqual(1);
  });
});

test("offeredAgents is read from the user's file, never the project's", async () => {
  await place(
    {
      user: '{ "offeredAgents": ["codex", "claude"] }',
      project: '{ "offeredAgents": ["goose"] }',
    },
    async (where) => {
      const { settings, problems } = await loadSettings({
        ...where,
        home: join(where.configHome, '..'),
      });
      const [, project] = settingsFiles(where);

      expect(settings.offeredAgents).toStrictEqual(['codex', 'claude']);
      expect(problems).toStrictEqual([
        {
          file: project!,
          kind: 'scope',
          key: ['offeredAgents'],
          message:
            '"offeredAgents" is read only from ~/config/chord/settings.json, ignored',
        },
      ]);
    },
  );
});

test("a project's offeredAgents alone leaves it unset", async () => {
  await place({ project: '{ "offeredAgents": ["goose"] }' }, async (where) => {
    const { settings, problems } = await loadSettings(where);

    expect(settings.offeredAgents).toStrictEqual(undefined);
    expect(problems.length).toStrictEqual(1);
  });
});

test('offeredAgents keeps its order and its repeats as written', () => {
  expect(
    parseSettings('f', '{ "offeredAgents": ["b", "a", "b"] }'),
  ).toStrictEqual({
    settings: { offeredAgents: ['b', 'a', 'b'] },
    problems: [],
  });
});

test('a bad offeredAgents counts as absent and costs the file nothing else', () => {
  for (const offeredAgents of [
    [],
    [''],
    ['claude', ''],
    ['claude', 1],
    [1, 2],
    'claude',
    'x',
    null,
    {},
  ]) {
    expect(
      parseSettings(
        'f',
        JSON.stringify({ offeredAgents, agent: 'fake', theme: 'dark' }),
      ),
    ).toStrictEqual({
      settings: { agent: 'fake', theme: 'dark' },
      problems: [
        {
          file: 'f',
          kind: 'validation',
          key: ['offeredAgents'],
          message:
            '"offeredAgents": expected a list of one or more agent names, ignored',
        },
      ],
    });
  }
});

test('each unknown name in offeredAgents is a problem of the file that gave it', () => {
  expect(unknownOffered('f', ['cdex', 'codx'])).toStrictEqual([
    {
      file: 'f',
      kind: 'validation',
      key: ['offeredAgents'],
      message: '"offeredAgents": no agent named cdex, left out',
    },
    {
      file: 'f',
      kind: 'validation',
      key: ['offeredAgents'],
      message: '"offeredAgents": no agent named codx, left out',
    },
  ]);
});

test('the later offeredAgents replaces the earlier one whole', () => {
  expect(
    mergeSettings({ offeredAgents: ['a', 'b'] }, { offeredAgents: ['c'] })
      .offeredAgents,
  ).toStrictEqual(['c']);
  expect(
    mergeSettings({ offeredAgents: ['a'] }, {}).offeredAgents,
  ).toStrictEqual(['a']);
});

test('a directory is shortened against the home directory alone, and the home path is never shown', () => {
  expect(homePath(join('/h', 'src', 'app'), '/h')).toStrictEqual(
    join('~', 'src', 'app'),
  );
  expect(homePath('/h', '/h')).toStrictEqual('~');
  expect(homePath('/h/', '/h')).toStrictEqual('~');
  // A sibling whose name starts like the home directory's is not under it.
  expect(homePath('/home2/app', '/home')).toStrictEqual('/home2/app');
  expect(homePath('/srv/app', '/h')).toStrictEqual('/srv/app');
  expect(homePath('/srv/app', undefined)).toStrictEqual('/srv/app');
  // The working directory is not the shortening's, as it is shownPath's.
  expect(shownPath('/h', { cwd: '/w', home: '/h' })).toStrictEqual('~');
});

describe("an agent's command chord refuses (CHD-466, the owner's Q52)", () => {
  const file = '/project/.chord/settings.json';
  const layer = (codex: Record<string, unknown>) => {
    const { settings, refused } = parseSettings(
      file,
      JSON.stringify({ agents: { codex } }),
    );

    return { file, settings, ...(refused === undefined ? {} : { refused }) };
  };

  test('an empty argument after the program is kept as written, and shown so by chord agents', () => {
    const found = startupOf('codex', { agent: 'fake' }, [
      layer({ command: ['tool', '--value', ''] }),
    ]);

    expect(found.agentCommand).toStrictEqual(['tool', '--value', '']);
    expect(commandLine(found.agentCommand!)).toStrictEqual("tool --value ''");
  });

  test("a resume line repeats the --agent-command the person gave, and never a settings command, which the settings give again (the owner's Q56)", () => {
    // The settings' command, a list or a line: the resume line has none.
    expect(
      resumeMessage({ agent: 'codex', sessionId: 'id' }, { agent: 'codex' }),
    ).toBe('Resume this session with:\nchord codex --resume id');

    // The flag's line, as typed: quoted once, read back whole by a shell.
    const typed = "tool --value ''";
    const words = parse(resumeCommand('codex', 'id', typed));

    expect(words.slice(0, 3)).toStrictEqual([
      'chord',
      'codex',
      '--agent-command',
    ]);
    expect(words[3]).toBe(typed);
    expect(words.slice(-2)).toStrictEqual(['--resume', 'id']);
  });

  test("its warning says the agent will not start, not that the value is ignored; another setting's still is", () => {
    const { problems } = parseSettings(
      file,
      JSON.stringify({ agents: { codex: { command: 7, model: 3 } } }),
    );

    expect(problems.map(({ message }) => message)).toStrictEqual([
      '"agents.codex.command": expected a string, got a number · codex will not start',
      '"agents.codex.model": invalid input: expected string, received number, ignored',
    ]);
  });

  test('a list whose program is empty is refused, saying so', () => {
    expect(
      startupOf('codex', { agent: 'fake' }, [layer({ command: ['', 'x'] })])
        .refused?.cause,
    ).toStrictEqual('expected a string, got a list whose program is empty');
  });

  test('a command given as a list is taken as the program and its arguments', () => {
    const found = startupOf('codex', { agent: 'fake' }, [
      layer({ command: ['bun', 'fake.ts'], model: 'fake-small' }),
    ]);

    expect(found.agentCommand).toStrictEqual(['bun', 'fake.ts']);
    expect(found.refused).toBeUndefined();
  });

  test("any other command marks the agent refused, with the cause, and never falls back to chord's own", () => {
    for (const [command, cause] of [
      [7, 'expected a string, got a number'],
      [true, 'expected a string, got a boolean'],
      ['', 'expected a string, got an empty string'],
      [[], 'expected a string, got an empty list'],
      [['bun', 3], 'expected a string, got a list with something not a string'],
      [{ run: 'x' }, 'expected a string, got an object'],
    ] as const) {
      const found = startupOf('codex', { agent: 'fake' }, [
        layer({ command, model: 'fake-small' }),
      ]);

      expect(found.agentCommand, String(command)).toBeUndefined();
      expect(found.refused).toStrictEqual({ file, cause });
    }
  });

  test("the last file to give a command decides, as settings merge: a later good one replaces a refused one, a later refused one refuses (the lead's call on Q52)", () => {
    const user = {
      ...layer({ command: 7 }),
      file: '/h/.config/chord/settings.json',
    };
    const good = layer({ command: ['bun', 'fake.ts'] });

    const replaced = startupOf('codex', { agent: 'fake' }, [user, good]);

    expect(replaced.refused).toBeUndefined();
    expect(replaced.agentCommand).toStrictEqual(['bun', 'fake.ts']);

    const refusedLater = startupOf('codex', { agent: 'fake' }, [
      { ...good, file: '/h/.config/chord/settings.json' },
      layer({ command: 7 }),
    ]);

    expect(refusedLater.agentCommand).toBeUndefined();
    expect(refusedLater.refused).toStrictEqual({
      file,
      cause: 'expected a string, got a number',
    });
  });

  test('a flag still gives the command; another agent is untouched', () => {
    const layers = [layer({ command: 7 })];

    expect(
      resolveStartup(
        { agent: 'codex', agentCommand: 'bun x.ts' },
        layers,
        'fake',
      ).refused,
    ).toBeUndefined();
    expect(
      startupOf('claude', { agent: 'fake' }, layers).refused,
    ).toBeUndefined();
  });

  test('the refusal reads with its file as the window shows paths', () => {
    expect(
      refusalLine(
        'codex',
        {
          file: '/h/.config/chord/settings.json',
          cause: 'expected a string, got a number',
        },
        { cwd: '/project', home: '/h' },
      ),
    ).toStrictEqual(
      'codex not started: agents.codex.command in ~/.config/chord/settings.json: expected a string, got a number',
    );
  });
});

describe('CHD-466 U1 tester: command settings boundaries', () => {
  test('null and malformed lists refuse the named runtime with their source', () => {
    for (const command of [
      null,
      [null],
      ['tool', null],
      ['tool', {}],
      [['tool']],
    ]) {
      const file = '/project/.chord/settings.json';
      const parsed = parseSettings(
        file,
        JSON.stringify({ agents: { custom: { command } } }),
      );
      const found = startupOf('custom', { agent: 'fake' }, [
        { file, ...parsed },
      ]);

      expect(found.agentCommand).toBeUndefined();
      expect(found.refused?.file).toBe(file);
      expect(found.refused?.cause).toContain('expected a string, got');
      expect(
        startupOf('fake', { agent: 'fake' }, [{ file, ...parsed }]).refused,
      ).toBeUndefined();
    }
  });

  test('settings argv is display-only while a typed resume flag is preserved verbatim', () => {
    const command: [string, ...string[]] = [
      'a program',
      '',
      'two words',
      "single'quote",
      '"quoted"',
      '$HOME',
      '$(touch ignored)',
      '; exit',
      '*',
      '\\path',
    ];
    const line = commandLine(command);
    const typed = "tool --literal '*' --empty '' --value 'two words'";
    const resume = parse(resumeCommand('custom', 'session-id', typed));
    const flag = resume[resume.indexOf('--agent-command') + 1];

    expect(line).toStartWith("'a program' '' 'two words'");
    expect(flag).toBe(typed);
    expect(commandArgv(typed)).toEqual([
      'tool',
      '--literal',
      '*',
      '--empty',
      '',
      '--value',
      'two words',
    ]);
    expect(
      resumeMessage(
        { agent: 'custom', sessionId: 'session-id' },
        { agent: 'custom' },
      ),
    ).toBe('Resume this session with:\nchord custom --resume session-id');
    expect(resume.slice(-2)).toEqual(['--resume', 'session-id']);
  });

  test('array commands are listed with quoting that preserves every argument', async () => {
    const command = ['a program', '', 'two words', '$literal'];
    const rows = await listedAgents({ 'tester-custom': command }, () =>
      Promise.resolve(undefined),
    );
    const row = rows.find(({ name }) => name === 'tester-custom');

    expect(row?.from).toBe('settings');
    expect(parse(row!.start)).toEqual(command);
  });

  test('an explicit flag overrides loaded malformed settings without affecting another runtime', async () => {
    await place(
      {
        user: JSON.stringify({
          agents: {
            custom: { command: null },
            other: { command: ['other-tool', ''] },
          },
        }),
        project: JSON.stringify({
          agents: { custom: { model: 'chosen-model' } },
        }),
      },
      async (where) => {
        const loaded = await loadSettings(where);
        const refused = resolveStartup(
          { agent: 'custom' },
          loaded.layers,
          'fake',
        );
        const selected = resolveStartup(
          { agent: 'custom', agentCommand: "tool --value ''" },
          loaded.layers,
          'fake',
        );

        expect(refused.refused?.cause).toBe('expected a string, got null');
        expect(refused.agentCommand).toBeUndefined();
        expect(selected.refused).toBeUndefined();
        expect(selected.agentCommand).toBe("tool --value ''");
        expect(selected.model?.id).toBe('chosen-model');
        expect(
          startupOf('other', selected, loaded.layers).agentCommand,
        ).toEqual(['other-tool', '']);
        expect(resumedStartup(selected, {}, loaded.layers).agentCommand).toBe(
          selected.agentCommand,
        );
      },
    );
  });
});

describe('CHD-466 U2 tester: last command-bearing layer', () => {
  for (const [user, project, allowed] of [
    [null, ['project-tool', ''], true],
    [['user-tool'], null, false],
    [null, undefined, false],
  ] as const) {
    test(`project command ${String(project)} decides after user command ${String(user)}`, async () => {
      await place(
        {
          user: JSON.stringify({ agents: { custom: { command: user } } }),
          project: JSON.stringify({
            agents: { custom: { command: project, model: 'project-model' } },
          }),
        },
        async (where) => {
          const loaded = await loadSettings(where);
          const found = resolveStartup(
            { agent: 'custom' },
            loaded.layers,
            'fake',
          );

          if (allowed) {
            expect(found.refused).toBeUndefined();
            expect(found.agentCommand).toEqual([...project]);
          } else {
            expect(found.agentCommand).toBeUndefined();
            expect(found.refused?.file).toBe(
              settingsFiles(where)[project === undefined ? 0 : 1],
            );
          }

          const overridden = resolveStartup(
            { agent: 'custom', agentCommand: 'flag-tool' },
            loaded.layers,
            'fake',
          );

          expect(overridden.refused).toBeUndefined();
          expect(overridden.agentCommand).toBe('flag-tool');
          expect(overridden.model?.id).toBe('project-model');
        },
      );
    });
  }
});

test("an agent's mcpServers setting is read from the last file that sets it, true or false (CHD-441)", () => {
  const layer = (file: string, openclaw: Record<string, unknown>) => ({
    file,
    settings: parseSettings(file, JSON.stringify({ agents: { openclaw } }))
      .settings,
  });

  expect(
    startupOf('openclaw', { agent: 'fake' }, [
      layer('/u.json', { mcpServers: true }),
    ]).mcpServers,
  ).toBe(true);
  expect(
    startupOf('openclaw', { agent: 'fake' }, [
      layer('/u.json', { mcpServers: true }),
      layer('/p.json', { mcpServers: false }),
    ]).mcpServers,
  ).toBe(false);
  expect(startupOf('openclaw', { agent: 'fake' }, []).mcpServers).toBe(
    undefined,
  );
  // The window's own agent too, whose other values are the invocation's.
  expect(
    startupOf('openclaw', { agent: 'openclaw', agentCommand: 'oc acp' }, [
      layer('/u.json', { mcpServers: false }),
    ]),
  ).toStrictEqual({
    agent: 'openclaw',
    agentCommand: 'oc acp',
    mcpServers: false,
  });
  // Only a boolean: anything else is a problem and is left out.
  expect(
    parseSettings(
      '/u.json',
      JSON.stringify({ agents: { x: { mcpServers: 'no' } } }),
    ).problems,
  ).not.toStrictEqual([]);
});

describe('tester: resource preference layering', () => {
  test('an empty later map preserves denied runtime lists and an explicit model reset', () => {
    const base = {
      teamSelection: {
        intent: 'prefer' as const,
        prefer: { agent: 'codex', model: 'large' },
        constraints: {
          agents: ['codex'],
          models: { codex: [] },
          modes: { codex: [] },
        },
      },
    };
    const result = mergeSettings(
      base,
      { teamSelection: { prefer: { model: null } } },
      { teamSelection: { constraints: { models: {}, modes: {} } } },
    );

    expect(result.teamSelection).toEqual({
      ...base.teamSelection,
      prefer: { agent: 'codex', model: null },
    });
    expect(base.teamSelection.prefer.model).toBe('large');
  });
});

describe('tester: fresh selected policy failure and repair', () => {
  test('a valid project override cannot hide an invalid policy in the user layer', async () => {
    await place(
      {
        user: JSON.stringify({
          teamSelection: { constraints: { models: { codex: null } } },
        }),
        project: JSON.stringify({
          teamSelection: { constraints: { models: { codex: ['supported'] } } },
        }),
      },
      async (where) => {
        expect(
          (await loadSettings(where)).settings.teamSelection?.constraints
            ?.models?.codex,
        ).toEqual(['supported']);
        expect(await readTeamSelection(where)).toHaveProperty('error');
      },
    );
  });

  test('repair and removal are observed without retaining an earlier failure or deny list', async () => {
    await place(
      {
        user: JSON.stringify({
          teamSelection: { constraints: { agents: ['codex'] } },
        }),
        project: JSON.stringify({
          teamSelection: { constraints: { agents: null } },
        }),
      },
      async (where) => {
        expect(await readTeamSelection(where)).toHaveProperty('error');

        const project = settingsFiles(where)[1]!;

        await writeFile(
          project,
          JSON.stringify({ teamSelection: { constraints: { agents: [] } } }),
        );
        expect(await readTeamSelection(where)).toEqual({
          policy: { constraints: { agents: [] } },
        });

        await rm(project);

        expect(await readTeamSelection(where)).toEqual({
          policy: { constraints: { agents: ['codex'] } },
        });
      },
    );
  });
});

describe('CHD-568 U1 tester: fresh path writes and hostile keys', () => {
  test('each write rereads unrelated hand edits and refuses a later broken file', async () => {
    await place({ user: '{}' }, async (where) => {
      const file = settingsFiles(where)[0]!;

      await saveSettingAt(file, ['theme'], { set: 'dark' });
      await writeFile(file, '{"theme":"light","keep":{"nested":[1,null]}}');
      await saveSettingAt(file, ['agents', 'my.agent', 'model'], { set: 'm' });
      expect(JSON.parse(await readFile(file, 'utf8'))).toEqual({
        theme: 'light',
        keep: { nested: [1, null] },
        agents: { 'my.agent': { model: 'm' } },
      });

      const broken = '{"env":{"TOKEN":secret123}}';

      await writeFile(file, broken);
      await expect(
        saveSettingAt(file, ['theme'], { set: 'dark' }),
      ).rejects.toThrow('it is not valid JSON');
      expect(await readFile(file, 'utf8')).toBe(broken);
      expect(readdirSync(join(file, '..'))).toEqual(['settings.json']);
    });
  });

  test('removing a dotted own agent name preserves its siblings and project bytes', async () => {
    const project = '{ "agents": {"my.agent":{"model":"project"}} }';

    await place(
      {
        user: '{"agents":{"my.agent":{"model":false},"hasOwnProperty":{"model":"keep"}}}',
        project,
      },
      async (where) => {
        const [user, local] = settingsFiles(where);

        await saveSettingAt(user, ['agents', 'my.agent', 'model'], {
          remove: true,
        });
        expect(JSON.parse(await readFile(user!, 'utf8'))).toEqual({
          agents: { hasOwnProperty: { model: 'keep' } },
        });
        expect(await readFile(local!, 'utf8')).toBe(project);
      },
    );
  });

  test('forbidden keys refuse removal at every depth without rewriting bytes', async () => {
    const raw = '{ "agents": {"codex":{"model":"m"}} }';

    await place({ user: raw }, async (where) => {
      const file = settingsFiles(where)[0]!;

      for (const key of ['__proto__', 'constructor', 'prototype']) {
        for (const path of [[key], ['agents', key], ['agents', 'codex', key]]) {
          await expect(
            saveSettingAt(file, path, { remove: true }),
          ).rejects.toThrow(/^No setting /u);
        }
      }

      expect(await readFile(file, 'utf8')).toBe(raw);
    });
  });

  test('nested values and unusual path keys encode terminal controls without losing Unicode', () => {
    const controls = Array.from({ length: 160 }, (_, code) =>
      String.fromCharCode(code),
    ).join('');
    const value = { [controls]: ['🙂', '\u200d\u2066\u2029', controls] };
    const shown = shownValue(value);

    expect(shown).not.toMatch(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u);
    expect(JSON.parse(shown)).toEqual(value);
    expect(shown).toContain('🙂');
    expect(shownSettingPath(['agents', '', 'my.agent', controls])).toBe(
      `agents.""."my.agent".${shownValue(controls)}`,
    );
  });
});

describe('the settings path writer (CHD-568)', () => {
  /** A user's settings file under a temporary root, as `text` when given. */
  async function inFile(
    text: string | undefined,
    run: (file: string, root: string) => Promise<void>,
  ) {
    const root = await mkdtemp(join(tmpdir(), 'chord-settings-at-'));
    const file = join(root, 'chord', 'settings.json');

    try {
      if (text !== undefined) {
        await mkdir(join(root, 'chord'));
        await writeFile(file, text);
      }

      await run(file, root);
    } finally {
      await rm(root, { recursive: true });
    }
  }

  const json = async (file: string): Promise<unknown> =>
    JSON.parse(await readFile(file, 'utf8'));

  test("a set keeps every other key, the same agent's too", async () => {
    await inFile(
      JSON.stringify({
        unknownKey: [1],
        theme: 42,
        agents: { codex: { command: 'codex-acp', model: 'old' }, other: {} },
      }),
      async (file) => {
        await saveSettingAt(file, ['agents', 'codex', 'model'], {
          set: 'new',
        });

        expect(await json(file)).toStrictEqual({
          unknownKey: [1],
          theme: 42,
          agents: { codex: { command: 'codex-acp', model: 'new' }, other: {} },
        });
      },
    );
  });

  test('a set makes the file, its directory and the parents it lacks', async () => {
    await inFile(undefined, async (file) => {
      await saveSettingAt(file, ['teamSelection', 'prefer', 'model'], {
        set: null,
      });

      expect(await json(file)).toStrictEqual({
        teamSelection: { prefer: { model: null } },
      });
    });
  });

  test('the file is two-space JSON with a final newline', async () => {
    await inFile('{"theme":"dark"}', async (file) => {
      await saveSettingAt(file, ['mouse'], { set: false });

      expect(await readFile(file, 'utf8')).toBe(
        '{\n  "theme": "dark",\n  "mouse": false\n}\n',
      );
    });
  });

  test('a bad value at the path itself is replaced', async () => {
    await inFile('{"theme":{"not":"a theme"}}', async (file) => {
      await saveSettingAt(file, ['theme'], { set: 'dark' });

      expect(await json(file)).toStrictEqual({ theme: 'dark' });
    });
  });

  test('a remove takes the leaf and the parents it leaves empty', async () => {
    await inFile(
      JSON.stringify({
        theme: 'dark',
        teamSelection: { prefer: { model: 'm' } },
      }),
      async (file) => {
        await saveSettingAt(file, ['teamSelection', 'prefer', 'model'], {
          remove: true,
        });

        expect(await json(file)).toStrictEqual({ theme: 'dark' });
      },
    );
  });

  test('a remove stops at a parent that still holds a key', async () => {
    await inFile(
      JSON.stringify({
        agents: { codex: { model: 'm', effort: 'high' }, claude: {} },
      }),
      async (file) => {
        await saveSettingAt(file, ['agents', 'codex', 'model'], {
          remove: true,
        });

        expect(await json(file)).toStrictEqual({
          agents: { codex: { effort: 'high' }, claude: {} },
        });
      },
    );
  });

  test('a remove of the last key leaves an empty object, not no file', async () => {
    await inFile('{"theme":"dark"}', async (file) => {
      await saveSettingAt(file, ['theme'], { remove: true });

      expect(await json(file)).toStrictEqual({});
    });
  });

  test('a remove takes a null, which is a value', async () => {
    await inFile('{"teamSelection":{"intent":null,"a":1}}', async (file) => {
      await saveSettingAt(file, ['teamSelection', 'intent'], { remove: true });

      expect(await json(file)).toStrictEqual({ teamSelection: { a: 1 } });
    });
  });

  test('a remove of an absent key writes nothing and makes nothing', async () => {
    const written = '{ "agents": {"codex": {}} }';

    await inFile(written, async (file) => {
      await saveSettingAt(file, ['agents', 'codex', 'model'], { remove: true });

      expect(await readFile(file, 'utf8')).toBe(written);
    });

    await inFile(undefined, async (file, root) => {
      await saveSettingAt(file, ['theme'], { remove: true });

      expect(readdirSync(root)).toStrictEqual([]);
    });
  });

  test('inherited names are no keys of a parent', async () => {
    await inFile('{"agents":{}}', async (file) => {
      await saveSettingAt(file, ['agents', 'toString', 'model'], {
        remove: true,
      });
      expect(await json(file)).toStrictEqual({ agents: {} });

      await saveSettingAt(file, ['agents', 'toString', 'model'], { set: 'm' });
      expect(await json(file)).toStrictEqual({
        agents: { toString: { model: 'm' } },
      });
    });
  });

  test.each([
    ['["a list"]', 'it is not a JSON object'],
    ['3', 'it is not a JSON object'],
    ['null', 'it is not a JSON object'],
    ['{ not json', 'it is not valid JSON'],
  ])('a file of %s is refused and stays as it was', async (written, why) => {
    await inFile(written, async (file, root) => {
      for (const change of [{ set: 'dark' }, { remove: true } as const]) {
        await expect(saveSettingAt(file, ['theme'], change)).rejects.toThrow(
          why,
        );
      }

      expect(await readFile(file, 'utf8')).toBe(written);
      expect(readdirSync(join(root, 'chord'))).toStrictEqual(['settings.json']);
    });
  });

  test.each([
    ['{"agents":3}', 'agents'],
    ['{"agents":[]}', 'agents'],
    ['{"agents":null}', 'agents'],
    ['{"agents":{"my.agent":"x"}}', 'agents."my.agent"'],
  ])(
    'a parent in %s is refused on set and remove alike',
    async (written, parent) => {
      await inFile(written, async (file) => {
        for (const change of [{ set: 'm' }, { remove: true } as const]) {
          await expect(
            saveSettingAt(file, ['agents', 'my.agent', 'model'], change),
          ).rejects.toThrow(`its ${parent} is not an object; edit it by hand`);
        }

        expect(await readFile(file, 'utf8')).toBe(written);
      });
    },
  );

  test('no home is refused', async () => {
    await expect(
      saveSettingAt(undefined, ['theme'], { set: 'dark' }),
    ).rejects.toThrow(NO_SETTINGS_HOME);
  });

  test.each(['__proto__', 'constructor', 'prototype'])(
    '%s is never a key',
    async (key) => {
      expect(canBeSettingPath(['agents', key, 'model'])).toBe(false);

      await inFile('{"agents":{}}', async (file) => {
        for (const path of [[key], ['agents', key, 'model']]) {
          await expect(
            saveSettingAt(file, path, { set: { polluted: true } }),
          ).rejects.toThrow(/^No setting /u);
        }

        expect(await json(file)).toStrictEqual({ agents: {} });
      });

      expect(({} as Record<string, unknown>)['polluted']).toBeUndefined();
    },
  );

  test('an empty path is no setting', async () => {
    expect(canBeSettingPath([])).toBe(false);

    await inFile(undefined, async (file) => {
      await expect(saveSettingAt(file, [], { set: {} })).rejects.toThrow(
        /^No setting /u,
      );
    });
  });

  test("a file's own __proto__ key survives a write of another", async () => {
    await inFile('{"__proto__":{"a":1},"theme":"dark"}', async (file) => {
      await saveSettingAt(file, ['mouse'], { set: true });

      expect(await readFile(file, 'utf8')).toContain('"__proto__"');
    });
  });

  test('a failed write leaves the file and no temporary beside it', async () => {
    await inFile('{"theme":"dark"}', async (file, root) => {
      const directory = join(root, 'chord');

      await chmod(directory, 0o500);

      try {
        await expect(
          saveSettingAt(file, ['theme'], { set: 'light' }),
        ).rejects.toThrow();
      } finally {
        await chmod(directory, 0o700);
      }

      expect(await readFile(file, 'utf8')).toBe('{"theme":"dark"}');
      expect(readdirSync(directory)).toStrictEqual(['settings.json']);
    });
  });

  test('readSettingsObject takes an absent file for none', async () => {
    await inFile(undefined, async (file) => {
      expect(await readSettingsObject(file)).toStrictEqual({});
    });
  });

  test('settingAt reads own keys and stops at what is not an object', () => {
    const settings = { agents: { codex: { model: 'm' } }, list: ['a'] };

    expect(settingAt(settings, ['agents', 'codex', 'model'])).toBe('m');
    expect(settingAt(settings, ['agents', 'toString'])).toBeUndefined();
    expect(settingAt(settings, ['list', '0'])).toBeUndefined();
    expect(settingAt(settings, [])).toBe(settings);
  });

  test('settingParentProblem says nothing of the leaf itself', () => {
    expect(settingParentProblem({ theme: 3 }, ['theme'])).toBeUndefined();
    expect(
      settingParentProblem({ agents: { a: {} } }, ['agents', 'b', 'model']),
    ).toBeUndefined();
  });

  test('shownValue escapes what JSON leaves raw', () => {
    expect(shownValue('gpt-6.1')).toBe('"gpt-6.1"');
    expect(shownValue(['claude', 'codex'])).toBe('["claude","codex"]');
    expect(shownValue(null)).toBe('null');
    expect(shownValue('a\u007fb')).toBe('"a\\u007fb"');
    expect(shownValue('a\u009bb')).toBe('"a\\u009bb"');
    expect(shownValue('a\u2028b\u2029c')).toBe('"a\\u2028b\\u2029c"');
    expect(shownValue('a\u202eb')).toBe('"a\\u202eb"');
    expect(shownValue('a\u{e0001}b')).toBe('"a\\udb40\\udc01b"');
    expect(shownValue('a\nb')).toBe('"a\\nb"');
  });

  test('shownSettingPath encodes a key that is not plain', () => {
    expect(shownSettingPath(['agents', 'codex', 'model'])).toBe(
      'agents.codex.model',
    );
    expect(shownSettingPath(['agents', 'my.agent', 'model'])).toBe(
      'agents."my.agent".model',
    );
    expect(shownSettingPath(['a\u202eb'])).toBe('"a\\u202eb"');
  });
});
