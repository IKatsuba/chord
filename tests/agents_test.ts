import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { RealEnvironment, which } from '@david/which';
import {
  agentsJson,
  agentStart,
  agentTable,
  DEFAULT_AGENT,
  findAgent,
  listAgents,
  listedAgents,
  missingCommand,
  offeredAgents,
  startLine,
  takesMcpServers,
} from '../src/agents.ts';
import { CLI_AGENTS } from '../src/clis.ts';
import { REGISTRY_AGENTS } from '../src/registry.ts';
import { frozenAgents } from '../scripts/dev/registry.ts';
import { FAKE_PROVIDER_ENV, riffAgentStart } from '../src/riff/start.ts';

test('the default agent is one chord knows', () => {
  expect(findAgent(DEFAULT_AGENT) !== undefined).toBeTruthy();
});

test("a registry agent says the package and version npx or uvx runs, one of chord's table none (CHD-454)", () => {
  const agoragentic = REGISTRY_AGENTS.find(
    (agent) => agent.id === 'agoragentic-acp',
  )!;

  expect(findAgent('agoragentic-acp')?.pinned).toStrictEqual(
    `${agoragentic.package}@${agoragentic.version}`,
  );
  expect(findAgent('zeroclaw')?.pinned).toBeUndefined();
});

test('claude and codex are the short names of the registry ids', () => {
  const names = listAgents().map(({ name }) => name);

  expect(names.includes('claude')).toBeTruthy();
  expect(names.includes('codex')).toBeTruthy();
  expect(!names.includes('claude-acp')).toBeTruthy();
  expect(!names.includes('codex-acp')).toBeTruthy();
  expect(agentStart('claude').command[2]).toStrictEqual(
    `@agentclientprotocol/claude-agent-acp@${
      REGISTRY_AGENTS.find(({ id }) => id === 'claude-acp')?.version
    }`,
  );
  expect(findAgent('codex')?.title).toStrictEqual('Codex');
});

test('every other agent is known by its registry id', () => {
  const gemini = REGISTRY_AGENTS.find(({ id }) => id === 'gemini');

  assert(gemini !== undefined);
  expect(agentStart('gemini').command).toStrictEqual([
    'npx',
    '-y',
    `@google/gemini-cli@${gemini.version}`,
    ...gemini.args,
  ]);
});

test('an agent starts through npx at its exact version, with its env', () => {
  const droid = REGISTRY_AGENTS.find(({ id }) => id === 'factory-droid');

  assert(droid !== undefined);

  const start = agentStart('factory-droid');

  expect(start.env).toStrictEqual(droid.env);
  expect(startLine(start)).toStrictEqual(
    [
      ...Object.entries(droid.env).map(([key, value]) => `${key}=${value}`),
      'npx',
      '-y',
      `droid@${droid.version}`,
      ...droid.args,
    ].join(' '),
  );

  for (const agent of REGISTRY_AGENTS) {
    expect(/^\d+\.\d+\.\d+/.test(agent.version), agent.id).toBeTruthy();
  }

  for (const { name, start, runner } of listAgents()) {
    if (runner === 'npx') {
      expect(start.command.slice(0, 2), name).toStrictEqual(['npx', '-y']);
    }
  }
});

test('a uvx agent starts through uvx at its exact version, with its env', () => {
  const fast = REGISTRY_AGENTS.find(({ id }) => id === 'fast-agent');

  assert(fast !== undefined);
  expect(fast.runner).toStrictEqual('uvx');
  expect(agentStart('fast-agent')).toStrictEqual({
    command: ['uvx', `${fast.package}@${fast.version}`, ...fast.args],
    env: fast.env,
  });
  expect(findAgent('fast-agent')?.install).toStrictEqual(fast.website);
});

test('a table agent starts by its own CLI, with no env', () => {
  expect(agentStart('cursor')).toStrictEqual({
    command: ['agent', 'acp'],
    env: {},
  });
  expect(findAgent('cursor')?.runner).toStrictEqual('cli');
  expect(findAgent('cursor')?.install).toStrictEqual(
    'https://cursor.com/docs/cli/installation',
  );
  expect(agentStart('cursor', 'my-cursor --acp')).toStrictEqual({
    command: 'my-cursor --acp',
    env: {},
  });
});

test('a name in the registry and the table starts as the registry says', () => {
  for (const { name } of CLI_AGENTS) {
    const registered = REGISTRY_AGENTS.some(({ id }) => id === name);

    expect(findAgent(name)?.runner === 'cli', name).toStrictEqual(!registered);
  }
});

/** A directory to stand for PATH, with an executable for each command. */
async function fakePath(...commands: string[]) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-path-'));

  for (const command of commands) {
    await writeFile(join(dir, command), '#!/bin/sh\n', {
      mode: 0o755,
    });
  }

  const environment = new (class extends RealEnvironment {
    override env(key: string) {
      return key === 'PATH' ? dir : super.env(key);
    }
  })();

  return {
    dir,
    lookup: (command: string) => which(command, environment),
  };
}

test('a command missing from PATH refuses with where to install it', async () => {
  const { dir, lookup } = await fakePath('npx');

  try {
    expect(await missingCommand('cursor', undefined, lookup)).toStrictEqual(
      'chord: cursor runs "agent", which is not on PATH; ' +
        'install it from https://cursor.com/docs/cli/installation',
    );
    expect(await missingCommand('claude', undefined, lookup)).toStrictEqual(
      undefined,
    );
  } finally {
    await rm(dir, { recursive: true });
  }
});

test('a missing npx points at Node.js, not at the agent', async () => {
  const { dir, lookup } = await fakePath('uvx');

  try {
    expect(await missingCommand('claude', undefined, lookup)).toStrictEqual(
      'chord: claude runs "npx", which is not on PATH; ' +
        'npx comes with Node.js: https://nodejs.org/en/download',
    );
  } finally {
    await rm(dir, { recursive: true });
  }
});

test('a missing uvx points at uv, not at the agent', async () => {
  const { dir, lookup } = await fakePath('npx');

  try {
    expect(await missingCommand('fast-agent', undefined, lookup)).toStrictEqual(
      'chord: fast-agent runs "uvx", which is not on PATH; ' +
        'uvx comes with uv: https://docs.astral.sh/uv/getting-started/installation/',
    );
  } finally {
    await rm(dir, { recursive: true });
  }
});

test('a command on PATH, or one that overrides the name, is not refused', async () => {
  const { dir, lookup } = await fakePath('agent');

  try {
    expect(await missingCommand('cursor', undefined, lookup)).toStrictEqual(
      undefined,
    );
    expect(await missingCommand('kiro', 'my-kiro', lookup)).toStrictEqual(
      undefined,
    );
    expect(
      await missingCommand('no-such-agent', undefined, lookup),
    ).toStrictEqual(undefined);
  } finally {
    await rm(dir, { recursive: true });
  }
});

test('an unknown name is refused unless a command overrides it', () => {
  expect(findAgent('no-such-agent')).toStrictEqual(undefined);
  expect(() => agentStart('no-such-agent')).toThrow(Error);
  expect(() => agentStart('no-such-agent')).toThrow('no-such-agent');
  expect(agentStart('no-such-agent', 'my-agent --acp')).toStrictEqual({
    command: 'my-agent --acp',
    env: {},
  });
});

test('an override replaces a known agent, the registry env with it', () => {
  expect(agentStart('claude', ['deno', 'run', 'fake.ts'])).toStrictEqual({
    command: ['deno', 'run', 'fake.ts'],
    env: {},
  });
});

test('the registry lists each agent once', () => {
  const names = listAgents().map(({ name }) => name);

  expect(new Set(names).size).toStrictEqual(names.length);
});

const REGISTRY = {
  version: '1.0.0',
  agents: [
    {
      id: 'binary-only',
      name: 'Binary only',
      distribution: {
        binary: { 'darwin-aarch64': { archive: 'x', cmd: 'x' } },
      },
    },
    {
      id: 'uvx-only',
      name: 'Uvx only',
      website: 'https://uvx.example',
      distribution: { uvx: { package: 'thing==1.0.0', args: ['acp'] } },
    },
    {
      id: 'uv-at',
      name: 'Uv at',
      repository: 'https://repo.example',
      distribution: { uvx: { package: 'other@0.1.44' } },
    },
    {
      id: 'both',
      name: 'Both',
      distribution: {
        uvx: { package: 'not-this==9.9.9' },
        binary: {},
        npx: {
          package: '@scope/both@1.2.3',
          args: ['--acp'],
          env: { NO_UPDATE: '1' },
        },
      },
    },
    {
      id: 'plain',
      name: 'Plain',
      distribution: { npx: { package: 'p@0.1.0' } },
    },
  ],
  extensions: [],
};

test('only agents npx or uvx starts are frozen, npx before uvx', () => {
  expect(frozenAgents(REGISTRY)).toStrictEqual([
    {
      id: 'uvx-only',
      name: 'Uvx only',
      runner: 'uvx',
      package: 'thing',
      version: '1.0.0',
      args: ['acp'],
      env: {},
      website: 'https://uvx.example',
    },
    {
      id: 'uv-at',
      name: 'Uv at',
      runner: 'uvx',
      package: 'other',
      version: '0.1.44',
      args: [],
      env: {},
      repository: 'https://repo.example',
    },
    {
      id: 'both',
      name: 'Both',
      runner: 'npx',
      package: '@scope/both',
      version: '1.2.3',
      args: ['--acp'],
      env: { NO_UPDATE: '1' },
    },
    {
      id: 'plain',
      name: 'Plain',
      runner: 'npx',
      package: 'p',
      version: '0.1.0',
      args: [],
      env: {},
    },
  ]);
});

test('a package without an exact version is refused, not frozen', () => {
  const refused = (distribution: unknown) => {
    const freeze = () =>
      frozenAgents({ agents: [{ id: 'x', name: 'X', distribution }] });

    expect(freeze).toThrow(Error);
    expect(freeze).toThrow('exact version');
  };

  for (const spec of ['p@latest', 'p@^1.0.0', 'p']) {
    refused({ npx: { package: spec } });
  }

  for (const spec of [
    'p',
    'p@latest',
    'p>=1.0',
    'p==1.*',
    'p==1.0,!=1.0.1',
    'p[extra]==1.0',
    'p==1.0; python_version>"3.8"',
  ]) {
    refused({ uvx: { package: spec } });
  }
});

test('chord agents marks the own CLIs PATH has, and lists the names only the settings define', async () => {
  const listed = await listedAgents(
    { mine: 'my-agent --acp', devin: 'my-devin acp' },
    (command) =>
      Promise.resolve(command === 'goose' ? '/bin/goose' : undefined),
  );
  const named = (name: string) => listed.find((agent) => agent.name === name);

  expect(named('goose')).toStrictEqual({
    name: 'goose',
    title: 'goose',
    start: 'goose acp',
    from: 'cli',
    found: true,
  });
  expect(named('cursor')?.found).toStrictEqual(false);
  // A settings command is the start, in the table's place, and needs no CLI.
  expect(named('devin')).toStrictEqual({
    name: 'devin',
    title: 'Devin',
    start: 'my-devin acp',
    from: 'settings',
  });
  expect(named('claude')?.from).toStrictEqual('npx');
  expect(named('claude')?.found).toStrictEqual(undefined);
  expect(listed.at(-1)).toStrictEqual({
    name: 'mine',
    title: undefined,
    start: 'my-agent --acp',
    from: 'settings',
  });
  expect(listed.length).toStrictEqual(listAgents().length + 1);
});

const CATALOG = [
  { name: 'claude', title: 'Claude', start: 'npx claude', from: 'npx' },
  { name: 'codex', title: 'Codex', start: 'npx codex', from: 'npx' },
  {
    name: 'goose',
    title: 'goose',
    start: 'goose acp',
    from: 'cli',
    found: true,
  },
  {
    name: 'cursor',
    title: 'Cursor',
    start: 'cursor-agent acp',
    from: 'cli',
    found: false,
  },
  { name: 'mine', title: undefined, start: 'mine --acp', from: 'settings' },
] as const;

const names = (offered: ReturnType<typeof offeredAgents>) =>
  offered.agents.map(({ name }) => name);

test('with no list, chord offers the catalog but for an own CLI PATH lacks', () => {
  const offered = offeredAgents(CATALOG, undefined);

  expect(names(offered)).toStrictEqual(['claude', 'codex', 'goose', 'mine']);
  expect(offered.unknown).toStrictEqual([]);
});

test("a list sets what is offered, in the list's order", () => {
  const offered = offeredAgents(CATALOG, ['mine', 'codex', 'claude']);

  expect(names(offered)).toStrictEqual(['mine', 'codex', 'claude']);
  expect(offered.unknown).toStrictEqual([]);
});

test('a listed own CLI PATH lacks keeps its row, marked as the catalog has it', () => {
  const offered = offeredAgents(CATALOG, ['cursor', 'goose']);

  expect(offered.agents).toStrictEqual([CATALOG[3], CATALOG[2]]);
});

test('a name the catalog lacks is unknown, in the order of the list', () => {
  const offered = offeredAgents(CATALOG, ['zed', 'codex', 'aider']);

  expect(names(offered)).toStrictEqual(['codex']);
  expect(offered.unknown).toStrictEqual(['zed', 'aider']);
});

test('a list of only unknown names offers nothing rather than the catalog', () => {
  expect(offeredAgents(CATALOG, ['zed'])).toStrictEqual({
    agents: [],
    unknown: ['zed'],
  });
});

test('a repeated name keeps its first place, known or unknown', () => {
  const offered = offeredAgents(CATALOG, [
    'codex',
    'zed',
    'claude',
    'codex',
    'zed',
  ]);

  expect(names(offered)).toStrictEqual(['codex', 'claude']);
  expect(offered.unknown).toStrictEqual(['zed']);
});

test('chord agents writes name, title, mark and start in columns', () => {
  expect(
    agentTable([
      {
        name: 'goose',
        title: 'goose',
        start: 'goose acp',
        from: 'cli',
        found: true,
      },
      {
        name: 'cursor',
        title: 'Cursor',
        start: 'agent acp',
        from: 'cli',
        found: false,
      },
      {
        name: 'claude',
        title: 'Claude Agent',
        start: 'npx -y c@1',
        from: 'npx',
      },
      { name: 'mine', title: undefined, start: 'my-agent', from: 'settings' },
    ]),
  ).toStrictEqual(
    [
      'goose   goose          own CLI · found        goose acp',
      'cursor  Cursor         own CLI · not on PATH  agent acp',
      'claude  Claude Agent   npx                    npx -y c@1',
      'mine    from settings  settings               my-agent',
    ].join('\n'),
  );
});

test('on a terminal, chord agents wraps a long start inside its column', () => {
  const listed = [
    {
      name: 'qwen',
      title: 'Qwen Code',
      start: 'npx -y @qwen-code/qwen-code@0.25.0 --acp --experimental-skills',
      from: 'npx',
    },
    {
      name: 'goose',
      title: 'goose',
      start: 'goose acp',
      from: 'cli',
      found: true,
    },
  ] as const;

  expect(agentTable(listed, 60)).toStrictEqual(
    [
      'qwen   Qwen Code  npx              npx -y @qwen-code/qwen-co',
      '                                   de@0.25.0 --acp',
      '                                   --experimental-skills',
      'goose  goose      own CLI · found  goose acp',
    ].join('\n'),
  );
  // Piped, one line each, for grep and awk.
  expect(agentTable(listed).split('\n').length).toStrictEqual(2);
});

test("openclaw takes no MCP servers by chord's own table, and a setting says otherwise either way (CHD-441)", () => {
  expect(takesMcpServers('openclaw')).toBe(false);
  expect(takesMcpServers('openclaw', true)).toBe(true);
  expect(takesMcpServers('codex')).toBe(true);
  expect(takesMcpServers('codex', false)).toBe(false);
  // An agent chord does not know takes them, as before.
  expect(takesMcpServers('somebody-else')).toBe(true);
});

describe('CHD-565 tester: offered catalog boundaries', () => {
  test('names match exactly and object property names remain ordinary agents', () => {
    const catalog = ['__proto__', 'constructor', 'toString'].map((name) => ({
      name,
      title: undefined,
      start: 'fixture --acp',
      from: 'settings' as const,
    }));

    expect(
      offeredAgents(catalog, [
        'toString',
        'Constructor',
        '__proto__',
        'constructor ',
        'constructor',
        '__proto__',
      ]),
    ).toStrictEqual({
      agents: [catalog[2]!, catalog[0]!, catalog[1]!],
      unknown: ['Constructor', 'constructor '],
    });
  });

  test('an unknown project name can become offered in its own directory', async () => {
    const elsewhere = await listedAgents({}, () => Promise.resolve(undefined));
    const project = await listedAgents(
      { 'project-fixture': ['fixture-agent', '--acp'] },
      () => Promise.resolve(undefined),
    );

    expect(offeredAgents(elsewhere, ['project-fixture'])).toStrictEqual({
      agents: [],
      unknown: ['project-fixture'],
    });
    expect(offeredAgents(project, ['project-fixture'])).toStrictEqual({
      agents: [
        {
          name: 'project-fixture',
          title: undefined,
          start: 'fixture-agent --acp',
          from: 'settings',
        },
      ],
      unknown: [],
    });
  });

  test('separate projections leave frozen inputs and the full catalog intact', () => {
    const catalog = Object.freeze(
      CATALOG.map((row) => Object.freeze({ ...row })),
    );
    const setting = Object.freeze(['cursor', 'missing', 'mine', 'cursor']);

    expect(names(offeredAgents(catalog, setting))).toStrictEqual([
      'cursor',
      'mine',
    ]);
    expect(names(offeredAgents(catalog, ['codex']))).toStrictEqual(['codex']);
    expect(names(offeredAgents(catalog, undefined))).toStrictEqual([
      'claude',
      'codex',
      'goose',
      'mine',
    ]);
    expect(catalog).toStrictEqual(CATALOG);
    expect(setting).toStrictEqual(['cursor', 'missing', 'mine', 'cursor']);
    expect(offeredAgents([], setting)).toStrictEqual({
      agents: [],
      unknown: ['cursor', 'missing', 'mine'],
    });
  });
});

describe('CHD-598 tester: JSON catalog boundaries', () => {
  test('repeated offered and unknown names keep first order without duplicate rows or problems', async () => {
    const listed = await listedAgents({}, () => Promise.resolve(undefined));
    const result = agentsJson({
      listed,
      offered: ['goose', 'missing-tester', 'claude', 'goose', 'missing-tester'],
      preferred: 'missing-preference',
      problems: [],
      refused: new Set(['claude', 'refused-only-tester']),
    });

    expect(result.preferred).toBe('missing-preference');
    expect(result.agents.map(({ name }) => name)).toStrictEqual([
      'goose',
      ...listed.filter(({ name }) => name !== 'goose').map(({ name }) => name),
    ]);
    expect(result.agents.filter(({ offered }) => offered)).toStrictEqual([
      {
        name: 'goose',
        title: 'goose',
        via: 'cli',
        found: false,
        offered: true,
        startable: true,
      },
    ]);
    expect(result.problems).toStrictEqual([
      { message: '"offeredAgents": no agent named missing-tester, left out' },
    ]);
  });

  test('an empty offered list leaves every catalog row present and unoffered', async () => {
    const listed = await listedAgents({}, () => Promise.resolve(undefined));
    const result = agentsJson({
      listed,
      offered: [],
      preferred: 'claude',
      problems: [],
      refused: new Set(),
    });

    expect(result.agents.map(({ name }) => name)).toStrictEqual(
      listed.map(({ name }) => name),
    );
    expect(result.agents.every(({ offered }) => !offered)).toBe(true);
    expect(result.problems).toStrictEqual([]);
  });
});

describe('chord agents --json (CHD-598)', () => {
  const listed = [
    { name: 'claude', title: 'Claude', start: 'npx claude', from: 'npx' },
    { name: 'fast', title: 'Fast', start: 'uvx fast', from: 'uvx' },
    {
      name: 'goose',
      title: 'goose',
      start: 'goose acp',
      from: 'cli',
      found: true,
    },
    {
      name: 'cursor',
      title: 'Cursor',
      start: 'cursor-agent acp',
      from: 'cli',
      found: false,
    },
    { name: 'codex', title: 'Codex', start: 'my-codex', from: 'settings' },
    { name: 'mine', title: undefined, start: 'mine --acp', from: 'settings' },
  ] as const;
  const json = (
    given: Partial<Parameters<typeof agentsJson>[0]> = {},
  ): ReturnType<typeof agentsJson> =>
    agentsJson({
      listed,
      offered: undefined,
      preferred: 'claude',
      problems: [],
      refused: new Set(),
      ...given,
    });
  const named = (name: string) =>
    json().agents.find((agent) => agent.name === name);

  test('the object carries the version, the preferred agent and every field', () => {
    expect(json({ preferred: 'goose' })).toStrictEqual({
      version: 1,
      preferred: 'goose',
      agents: [
        {
          name: 'claude',
          title: 'Claude',
          via: 'npx',
          found: null,
          offered: true,
          startable: true,
        },
        {
          name: 'fast',
          title: 'Fast',
          via: 'uvx',
          found: null,
          offered: true,
          startable: true,
        },
        {
          name: 'goose',
          title: 'goose',
          via: 'cli',
          found: true,
          offered: true,
          startable: true,
        },
        {
          name: 'codex',
          title: 'Codex',
          via: 'settings',
          found: null,
          offered: true,
          startable: true,
        },
        {
          name: 'mine',
          title: null,
          via: 'settings',
          found: null,
          offered: true,
          startable: true,
        },
        {
          name: 'cursor',
          title: 'Cursor',
          via: 'cli',
          found: false,
          offered: false,
          startable: true,
        },
      ],
      problems: [],
    });
  });

  test('found is a boolean for an own CLI only', () => {
    expect(named('goose')?.found).toBe(true);
    expect(named('cursor')?.found).toBe(false);

    for (const name of ['claude', 'fast', 'codex', 'mine']) {
      expect(named(name)?.found).toBeNull();
    }
  });

  test("with the setting, its names come first in its order, the rest in the catalog's", () => {
    const agents = json({ offered: ['mine', 'cursor', 'claude'] }).agents;

    expect(agents.map(({ name, offered }) => [name, offered])).toStrictEqual([
      ['mine', true],
      ['cursor', true],
      ['claude', true],
      ['fast', false],
      ['goose', false],
      ['codex', false],
    ]);
  });

  test('a name the setting gives that chord lacks is a problem without a file', () => {
    const problem = {
      file: '/config/chord/settings.json',
      kind: 'validation',
      message: 'unknown key "x", ignored',
    } as const;

    expect(
      json({ offered: ['zed', 'claude'], problems: [problem] }).problems,
    ).toStrictEqual([
      { file: problem.file, message: problem.message },
      { message: '"offeredAgents": no agent named zed, left out' },
    ]);
  });

  test('a refused command leaves its agent unstartable and not offered, with or without the setting', () => {
    for (const offered of [undefined, ['codex', 'claude']]) {
      const agents = json({ offered, refused: new Set(['codex']) }).agents;

      expect(agents.find(({ name }) => name === 'codex')).toStrictEqual({
        name: 'codex',
        title: 'Codex',
        via: 'settings',
        found: null,
        offered: false,
        startable: false,
      });
      expect(
        agents.filter(({ startable }) => !startable).map(({ name }) => name),
      ).toStrictEqual(['codex']);
    }
  });
});

describe('riff in the agent list (CHD-604c)', () => {
  const off = {};
  const on = { [FAKE_PROVIDER_ENV]: 'http://localhost:1/v1' };
  const none: (command: string) => Promise<string | undefined> = () =>
    Promise.resolve(undefined);
  const riffRow = {
    name: 'riff',
    title: "chord's own agent · on a ChatGPT or Grok plan",
    start: startLine(riffAgentStart()),
    from: 'builtin',
  } as const;

  test('off the fake provider riff is available without reading a credential', async () => {
    expect(findAgent('riff', off)?.runner).toBe('builtin');
    expect(listAgents(off)[0]?.name).toBe('riff');
    expect(
      (await listedAgents({}, none, off)).map(({ name }) => name),
    ).toContain('riff');
    expect(findAgent('riff', { [FAKE_PROVIDER_ENV]: '' })?.runner).toBe(
      'builtin',
    );
  });

  test("on it riff is the catalog's first row, built in", async () => {
    expect(findAgent('riff', on)?.runner).toBe('builtin');
    expect(listAgents(on)[0]?.name).toBe('riff');
    expect(listAgents(on)).toStrictEqual(listAgents(off));

    const looked: string[] = [];
    const listed = await listedAgents(
      {},
      (command) => {
        looked.push(command);

        return Promise.resolve(undefined);
      },
      on,
    );

    expect(listed[0]).toStrictEqual(riffRow);
    // chord itself is not looked for on PATH.
    expect(looked).not.toContain(riffAgentStart().command[0]);
  });

  test('a settings command for riff wins, as for any agent', async () => {
    const [first] = await listedAgents({ riff: 'my-riff' }, none, on);

    expect(first).toStrictEqual({
      name: 'riff',
      title: riffRow.title,
      start: 'my-riff',
      from: 'settings',
    });
  });

  test("offered first without the setting; the setting's order wins", async () => {
    const listed = await listedAgents({}, none, on);

    expect(offeredAgents(listed, undefined).agents[0]?.name).toBe('riff');
    expect(
      offeredAgents(listed, ['claude', 'riff']).agents.map(({ name }) => name),
    ).toStrictEqual(['claude', 'riff']);
  });

  test('chord agents says built in; --json says builtin, found null', () => {
    const table = agentTable([riffRow]);

    expect(table).toContain('built in');
    expect(table.startsWith('riff')).toBeTruthy();
    expect(
      agentsJson({
        listed: [riffRow],
        offered: undefined,
        preferred: DEFAULT_AGENT,
        problems: [],
        refused: new Set(),
      }),
    ).toStrictEqual({
      version: 1,
      preferred: 'claude',
      agents: [
        {
          name: 'riff',
          title: riffRow.title,
          via: 'builtin',
          found: null,
          offered: true,
          startable: true,
        },
      ],
      problems: [],
    });
  });

  test('claude stays the default', () => {
    expect(DEFAULT_AGENT).toBe('claude');
  });
});

describe('CHD-604c tester: catalog environment boundaries', () => {
  const lookup = (command: string) =>
    Promise.resolve(command === 'agent' ? '/fixture/bin/agent' : undefined);

  test('an explicit offered list names riff once with or without a fake provider', async () => {
    for (const provider of [undefined, '', 'http://localhost:1/v1']) {
      const listed = await listedAgents({}, lookup, {
        [FAKE_PROVIDER_ENV]: provider,
      });
      const offered = offeredAgents(listed, ['riff', 'claude', 'riff']);

      expect(offered.agents.map(({ name }) => name)).toStrictEqual([
        'riff',
        'claude',
      ]);
      expect(offered.unknown).toStrictEqual([]);
      expect(DEFAULT_AGENT).toBe('claude');
    }
  });

  test('the fake provider preserves the complete catalog JSON', async () => {
    const commands = { mine: 'fixture-agent --token fixture-secret' };
    const snapshot = async (enabled: boolean) =>
      agentsJson({
        listed: await listedAgents(commands, lookup, {
          [FAKE_PROVIDER_ENV]: enabled ? 'http://localhost:1/v1' : undefined,
        }),
        offered: undefined,
        preferred: DEFAULT_AGENT,
        problems: [
          {
            file: '/fixture/settings.json',
            kind: 'validation',
            message: 'fixture settings problem',
          },
        ],
        refused: new Set(['mine']),
      });
    const before = await snapshot(false);
    const after = await snapshot(true);

    expect(after).toStrictEqual(before);
    expect(after.agents.filter(({ name }) => name === 'riff')).toHaveLength(1);
    expect(Object.keys(after).sort()).toStrictEqual([
      'agents',
      'preferred',
      'problems',
      'version',
    ]);
    expect(JSON.stringify(after)).not.toContain('fixture-secret');
    expect(after.agents[0]).toMatchObject({
      name: 'riff',
      via: 'builtin',
      found: null,
      offered: true,
      startable: true,
    });
  });

  test('an explicit list can leave built-in riff unoffered without changing the preference', async () => {
    const listed = await listedAgents({}, lookup, {
      [FAKE_PROVIDER_ENV]: 'http://localhost:1/v1',
    });

    for (const offered of [[], ['claude']]) {
      const json = agentsJson({
        listed,
        offered,
        preferred: DEFAULT_AGENT,
        problems: [],
        refused: new Set(),
      });

      expect(json.preferred).toBe('claude');
      expect(json.agents.find(({ name }) => name === 'riff')).toMatchObject({
        via: 'builtin',
        found: null,
        offered: false,
        startable: true,
      });
      expect(json.problems).toStrictEqual([]);
    }
  });
});
