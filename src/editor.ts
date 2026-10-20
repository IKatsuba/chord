/**
 * ctrl+g: the draft in the user's editor and back. The file and the editor's
 * run are @inquirer/external-editor's; the command, the file's last newline
 * and what an editor's end means are here.
 */
import { ExternalEditor } from '@inquirer/external-editor';
import { statSync } from 'node:fs';
import process from 'node:process';

/** How an editor's run ended. */
export type EditorEnd =
  /** It exited 0, and this is the file as it left it, back as a draft. */
  | { readonly text: string }
  /** It did not end well; the draft stays as it was. */
  | { readonly failed: string };

export interface EditorOptions {
  /** Reads an environment variable; this process's by default. */
  readonly env?: (name: string) => string | undefined;
  /** The shell and the flag before the command; the user's own by default. */
  readonly shell?: readonly [string, ...string[]];
}

const WINDOWS = process.platform === 'win32';

/**
 * The editor as the user set it: `$VISUAL`, then `$EDITOR`, then vi, the one
 * every Unix has, or Windows's notepad. An empty variable counts as unset, as
 * git reads them.
 */
export function editorCommand(
  env: (name: string) => string | undefined,
): string {
  return (
    env('VISUAL')?.trim() ||
    env('EDITOR')?.trim() ||
    (WINDOWS ? 'notepad' : 'vi')
  );
}

/** The command's program without its path or flags, for the status line. */
export function editorName(command: string): string {
  const program = command.trim().split(/\s+/)[0] ?? command;

  return program.split(/[\\/]/).pop() || program;
}

/**
 * The draft as the file holds it: a text file's lines end with a newline,
 * so the editor neither adds one nor complains that it is missing.
 */
export function draftFile(draft: string): string {
  return draft === '' ? '' : `${draft}\n`;
}

/** The file back as a draft: the last line's newline is the file's, not the draft's. */
export function fileDraft(text: string): string {
  return text.replace(/\r?\n$/, '');
}

/** The signals an editor is most often stopped by, by number. */
const SIGNALS: Readonly<Record<number, string>> = {
  1: 'SIGHUP',
  2: 'SIGINT',
  3: 'SIGQUIT',
  6: 'SIGABRT',
  9: 'SIGKILL',
  15: 'SIGTERM',
};

/** What the status line says of an editor that did not end well. */
export function editorFailure(name: string, code: number): string {
  // 127 is the shell's word for a command it could not find, and 128 + N
  // its word for a command signal N stopped.
  if (code === 127) {
    return `${name} was not found; the draft is unchanged`;
  }

  if (code > 128 && code <= 128 + 64) {
    const signal = SIGNALS[code - 128] ?? `signal ${code - 128}`;

    return `${name} was stopped by ${signal}; the draft is unchanged`;
  }

  return `${name} exited with code ${code}; the draft is unchanged`;
}

/**
 * Stands between the library and the user's shell. The library reads an
 * exit by signal as 0, so a shell or editor that was killed would hand back
 * a half-written file as the draft; run as a child of this one, it ends as
 * 128 + N, which no editor's success is. `exit` after the command keeps sh
 * from exec'ing into it and being killed in its place.
 */
const GUARD = '"$@"; exit $?';

function isFile(path: string): boolean {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

/**
 * Opens `draft` in the user's editor and waits for it to exit. The terminal
 * must already be the editor's: the caller suspends the window around this.
 */
export async function editInEditor(
  draft: string,
  options: EditorOptions = {},
): Promise<EditorEnd> {
  const env = options.env ?? ((name) => process.env[name]);
  const command = editorCommand(env);
  const name = editorName(command);
  const editor = new ExternalEditor(draftFile(draft), {
    prefix: 'chord-prompt-',
    // Editors colour and wrap a `.md` file as prose.
    postfix: '.md',
  });

  // Through the user's shell, as git runs `$EDITOR`, so a command with
  // quotes, variables or `~` in it means what it does at the prompt. The
  // library appends the file, which the shell hands on as `$1`.
  // POSIX sh's GUARD runs that shell. On Windows, where cmd.exe has no
  // `$1`, the library splits the command and starts it itself.
  if (options.shell || !WINDOWS) {
    const [program, ...flags] = options.shell ?? [
      env('SHELL') || '/bin/sh',
      '-c',
    ];

    // Behind GUARD a missing shell would read as a missing editor.
    if (program.includes('/') && !isFile(program)) {
      return { failed: `${name} did not start: ${program} was not found` };
    }

    editor.editor = {
      bin: '/bin/sh',
      args: [
        '-c',
        GUARD,
        'chord',
        program,
        ...flags,
        `${command} "$1"`,
        'chord',
      ],
    };
  }

  try {
    const text = await editor.runAsync();

    return editor.lastExitStatus === 0
      ? { text: fileDraft(text) }
      : { failed: editorFailure(name, editor.lastExitStatus) };
  } catch (error) {
    return {
      failed: `${name} did not start: ${
        error instanceof Error ? error.message : String(error)
      }`,
    };
  }
}
