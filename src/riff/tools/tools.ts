/**
 * riff's host tools of this part, as libfx takes them, and how each call is
 * drawn: a verb-first title, its ACP kind and locations (CHD-485, "Tools",
 * "The session"; CHD-604b, "The rows").
 */
import type {
  PermissionOption,
  ToolCallUpdate,
} from '@agentclientprotocol/sdk/unstable';
import { z } from '@zod/zod';
import type { FxAgentHostTool } from 'libfx/node';
import type { Finder } from '../../platform/fff.ts';
import type { Drawn } from '../events.ts';
import type { RiffMode } from '../models.ts';
import { list, LIST_DESCRIPTION, ListInput } from './list.ts';
import { realOf, resolveIn, shown } from './paths.ts';
import {
  ALLOW,
  ALLOW_SESSION,
  asks,
  DENY,
  type Grants,
  grantKey,
  permissionOptions,
  type Reach,
} from './permission.ts';
import { READ_DESCRIPTION, ReadInput, readLines } from './read.ts';
import { SEARCH_DESCRIPTION, SearchInput, searcher } from './search.ts';

/** The session a tool works in. */
export interface ToolSession {
  /** The session's directory, as its real path. */
  readonly directory: string;
  readonly finder: Finder;
  /**
   * Keeps what the window shows of a call in place of what the model reads,
   * by the call's id; nothing kept, the window shows the model's.
   */
  readonly show?: (executionId: string, shown: string) => void;
  /** The session's mode as it is now; `auto` when not given. */
  readonly mode?: () => RiffMode;
  /** What the person has allowed for the rest of the session. */
  readonly grants?: Grants;
  /**
   * Asks the person about a call in the window: the option chosen, or
   * undefined when the ask was cancelled or nobody can answer it. Without
   * it, no one answers, and a call that asks does not run.
   */
  readonly ask?: (
    toolCall: ToolCallUpdate,
    options: PermissionOption[],
    signal: AbortSignal,
  ) => Promise<string | undefined>;
}

function parsed<T>(schema: z.ZodType<T>, input: unknown): T {
  const result = schema.safeParse(input);

  if (!result.success) {
    throw new Error(`invalid input: ${z.prettifyError(result.error)}`);
  }

  return result.data;
}

/** One of riff's tools: what a call reaches, and how it runs. */
interface ToolSpec<T> {
  readonly name: string;
  readonly description: string;
  readonly schema: z.ZodType<T>;
  /** What the call reaches, or undefined when it reaches nothing to ask about. */
  readonly reach: (input: T) => Promise<Reach | undefined>;
  readonly run: (
    input: T,
    reach: Reach | undefined,
    signal: AbortSignal,
    executionId: string,
  ) => Promise<string>;
}

/** Throws unless the call may run: granted, admitted by the mode, or allowed. */
async function permit(
  session: ToolSession,
  toolCallId: string,
  name: string,
  input: unknown,
  reach: Reach | undefined,
  signal: AbortSignal,
): Promise<void> {
  const { directory, grants = new Set() } = session;
  const mode = session.mode?.() ?? 'auto';

  if (reach === undefined || !asks(mode, reach, directory, grants)) {
    return;
  }

  const chosen = await session.ask?.(
    { toolCallId, ...drawn(directory, name, input) },
    permissionOptions(reach, directory),
    signal,
  );

  signal.throwIfAborted();

  if (chosen === ALLOW_SESSION) {
    grants.add(grantKey(reach, directory));
  }

  if (chosen === ALLOW || chosen === ALLOW_SESSION) {
    return;
  }

  throw new Error(
    chosen === DENY
      ? 'The person denied this call.'
      : 'Nobody answered the permission ask; the call did not run.',
  );
}

function hostTool<T>(session: ToolSession, spec: ToolSpec<T>): FxAgentHostTool {
  return {
    name: spec.name,
    description: spec.description,
    inputSchema: z.toJSONSchema(spec.schema) as FxAgentHostTool['inputSchema'],
    idempotent: true,
    writes: false,
    // Input the schema refuses is a failed call, not a throw out of execute.
    execute: (input: unknown, { signal, executionId }) =>
      Promise.try(async () => {
        const call = parsed(spec.schema, input);
        const reach = await spec.reach(call);

        await permit(session, executionId, spec.name, input, reach, signal);

        return await spec.run(call, reach, signal, executionId);
      }),
  };
}

/** read, list and search over `session`, each asking as its mode says. */
export function riffTools(session: ToolSession): FxAgentHostTool[] {
  const { directory, finder } = session;
  const search = searcher(finder);

  return [
    hostTool(session, {
      name: 'read',
      description: READ_DESCRIPTION,
      schema: ReadInput,
      // A path with no real path is refused here, before any ask: nothing
      // is read that the mode and the person did not see.
      reach: async (input) => {
        const path = resolveIn(directory, input.path);

        return {
          tool: 'read',
          real: await realOf(path, shown(directory, path)),
        };
      },
      // The file read is the one asked about: a path whose real path has
      // changed since is refused.
      run: (input, reach, signal, id) => {
        if (reach?.tool !== 'read') {
          throw new Error('read reached no file');
        }

        return readLines(reach.real, input, signal, {
          label: shown(directory, resolveIn(directory, input.path)),
          onShown: (text: string) => session.show?.(id, text),
          exact: true,
        });
      },
    }),
    hostTool(session, {
      name: 'list',
      description: LIST_DESCRIPTION,
      schema: ListInput,
      reach: () => Promise.resolve({ tool: 'list' }),
      run: (input, _reach, signal) => list(finder, input, signal),
    }),
    hostTool(session, {
      name: 'search',
      description: SEARCH_DESCRIPTION,
      schema: SearchInput,
      reach: () => Promise.resolve({ tool: 'search' }),
      run: (input, _reach, signal) => search(input, signal),
    }),
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
        // An empty pattern lists from the directory itself.
        title: listed.success ? `List ${listed.data.pattern || '.'}` : 'List',
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
