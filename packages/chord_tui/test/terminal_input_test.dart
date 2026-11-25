import 'dart:async';
import 'dart:convert';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

class MemoryStdio extends StdioTerminal {
  MemoryStdio(this.source) : super(input: source.stream);
  final StreamController<List<int>> source;
  int enters = 0;
  int leaves = 0;
  final output = StringBuffer();
  @override
  Size get size => const Size(80, 24);
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  void enter() => enters++;
  @override
  Future<void> leave() async {
    leaves++;
  }

  @override
  void write(String data) {
    output.write(data);
    if (data == '\x1b]11;?\x07') {
      source.add(utf8.encode('\x1b]11;rgb:0000/0000/0000\x07'));
    } else if (data.contains('stage')) {
      source.add(utf8.encode('$enters'));
    }
  }
}

void main() {
  test(
    'caller-owned input serves consecutive apps then closes its source subscription',
    () async {
      var canceled = 0;
      var paused = 0;
      var resumed = 0;
      final source = StreamController<List<int>>(
        onCancel: () {
          canceled++;
        },
        onPause: () {
          paused++;
        },
        onResume: () {
          resumed++;
        },
      );
      final terminal = MemoryStdio(source);
      final keys = <String>[];
      for (var i = 1; i <= 2; i++) {
        await runApp(
          Builder(
            builder: (context) => Actions(
              bindings: [
                Binding('$i', 'Finish stage $i', () {
                  keys.add('$i');
                  exitApp(context);
                }),
              ],
              child: Focus(autofocus: true, child: Text('stage $i')),
            ),
          ),
          terminal: terminal,
          exitProcess: false,
          environment: const {'NO_COLOR': '1'},
        ).timeout(const Duration(seconds: 3));
        expect(canceled, 0);
      }
      expect(keys, ['1', '2']);
      expect(terminal.enters, 2);
      expect(terminal.leaves, 2);
      expect(terminal.output.toString(), contains('stage 1'));
      expect(terminal.output.toString(), contains('stage 2'));
      expect(paused, greaterThanOrEqualTo(2));
      expect(resumed, greaterThanOrEqualTo(1));
      await terminal.close();
      await terminal.close();
      expect(canceled, 1);
      expect(() => terminal.input, throwsStateError);
      await source.close().timeout(const Duration(seconds: 1));
    },
  );
  for (final listened in [false, true]) {
    test(
      'cached input cannot reconnect after close, previously listened: $listened',
      () async {
        var connections = 0;
        var cancellations = 0;
        final source = StreamController<List<int>>(
          onListen: () {
            connections++;
          },
          onCancel: () {
            cancellations++;
          },
        );
        final terminal = StdioTerminal(input: source.stream);
        final cached = terminal.input;
        if (listened) {
          final subscription = cached.listen((_) {});
          await subscription.cancel();
        }
        await terminal.close();
        source.add(utf8.encode('late'));
        expect(
          await cached.toList().timeout(const Duration(seconds: 1)),
          isEmpty,
        );
        await terminal.close();
        expect(connections, listened ? 1 : 0);
        expect(cancellations, listened ? 1 : 0);
        if (!listened) {
          final drain = source.stream.drain<void>();
          await source.close();
          await drain;
        } else {
          await source.close();
        }
      },
    );
  }
  test(
    'closing unused input is idempotent and does not consume the caller source',
    () async {
      final source = StreamController<List<int>>();
      final terminal = StdioTerminal(input: source.stream);
      await terminal.close();
      await terminal.close();
      expect(() => terminal.input, throwsStateError);
      final done = source.stream.drain<void>();
      await source.close();
      await done;
    },
  );
}
