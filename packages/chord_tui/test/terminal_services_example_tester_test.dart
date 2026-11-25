import 'dart:async';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../example/terminal_services.dart';

void main() {
  group('tester: service demo editor completion ownership', () {
    for (final failure in [false, true]) {
      testWidgets(
        'removed demo ignores late editor completion failure=$failure',
        (t) async {
          final directory = Directory.systemTemp.createTempSync(
            'service-tester-',
          );
          addTearDown(() => directory.deleteSync(recursive: true));
          final file = File('${directory.path}/sample.md');
          final terminal = _Terminal();
          await t.pumpWidget(
            TerminalServicesExample(terminal: terminal, file: file),
          );
          await t.press('ctrl+g ctrl+g');
          expect(terminal.calls, 1);
          await t.pumpWidget(const SizedBox());
          file.deleteSync();
          if (failure) {
            terminal.result.completeError(StateError('late editor failure'));
          } else {
            terminal.result.complete(0);
          }
          await t.pump();
          expect(t.screen.text, isEmpty);
          expect(file.existsSync(), isFalse);
        },
      );
    }
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('nonzero editor keeps original Unicode draft at $size', (
        t,
      ) async {
        final directory = Directory.systemTemp.createTempSync(
          'service-tester-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}/sample.md');
        final terminal = _Terminal();
        const draft = '界👩‍💻e\u0301\nsecond';
        await t.pumpWidget(
          TerminalServicesExample(
            terminal: terminal,
            file: file,
            initialText: draft,
          ),
          size: size,
        );
        await t.press('ctrl+g');
        file.writeAsStringSync('unusable changed file');
        terminal.result.complete(7);
        await t.pump();
        expect(t.screen, shows('Editor: exited 7'));
        await t.press('ctrl+y');
        expect(terminal.copied, draft);
        expect(t.screen, shows('super+left Move to row start'));
        expect(t.screen, shows('super+right Move to row end'));
      });
    }
  });
}

class _Terminal extends Terminal {
  final result = Completer<int>();
  var calls = 0;
  String? copied;
  @override
  Size get size => const Size(80, 24);
  @override
  Stream<String> get input => const Stream.empty();
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  void enter() {}
  @override
  Future<void> leave() async {}
  @override
  void write(String bytes) => throw StateError('No host effects');
  @override
  void copyToClipboard(String text) => copied = text;
  @override
  Future<int> runEditor(
    String path, {
    String? command,
    String? workingDirectory,
  }) {
    calls++;
    return result.future;
  }
}
