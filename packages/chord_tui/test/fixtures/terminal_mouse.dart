import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

/// Takes and gives back a terminal, the mouse as args[0] says, writing what
/// it wrote to args[1] and the terminal it ran on to args[2].
Future<void> main(List<String> args) async {
  File(args[2]).writeAsStringSync(
    Process.runSync('sh', ['-c', 'tty < /dev/tty']).stdout.toString(),
  );
  final sink = File(args[1]).openWrite();
  final terminal = StdioTerminal(mouse: args[0] == 'on', output: sink);
  terminal.enter();
  await terminal.leave();
  await terminal.close();
  await sink.close();
}
