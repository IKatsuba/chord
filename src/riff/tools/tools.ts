/**
 * riff's host tools of this part, as libfx takes them, and how each call is
 * drawn: a verb-first title, its ACP kind and locations (CHD-485, "Tools",
 * "The session"; CHD-604b, "The rows").
 */
import type {
  PermissionOption,
  ToolCallUpdate,
  ToolCallContent,
  RequestPermissionRequest,
} from '@agentclientprotocol/sdk/unstable';
import { z } from '@zod/zod';
import type { FxAgentHostTool, FxToolResult } from 'libfx/node';
import { realpathSync } from 'node:fs';
import { basename, dirname } from 'node:path';
import type { Finder } from '../../platform/fff.ts';
import type { Drawn } from '../events.ts';
import type { RiffMode } from '../models.ts';
import { edit, EDIT_DESCRIPTION, EditInput } from './edit.ts';
import { apply, type Proposal } from './mutation.ts';
import { write, WRITE_DESCRIPTION, WriteInput } from './write.ts';
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
import { shell, SHELL_DESCRIPTION, ShellInput } from './shell.ts';
import { SEARCH_DESCRIPTION, SearchInput, searcher } from './search.ts';
import type { ReviewAction } from '../review/input.ts';
import type { AutoReview } from '../review/admission.ts';
import { reviewAction } from '../review/action.ts';
import { reviewedPermission } from '../review/permission.ts';

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
  /** Captures this execution's turn for terminal updates, including display content. */
  readonly stream?: (
    executionId: string,
  ) => (update: ToolCallUpdate) => void | Promise<void>;
  readonly showContent?: (
    executionId: string,
    content: ToolCallContent[],
  ) => void;
  /** Makes sure the window has the call, before it is asked about. */
  readonly announce?: (
    executionId: string,
    name: string,
    input: unknown,
  ) => void | Promise<void>;
  /**
   * Says a call's effect begins: allowed, or admitted without an ask, and
   * about to touch the file system. Never for a call that does not run.
   */
  readonly begin?: (
    executionId: string,
    name: string,
    input: unknown,
  ) => void | Promise<void>;
  /** The session's mode as it is now; `auto` when not given. */
  readonly mode?: () => RiffMode;
  /** What the person has allowed for the rest of the session. */
  readonly grants?: Grants;
  /** Marks a waiting permission so its refusal is not retained as tool evidence. */
  readonly permissionWaiting?: (executionId: string) => void;
  readonly review?: (
    action: ReviewAction,
    arguments_: unknown,
    signal: AbortSignal,
  ) => Promise<AutoReview>;
  /**
   * Asks the person about a call in the window: the option chosen, or
   * undefined when the ask was cancelled or nobody can answer it. Without
   * it, no one answers, and a call that asks does not run.
   */
  readonly ask?: (
    toolCall: ToolCallUpdate,
    options: PermissionOption[],
    signal: AbortSignal,
    metadata?: RequestPermissionRequest['_meta'],
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
  readonly writes?: boolean;
  readonly prepare?: (input: T, signal: AbortSignal) => Promise<Proposal>;
  readonly reach: (input: T, proposal?: Proposal) => Promise<Reach | undefined>;
  readonly run: (
    input: T,
    reach: Reach | undefined,
    signal: AbortSignal,
    executionId: string,
    proposal?: Proposal,
  ) => Promise<string | FxToolResult>;
}

/** Throws unless the call may run: granted, admitted by the mode, or allowed. */
async function permit(
  session: ToolSession,
  toolCallId: string,
  name: string,
  input: unknown,
  reach: Reach | undefined,
  signal: AbortSignal,
  proposal?: Proposal,
): Promise<void> {
  const { directory, grants = new Set() } = session;
  const mode = session.mode?.() ?? 'auto';

  if (reach === undefined || !asks(mode, reach, directory, grants)) {
    return;
  }

  await session.announce?.(toolCallId, name, input);

  session.permissionWaiting?.(toolCallId);

  const toolCall: ToolCallUpdate = {
    toolCallId,
    ...drawn(directory, name, input, 'real' in reach ? reach.real : undefined),
    // A read's title names its file already; list and search keep the
    // directory "this directory" means.
    ...('real' in reach ? { locations: [] } : {}),
    ...(proposal === undefined ? {} : { content: proposal.content }),
  };

  if (mode === 'auto') {
    const action = reviewAction(reach, directory, proposal);
    const outcome =
      action === undefined
        ? {
            outcome: 'unavailable' as const,
            reason: 'The pending action could not be inspected.',
          }
        : ((await session.review?.(action, input, signal)) ?? {
            outcome: 'unavailable' as const,
            reason: 'The safety reviewer is unavailable.',
          });

    signal.throwIfAborted();

    // A switch during review drops its verdict and asks under the new mode.
    if ((session.mode?.() ?? 'auto') === 'auto') {
      if (outcome.outcome !== 'clear') {
        await reviewedPermission(session, toolCall, outcome, signal);
      }

      return;
    }
  }

  const chosen = await session.ask?.(
    toolCall,
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
    idempotent: !spec.writes,
    writes: spec.writes ?? false,
    // Input the schema refuses is a failed call, not a throw out of execute.
    execute: (input: unknown, { signal, executionId }) =>
      Promise.try(async () => {
        signal.throwIfAborted();

        const call = parsed(spec.schema, input);
        const proposal = await spec.prepare?.(call, signal);
        const reach = await spec.reach(call, proposal);

        await permit(
          session,
          executionId,
          spec.name,
          input,
          reach,
          signal,
          proposal,
        );
        signal.throwIfAborted();
        await session.begin?.(executionId, spec.name, input);
        signal.throwIfAborted();

        return await spec.run(call, reach, signal, executionId, proposal);
      }),
  };
}

/** File mutation metadata and the shared permission/effect ordering. */
function fileTool<T>(
  session: ToolSession,
  name: 'edit' | 'write',
  description: string,
  schema: z.ZodType<T>,
  prepare: (input: T, signal: AbortSignal) => Promise<Proposal>,
): FxAgentHostTool {
  return hostTool(session, {
    name,
    description,
    schema,
    prepare,
    writes: true,
    reach: (_input, proposal) =>
      Promise.resolve(
        proposal === undefined
          ? undefined
          : { tool: name, real: proposal.real },
      ),
    run: async (_input, _reach, signal, id, proposal) => {
      if (proposal === undefined) {
        throw new Error('mutation reached no file');
      }

      await apply(proposal, signal);
      session.showContent?.(id, proposal.content);

      return `Updated ${shown(session.directory, proposal.real)}\n${proposal.patch}`;
    },
  });
}

/** riff's host tools over `session`, each asking as its mode says. */
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
    fileTool(session, 'edit', EDIT_DESCRIPTION, EditInput, (input, signal) =>
      edit(resolveIn(directory, input.path), input, signal),
    ),
    fileTool(session, 'write', WRITE_DESCRIPTION, WriteInput, (input, signal) =>
      write(resolveIn(directory, input.path), input, signal),
    ),
    hostTool(session, {
      name: 'shell',
      description: SHELL_DESCRIPTION,
      schema: ShellInput,
      writes: true,
      reach: (input) =>
        Promise.resolve({ tool: 'shell', command: input.command }),
      run: (input, _reach, signal, id) => {
        session.showContent?.(id, [{ type: 'terminal', terminalId: id }]);

        const stream =
          session.stream?.(id) ??
          ((update: ToolCallUpdate) => {
            if (update.content !== undefined && update.content !== null) {
              session.showContent?.(id, update.content);
            }
          });

        return shell(directory, input, signal, id, stream);
      },
    }),
  ];
}

/**
 * `path`'s real path as it is now, or undefined when it has none; for a
 * call's row, drawn as its call starts, before the read decides anything.
 */
function realOrNone(path: string): string | undefined {
  try {
    return realpathSync(path);
  } catch {
    return undefined;
  }
}

/** The range a read names, as `:10-40`, or nothing for the whole file. */
function range({ offset, limit }: ReadInput): string {
  if (offset === undefined && limit === undefined) {
    return '';
  }

  const first = offset ?? 1;

  if (limit === undefined || limit === 1) {
    return `:${first}`;
  }

  return `:${first}-${first + limit - 1}`;
}

/**
 * How `name`'s call with `input` is drawn in `directory`; a tool riff does
 * not know, or an input it cannot read, by its name alone. A read names the
 * file it reaches, `real` or its real path now, when that is not the path
 * asked for.
 */
export function drawn(
  directory: string,
  name: string,
  input: unknown,
  real?: string,
): Drawn {
  switch (name) {
    case 'read': {
      const read = ReadInput.safeParse(input);

      if (!read.success) {
        return { title: 'Read', kind: 'read' };
      }

      const path = resolveIn(directory, read.data.path);
      const target = real ?? realOrNone(path);
      // Through a link, the title says where it points, as option 2 does.
      const through =
        target === undefined || target === path
          ? ''
          : ` → ${shown(directory, target)}`;

      return {
        title: `Read ${shown(directory, path)}${range(read.data)}${through}`,
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
    case 'edit':
    case 'write': {
      const mutation = (name === 'edit' ? EditInput : WriteInput).safeParse(
        input,
      );
      const verb = name === 'edit' ? 'Update' : 'Write';

      if (!mutation.success) {
        return { title: verb, kind: 'edit' };
      }

      const path = resolveIn(directory, mutation.data.path);
      const target =
        real ??
        realOrNone(path) ??
        realOrNone(dirname(path))?.concat(`/${basename(path)}`);
      const through =
        target === undefined || target === path
          ? ''
          : ` → ${shown(directory, target)}`;

      return {
        title: `${verb} ${shown(directory, path)}${through}`,
        kind: 'edit',
        locations: [{ path: target ?? path }],
      };
    }
    case 'shell': {
      const command = ShellInput.safeParse(input);

      return {
        title: command.success ? `Bash ${command.data.command}` : 'Bash',
        kind: 'execute',
        locations: [{ path: directory }],
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
