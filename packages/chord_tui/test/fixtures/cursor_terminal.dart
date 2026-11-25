import 'package:chord_tui/chord_tui.dart';

class _Probe extends StdioTerminal {
  final writes = <String>[];
  bool fail = false;
  @override
  void write(String data) {
    writes.add(data);
    if (fail && data == '\x1b[?2004l') {
      fail = false;
      throw StateError('scripted release failure');
    }
    super.write(data);
  }
}

void check(bool value) {
  if (!value) throw StateError('Cursor lifecycle check failed');
}

Future<void> main() async {
  final terminal = _Probe();
  try {
    for (var i = 0; i < 2; i++) {
      terminal.enter();
      terminal.write(diffBuffers(null, Buffer(2, 1)..cursor = Offset.zero));
      await terminal.suspend(() async {
        check(
          terminal.writes.lastIndexOf('\x1b[0 q') <
              terminal.writes.lastIndexOf('\x1b[?25h'),
        );
        check(terminal.writes.contains('\x1b[0 q'));
      });
      terminal.write(diffBuffers(null, Buffer(2, 1)..cursor = Offset.zero));
      check(terminal.writes.last.contains('\x1b[2 q'));
      if (i == 1) terminal.fail = true;
      try {
        await terminal.leave();
        check(i == 0);
      } on StateError {
        check(i == 1);
      }
      check(
        terminal.writes.where((s) => s == '\x1b[0 q').length == (i + 1) * 2,
      );
      check(
        terminal.writes.lastIndexOf('\x1b[0 q') <
            terminal.writes.lastIndexOf('\x1b[?25h'),
      );
      await terminal.leave();
    }
  } finally {
    await terminal.close();
  }
  print('CURSOR_LIFECYCLE_PASS');
}
