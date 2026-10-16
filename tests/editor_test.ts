import { execFile } from 'node:child_process';
import { expect, test } from 'bun:test';
import process from 'node:process';
import {
  draftFile,
  editInEditor,
  editorCommand,
  editorFailure,
  editorName,
  fileDraft,
} from '../src/editor.ts';

/** An environment holding only `vars`. */
function envOf(vars: Record<string, string>) {
  return (name: string) => vars[name];
}

/**
 * `editInEditor` with `editor` as `$EDITOR`, run by sh: a scripted editor,
 * never a real one.
 */
function edit(draft: string, editor: string) {
  return editInEditor(draft, {
    env: envOf({ EDITOR: editor }),
    shell: ['/bin/sh', '-c'],
  });
}

test('the editor is $VISUAL, then $EDITOR, then vi', () => {
  expect(
    editorCommand(envOf({ VISUAL: 'nvim', EDITOR: 'nano' })),
  ).toStrictEqual('nvim');
  expect(editorCommand(envOf({ EDITOR: 'nano' }))).toStrictEqual('nano');
  // An empty variable counts as unset, as git reads them.
  expect(editorCommand(envOf({ VISUAL: ' ', EDITOR: 'nano' }))).toStrictEqual(
    'nano',
  );
  expect(editorCommand(envOf({}))).toStrictEqual('vi');
});

test('the status line names the program, not its path or flags', () => {
  expect(editorName('vi')).toStrictEqual('vi');
  expect(editorName('/usr/local/bin/code --wait')).toStrictEqual('code');
  expect(editorFailure('code', 1)).toStrictEqual(
    'code exited with code 1; the draft is unchanged',
  );
  expect(editorFailure('nvimm', 127)).toStrictEqual(
    'nvimm was not found; the draft is unchanged',
  );
});

test('the file ends with a newline the draft gets back without', () => {
  expect(draftFile('one\ntwo')).toStrictEqual('one\ntwo\n');
  expect(draftFile('')).toStrictEqual('');
  expect(fileDraft('one\ntwo\n')).toStrictEqual('one\ntwo');
  expect(fileDraft('one\r\n')).toStrictEqual('one');
  // Only the file's own newline goes; one the draft had stays.
  expect(fileDraft(draftFile('one\n'))).toStrictEqual('one\n');
  expect(fileDraft('no newline')).toStrictEqual('no newline');
});

/**
 * `edit` in a Bun of its own, whose stderr is kept: the shells the editor
 * runs under have the terminal's, as the editor library gives it them, and
 * say there what became of a command they ran.
 */
function editAside(
  draft: string,
  editor: string,
): Promise<{ end: unknown; stderr: string }> {
  const script = `
    const { editInEditor } = await import(${JSON.stringify(
      new URL('../src/editor.ts', import.meta.url).href,
    )});
    const end = await editInEditor(process.env.CHORD_TEST_DRAFT, {
      env: (name) =>
        name === 'EDITOR' ? process.env.CHORD_TEST_EDITOR : undefined,
      shell: ['/bin/sh', '-c'],
    });

    process.stdout.write('\\n' + JSON.stringify(end));
  `;

  return new Promise((resolve, reject) => {
    execFile(
      process.execPath,
      ['-e', script],
      {
        env: {
          ...process.env,
          CHORD_TEST_DRAFT: draft,
          CHORD_TEST_EDITOR: editor,
        },
      },
      (error, stdout, stderr) => {
        try {
          if (error) {
            throw error;
          }

          resolve({
            end: JSON.parse(stdout.split('\n').at(-1) ?? '') as unknown,
            stderr,
          });
        } catch (failed) {
          reject(failed as Error);
        }
      },
    );
  });
}

test('a draft comes back from an editor that leaves it as it was', async () => {
  const draft = 'first line\n  indented second\n\nunicode: héllo, привет, ✻';

  expect(await edit(draft, 'true')).toStrictEqual({ text: draft });
  expect(await edit('', 'true')).toStrictEqual({ text: '' });
});

test("the editor's edit comes back as the draft", async () => {
  expect(await edit('the draft', "printf 'appended\\n' >>")).toStrictEqual({
    text: 'the draft\nappended',
  });
  // The file is the editor's last argument, whatever the command holds.
  expect(
    await edit('x', 'sh -c \'printf "replaced\\n" > "$1"\' editor'),
  ).toStrictEqual({ text: 'replaced' });
});

test('an editor that fails says so and gives nothing back', async () => {
  expect(
    await edit('kept', 'sh -c \'echo y >> "$1"; exit 3\' ed'),
  ).toStrictEqual({
    failed: 'sh exited with code 3; the draft is unchanged',
  });

  const missing = await editAside('kept', 'chord-no-such-editor');

  expect(missing.end).toStrictEqual({
    failed: 'chord-no-such-editor was not found; the draft is unchanged',
  });
  // bash's `command not found`, dash's `not found`.
  expect(missing.stderr).toMatch(/chord-no-such-editor: (command )?not found/);
});

test('an editor or shell killed by a signal is a failure, not an edit', async () => {
  // The shell that runs the editor is killed after the file was written,
  // and chord's own shell around it says so.
  const terminated = await editAside(
    'kept',
    'printf changed > "$1"; kill -TERM $$ #',
  );

  expect(terminated.end).toStrictEqual({
    failed: 'printf was stopped by SIGTERM; the draft is unchanged',
  });
  expect(terminated.stderr).toContain('Terminated');

  // A program the shell started is killed.
  const killed = await editAside(
    'kept',
    'sh -c \'printf changed > "$1"; kill -KILL $$\' ed',
  );

  expect(killed.end).toStrictEqual({
    failed: 'sh was stopped by SIGKILL; the draft is unchanged',
  });
  expect(killed.stderr).toContain('Killed');
});

test('the status line names the signal that stopped an editor', () => {
  expect(editorFailure('vi', 128 + 1)).toStrictEqual(
    'vi was stopped by SIGHUP; the draft is unchanged',
  );
  expect(editorFailure('vi', 128 + 10)).toStrictEqual(
    'vi was stopped by signal 10; the draft is unchanged',
  );
  expect(editorFailure('vi', 200)).toStrictEqual(
    'vi exited with code 200; the draft is unchanged',
  );
});

test('a shell that does not start is a failure, not a throw', async () => {
  const end = await editInEditor('kept', {
    env: envOf({ EDITOR: 'true' }),
    shell: ['/no/such/shell', '-c'],
  });

  expect('failed' in end).toStrictEqual(true);
  expect('failed' in end ? end.failed : '').toContain(
    'true did not start: /no/such/shell was not found',
  );
});
