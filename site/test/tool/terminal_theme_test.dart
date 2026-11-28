import 'dart:async';

import 'package:chord_site/palette.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

import '../../tool/terminal.dart';

/// A terminal that keeps what the site writes and takes typed keys.
class _Recording extends Terminal {
  final keys = StreamController<String>();
  final written = StringBuffer();
  final _drawn = Completer<void>();

  Future<void> get drawn => _drawn.future;

  @override
  Size get size => const Size(120, 40);

  @override
  Stream<String> get input => keys.stream;

  @override
  Stream<Size> get resizes => const Stream.empty();

  @override
  void enter() {}

  @override
  Future<void> leave() async {}

  @override
  void write(String data) {
    written.write(data);
    if (!_drawn.isCompleted && written.toString().contains('CHORD')) {
      _drawn.complete();
    }
  }
}

String _fg(RgbColor colour) => colour.fgCode;

void main() {
  test('the site in a terminal draws in the site theme', () async {
    final terminal = _Recording();
    final run = runInTerminal(
      terminal,
      '/',
      exitProcess: false,
      handleSignals: false,
      environment: const {},
    );
    try {
      await terminal.drawn.timeout(const Duration(seconds: 10));
      // Let the frame finish before reading it.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final out = terminal.written.toString();
      // Muted captions and rule-coloured frames are the site's own;
      // chord_tui's default theme has neither.
      expect(out, contains(_fg(SiteColors.muted)));
      expect(out, contains(_fg(SiteColors.rule)));
    } finally {
      // Ctrl+X ends the run, even when a check above failed.
      terminal.keys.add('\x18');
      await run.timeout(const Duration(seconds: 10));
      await terminal.keys.close();
    }
  });
}
