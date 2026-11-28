import 'dart:async';

import 'package:chord_tui/chord_tui.dart';

const _web = bool.fromEnvironment('dart.library.js_interop');

// The same failures must be consumed on native and returned by Wasm.
Future<void> main() async {
  for (final how in ['writes', 'leaves', 'hook', 'enters and hook']) {
    final primary = StateError('tester $how');
    final secondary = StateError('tester secondary');
    final stack = StackTrace.fromString('tester primary stack');
    final term = _Terminal(how, primary, stack);
    var hooks = 0;
    Object? caught;
    StackTrace? caughtStack;
    try {
      await runApp(
        Text('ready'),
        terminal: term,
        exitProcess: false,
        // Defaults exercise the web's signal guard and environment seam.
        beforeExit: () async {
          hooks++;
          if (term.leaves != 1 || !term.closed) {
            throw StateError('hook ran before terminal cleanup');
          }
          await Future<void>.value();
          if (how == 'hook') Error.throwWithStackTrace(primary, stack);
          if (how == 'enters and hook') throw secondary;
        },
      );
    } catch (error, trace) {
      caught = error;
      caughtStack = trace;
    }
    if (hooks != 1 || term.leaves != 1 || !term.closed) {
      throw StateError('cleanup did not finish exactly once: $how');
    }
    if (_web) {
      if (!identical(caught, primary) ||
          !caughtStack.toString().contains('tester primary stack')) {
        throw StateError('primary error or stack lost: $how, $caught');
      }
    } else if (caught != null) {
      throw StateError('native embedded failure escaped: $how, $caught');
    }
    print('$how: cleaned, ${_web ? 'propagated' : 'returned'}');
  }
}

class _Terminal extends Terminal {
  _Terminal(this.how, this.failure, this.stack);

  final String how;
  final Object failure;
  final StackTrace stack;
  final _input = StreamController<String>();
  var leaves = 0;
  var closed = false;
  var quitting = false;

  @override
  Size get size => const Size(80, 24);

  @override
  Stream<String> get input => _input.stream;

  @override
  Stream<Size> get resizes => const Stream.empty();

  @override
  void enter() {
    if (how == 'enters and hook') Error.throwWithStackTrace(failure, stack);
  }

  @override
  Future<void> leave() async {
    leaves++;
    // A cancelled single-subscription stream can be closed without waiting
    // for a listener that never mounted after enter failed.
    unawaited(_input.close());
    closed = true;
    if (how == 'leaves') Error.throwWithStackTrace(failure, stack);
  }

  @override
  void write(String data) {
    if (data.isEmpty || data.startsWith('\x1b]11') || data == '\x1b[?u') {
      return;
    }
    if (how == 'writes') Error.throwWithStackTrace(failure, stack);
    if (!quitting) {
      quitting = true;
      _input.add('\x03');
    }
  }
}
