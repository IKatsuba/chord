import { describe, expect, test } from 'bun:test';
import { readdirSync } from 'node:fs';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  agentCommands,
  homePath,
  knownAgents,
  loadSettings,
  mergeSettings,
  parseSettings,
  problemLine,
  problemNote,
  refusalLine,
  resolveStartup,
  resumedStartup,
  saveEditorMode,
  saveTheme,
  settingsFiles,
  setWhere,
  shownPath,
  startupOf,
  unseenProblems,
} from '../src/settings.ts';
import { parse } from 'shell-quote';
import { commandLine, listedAgents } from '../src/agents.ts';
import { commandArgv } from '../src/acp/process.ts';
import { resumeCommand } from '../src/session/sessions.ts';

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
      ).toStrictEqual([{ file, message: 'unknown key "colour", ignored' }]);
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

  test('an empty argument after the program is kept as written, through the line it is shown and resumed by', () => {
    const found = startupOf('codex', { agent: 'fake' }, [
      layer({ command: ['tool', '--value', ''] }),
    ]);

    expect(found.agentCommand).toStrictEqual(['tool', '--value', '']);
    expect(commandLine(found.agentCommand!)).toStrictEqual("tool --value ''");

    // As a shell reads the resume line, then as chord splits the flag.
    const words = parse(resumeCommand('codex', 'id', found.agentCommand));
    const flag = words[words.indexOf('--agent-command') + 1];

    expect(parse(String(flag))).toStrictEqual(['tool', '--value', '']);
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

  test('literal special and empty arguments survive display and a resume flag', () => {
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
    const resume = parse(resumeCommand('custom', 'session-id', command));
    const flag = resume[resume.indexOf('--agent-command') + 1];

    expect(commandArgv(line)).toEqual(command);
    expect(commandArgv(String(flag))).toEqual(command);
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
