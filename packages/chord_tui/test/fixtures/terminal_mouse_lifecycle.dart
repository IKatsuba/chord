import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

Future<void> main(List<String> args) async {
  String modes() => Process.runSync('sh', [
    '-c',
    'stty -g < /dev/tty',
  ]).stdout.toString().trim();
  final before = modes();
  final sink = File(args[1]).openWrite();
  final terminal = StdioTerminal(
    mouse: args[0] == 'on',
    output: sink,
    input: const Stream<List<int>>.empty(),
  );
  terminal.enter();
  terminal.enter();
  await terminal.suspend(() async {});
  await terminal.leave();
  await terminal.leave();
  terminal.enter();
  await terminal.leave();
  await terminal.close();
  await sink.close();
  File(args[2]).writeAsStringSync('$before\n${modes()}\n');
}
