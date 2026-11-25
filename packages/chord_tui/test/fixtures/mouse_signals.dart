import 'dart:async';
import 'dart:io';
import 'package:chord_tui/chord_tui.dart';

Future<void> main(List<String> args) async {
  final scenario = args.single;
  final before = Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout;
  final terminal = StdioTerminal();
  await runApp(
    Builder(
      builder: (context) => Actions(
        bindings: [Binding('ctrl+q', 'Quit', () => exitApp(context))],
        child: Text('MOUSE_READY'),
      ),
    ),
    terminal: terminal,
    exitProcess: false,
    beforeExit: () async {
      stdout.writeln('CLEANUP_START');
      await stdout.flush();
      await terminal.close();
      final after = Process.runSync('sh', ['-c', 'stty -g < /dev/tty']).stdout;
      if (before != after) throw StateError('Termios changed');
      stdout.writeln('EXACT=true');
      if (scenario == 'repeat') {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      stdout.writeln('CLEANUP_DONE');
      await stdout.flush();
    },
  );
  stdout.writeln('RETURNED');
  await stdout.flush();
  if (scenario == 'after_return') {
    await Future<void>.delayed(const Duration(seconds: 5));
  }
}
