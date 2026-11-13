/**
 * `/new`'s words read, whoever hosts it: `[agent] --name <name>`. The first
 * word is always an agent, never guessed as a name; the name is the rest of
 * the line after `--name`, so it may hold spaces as `/fork <name>`'s does.
 */

/** What `/new` was asked: a runtime, a name, both or neither. */
export type NewArgs =
  | { readonly agent?: string; readonly name?: string }
  /** Words `/new` cannot read, and what it says of them. */
  | { readonly problem: string };

const USAGE = '/new [agent] --name <name>';

/** Said of `--name` with nothing after it. */
export const NO_NAME = `--name needs a name · ${USAGE}`;

/** Said of any other word after the agent, `--name=x` among them. */
export const NOT_NAME = `/new takes an agent, then --name <name> · ${USAGE}`;

export function newArgs(args: string): NewArgs {
  const text = args.trim();
  const first = /^\S*/.exec(text)?.[0] ?? '';
  const agent = first === '--name' ? '' : first;
  const rest = text.slice(agent.length).trim();
  const named = agent === '' ? {} : { agent };

  if (rest === '') {
    return named;
  }

  const flag = /^--name(?:\s+|$)/.exec(rest);

  if (flag === null) {
    return { problem: NOT_NAME };
  }

  const name = rest.slice(flag[0].length).trim();

  return name === '' ? { problem: NO_NAME } : { ...named, name };
}
