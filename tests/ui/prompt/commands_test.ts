import { expect, test } from 'bun:test';
import type { AvailableCommand } from '@agentclientprotocol/sdk';
import {
  agentItems,
  agentQuery,
  commandItems,
  commandQuery,
  completion,
  itemLabel,
  matchAgents,
  matchCommands,
  menuRowLimit,
  moveHighlight,
  submitted,
  teamItems,
  teamQuery,
  visibleRange,
} from '../../../src/ui/prompt/commands.ts';

// An agent may leave a description out, as nothing checks its updates.
const AGENT = [
  { name: 'review', description: 'Review a pull request' },
  { name: 'compact', description: 'Compact the conversation' },
  { name: 'init' },
] as AvailableCommand[];

const names = (items: readonly { name: string }[]) =>
  items.map(({ name }) => name);

test("the list is chord's commands and the agent's, by name", () => {
  const items = commandItems(AGENT);

  expect(names(items)).toStrictEqual([
    'clear',
    'compact',
    'config',
    'context',
    'cost',
    'exit',
    'help',
    'init',
    'mcp',
    'model',
    'new',
    'resume',
    'review',
    'status',
    'team',
    'theme',
    'vim',
  ]);
  expect(items.find(({ name }) => name === 'clear')?.owner).toStrictEqual(
    'chord',
  );
  expect(items.find(({ name }) => name === 'review')).toStrictEqual({
    name: 'review',
    description: 'Review a pull request',
    owner: 'agent',
  });
  // A command with no description has none, rather than an empty one.
  expect(items.find(({ name }) => name === 'init')).toStrictEqual({
    name: 'init',
    owner: 'agent',
  });
  expect(names(commandItems([]))).toStrictEqual([
    'clear',
    'config',
    'context',
    'cost',
    'exit',
    'help',
    'mcp',
    'model',
    'new',
    'resume',
    'status',
    'team',
    'theme',
    'vim',
  ]);
});

test('a description is its first line, so each command is one row', () => {
  const agent = (description: string) =>
    commandItems([{ name: 'skill', description }]).find(
      ({ owner }) => owner === 'agent',
    );

  expect(
    agent('  Reference for the API.\nTRIGGER — read first.\n')?.description,
  ).toStrictEqual('Reference for the API.');
  // A blank one is none, rather than an empty row beside the name.
  expect(agent(' \n')).toStrictEqual({ name: 'skill', owner: 'agent' });
});

test("an agent command named like chord's is left out", () => {
  const items = commandItems([{ name: 'help', description: 'Agent help' }]);

  expect(items.filter(({ name }) => name === 'help')).toStrictEqual([
    {
      name: 'help',
      description: 'Show keyboard shortcuts',
      owner: 'chord',
    },
  ]);
});

test('the list is open while the draft is a slash and part of a name', () => {
  expect(commandQuery('/')).toStrictEqual('');
  expect(commandQuery('/he')).toStrictEqual('he');
  expect(commandQuery('/pr-comments')).toStrictEqual('pr-comments');
  expect(commandQuery('')).toStrictEqual(undefined);
  expect(commandQuery('hello')).toStrictEqual(undefined);
  expect(commandQuery(' /he')).toStrictEqual(undefined);
  // Once arguments start, or a second line, the list is put away.
  expect(commandQuery('/echo ')).toStrictEqual(undefined);
  expect(commandQuery('/echo hi')).toStrictEqual(undefined);
  expect(commandQuery('/he\nx')).toStrictEqual(undefined);
});

test("a team's name is completed after /team show, run and stop, a run's after stop", () => {
  expect(teamQuery('/team show bu')).toStrictEqual({
    form: 'show',
    name: 'bu',
  });
  expect(teamQuery('/team edit bu')).toStrictEqual(undefined);
  expect(teamQuery('/team run ')).toStrictEqual({ form: 'run', name: '' });
  expect(teamQuery('/team stop bugfix 2')).toStrictEqual({
    form: 'stop',
    name: 'bugfix 2',
  });
  // Once the job starts, or for a form that takes no name, it is put away.
  expect(teamQuery('/team run bugfix fix it')).toStrictEqual(undefined);
  expect(teamQuery('/team new a')).toStrictEqual(undefined);
  expect(teamQuery('/team show')).toStrictEqual(undefined);

  const teams = [
    { name: 'bugfix', broken: false },
    { name: 'triage', broken: true },
  ];

  expect(names(teamItems('run', teams, ['bugfix 2']))).toStrictEqual([
    'bugfix',
  ]);
  expect(names(teamItems('show', teams, []))).toStrictEqual(['bugfix']);
  expect(names(teamItems('stop', teams, ['bugfix', 'bugfix 2']))).toStrictEqual(
    ['bugfix', 'bugfix 2'],
  );

  const [show] = teamItems('show', teams, []);
  const [run] = teamItems('run', teams, []);

  expect(itemLabel(show!)).toStrictEqual('bugfix');
  expect(completion(show!)).toStrictEqual('/team show bugfix ');
  expect(submitted('/team show bu', show)).toStrictEqual({
    type: 'chord',
    name: 'team',
    args: 'show bugfix',
  });
  // A run's job is still to be typed, so Enter puts the name in the box.
  expect(submitted('/team run bu', run)).toStrictEqual({
    type: 'complete',
    text: '/team run bugfix ',
  });
});

test('typing filters by the letters in order, best match first', () => {
  const items = commandItems(AGENT);

  expect(names(matchCommands(items, ''))).toStrictEqual(names(items));
  expect(names(matchCommands(items, 'he'))).toStrictEqual(['help', 'theme']);
  // Letters in order, not side by side, as Claude Code matches them.
  expect(names(matchCommands(items, 'rv'))).toStrictEqual(['review']);
  expect(names(matchCommands(items, 'cl'))[0]).toStrictEqual('clear');
  expect(names(matchCommands(items, 'HE'))).toStrictEqual(['help', 'theme']);
  expect(matchCommands(items, 'zz')).toStrictEqual([]);
});

test('↑ and ↓ wrap round at either end', () => {
  expect(moveHighlight(0, 3, 1)).toStrictEqual(1);
  expect(moveHighlight(2, 3, 1)).toStrictEqual(0);
  expect(moveHighlight(0, 3, -1)).toStrictEqual(2);
  expect(moveHighlight(0, 0, 1)).toStrictEqual(0);
});

test('a long list shows the rows around the highlight', () => {
  expect(visibleRange(4, 3, 5)).toStrictEqual({ start: 0, end: 4 });
  expect(visibleRange(10, 0, 4)).toStrictEqual({ start: 0, end: 4 });
  // Moving down past the last row moves the window by one.
  expect(visibleRange(10, 4, 4, 0)).toStrictEqual({ start: 1, end: 5 });
  // Moving up within it leaves it where it was.
  expect(visibleRange(10, 2, 4, 1)).toStrictEqual({ start: 1, end: 5 });
  expect(visibleRange(10, 0, 4, 1)).toStrictEqual({ start: 0, end: 4 });
  // Wrapping to the end shows the end.
  expect(visibleRange(10, 9, 4, 0)).toStrictEqual({ start: 6, end: 10 });
  // A window left past a list that got shorter comes back.
  expect(visibleRange(6, 5, 4, 5)).toStrictEqual({ start: 2, end: 6 });
});

test('the list takes a quarter of the window, three rows at least', () => {
  expect(menuRowLimit(40)).toStrictEqual(10);
  expect(menuRowLimit(24)).toStrictEqual(6);
  expect(menuRowLimit(8)).toStrictEqual(3);
});

test('Tab completes the name and leaves room for what follows', () => {
  expect(completion({ name: 'echo', owner: 'agent' })).toStrictEqual('/echo ');
});

test("Enter runs chord's commands and sends the agent's", () => {
  const help = { name: 'help', owner: 'chord' } as const;
  const greet = { name: 'greet', owner: 'agent' } as const;

  // The highlighted item, whatever part of its name was typed.
  expect(submitted('/he', help)).toStrictEqual({
    type: 'chord',
    name: 'help',
    args: '',
  });
  expect(submitted('/gr', greet)).toStrictEqual({
    type: 'send',
    text: '/greet',
  });
  // With the list put away, what was typed.
  expect(submitted('/clear')).toStrictEqual({
    type: 'chord',
    name: 'clear',
    args: '',
  });
  expect(submitted('/clear ')).toStrictEqual({
    type: 'chord',
    name: 'clear',
    args: '',
  });
  expect(submitted('/exit now')).toStrictEqual({
    type: 'chord',
    name: 'exit',
    args: 'now',
  });
  // What follows the name goes with it, as `/new` names an agent.
  expect(submitted('/new  codex ')).toStrictEqual({
    type: 'chord',
    name: 'new',
    args: 'codex',
  });
  expect(submitted('/new', { name: 'new', owner: 'chord' })).toStrictEqual({
    type: 'chord',
    name: 'new',
    args: '',
  });
  expect(submitted('/model')).toStrictEqual({
    type: 'chord',
    name: 'model',
    args: '',
  });
  expect(submitted('/echo hi there ')).toStrictEqual({
    type: 'send',
    text: '/echo hi there',
  });
  expect(submitted('/unknown')).toStrictEqual({
    type: 'send',
    text: '/unknown',
  });
  expect(submitted('/clearer')).toStrictEqual({
    type: 'send',
    text: '/clearer',
  });
  expect(submitted('hello /clear')).toStrictEqual({
    type: 'send',
    text: 'hello /clear',
  });
});

const AGENTS = agentItems(
  ['fake2', 'fake', 'codex', 'mine'],
  [
    { name: 'fake', title: 'Fake', start: 'fake', from: 'npx' },
    { name: 'fake2', title: 'Fake 2', start: 'fake2', from: 'npx' },
    { name: 'codex', title: 'Codex', start: 'codex', from: 'npx' },
    { name: 'mine', title: undefined, start: 'my-agent', from: 'settings' },
  ],
);

test("/new and a space opens the list of agents, until the name's end", () => {
  expect(agentQuery('/new ')).toStrictEqual('');
  expect(agentQuery('/new co')).toStrictEqual('co');
  expect(agentQuery('/new')).toStrictEqual(undefined);
  expect(agentQuery('/new co ')).toStrictEqual(undefined);
  expect(agentQuery('/new co\nx')).toStrictEqual(undefined);
  expect(agentQuery('/model co')).toStrictEqual(undefined);
});

test('an agent is described by its title, one the settings alone define by them', () => {
  expect(AGENTS.map(({ description }) => description)).toStrictEqual([
    'from settings',
    'Fake 2',
    'Fake',
    'Codex',
  ]);
  expect(itemLabel(AGENTS[0]!)).toStrictEqual('mine');
  expect(itemLabel({ name: 'new', owner: 'chord' })).toStrictEqual('/new');
});

test('/new puts what will start on top, and marks an own CLI PATH lacks', () => {
  const items = agentItems(
    ['fake', 'claude', 'cursor', 'goose', 'mine'],
    [
      { name: 'claude', title: 'Claude', start: 'npx c', from: 'npx' },
      {
        name: 'cursor',
        title: 'Cursor',
        start: 'agent acp',
        from: 'cli',
        found: false,
      },
      {
        name: 'goose',
        title: 'goose',
        start: 'goose acp',
        from: 'cli',
        found: true,
      },
      { name: 'mine', title: undefined, start: 'mine', from: 'settings' },
    ],
  );

  expect(
    items.map(({ name, description }) => [name, description]),
  ).toStrictEqual([
    // Not listed, as --agent-command names one: by its name alone.
    ['fake', undefined],
    ['mine', 'from settings'],
    ['goose', 'goose'],
    ['claude', 'Claude'],
    ['cursor', 'Cursor · not on PATH'],
  ]);
});

test('the agent named exactly comes first', () => {
  expect(names(matchAgents(AGENTS, 'fake'))).toStrictEqual(['fake', 'fake2']);
  expect(names(matchAgents(AGENTS, ''))).toStrictEqual(names(AGENTS));
  expect(matchAgents(AGENTS, 'zz')).toStrictEqual([]);
});

test('Tab and Enter on an agent are /new with its name', () => {
  const mine = AGENTS[0]!;

  expect(completion(mine)).toStrictEqual('/new mine ');
  expect(submitted('/new mi', mine)).toStrictEqual({
    type: 'chord',
    name: 'new',
    args: 'mine',
  });
});
