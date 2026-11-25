import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

class _Terminal extends Terminal {
  final source = StreamController<String>(sync: true);
  final resize = StreamController<Size>(sync: true);
  final ownership = StreamController<TerminalState>.broadcast(sync: true);
  final writes = <String>[];
  var dimensions = const Size(20, 6);
  Completer<void>? released;
  bool leaving = false;
  @override
  Size get size => dimensions;
  @override
  Stream<String> get input => source.stream;
  @override
  Stream<Size> get resizes => resize.stream;
  @override
  Stream<TerminalState> get states => ownership.stream;
  @override
  void enter() => ownership.add(TerminalState.active);
  @override
  Future<void> leave() async {
    leaving = true;
    if (released == null) ownership.add(TerminalState.inactive);
    await released?.future;
  }

  @override
  void write(String bytes) {
    writes.add(bytes);
    if (bytes == '\x1b]11;?\x07') {
      scheduleMicrotask(() => source.add('\x1b]11;#000000\x07'));
    }
  }

  @override
  Future<T> suspend<T>(Future<T> Function() action) async {
    final done = Completer<void>();
    released = done;
    ownership.add(TerminalState.suspended);
    try {
      return await action();
    } finally {
      if (!leaving) ownership.add(TerminalState.active);
      released = null;
      done.complete();
    }
  }

  Future<void> close() async {
    await source.close();
    await resize.close();
    await ownership.close();
  }
}

Future<void> _until(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) throw StateError('Fixture did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  test('parser reset discards both control fragments and unfinished paste', () {
    final parser = InputParser();
    for (final pending in ['\x1b[', '\x1b]11;#000', '\x1b[200~child text']) {
      expect(parser.feed(pending), isEmpty);
      parser.reset();
      expect(parser.hasPending, isFalse);
      expect(parser.flush(), isEmpty);
      expect((parser.feed('z').single as KeyEvent).key, 'z');
    }
  });
  test('cancelPendingChord keeps focus and dispatches no cancellation key', () {
    var called = 0;
    final host = AppHost(
      Actions(
        bindings: [
          Binding('ctrl+x a', 'Complete chord', () {
            called++;
          }),
          Binding('esc', 'Escape action', () {
            called++;
          }),
        ],
        child: Focus(autofocus: true, child: Text('focus')),
      ),
    );
    addTearDown(host.dispose);
    host.drawFrame(const Size(20, 6));
    final focus = host.focusManager.primaryFocus;
    host.handleKey(KeyCombo.parse('ctrl+x').toEvent());
    expect(host.focusManager.pendingChord, isNotEmpty);
    host.focusManager.cancelPendingChord();
    expect(host.focusManager.pendingChord, isEmpty);
    expect(host.focusManager.primaryFocus, same(focus));
    host.handleKey(KeyCombo.parse('a').toEvent());
    expect(called, 0);
  });
  for (final failure in [false, true]) {
    test(
      'runApp gates input/frames and redraws latest resize after callback failure=$failure',
      () async {
        final terminal = _Terminal();
        final text = ValueNotifier('before');
        final release = Completer<void>();
        final began = Completer<void>();
        final resumed = Completer<void>();
        final keys = <String>[];
        var chord = 0;
        late BuildContext context;
        final original = StateError('child failed');
        Object? caught;
        Future<void> edit() async {
          try {
            await terminal.suspend(() async {
              began.complete();
              await release.future;
              if (failure) throw original;
            });
          } catch (error) {
            caught = error;
          }
          resumed.complete();
        }

        final run = runApp(
          Builder(
            builder: (c) {
              context = c;
              return Actions(
                bindings: [
                  Binding('ctrl+g', 'Scripted editor', () {
                    unawaited(edit());
                  }),
                  Binding('ctrl+x a', 'Complete chord', () {
                    chord++;
                  }),
                ],
                child: Focus(
                  autofocus: true,
                  onKey: (key) {
                    keys.add(key.combo.toString());
                    return false;
                  },
                  child: ListenableBuilder(
                    listenable: text,
                    builder: (_) => Text(text.value),
                  ),
                ),
              );
            },
          ),
          terminal: terminal,
          exitProcess: false,
        );
        await _until(() => terminal.writes.any((s) => s.contains('before')));
        terminal.source.add('\x07z');
        await began.future;
        final count = terminal.writes.length;
        text.value = 'after';
        terminal.dimensions = const Size(30, 8);
        terminal.resize.add(terminal.size);
        terminal.source.add('child\x1b[200~paste\x1b[201~');
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(terminal.writes.length, count);
        expect(keys, ['ctrl+g']);
        release.complete();
        await resumed.future;
        await _until(
          () => terminal.writes.skip(count).any((s) => s.contains('after')),
        );
        final frame = terminal.writes
            .skip(count)
            .firstWhere((s) => s.contains('\x1b[2J'));
        expect(frame, contains('after'));
        expect(frame, contains('\x1b[8;1H'));
        expect(caught, failure ? same(original) : isNull);
        // An external suspension clears an unfinished chord and partial paste.
        terminal.source.add('\x18');
        final secondRelease = Completer<void>();
        final second = terminal.suspend(() => secondRelease.future);
        terminal.source.add('a');
        secondRelease.complete();
        await second;
        terminal.source.add('a\x1b[200~unfinished');
        final thirdRelease = Completer<void>();
        final third = terminal.suspend(() => thirdRelease.future);
        thirdRelease.complete();
        await third;
        terminal.source.add('q');
        expect(chord, 0);
        expect(keys.last, 'q');
        exitApp(context);
        await run;
        await terminal.close();
        text.dispose();
      },
    );
  }
  test('active release gates dispatch and frames synchronously', () async {
    final terminal = _Terminal();
    final keys = <String>[];
    final text = ValueNotifier('ready');
    final run = runApp(
      Focus(
        autofocus: true,
        onKey: (event) {
          keys.add(event.key);
          return true;
        },
        child: ListenableBuilder(
          listenable: text,
          builder: (_) => Text(text.value),
        ),
      ),
      terminal: terminal,
      exitProcess: false,
    );
    await _until(() => terminal.writes.any((s) => s.contains('ready')));
    final count = terminal.writes.length;
    final leaving = terminal.leave();
    terminal.source.add('z');
    text.value = 'must not draw';
    terminal.resize.add(const Size(30, 8));
    await leaving;
    await run;
    expect(keys, isEmpty);
    expect(terminal.writes.length, count);
    await terminal.close();
    text.dispose();
  });
  test(
    'quit while suspended waits for callback without unmount or reentry',
    () async {
      final terminal = _Terminal();
      final release = Completer<void>();
      var disposed = false;
      var exited = false;
      late BuildContext context;
      final run = runApp(
        Builder(
          builder: (c) {
            context = c;
            return _Lifetime(() {
              disposed = true;
            });
          },
        ),
        terminal: terminal,
        exitProcess: false,
        beforeExit: () async {
          exited = true;
        },
      );
      await _until(() => terminal.writes.any((s) => s.contains('ready')));
      final operation = terminal.suspend(() => release.future);
      final count = terminal.writes.length;
      exitApp(context);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(disposed, isFalse);
      expect(exited, isFalse);
      expect(terminal.leaving, isTrue);
      release.complete();
      await operation;
      await run;
      expect(disposed, isTrue);
      expect(exited, isTrue);
      expect(terminal.writes.length, count);
      await terminal.close();
    },
  );
}

class _Lifetime extends StatefulWidget {
  const _Lifetime(this.onDispose);
  final void Function() onDispose;
  @override
  State<_Lifetime> createState() => _LifetimeState();
}

class _LifetimeState extends State<_Lifetime> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('ready');
}
