// ctrl+g's editor, from the original's tests/editor_test.ts: scripted
// editors run by sh, never a real one.
import 'dart:async';
import 'dart:io';

import 'package:chord/editor.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

/// A terminal that runs the editor as the framework's does, through sh,
/// with no window to suspend.
class ShellTerminal extends Terminal {
  final commands = <String>[];

  @override
  Size get size => const Size(80, 24);
  @override
  Stream<String> get input => const Stream.empty();
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  void write(String data) {}
  @override
  void enter() {}
  @override
  Future<void> leave() async {}

  @override
  Future<int> runEditor(
    String path, {
    String? command,
    String? workingDirectory,
  }) async {
    commands.add(command!);
    final run = await Process.run('/bin/sh', [
      '-c',
      '$command "\$1"',
      'editor',
      path,
    ]);
    return run.exitCode;
  }
}

String? Function(String) envOf(Map<String, String> vars) =>
    (name) => vars[name];

Future<EditorEnd> edit(String draft, String editor) => editInEditor(
  draft,
  terminal: ShellTerminal(),
  env: envOf({'EDITOR': editor, 'SHELL': '/bin/sh'}),
);

void main() {
  test(r'the editor is $VISUAL, then $EDITOR, then vi', () {
    expect(editorCommand(envOf({'VISUAL': 'nvim', 'EDITOR': 'nano'})), 'nvim');
    expect(editorCommand(envOf({'EDITOR': 'nano'})), 'nano');
    // An empty variable counts as unset, as git reads them.
    expect(editorCommand(envOf({'VISUAL': ' ', 'EDITOR': 'nano'})), 'nano');
    expect(editorCommand(envOf({})), 'vi');
  });

  test('the status line names the program, not its path or flags', () {
    expect(editorName('vi'), 'vi');
    expect(editorName('/usr/local/bin/code --wait'), 'code');
    expect(
      editorFailure('code', 1),
      'code exited with code 1; the draft is unchanged',
    );
    expect(
      editorFailure('nvimm', 127),
      'nvimm was not found; the draft is unchanged',
    );
    expect(
      editorFailure('vi', 143),
      'vi was stopped by SIGTERM; the draft is unchanged',
    );
    // Dart reports a process a signal stopped by its negative number.
    expect(
      editorFailure('vi', -9),
      'vi was stopped by SIGKILL; the draft is unchanged',
    );
  });

  test('the file ends with a newline the draft gets back without', () {
    expect(draftFile('one\ntwo'), 'one\ntwo\n');
    expect(draftFile(''), '');
    expect(fileDraft('one\ntwo\n'), 'one\ntwo');
    expect(fileDraft('one\r\n'), 'one');
    // Only the file's own newline goes; one the draft had stays.
    expect(fileDraft(draftFile('one\n')), 'one\n');
    expect(fileDraft('no newline'), 'no newline');
  });

  test('a draft comes back from an editor that leaves it as it was', () async {
    const draft = 'first line\n  indented second\n\nunicode: héllo, привет, ✻';
    expect(((await edit(draft, 'true')) as EditorText).text, draft);
    expect(((await edit('', 'true')) as EditorText).text, '');
  });

  test("the editor's edit comes back as the draft", () async {
    expect(
      ((await edit('the draft', r"printf 'appended\n' >>")) as EditorText).text,
      'the draft\nappended',
    );
    // The file is the editor's last argument, whatever the command holds.
    expect(
      ((await edit('x', r'''sh -c 'printf "replaced\n" > "$1"' editor'''))
              as EditorText)
          .text,
      'replaced',
    );
  });

  test('an editor that fails says so and gives nothing back', () async {
    expect(
      ((await edit('kept', r'''sh -c 'echo y >> "$1"; exit 3' ed'''))
              as EditorFailed)
          .message,
      'sh exited with code 3; the draft is unchanged',
    );
    expect(
      ((await edit('kept', 'chord-no-such-editor')) as EditorFailed).message,
      'chord-no-such-editor was not found; the draft is unchanged',
    );
  });

  test('an editor killed by a signal is a failure, not an edit', () async {
    expect(
      ((await edit('kept', r'''sh -c 'echo y >> "$1"; kill -TERM $$' ed'''))
              as EditorFailed)
          .message,
      'sh was stopped by SIGTERM; the draft is unchanged',
    );
  });

  test('a missing shell is said as such, not as a missing editor', () async {
    final end = await editInEditor(
      'kept',
      terminal: ShellTerminal(),
      env: envOf({'EDITOR': 'vi', 'SHELL': '/no/such/shell'}),
    );
    expect(
      (end as EditorFailed).message,
      'vi did not start: /no/such/shell was not found',
    );
  });

  test('no file is left behind', () async {
    final before = Directory.systemTemp
        .listSync()
        .where((e) => e.path.contains('chord-prompt-'))
        .length;
    await edit('kept', 'true');
    await edit('kept', 'false');
    expect(
      Directory.systemTemp
          .listSync()
          .where((e) => e.path.contains('chord-prompt-'))
          .length,
      before,
    );
  });
}
