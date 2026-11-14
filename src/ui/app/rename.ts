/**
 * What `/rename` says under the command as typed (CHD-629), by the state the
 * session it acts on is in: the window draws it and dispatches.
 */
import stripAnsi from 'strip-ansi';
import { titleLine } from '../../session/sessions.ts';

/** An agent's string as a note draws it: its escapes gone, on one line. */
function clean(text: string): string {
  return titleLine(stripAnsi(text));
}

/** Where `/rename` acts: a session it may rename, or why not. */
export type RenameTarget<C> =
  | {
      readonly kind: 'open';
      readonly key: number;
      /** Its runtime, as a note names the agent. */
      readonly agent: string;
      readonly conversation: C;
    }
  | { readonly kind: 'starting' }
  | { readonly kind: 'exited'; readonly name: string }
  | { readonly kind: 'task'; readonly name: string };

/** A note's words and whether it reads as an error. */
export interface RenameNote {
  readonly text: string;
  readonly failed: boolean;
}

/** The note for a target `/rename` refuses; none for one it renames. */
export function refusedNote<C>(
  target: RenameTarget<C>,
): RenameNote | undefined {
  switch (target.kind) {
    case 'starting':
      return {
        text: 'The session is not open yet; rename it once it is.',
        failed: true,
      };
    case 'exited':
      return {
        text: `${target.name} has exited; its session cannot be renamed.`,
        failed: true,
      };
    case 'task':
      return {
        text: `${target.name} is a task; it keeps the title it was given.`,
        failed: true,
      };
    case 'open':
      return undefined;
  }
}

/** The note for `/rename` with no title: how, and the title it has. */
export function unnamedNote(title: string | undefined): RenameNote {
  return {
    text: `Name the session: /rename <title>${
      title === undefined ? '' : `. Now: ${clean(title)}`
    }`,
    failed: false,
  };
}

/** The note while the agent has the rename. */
export function renamingNote(title: string): RenameNote {
  return { text: `Renaming to ${clean(title)}…`, failed: false };
}

/**
 * The note once the session is renamed: by the agent, to the title it
 * answered, or in chord only, for an agent that takes no title.
 */
export function renamedNote(
  title: string,
  agent: string,
  taken: boolean,
): RenameNote {
  return {
    text: taken
      ? `Renamed to ${clean(title)}`
      : `Renamed to ${clean(title)} in chord only: ${agent} takes no title, and its own may replace it`,
    failed: false,
  };
}

/** The note for a rename the agent refused, in its own words (Q1 a). */
export function refusedByAgentNote(agent: string, message: string): RenameNote {
  return {
    text: `Could not rename: ${agent} refused it: ${clean(message)}`,
    failed: true,
  };
}
