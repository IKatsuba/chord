/**
 * riff's host tools of this part, as libfx takes them, and how each call is
 * drawn: a verb-first title, its ACP kind and locations (CHD-485, "Tools",
 * "The session"; CHD-604b, "The rows").
 */
import { z } from '@zod/zod';
import type { FxAgentHostTool } from 'libfx/node';
import type { Finder } from '../../platform/fff.ts';
import type { Drawn } from '../events.ts';
import { list, LIST_DESCRIPTION, ListInput } from './list.ts';
import { resolveIn, shown } from './paths.ts';
import { READ_DESCRIPTION, ReadInput, readLines } from './read.ts';
import { SEARCH_DESCRIPTION, SearchInput, searcher } from './search.ts';

/** The session a tool works in. */
export interface ToolSession {
  /** The session's directory, as its real path. */
  readonly directory: string;
  readonly finder: Finder;
}

function parsed<T>(schema: z.ZodType<T>, input: unknown): T {
  const result = schema.safeParse(input);

  if (!result.success) {
    throw new Error(`invalid input: ${z.prettifyError(result.error)}`);
  }

  return result.data;
}

function hostTool<T>(
  name: string,
  description: string,
  schema: z.ZodType<T>,
  run: (input: T, signal: AbortSignal) => Promise<string>,
): FxAgentHostTool {
  return {
    name,
    description,
    inputSchema: z.toJSONSchema(schema) as FxAgentHostTool['inputSchema'],
    idempotent: true,
    writes: false,
    // Input the schema refuses is a failed call, not a throw out of execute.
    execute: (input: unknown, { signal }) =>
      Promise.try(() => run(parsed(schema, input), signal)),
  };
}

/** read, list and search over `session`. */
export function riffTools(session: ToolSession): FxAgentHostTool[] {
  const search = searcher(session.finder);

  return [
    hostTool('read', READ_DESCRIPTION, ReadInput, (input, signal) =>
      readLines(resolveIn(session.directory, input.path), input, signal),
    ),
    hostTool('list', LIST_DESCRIPTION, ListInput, (input, signal) =>
      list(session.finder, input, signal),
    ),
    hostTool('search', SEARCH_DESCRIPTION, SearchInput, search),
  ];
}

/** The range a read names, as `:10-40`, or nothing for the whole file. */
function range({ offset, limit }: ReadInput): string {
  if (offset === undefined && limit === undefined) {
    return '';
  }

  const first = offset ?? 1;

  return limit === undefined ? `:${first}` : `:${first}-${first + limit - 1}`;
}

/**
 * How `name`'s call with `input` is drawn in `directory`; a tool riff does
 * not know, or an input it cannot read, by its name alone.
 */
export function drawn(directory: string, name: string, input: unknown): Drawn {
  switch (name) {
    case 'read': {
      const read = ReadInput.safeParse(input);

      if (!read.success) {
        return { title: 'Read', kind: 'read' };
      }

      const path = resolveIn(directory, read.data.path);

      return {
        title: `Read ${shown(directory, path)}${range(read.data)}`,
        kind: 'read',
        locations: [
          {
            path,
            ...(read.data.offset === undefined
              ? {}
              : { line: read.data.offset }),
          },
        ],
      };
    }
    case 'list': {
      const listed = ListInput.safeParse(input);

      return {
        title: listed.success ? `List ${listed.data.pattern}`.trim() : 'List',
        kind: 'search',
        locations: [{ path: directory }],
      };
    }
    case 'search': {
      const searched = SearchInput.safeParse(input);

      return {
        title: searched.success ? `Search ${searched.data.query}` : 'Search',
        kind: 'search',
        locations: [{ path: directory }],
      };
    }
    default:
      return { title: name, kind: 'other' };
  }
}
