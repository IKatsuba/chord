import 'dart:async';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../example/terminal_services.dart';

class _Terminal extends Terminal {
  final effects = <Object>[];
  final editorStarted = Completer<void>();
  final editorResult = Completer<int>();
  String? editedPath;
  @override
  Size get size => const Size(80, 24);
  @override
  Stream<String> get input => const Stream.empty();
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  void write(String data) =>
      throw StateError('No host effects in example tests');
  @override
  void enter() {}
  @override
  Future<void> leave() async {}
  @override
  void copyToClipboard(String text) => effects.add(('copy', text));
  @override
  void bell() => effects.add('bell');
  @override
  void setTitle(String title) => effects.add(('title', title));
  @override
  void notify(
    String message, {
    required NotificationChannel channel,
    String title = '',
  }) => effects.add(('notify', channel, title, message));
  @override
  Future<int> runEditor(
    String path, {
    String? command,
    String? workingDirectory,
  }) {
    editedPath = path;
    editorStarted.complete();
    return editorResult.future;
  }
}

Future<void> _settle(WidgetTester tester, String text) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!tester.screen.text.contains(text)) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Example did not show $text');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await tester.pump();
  }
}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'all service and Super help remains visible with semantic effects at $size',
      (t) async {
        final dir = Directory.systemTemp.createTempSync('service-example-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/sample.md');
        final terminal = _Terminal();
        await t.pumpWidget(
          TerminalServicesExample(terminal: terminal, file: file),
          size: size,
        );
        for (final key in [
          'ctrl+y',
          'ctrl+g',
          'ctrl+b',
          'ctrl+n',
          'ctrl+x n',
          'ctrl+t',
          'ctrl+q',
          'super+left',
          'super+right',
        ]) {
          expect(t.screen, shows(key));
        }
        expect(t.screen, shows('Editor: ready'));
        expect(t.screen, shows('Last key: none'));
        final focus = t.focusManager.primaryFocus;
        await t.press('ctrl+y ctrl+b ctrl+n ctrl+x n ctrl+t');
        expect(terminal.effects, [
          ('copy', serviceSample),
          'bell',
          (
            'notify',
            NotificationChannel.osc9,
            'Terminal services',
            'Sample is ready',
          ),
          (
            'notify',
            NotificationChannel.osc777,
            'Terminal services',
            'Sample is ready',
          ),
          ('title', 'Terminal services'),
        ]);
        await t.press('super+left');
        expect(t.screen, shows('Last key: super+left'));
        await t.press('super+right');
        expect(t.screen, shows('Last key: super+right'));
        await t.press('ctrl+g');
        await terminal.editorStarted.future;
        expect(file.readAsStringSync(), serviceSample);
        file.writeAsStringSync('$serviceSample\nscripted edit');
        terminal.editorResult.complete(0);
        await _settle(t, 'Editor: exited 0');
        expect(t.screen, shows('scripted edit'));
        expect(t.focusManager.primaryFocus, same(focus));
        await t.press('ctrl+y');
        expect(terminal.effects.last, (
          'copy',
          '$serviceSample\nscripted edit',
        ));
      },
    );
    testWidgets(
      'long draft leaves help visible and copy retains all text at $size',
      (t) async {
        final dir = Directory.systemTemp.createTempSync('service-long-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final terminal = _Terminal();
        final sample = 'long sample ' * 100;
        await t.pumpWidget(
          TerminalServicesExample(
            terminal: terminal,
            file: File('${dir.path}/sample.md'),
            initialText: sample,
          ),
          size: size,
        );
        for (final key in [
          'ctrl+y',
          'ctrl+g',
          'ctrl+b',
          'ctrl+n',
          'ctrl+x n',
          'ctrl+t',
          'ctrl+q',
          'super+left',
          'super+right',
        ]) {
          expect(t.screen, shows(key));
        }
        expect(t.screen.lines[1], endsWith('…'));
        await t.press('ctrl+y');
        expect(terminal.effects.single, ('copy', sample));
      },
    );
    for (final failure in [false, true]) {
      testWidgets('empty sample and editor failure=$failure at $size', (
        t,
      ) async {
        final dir = Directory.systemTemp.createTempSync('service-empty-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/sample.md');
        final terminal = _Terminal();
        await t.pumpWidget(
          TerminalServicesExample(
            terminal: terminal,
            file: file,
            initialText: '',
          ),
          size: size,
        );
        await t.press('ctrl+y');
        expect(terminal.effects.single, ('copy', ''));
        await t.press('ctrl+g');
        await terminal.editorStarted.future;
        expect(file.readAsStringSync(), '');
        terminal.editorResult.complete(failure ? 7 : 0);
        await _settle(t, 'Editor: exited ${failure ? 7 : 0}');
        await t.press('ctrl+y');
        expect(terminal.effects.last, ('copy', ''));
      });
    }
  }
}
