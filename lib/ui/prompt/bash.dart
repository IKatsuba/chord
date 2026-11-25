import '../../session/context.dart';
import '../../session/transcript/types.dart';

/// Bash history's mode prefix, excluded from the editable command.
const bashPrefix = '!';

/// Output rows in the original helper's collapsed view, unused by its screen.
const shellLines = 10;

/// A recalled command without its prefix; null for an ordinary prompt.
String? bashCommand(String text) =>
    text.startsWith(bashPrefix) ? text.substring(1) : null;

/// The text stored in prompt history.
String typedText(bool bash, String draft) => bash ? '$bashPrefix$draft' : draft;

/// A typed or pasted prefix enters bash mode only from an empty ordinary draft.
String? entersBash(bool bash, String draft, String value) =>
    !bash && draft.isEmpty ? bashCommand(value) : null;

typedef ShellLine = ({String text, bool stderr});
typedef ShellNote = ({String text, bool failed});

/// Plain presentation of a local command's output and original ending note.
final class ShellView {
  ShellView(Iterable<ShellLine> lines, this.hidden, this.note)
    : lines = List.unmodifiable(lines);
  final List<ShellLine> lines;
  final int hidden;
  final ShellNote? note;
}

/// The actual shell row requests expanded output regardless of verbose state.
ShellView shellView(ShellRun run, bool expanded, String? stopKey) {
  List<ShellLine> linesOf(String text, bool stderr) {
    final clean = cleanOutput(text);
    return clean.isEmpty
        ? []
        : [for (final line in clean.split('\n')) (text: line, stderr: stderr)];
  }

  final lines = [
    ...linesOf(run.stdout, false),
    if (run.truncated) (text: truncated, stderr: false),
    ...linesOf(run.stderr, true),
  ];
  final shown = expanded ? lines : lines.take(shellLines).toList();
  final ended = endNote(run);
  final ShellNote? note = run.running
      ? (
          text: stopKey == null ? 'Running…' : 'Running… ($stopKey to stop)',
          failed: false,
        )
      : ended != null
      ? (text: ended, failed: !run.stopped)
      : lines.isEmpty
      ? (text: '(No output)', failed: false)
      : null;
  return ShellView(shown, lines.length - shown.length, note);
}

/// A fenced script with only column-zero shell prompt prefixes removed.
String runCommand(String text) => text
    .split('\n')
    .map((line) => line.startsWith(r'$ ') ? line.substring(2) : line)
    .join('\n');
