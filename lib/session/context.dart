import 'package:chord_tui/chord_tui.dart' show stripAnsi;
import 'transcript/types.dart';

/// Maximum UTF-16 units kept for each local command output stream.
const outputLimit = 30000;

/// The original marker for a stream whose output exceeded its bound.
const truncated = '… output cut';
const _stopped = 'Stopped by the user';
final _trailingSpace = RegExp(r'\s+$');

/// Terminal output without ANSI, superseded carriage-return text or trailing space.
String cleanOutput(String text) => stripAnsi(text)
    .replaceAll('\r\n', '\n')
    .split('\n')
    .map((line) => line.substring(line.lastIndexOf('\r') + 1))
    .join('\n')
    .replaceFirst(_trailingSpace, '');

/// A failed or stopped ending; no news while running or after success.
String? endNote(ShellRun run) {
  if (run.running) return null;
  if (run.error != null) return 'Error: ${run.error}';
  if (run.stopped) return _stopped;
  return run.code == null || run.code == 0 ? null : 'Exit code ${run.code}';
}

/// Finished local runs as Claude Code's original context envelopes.
String shellContext(Iterable<ShellRun> runs) => runs
    .map((run) {
      final note = endNote(run), cut = run.truncated ? '\n$truncated' : '';
      return '<bash-input>${run.command}</bash-input>\n'
          '<bash-stdout>${cleanOutput(run.stdout)}$cut</bash-stdout>'
          '<bash-stderr>${cleanOutput(run.stderr)}</bash-stderr>'
          '${note == null ? '' : '<bash-status>$note</bash-status>'}';
    })
    .join('\n');

/// Held context precedes the typed prompt, separated by a blank line.
String withContext(String context, String prompt) =>
    context.isEmpty ? prompt : '$context\n\n$prompt';

final _run = RegExp(
  r'^<bash-input>([\s\S]*?)</bash-input>\n<bash-stdout>([\s\S]*?)</bash-stdout><bash-stderr>([\s\S]*?)</bash-stderr>(?:<bash-status>([\s\S]*?)</bash-status>)?\n*',
);

/// Separates the original context envelopes from the person's prompt text.
({List<ShellRun> runs, String text}) splitContext(String text) {
  final runs = <ShellRun>[];
  var rest = text;
  while (true) {
    final match = _run.firstMatch(rest);
    if (match == null) break;
    final stdout = match[2]!, note = match[4];
    final cut = stdout.endsWith('\n$truncated');
    final code = note == null
        ? 0
        : num.tryParse(
            RegExp(r'^Exit code (-?\d+)$').firstMatch(note)?[1] ?? '',
          );
    runs.add(
      ShellRun(
        command: match[1]!,
        running: false,
        stdout: cut
            ? stdout.substring(0, stdout.length - truncated.length - 1)
            : stdout,
        stderr: match[3]!,
        code: code,
        stopped: note == _stopped,
        error: note == null || code != null || note == _stopped
            ? null
            : note.replaceFirst(RegExp(r'^Error: '), ''),
        truncated: cut,
      ),
    );
    rest = rest.substring(match.end);
  }
  return (runs: List.unmodifiable(runs), text: rest);
}
