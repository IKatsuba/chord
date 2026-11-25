import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

Future<void> main(List<String> args) async {
  final setup = Process.runSync('sh', [
    '-c',
    'stty ${args[0] == 'canonical' ? 'icanon' : '-icanon'} '
        '-echo -pendin rows ${args[1]} columns ${args[2]} < /dev/tty',
  ]);
  if (setup.exitCode != 0) throw StateError('Cannot configure terminal');
  String snapshot() {
    final result = Process.runSync('sh', ['-c', 'stty -g < /dev/tty']);
    if (result.exitCode != 0) throw StateError('Cannot inspect terminal');
    return (result.stdout as String).trim();
  }

  final before = snapshot();
  final terminal = StdioTerminal();
  for (var cycle = 0; cycle < 2; cycle++) {
    terminal.enter();
    await terminal.leave();
    if (snapshot() != before) {
      throw StateError('Termios changed on cycle $cycle');
    }
  }
  await terminal.close();
  stdout.writeln('EXACT_TWICE=true');
}
