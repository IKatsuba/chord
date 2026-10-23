/**
 * The slash command list: chord's own commands and the agent's, which ones a
 * typed `/name` matches, which is highlighted, and what Tab and Enter do with
 * it. The window draws it and dispatches; nothing here touches a terminal.
 */
import type { AvailableCommand } from '@agentclientprotocol/sdk';
import { Fzf } from 'fzf';
import { agentNote, type ListedAgent } from '../../agents.ts';

/** chord's own commands; the agent never hears of them. */
export type ChordCommand =
  | 'clear'
  | 'config'
  | 'context'
  | 'cost'
  | 'help'
  | 'mcp'
  | 'model'
  | 'new'
  | 'resume'
  | 'status'
  | 'team'
  | 'theme'
  | 'vim'
  | 'exit';

export interface CommandItem {
  readonly name: string;
  readonly description?: string;
  /** Whose it is: chord runs its own, an agent's goes to the agent. */
  readonly owner: 'chord' | 'agent';
  /** The command it is a name for, as an agent is `/new`'s. */
  readonly of?: ChordCommand;
  /** The word between the command and the name: `/team run bugfix`'s `run`. */
  readonly verb?: string;
}

const CHORD_COMMANDS: readonly (CommandItem & { name: ChordCommand })[] = [
  {
    name: 'clear',
    description: 'Start a new session with an empty transcript',
    owner: 'chord',
  },
  {
    name: 'config',
    description: "Change the agent's settings for this session, such as effort",
    owner: 'chord',
  },
  {
    name: 'context',
    description: "Show how full the agent's context window is",
    owner: 'chord',
  },
  {
    name: 'cost',
    description: 'Show the tokens and cost this session has spent',
    owner: 'chord',
  },
  { name: 'help', description: 'Show keyboard shortcuts', owner: 'chord' },
  {
    name: 'mcp',
    description: 'Show the MCP servers chord passed to the agent',
    owner: 'chord',
  },
  {
    name: 'model',
    description: "Switch the agent's model",
    owner: 'chord',
  },
  {
    name: 'new',
    description: 'Open a new agent beside main and go to it',
    owner: 'chord',
  },
  {
    name: 'resume',
    description: 'Resume an earlier session, here or from another directory',
    owner: 'chord',
  },
  {
    name: 'status',
    description: 'Show the agent, model, mode, session and directory',
    owner: 'chord',
  },
  {
    name: 'team',
    description: 'Describe, keep and run teams of agents',
    owner: 'chord',
  },
  {
    name: 'theme',
    description: "Choose chord's colours for a dark or light terminal",
    owner: 'chord',
  },
  {
    name: 'vim',
    description: 'Turn vim mode for the prompt on or off',
    owner: 'chord',
  },
  { name: 'exit', description: 'Quit chord', owner: 'chord' },
];

/**
 * chord's commands and the agent's, by name. An agent command named like one
 * of chord's is left out: chord's is the one that runs, so listing both would
 * offer one that cannot be picked.
 */
export function commandItems(
  agent: readonly AvailableCommand[],
): CommandItem[] {
  const ours = new Set<string>(CHORD_COMMANDS.map(({ name }) => name));
  const theirs = agent
    .filter(({ name }) => !ours.has(name))
    .map(({ name, description }): CommandItem => {
      // Each command is one row: a skill's description can run to paragraphs,
      // and its first line is the summary.
      const summary = description?.trim().split('\n')[0]?.trim();

      return {
        name,
        ...(summary ? { description: summary } : {}),
        owner: 'agent',
      };
    });

  return [...CHORD_COMMANDS, ...theirs].sort((a, b) =>
    a.name.localeCompare(b.name),
  );
}

/**
 * The name being typed when the draft is a slash and a name, nothing else;
 * undefined once it holds a space, a second line or anything before the `/`,
 * which is when the list is put away.
 */
export function commandQuery(draft: string): string | undefined {
  return /^\/(\S*)$/.exec(draft)?.[1];
}

/**
 * The agent being named after `/new ` and nothing else; undefined once it
 * holds a second word or line, when the list of agents is put away.
 */
export function agentQuery(draft: string): string | undefined {
  return /^\/new +(\S*)$/.exec(draft)?.[1];
}

/** The forms of `/team` that take a team's name next. */
export type NamedForm = 'show' | 'run' | 'stop';

/**
 * The form and the name being typed after `/team show `, `run ` or `stop `
 * and nothing else; undefined once a word follows the name, when the list
 * of names is put away. `stop` takes a run's name, which may be numbered
 * (`bugfix 2`), so its name runs on to the end of the line.
 */
export function teamQuery(
  draft: string,
): { readonly form: NamedForm; readonly name: string } | undefined {
  const match = /^\/team +(show|run|stop) +([^\n]*)$/.exec(draft);
  const form = match?.[1] as NamedForm | undefined;
  const name = match?.[2];

  if (form === undefined || name === undefined) {
    return undefined;
  }

  return form === 'stop' || !/\s/.test(name) ? { form, name } : undefined;
}

/**
 * The names `/team <form> ` offers: the saved teams' that chord can run for
 * `show` and `run`, and the open runs' for `stop`.
 */
export function teamItems(
  form: NamedForm,
  teams: readonly { readonly name: string; readonly broken: boolean }[],
  runs: readonly string[],
): CommandItem[] {
  const names =
    form === 'stop'
      ? runs
      : teams.filter(({ broken }) => !broken).map(({ name }) => name);

  return names.map((name) => ({
    name,
    owner: 'chord',
    of: 'team',
    verb: form,
  }));
}

/**
 * The agents `/new` offers, by name, as chord can start them in the window,
 * each described as `chord agents` lists it in `listed`; one it does not
 * list, as `--agent-command` names, by its name alone. Those the settings
 * files start come first, then own CLIs PATH has, then the registry's, and
 * own CLIs PATH lacks last, so what will start is on top.
 */
export function agentItems(
  names: readonly string[],
  listed: readonly ListedAgent[],
): CommandItem[] {
  const ranked = names.map((name) => {
    const agent = listed.find((each) => each.name === name);

    return {
      rank: agent === undefined ? 0 : readiness(agent),
      item: {
        name,
        ...(agent === undefined ? {} : { description: agentNote(agent) }),
        owner: 'chord',
        of: 'new',
      } satisfies CommandItem,
    };
  });

  return ranked.toSorted((a, b) => a.rank - b.rank).map(({ item }) => item);
}

function readiness({ from, found }: ListedAgent): number {
  switch (from) {
    case 'settings':
      return 0;
    case 'cli':
      return found === true ? 1 : found === false ? 3 : 2;
    default:
      return 2;
  }
}

/**
 * The agents `query` matches, as `matchCommands` matches commands, but the
 * one named exactly first: `/new fake` and Enter opens fake, not fake2.
 */
export function matchAgents(
  items: readonly CommandItem[],
  query: string,
): CommandItem[] {
  const found = matchCommands(items, query);
  const exact = found.find(({ name }) => name === query);

  return exact === undefined
    ? found
    : [exact, ...found.filter((item) => item !== exact)];
}

/**
 * The items `query` matches, best first, by fzf's scoring: the letters in
 * order, anywhere in the name, as Claude Code matches them, whatever the
 * case. Every item, in order, for an empty query.
 */
export function matchCommands(
  items: readonly CommandItem[],
  query: string,
): CommandItem[] {
  if (query === '') {
    return [...items];
  }

  return new Fzf(items, {
    selector: ({ name }) => name,
    casing: 'case-insensitive',
  })
    .find(query)
    .map(({ item }) => item);
}

/** The highlight one step up or down, wrapping round at either end. */
export function moveHighlight(
  index: number,
  count: number,
  step: 1 | -1,
): number {
  return count === 0 ? 0 : (index + step + count) % count;
}

/**
 * The rows the list shows when it has more items than `rows`: a window that
 * keeps the highlight in view and moves only when the highlight leaves it.
 * `start` is where the last window began.
 */
export function visibleRange(
  count: number,
  highlighted: number,
  rows: number,
  start = 0,
): { readonly start: number; readonly end: number } {
  if (count <= rows) {
    return { start: 0, end: count };
  }

  const from = Math.min(
    Math.max(start, highlighted - rows + 1, 0),
    highlighted,
    count - rows,
  );

  return { start: from, end: from + rows };
}

/** How many of the list's rows fit: a quarter of the window, three at least. */
export function menuRowLimit(windowRows: number): number {
  return Math.max(3, Math.floor(windowRows / 4));
}

/** How the list writes an item: a command with its slash, a name bare. */
export function itemLabel(item: CommandItem): string {
  return item.of === undefined ? `/${item.name}` : item.name;
}

/**
 * What Tab puts in the prompt: the name, and a space for what follows; for a
 * name a command takes, the command with it.
 */
export function completion(item: CommandItem): string {
  return item.of === undefined
    ? `/${item.name} `
    : `/${[item.of, item.verb, item.name].filter(Boolean).join(' ')} `;
}

/** What Enter on the prompt does. */
export type Submitted =
  | {
      readonly type: 'chord';
      readonly name: ChordCommand;
      /** What follows the name, trimmed, such as the agent `/new` names. */
      readonly args: string;
    }
  | { readonly type: 'send'; readonly text: string }
  /** The name goes into the box, as Tab puts it, for more to be typed. */
  | { readonly type: 'complete'; readonly text: string };

/**
 * Enter on `draft`, with `highlighted` the item the open list points at. A
 * highlighted item runs as itself, whatever part of its name was typed; a
 * draft that names one of chord's commands runs it, whatever follows the name;
 * anything else, an agent's command among it, goes to the agent as written.
 */
export function submitted(draft: string, highlighted?: CommandItem): Submitted {
  // A team's run needs its job after the name, which is still to be typed.
  if (highlighted?.verb === 'run') {
    return { type: 'complete', text: completion(highlighted) };
  }

  if (highlighted?.of !== undefined) {
    return {
      type: 'chord',
      name: highlighted.of,
      args:
        highlighted.verb === undefined
          ? highlighted.name
          : `${highlighted.verb} ${highlighted.name}`,
    };
  }

  const typed = /^\/(\S+)(?:\s+([\s\S]*))?$/.exec(draft.trim());
  const name = highlighted?.name ?? typed?.[1];
  const ours = CHORD_COMMANDS.find((command) => command.name === name);

  if (ours) {
    return {
      type: 'chord',
      name: ours.name,
      args: highlighted ? '' : (typed?.[2]?.trim() ?? ''),
    };
  }

  return {
    type: 'send',
    text: highlighted ? `/${highlighted.name}` : draft.trim(),
  };
}
