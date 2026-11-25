import '../../../session/transcript/types.dart';

/// Latest output lines shown while a terminal is folded.
const terminalLines = 3;

/// The terminal's end note, separate from the output's own tone.
final class TerminalNote {
  /// A note and whether it describes failure.
  const TerminalNote(this.text, {required this.failed});

  /// The exit, signal or no-output wording.
  final String text;

  /// Whether the command failed.
  final bool failed;
}

/// A terminal's visible tail or expanded output and its end note.
final class TerminalView {
  /// Output lines with their hidden count and optional end note.
  const TerminalView(this.lines, this.hidden, {required this.id, this.note});

  /// Domain terminal identity, independent of list position.
  final String id;

  /// Visible output, newest lines while folded.
  final List<String> lines;

  /// Output lines before those shown.
  final int hidden;

  /// Failure or no-output wording under the output.
  final TerminalNote? note;
}

/// Keeps a running command's newest lines; ctrl+o includes the cut marker.
TerminalView terminalView(Terminal terminal, bool expanded) {
  final lines = _outputLines(terminal.output);
  final start = (lines.length - terminalLines).clamp(0, lines.length);
  final shown = expanded
      ? [if (terminal.truncated) '… output cut', ...lines]
      : lines.sublist(start);
  final note =
      _endNote(terminal) ??
      (terminal.exited && lines.isEmpty
          ? const TerminalNote('(No output)', failed: false)
          : null);
  return TerminalView(
    shown,
    expanded ? 0 : lines.length - shown.length,
    id: terminal.id,
    note: note,
  );
}

/// Whether there is anything for the tool to draw.
bool isEmpty(TerminalView view) => view.lines.isEmpty && view.note == null;

TerminalNote? _endNote(Terminal terminal) {
  if (terminal.signal != null) {
    final signal = _outputLines(terminal.signal!).join(' ');
    return TerminalNote(
      signal.isEmpty ? 'Killed' : 'Killed by $signal',
      failed: true,
    );
  }
  final code = terminal.exitCode;
  return code == null || code == 0
      ? null
      : TerminalNote('Exit code ${_shownNumber(code)}', failed: true);
}

List<String> _outputLines(String output) {
  final text = output.trimRight();
  return text.isEmpty ? [] : text.split('\n');
}

// JSON numbers are kept as num; JavaScript omits the decimal suffix for
// integral doubles and uses exponential notation at 1e21.
String _shownNumber(num value) {
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value
        .toString()
        .replaceFirst(RegExp(r'\.0$'), '')
        .replaceFirst('.0e', 'e');
  }
  return value.toString();
}
