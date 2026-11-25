import 'package:chord_tui/chord_tui.dart';

class _Terminal extends StdioTerminal {
  _Terminal() : super(input: const Stream.empty(), tmuxPassthrough: true);
  final writes = <String>[];
  @override
  void write(String data) => writes.add(data);
}

Future<void> main(List<String> args) async {
  final fails = args.single == 'true';
  final terminal = _Terminal();
  const working = '\x1b]7501;state=working\x1b\\';
  const done = '\x1b]7501;state=done\x1b\\';
  const clear = '\x1b]7501;state=clear\x1b\\';
  var resumed = false;
  final events = terminal.states.listen((state) {
    if (resumed && state == TerminalState.active) {
      terminal.setProgramStatus(const ProgramStatus(ProgramState.done));
    }
  });
  try {
    terminal.enter();
    terminal.setProgramStatus(const ProgramStatus(ProgramState.working));
    try {
      await terminal.suspend(() async {
        if (terminal.writes.where((s) => s.startsWith('\x1b]7501;')).last !=
            clear) {
          throw StateError('Status not cleared before lending the terminal');
        }
        resumed = true;
        if (fails) throw StateError('scripted editor failure');
      });
    } catch (error) {
      if (!fails || '$error' != 'Bad state: scripted editor failure') rethrow;
    }
    final statuses = terminal.writes
        .where((s) => s.startsWith('\x1b]7501;'))
        .toList();
    if (statuses.join() != [working, clear, done].join()) {
      throw StateError('Status not restored exactly once after suspension');
    }
    await terminal.leave();
    final clears = terminal.writes.where((s) => s == clear).length;
    if (clears != 2) {
      throw StateError('Final release did not clear latest status');
    }
    await terminal.close();
    if (terminal.writes.where((s) => s == clear).length != clears) {
      throw StateError('Close repeated the clear');
    }
  } finally {
    await terminal.close();
    await events.cancel();
  }
  print('STATUS_RELEASE_PASS=$fails');
}
