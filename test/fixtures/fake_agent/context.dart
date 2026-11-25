// A sent prompt taken apart again, as the original's src/session/context.ts
// does: the shell runs whose output chord sent ahead of it, and what was
// typed. A copy of that part alone, so the fake imports nothing of the app.

/// Said where output was cut.
const _truncated = '… output cut';

final _run = RegExp(
  r'^<bash-input>([\s\S]*?)<\/bash-input>\n<bash-stdout>([\s\S]*?)<\/bash-stdout><bash-stderr>([\s\S]*?)<\/bash-stderr>(?:<bash-status>([\s\S]*?)<\/bash-status>)?\n*',
);

/// A run held ahead of a prompt: its command and what it wrote.
typedef ShellRun = ({String command, String stdout});

/// The runs ahead of [text], and the rest.
({List<ShellRun> runs, String text}) splitContext(String text) {
  final runs = <ShellRun>[];
  var rest = text;
  for (
    var match = _run.firstMatch(rest);
    match != null;
    match = _run.firstMatch(rest)
  ) {
    final stdout = match.group(2) ?? '';
    final cut = stdout.endsWith('\n$_truncated');
    runs.add((
      command: match.group(1) ?? '',
      stdout: cut
          ? stdout.substring(0, stdout.length - _truncated.length - 1)
          : stdout,
    ));
    rest = rest.substring(match.group(0)!.length);
  }
  return (runs: runs, text: rest);
}
