import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

class _MouseTerminal extends Terminal {
  final source = StreamController<String>();
  final frame = Completer<void>();
  @override
  Size get size => const Size(80, 24);
  @override
  Stream<String> get input => source.stream;
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  void enter() {}
  @override
  Future<void> leave() async {}
  @override
  void write(String bytes) {
    if (bytes == '\x1b]11;?\x07') {
      source.add('\x1b[<64;3;4M\x1b]11;#000000\x07');
    } else if (bytes == '\x1b[?u') {
      source.add('\x1b[?0u');
    } else if (!frame.isCompleted && bytes != '\x1b[>5u') {
      frame.complete();
    }
  }
}

void main() {
  test(
    'runApp delivers early and live mouse once without key or paste leakage',
    () async {
      final terminal = _MouseTerminal();
      final mouse = <MouseEvent>[];
      final keys = <String>[];
      final pastes = <String>[];
      final delivered = Completer<void>();
      final running = runApp(
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (event) {
            mouse.add(event);
            if (mouse.length == 2) delivered.complete();
          },
          child: Focus(
            autofocus: true,
            onKey: (event) {
              keys.add(event.combo.toString());
              return true;
            },
            onPaste: (text) {
              pastes.add(text);
              return true;
            },
            child: Text('ready'),
          ),
        ),
        terminal: terminal,
        exitProcess: false,
        environment: const {},
      );
      await terminal.frame.future.timeout(const Duration(seconds: 3));
      terminal.source.add('a\x1b[<65;80;24M\x1b[<32;1;1M\x1b[<99;1;1M');
      terminal.source.add('\x1b[200~\x1b[<64;2;2M\x1b[201~');
      await delivered.future.timeout(const Duration(seconds: 3));
      await terminal.source.close();
      await running;
      expect(mouse.map((e) => e.position), [
        const Offset(2, 3),
        const Offset(79, 23),
      ]);
      expect(mouse.map((e) => e.scrollDelta), [
        const Offset(0, -1),
        const Offset(0, 1),
      ]);
      expect(keys, ['a']);
      expect(pastes, ['\x1b[<64;2;2M']);
    },
  );

  test(
    'runApp merges a wheel run from one read into one report and layout',
    () async {
      final terminal = _MouseTerminal();
      final mouse = <MouseEvent>[];
      final rows = ValueNotifier(0);
      var builds = 0;
      final delivered = Completer<void>();
      final running = runApp(
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (event) {
            mouse.add(event);
            // As a scrolling view does: each step dirties the tree.
            rows.value += event.scrollDelta.y;
            if (mouse.length == 5) delivered.complete();
          },
          child: ListenableBuilder(
            listenable: rows,
            builder: (_) {
              builds++;
              return Text('rows ${rows.value}');
            },
          ),
        ),
        terminal: terminal,
        exitProcess: false,
        environment: const {},
      );
      await terminal.frame.future.timeout(const Duration(seconds: 3));
      final before = builds;
      terminal.source.add(
        '${'\x1b[<65;5;5M' * 5}\x1b[<64;5;5Mx\x1b[<65;5;5M\x1b[<65;6;5M',
      );
      await delivered.future.timeout(const Duration(seconds: 3));
      await terminal.source.close();
      await running;
      // The first is the terminal's early report, held until mounted.
      expect(mouse.map((e) => (e.position, e.scrollDelta)), [
        (const Offset(2, 3), const Offset(0, -1)),
        (const Offset(4, 4), const Offset(0, 5)),
        (const Offset(4, 4), const Offset(0, -1)),
        (const Offset(4, 4), const Offset(0, 1)),
        (const Offset(5, 4), const Offset(0, 1)),
      ]);
      // One rebuild before each report after the first, none per merged step.
      expect(builds - before, lessThanOrEqualTo(4));
    },
  );
}
