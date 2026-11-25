// ctrl+g: the draft in the user's editor and back, as the original's
// src/editor.ts. The editor's run is the framework terminal's runEditor;
// the command, the file's last newline and what an editor's end means are
// here.
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';
import 'package:path/path.dart' as p;

/// How an editor's run ended.
sealed class EditorEnd {
  const EditorEnd();
}

/// It exited 0, and this is the file as it left it, back as a draft.
final class EditorText extends EditorEnd {
  const EditorText(this.text);
  final String text;
}

/// It did not end well; the draft stays as it was.
final class EditorFailed extends EditorEnd {
  const EditorFailed(this.message);
  final String message;
}

/// The editor as the user set it: `$VISUAL`, then `$EDITOR`, then vi. An
/// empty variable counts as unset, as git reads them.
String editorCommand(String? Function(String) env) {
  String? set(String name) {
    final value = env(name)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  return set('VISUAL') ?? set('EDITOR') ?? 'vi';
}

/// The command's program without its path or flags, for the status line.
String editorName(String command) {
  final program = command.trim().split(RegExp(r'\s+')).first;
  final name = program.split(RegExp(r'[\\/]')).last;
  return name.isEmpty ? program : name;
}

/// The draft as the file holds it: a text file's lines end with a newline,
/// so the editor neither adds one nor complains that it is missing.
String draftFile(String draft) => draft.isEmpty ? '' : '$draft\n';

/// The file back as a draft: the last line's newline is the file's.
String fileDraft(String text) => text.replaceFirst(RegExp(r'\r?\n$'), '');

/// The signals an editor is most often stopped by, by number.
const _signals = {
  1: 'SIGHUP',
  2: 'SIGINT',
  3: 'SIGQUIT',
  6: 'SIGABRT',
  9: 'SIGKILL',
  15: 'SIGTERM',
};

/// What the status line says of an editor that did not end well. A
/// negative [code] is a signal's, as Dart reports a process it stopped.
String editorFailure(String name, int code) {
  // 127 is the shell's word for a command it could not find, and 128 + N
  // its word for a command signal N stopped.
  final shellCode = code < 0 ? 128 - code : code;
  if (shellCode == 127) return '$name was not found; the draft is unchanged';
  if (shellCode > 128 && shellCode <= 128 + 64) {
    final signal = _signals[shellCode - 128] ?? 'signal ${shellCode - 128}';
    return '$name was stopped by $signal; the draft is unchanged';
  }
  return '$name exited with code $code; the draft is unchanged';
}

/// Opens [draft] in the user's editor through [terminal], which suspends
/// the window around it, and waits for it to exit.
Future<EditorEnd> editInEditor(
  String draft, {
  required Terminal terminal,
  String? Function(String)? env,
}) async {
  final read = env ?? (name) => Platform.environment[name];
  final command = editorCommand(read);
  final name = editorName(command);
  // Behind the shell a missing shell would read as a missing editor.
  final shell = read('SHELL')?.trim() ?? '';
  if (shell.contains('/') && !File(shell).existsSync()) {
    return EditorFailed('$name did not start: $shell was not found');
  }
  final directory = await Directory.systemTemp.createTemp('chord-prompt-');
  try {
    // Editors colour and wrap a `.md` file as prose.
    final file = File(p.join(directory.path, 'prompt.md'));
    await file.writeAsString(draftFile(draft));
    final int code;
    try {
      code = await terminal.runEditor(file.path, command: command);
    } catch (error) {
      final why = error is ProcessException ? error.message : '$error';
      return EditorFailed('$name did not start: $why');
    }
    return code == 0
        ? EditorText(fileDraft(await file.readAsString()))
        : EditorFailed(editorFailure(name, code));
  } finally {
    await directory.delete(recursive: true);
  }
}
