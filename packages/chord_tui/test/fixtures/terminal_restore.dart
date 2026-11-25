import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

Future<void> main(List<String> args) async {
  if (args[1] == 'pending') {
    final set = Process.runSync('sh', ['-c', 'stty pendin < /dev/tty']);
    if (set.exitCode != 0) throw StateError('Cannot seed PENDIN');
  }
  String snapshot() {
    final result = Process.runSync('sh', ['-c', 'stty -g < /dev/tty']);
    if (result.exitCode != 0) throw StateError('Cannot inspect terminal');
    return (result.stdout as String).trim();
  }

  final before = snapshot();
  final terminal = StdioTerminal();
  terminal.enter();
  stdout.write('READY');
  await stdout.flush();
  final queued = File(args[0]);
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!queued.existsSync()) {
    if (DateTime.now().isAfter(deadline)) throw StateError('Input not queued');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  await terminal.leave();
  final after = snapshot();
  stdout.writeln('EXACT=${before == after}');
  final input = List.generate(5, (_) => stdin.readByteSync());
  stdout.writeln('KEPT=${String.fromCharCodes(input) == 'kept\n'}');
  await terminal.close();
}
