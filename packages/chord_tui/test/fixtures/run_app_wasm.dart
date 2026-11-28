// runApp compiled to Wasm, for run_app_wasm_compile_test.dart: `ok` quits by
// Ctrl+C, `enters` has a terminal that cannot enter. Each says on the
// console whether runApp returned or failed.
import 'dart:async';
import 'dart:js_interop';

import 'package:chord_tui/chord_tui.dart';

@JS('console.log')
external void _log(JSString line);

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
  Future<void> leave() async {}

  @override
  void write(String data) {
    // The first frame, after runApp's questions: quit.
    if (data.isEmpty || data.startsWith('\x1b]11') || data == '\x1b[?u') {
      return;
    }
    _input.add('\x03');
  }
}

Future<void> main() async {
  for (final how in ['ok', 'enters']) {
    try {
      // Signals and exiting left at their defaults: a page has neither.
      await runApp(Text('app'), terminal: _Terminal(how));
      _log('$how returned'.toJS);
    } catch (error) {
      _log('$how failed: $error'.toJS);
    }
  }
}
