// runApp with exitProcess on a terminal of its own, for run_app_test.dart:
// `ok` quits cleanly, `fails` fails through its input; `throws` makes
// beforeExit throw; `enters` has a terminal that cannot enter, `writes`
// one whose first frame cannot be written (CTUI-114). beforeExit says
// `closed` once it has run.
import 'dart:async';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

class _Terminal extends Terminal {
  _Terminal(this.how);

  final String how;
  final _input = StreamController<String>();

  @override
  Size get size => const Size(20, 2);

  @override
  Stream<String> get input => _input.stream;

  @override
  Stream<Size> get resizes => const Stream.empty();

  @override
  void enter() {
    if (how == 'enters') throw StateError('enter failed');
  }

  @override
  Future<void> leave() async => stdout.writeln('left');

  @override
  void write(String data) {
    if (data.isEmpty || data == '\x1b]11;?\x07') return;
    // The first frame: quit, or fail.
    if (how == 'writes') throw StateError('write failed');
    if (how == 'fails') {
      _input.addError(StateError('input failed'));
    } else {
      _input.add('\x03');
    }
  }
}

Future<void> main(List<String> args) async {
  final [how] = args;
  await runApp(
    Text('app'),
    terminal: _Terminal(how),
    environment: const {},
    beforeExit: () async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      stdout.writeln('closed');
      await stdout.flush();
      if (how == 'throws') throw StateError('close failed');
    },
  );
}
