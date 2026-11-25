import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

class _Terminal extends Terminal {
  final source = StreamController<String>(sync: true);
  final ownership = StreamController<TerminalState>.broadcast(sync: true);
  final ready = Completer<void>();
  final effects = <String>[];
  @override
  Size get size => const Size(80, 24);
  @override
  Stream<String> get input => source.stream;
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  Stream<TerminalState> get states => ownership.stream;
  @override
  void enter() => ownership.add(TerminalState.active);
  @override
  Future<void> leave() async {
    ownership.add(TerminalState.inactive);
    effects.add('released');
  }

  @override
  void write(String data) {
    if (data == '\x1b]11;?\x07') {
      scheduleMicrotask(() => source.add('\x1b]11;#000000\x07'));
    } else if (data == '\x1b[?u') {
      scheduleMicrotask(() => source.add('\x1b[?0u'));
    } else if (data.contains('target') && !ready.isCompleted) {
      ready.complete();
    }
  }

  @override
  Future<T> suspend<T>(Future<T> Function() action) async {
    ownership.add(TerminalState.suspended);
    effects.add('suspended');
    try {
      return await action();
    } finally {
      ownership.add(TerminalState.active);
    }
  }

  Future<void> close() async {
    await source.close();
    await ownership.close();
  }
}

void main() {
  for (final ending in ['suspend', 'inactive', 'quit', 'input end']) {
    test(
      'runApp cancels captured pointer before $ending ownership cleanup',
      () async {
        final terminal = _Terminal();
        final capture = PointerCaptureController();
        late BuildContext context;
        var ups = 0;
        final running = runApp(
          Builder(
            builder: (c) {
              context = c;
              return Listener(
                captureController: capture,
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => capture.capture(),
                onPointerCancel: (_) {
                  expect(capture.isCaptured, isFalse);
                  terminal.effects.add('cancel');
                  // A synchronous cancellation observer cannot revive input.
                  if (!terminal.source.isClosed) {
                    terminal.source.add('\x1b[<0;1;1M');
                  }
                },
                onPointerUp: (_) => ups++,
                child: Text('target'),
              );
            },
          ),
          terminal: terminal,
          exitProcess: false,
          environment: const {},
        );
        await terminal.ready.future.timeout(const Duration(seconds: 3));
        terminal.source.add('\x1b[<0;1;1M\x1b[<32;80;24M');
        expect(capture.isCaptured, isTrue);
        switch (ending) {
          case 'suspend':
            await terminal.suspend(() async {
              expect(terminal.effects, ['cancel', 'suspended']);
              terminal.source.add('\x1b[<0;1;1m');
            });
            expect(capture.isCaptured, isFalse);
            // Resumption starts a new capture, rather than reviving the old one.
            terminal.source.add('\x1b[<0;1;1M');
            expect(capture.isCaptured, isTrue);
            exitApp(context);
          case 'inactive':
            await terminal.leave();
          case 'quit':
            exitApp(context);
          case 'input end':
            await terminal.source.close();
        }
        await running.timeout(const Duration(seconds: 3));
        expect(terminal.effects.first, 'cancel');
        expect(
          terminal.effects.where((s) => s == 'cancel'),
          hasLength(ending == 'suspend' ? 2 : 1),
        );
        expect(ups, 0);
        expect(capture.isCaptured, isFalse);
        capture.dispose();
        await terminal.close();
      },
    );
  }
}
