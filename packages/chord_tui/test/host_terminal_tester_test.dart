import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/terminal/host_terminal.dart';
import 'package:test/test.dart';

const _enter = '\x1b[?1049h\x1b[?25l\x1b[?2004h';
const _mouseOn = '\x1b[?1000h\x1b[?1002h\x1b[?1006h';
const _mouseOff = '\x1b[?1000l\x1b[?1002l\x1b[?1006l';
const _leave = '\x1b[?2004l\x1b[0m\x1b[0 q\x1b[?25h\x1b[?1049l';

void main() {
  group('tester: host restoration failure boundaries', () {
    for (final (label, failing) in [
      ('mouse', {_mouseOff}),
      ('screen', {_leave}),
      ('both', {_mouseOff, _leave}),
    ]) {
      test(
        'attempts every restore, preserves the first error: $label',
        () async {
          final writes = <String>[];
          final first = StateError('first restore');
          final second = StateError('second restore');
          final stack = StackTrace.fromString('tester restore stack');
          var throwing = true;
          final terminal = HostTerminal(
            write: (bytes) {
              writes.add(bytes);
              if (throwing && failing.contains(bytes)) {
                Error.throwWithStackTrace(
                  bytes == _mouseOff || !failing.contains(_mouseOff)
                      ? first
                      : second,
                  stack,
                );
              }
            },
            input: const Stream.empty(),
            size: () => const Size(80, 24),
            resizes: const Stream.empty(),
            mouse: true,
          );
          terminal.enter();
          Object? caught;
          StackTrace? caughtStack;
          try {
            await terminal.leave();
          } catch (error, trace) {
            caught = error;
            caughtStack = trace;
          }
          expect(caught, same(first));
          expect(caughtStack.toString(), contains('tester restore stack'));
          expect(writes, [_enter, _mouseOn, _mouseOff, _leave]);
          await terminal.leave();
          expect(writes, hasLength(4));
          throwing = false;
          terminal.enter();
          await terminal.leave();
          expect(writes.skip(4), [_enter, _mouseOn, _mouseOff, _leave]);
        },
      );
    }

    for (final (label, failsAt) in [('screen', _enter), ('mouse', _mouseOn)]) {
      test(
        'partial enter still permits complete restoration: $label',
        () async {
          final writes = <String>[];
          final error = StateError('enter failed');
          final terminal = HostTerminal(
            write: (bytes) {
              writes.add(bytes);
              if (bytes == failsAt) throw error;
            },
            input: const Stream.empty(),
            size: () => const Size(1, 1),
            resizes: const Stream.empty(),
            mouse: true,
          );
          expect(terminal.enter, throwsA(same(error)));
          await terminal.leave();
          expect(writes.sublist(writes.length - 2), [_mouseOff, _leave]);
        },
      );
    }
  });

  group('tester: host data and run ownership', () {
    test(
      'preserves Unicode and escape bytes and zero or one cell sizes',
      () async {
        final input = StreamController<String>.broadcast();
        final resizes = StreamController<Size>.broadcast();
        addTearDown(input.close);
        addTearDown(resizes.close);
        var size = Size.zero;
        final output = <String>[];
        final terminal = HostTerminal(
          write: output.add,
          input: input.stream,
          size: () => size,
          resizes: resizes.stream,
        );
        const text = '界🙂e\u0301\x1b[31m\x1b]11;literal\x07';
        final nextInput = terminal.input.first;
        input.add(text);
        expect(await nextInput, text);
        terminal.write(text);
        expect(output, [text]);
        for (final next in [Size.zero, const Size(1, 1), const Size(120, 40)]) {
          final resized = terminal.resizes.first;
          size = next;
          resizes.add(next);
          expect(await resized, next);
          expect(terminal.size, next);
        }
      },
    );

    test(
      'a burst and resize reach the current run and listeners leave with it',
      () async {
        final input = StreamController<String>.broadcast();
        final resizes = StreamController<Size>.broadcast();
        addTearDown(input.close);
        addTearDown(resizes.close);
        final written = <String>[];
        var size = const Size(120, 40);
        final terminal = HostTerminal(
          write: written.add,
          input: input.stream,
          size: () => size,
          resizes: resizes.stream,
          mouse: true,
        );
        for (var run = 0; run < 2; run++) {
          final mounted = Completer<void>();
          final received = Completer<void>();
          final resized = Completer<void>();
          final pasted = Completer<String>();
          var count = 0;
          final running = runApp(
            Focus(
              autofocus: true,
              onKey: (event) {
                if (event.combo.toString() != 'a') return false;
                if (++count == 1000) received.complete();
                return true;
              },
              onPaste: (text) {
                pasted.complete(text);
                return true;
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (!mounted.isCompleted) mounted.complete();
                  if (constraints.maxWidth == 80 && !resized.isCompleted) {
                    resized.complete();
                  }
                  return Text('界🙂e\u0301');
                },
              ),
            ),
            terminal: terminal,
            exitProcess: false,
            handleSignals: false,
            environment: const {},
          );
          await mounted.future.timeout(const Duration(seconds: 5));
          input.add('a' * 1000);
          await received.future.timeout(const Duration(seconds: 5));
          const paste = '界🙂e\u0301\x1b[31m';
          input.add('\x1b[200~$paste\x1b[201~');
          expect(
            await pasted.future.timeout(const Duration(seconds: 5)),
            paste,
          );
          size = const Size(80, 24);
          resizes.add(size);
          await resized.future.timeout(const Duration(seconds: 5));
          input.add('\x03');
          await running.timeout(const Duration(seconds: 5));
          expect(count, 1000);
          expect(input.hasListener, isFalse);
          expect(resizes.hasListener, isFalse);
          expect(written.last, _leave);
          size = const Size(120, 40);
        }
        expect(written.where((s) => s == _mouseOn), hasLength(2));
        expect(written.where((s) => s == _mouseOff), hasLength(2));
      },
    );
  });
}
