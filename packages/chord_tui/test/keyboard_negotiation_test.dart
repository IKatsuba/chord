import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

const _query = '\x1b[?u';
const _push = '\x1b[>5u';
const _pop = '\x1b[<u';

class _Terminal extends Terminal {
  final source = StreamController<String>.broadcast(sync: true);
  final resize = StreamController<Size>.broadcast(sync: true);
  final ownership = StreamController<TerminalState>.broadcast(sync: true);
  final writes = <String>[];
  void Function(String)? onWrite;
  Completer<void>? released;
  bool leaving = false;
  var dimensions = const Size(20, 6);
  @override
  Size get size => dimensions;
  @override
  Stream<String> get input => source.stream;
  @override
  Stream<Size> get resizes => resize.stream;
  @override
  Stream<TerminalState> get states => ownership.stream;
  @override
  void write(String bytes) {
    writes.add(bytes);
    if (bytes == '\x1b]11;?\x07') {
      scheduleMicrotask(() => source.add('\x1b]11;#000000\x07'));
    }
    onWrite?.call(bytes);
  }

  @override
  void enter() {
    leaving = false;
    writes.add('enter');
    ownership.add(TerminalState.active);
  }

  @override
  Future<void> leave() async {
    leaving = true;
    await released?.future;
    writes.add('leave');
  }

  @override
  Future<T> suspend<T>(Future<T> Function() action) async {
    final done = Completer<void>();
    released = done;
    ownership.add(TerminalState.suspended);
    writes.add('released');
    try {
      return await action();
    } finally {
      if (!leaving) {
        writes.add('acquired');
        ownership.add(TerminalState.active);
      }
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

class _App {
  final keys = <String>[];
  final pastes = <String>[];
  late BuildContext context;
  var mounts = 0;
  Widget get widget => Builder(
    builder: (c) {
      context = c;
      mounts++;
      return Focus(
        autofocus: true,
        onKey: (event) {
          keys.add('${event.combo}');
          return true;
        },
        onPaste: (text) {
          pastes.add(text);
          return true;
        },
        child: Text('ready'),
      );
    },
  );
}

Future<void> _until(bool Function() predicate) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) {
      throw StateError('Negotiation fixture did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _ready(_Terminal terminal) =>
    _until(() => terminal.writes.any((s) => s.contains('ready')));

void main() {
  test(
    'fragmented supported reply shares startup budget and early input once',
    () async {
      final terminal = _Terminal();
      final app = _App();
      terminal.onWrite = (bytes) {
        if (bytes == _query) {
          scheduleMicrotask(() {
            terminal.source.add('a\x1b[200~paste\x1b[201~\x1b[?');
            unawaited(
              Future<void>.delayed(const Duration(milliseconds: 40), () {
                terminal.source.add('31ub');
              }),
            );
          });
        }
      };
      final run = runApp(app.widget, terminal: terminal, exitProcess: false);
      await _ready(terminal);
      expect(app.mounts, 1);
      expect(app.keys, ['a', 'b']);
      expect(app.pastes, ['paste']);
      expect(terminal.writes.where((s) => s == _push), hasLength(1));
      terminal.source.add('\x1b[?31u');
      expect(terminal.writes.where((s) => s == _push), hasLength(1));
      exitApp(app.context);
      await run;
      expect(terminal.writes.where((s) => s == _pop), hasLength(1));
      expect(
        terminal.writes.indexOf(_pop),
        lessThan(terminal.writes.indexOf('leave')),
      );
      await terminal.close();
    },
  );
  test(
    'early picker input waits for layout focus and submits only once',
    () async {
      final terminal = _Terminal();
      final selected = <int>[];
      var callbacks = 0;
      terminal.onWrite = (bytes) {
        if (bytes == _query) {
          scheduleMicrotask(() => terminal.source.add('2\r\r\x1b[?1u'));
        }
      };
      final run = runApp(
        Builder(
          builder: (context) => Picker<int>(
            items: const [
              PickerItem(value: 1, label: 'First'),
              PickerItem(value: 2, label: 'Second'),
            ],
            onSelected: (value) {
              selected.add(value);
              callbacks++;
              exitApp(context);
            },
            onCanceled: () => exitApp(context),
          ),
        ),
        terminal: terminal,
        exitProcess: false,
      );
      await run.timeout(const Duration(seconds: 2));
      expect(selected, [2]);
      expect(callbacks, 1);
      expect(terminal.writes.any((s) => s.contains('Second')), isTrue);
      expect(terminal.writes.where((s) => s == _push), hasLength(1));
      expect(terminal.writes.where((s) => s == _pop), hasLength(1));
      await terminal.close();
    },
  );
  test(
    'unsupported timeout consumes late replies without enabling or typing them',
    () async {
      final terminal = _Terminal();
      final app = _App();
      final clock = Stopwatch()..start();
      final run = runApp(app.widget, terminal: terminal, exitProcess: false);
      await _ready(terminal);
      expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(90));
      terminal.source.add('\x1b[?1u\x1b[?1uz');
      expect(app.keys, ['z']);
      exitApp(app.context);
      await run;
      expect(terminal.writes, isNot(contains(_push)));
      expect(terminal.writes, isNot(contains(_pop)));
      await terminal.close();
    },
  );
  test(
    'a fragmented reply completed after timeout never types its late tail',
    () async {
      final terminal = _Terminal();
      final app = _App();
      terminal.onWrite = (bytes) {
        if (bytes == _query) {
          scheduleMicrotask(() => terminal.source.add('\x1b[?1'));
          unawaited(
            Future<void>.delayed(const Duration(milliseconds: 160), () {
              terminal.source.add('uz');
            }),
          );
        }
      };
      final run = runApp(app.widget, terminal: terminal, exitProcess: false);
      await _ready(terminal);
      await _until(() => app.keys.isNotEmpty);
      expect(app.keys, ['z']);
      expect(terminal.writes, isNot(contains(_push)));
      exitApp(app.context);
      await run;
      await terminal.close();
    },
  );
  test(
    'each sequential app negotiates and balances exactly its own push',
    () async {
      final terminal = _Terminal();
      terminal.onWrite = (bytes) {
        if (bytes == _query) {
          scheduleMicrotask(() => terminal.source.add('\x1b[?0u\x1b[?0u'));
        }
      };
      for (var i = 0; i < 2; i++) {
        final app = _App();
        final start = terminal.writes.length;
        final run = runApp(app.widget, terminal: terminal, exitProcess: false);
        await _until(
          () => terminal.writes.skip(start).any((s) => s.contains('ready')),
        );
        exitApp(app.context);
        await run;
      }
      for (final bytes in [_query, _push, _pop]) {
        expect(terminal.writes.where((s) => s == bytes), hasLength(2));
      }
      await terminal.close();
    },
  );
  for (final fail in [false, true]) {
    test(
      'suspend pops before release and resumes with fresh negotiation, failure=$fail',
      () async {
        final terminal = _Terminal();
        final app = _App();
        terminal.onWrite = (bytes) {
          if (bytes == _query) {
            scheduleMicrotask(() => terminal.source.add('\x1b[?1u'));
          }
        };
        final run = runApp(app.widget, terminal: terminal, exitProcess: false);
        await _ready(terminal);
        final release = Completer<void>();
        final original = StateError('child failed');
        final operation = terminal.suspend(() async {
          await release.future;
          if (fail) throw original;
        });
        expect(
          terminal.writes.indexOf(_pop),
          lessThan(terminal.writes.indexOf('released')),
        );
        terminal.source.add('\x1b[?1ux');
        expect(app.keys, isEmpty);
        terminal.dimensions = const Size(30, 8);
        terminal.resize.add(terminal.size);
        release.complete();
        try {
          await operation;
        } catch (error) {
          expect(error, same(original));
        }
        await _until(
          () => terminal.writes.where((s) => s == _push).length == 2,
        );
        expect(
          terminal.writes.indexOf('acquired'),
          lessThan(terminal.writes.lastIndexOf(_query)),
        );
        expect(app.keys, isEmpty);
        exitApp(app.context);
        await run;
        expect(terminal.writes.where((s) => s == _pop), hasLength(2));
        await terminal.close();
      },
    );
  }
  test('quit while suspended never pushes a late reply or resumes', () async {
    final terminal = _Terminal();
    final app = _App();
    terminal.onWrite = (bytes) {
      if (bytes == _query) {
        scheduleMicrotask(() => terminal.source.add('\x1b[?1u'));
      }
    };
    final run = runApp(app.widget, terminal: terminal, exitProcess: false);
    await _ready(terminal);
    final release = Completer<void>();
    final operation = terminal.suspend(() => release.future);
    exitApp(app.context);
    await Future<void>.delayed(Duration.zero);
    terminal.source.add('\x1b[?1u');
    release.complete();
    await operation;
    await run;
    expect(terminal.writes, isNot(contains('acquired')));
    expect(terminal.writes.where((s) => s == _push), hasLength(1));
    expect(terminal.writes.where((s) => s == _pop), hasLength(1));
    await terminal.close();
  });
  for (final failedBytes in [_push, _pop]) {
    test(
      'failed keyboard mode write still leaves and reaches beforeExit: $failedBytes',
      () async {
        final terminal = _Terminal();
        final app = _App();
        var exited = 0;
        terminal.onWrite = (bytes) {
          if (bytes == _query) {
            scheduleMicrotask(() => terminal.source.add('\x1b[?1u'));
          }
          if (bytes == failedBytes) throw StateError('keyboard write failed');
        };
        final run = runApp(
          app.widget,
          terminal: terminal,
          exitProcess: false,
          beforeExit: () async {
            exited++;
          },
        );
        if (failedBytes == _pop) {
          await _ready(terminal);
          exitApp(app.context);
        }
        await run;
        expect(exited, 1);
        expect(terminal.writes.where((s) => s == 'leave'), hasLength(1));
        expect(terminal.writes.where((s) => s == _pop), hasLength(1));
        await terminal.close();
      },
    );
  }
}
