import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/terminal/host_terminal.dart';
import 'package:test/test.dart';

const _enter = '\x1b[?1049h\x1b[?25l\x1b[?2004h';
const _mouseOn = '\x1b[?1000h\x1b[?1002h\x1b[?1006h';
const _mouseOff = '\x1b[?1000l\x1b[?1002l\x1b[?1006l';
const _leave = '\x1b[?2004l\x1b[0m\x1b[0 q\x1b[?25h\x1b[?1049l';

class _Host {
  final written = <String>[];
  final input = StreamController<String>.broadcast();
  final resizes = StreamController<Size>.broadcast();
  var size = const Size(20, 3);

  HostTerminal terminal({bool mouse = false}) => HostTerminal(
    write: written.add,
    input: input.stream,
    size: () => size,
    resizes: resizes.stream,
    mouse: mouse,
  );
}

void main() {
  test('enter takes the screen and leave gives it back', () async {
    final host = _Host();
    final terminal = host.terminal();
    terminal.enter();
    terminal.enter();
    expect(host.written, [_enter]);
    await terminal.leave();
    await terminal.leave();
    expect(host.written, [_enter, _leave]);
  });

  test('with mouse it asks for SGR reports and stops them first', () async {
    final host = _Host();
    final terminal = host.terminal(mouse: true);
    terminal.enter();
    await terminal.leave();
    expect(host.written, [_enter, _mouseOn, _mouseOff, _leave]);
  });

  test('leave before enter writes nothing', () async {
    final host = _Host();
    await host.terminal().leave();
    expect(host.written, isEmpty);
  });

  test('suspend and runEditor are refused: there is no process', () async {
    final terminal = _Host().terminal();
    var ran = false;
    await expectLater(
      terminal.suspend(() async => ran = true),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('no process'),
        ),
      ),
    );
    expect(ran, isFalse);
    await expectLater(
      terminal.runEditor('notes.md'),
      throwsA(isA<StateError>()),
    );
  });

  test('runApp draws on the host, follows its resizes and quits', () async {
    final host = _Host();
    final run = runApp(
      LayoutBuilder(
        builder: (context, constraints) =>
            Text('${constraints.maxWidth}x${constraints.maxHeight}'),
      ),
      terminal: host.terminal(),
      exitProcess: false,
      handleSignals: false,
      environment: const {},
    );
    await _until(() => host.written.join().contains('20x3'));
    host.size = const Size(30, 4);
    host.resizes.add(host.size);
    await _until(() => host.written.join().contains('30x4'));
    host.input.add('\x03');
    await run.timeout(const Duration(seconds: 5));
    expect(host.written.first, _enter);
    expect(host.written.last, _leave);
  });
}

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
