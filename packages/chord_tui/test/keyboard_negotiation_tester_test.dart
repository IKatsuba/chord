import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

const _query = '\x1b[?u';
const _push = '\x1b[>5u';
const _pop = '\x1b[<u';

void main() {
  group('tester: keyboard renegotiation ownership', () {
    test(
      'supported startup then unsupported resume never reuses old push',
      () async {
        final terminal = _Terminal();
        late BuildContext context;
        final keys = <String>[];
        final run = runApp(
          Builder(
            builder: (c) {
              context = c;
              return Focus(
                autofocus: true,
                onKey: (event) {
                  keys.add('${event.combo}');
                  return true;
                },
                child: Text('ready'),
              );
            },
          ),
          terminal: terminal,
          exitProcess: false,
        );
        await _until(() => terminal.writes.any((s) => s.contains('ready')));
        terminal.ownership.add(TerminalState.suspended);
        expect(terminal.writes.where((s) => s == _pop), hasLength(1));
        terminal.source.add('\x1b[?1u\x1b[120u');
        final before = terminal.writes.length;
        terminal.ownership.add(TerminalState.active);
        await _until(
          () => terminal.writes.skip(before).any((s) => s.contains('ready')),
        );
        await Future<void>.delayed(const Duration(milliseconds: 140));
        terminal.source.add('\x1b[?1u\x1b[?0u\x1b[105;5u');
        expect(keys, ['ctrl+i']);
        expect(terminal.writes.where((s) => s == _query), hasLength(2));
        expect(terminal.writes.where((s) => s == _push), hasLength(1));
        exitApp(context);
        await run;
        expect(terminal.writes.where((s) => s == _pop), hasLength(1));
        await terminal.close();
      },
    );
  });
}

Future<void> _until(bool Function() condition) async {
  final until = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(until)) {
      throw StateError('Tester negotiation timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _Terminal extends Terminal {
  final source = StreamController<String>.broadcast(sync: true);
  final ownership = StreamController<TerminalState>.broadcast(sync: true);
  final writes = <String>[];
  var queries = 0;
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
  Future<void> leave() async {}
  @override
  void write(String data) {
    writes.add(data);
    if (data == '\x1b]11;?\x07') {
      scheduleMicrotask(() => source.add('\x1b]11;#000000\x07'));
    }
    if (data == _query && ++queries == 1) {
      scheduleMicrotask(() => source.add('\x1b[?1u'));
    }
  }

  Future<void> close() async {
    await source.close();
    await ownership.close();
  }
}
