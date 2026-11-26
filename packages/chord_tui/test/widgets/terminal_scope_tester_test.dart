import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('CHD-638 tester: terminal scope replacement', () {
    testWidgets('a retained URI link follows a replaced scoped terminal', (
      t,
    ) async {
      final first = TestTerminal(), second = TestTerminal();
      final current = ValueNotifier(first);
      addTearDown(current.dispose);
      final link = Link(
        'Docs',
        uri: Uri.parse('https://example.com/docs'),
        autofocus: true,
      );
      await t.pumpWidget(
        ListenableBuilder(
          listenable: current,
          builder: (_) => TerminalScope(
            terminal: current.value,
            child: Align(alignment: Alignment.topLeft, child: link),
          ),
        ),
      );
      await t.press('enter');
      current.value = second;
      await t.pump();
      await t.press('enter');
      expect(first.openedUrls, ['https://example.com/docs']);
      expect(second.openedUrls, ['https://example.com/docs']);
      expect(t.terminal.openedUrls, isEmpty);
    });

    testWidgets('nested scopes keep URL and clipboard services local', (
      t,
    ) async {
      final outer = TestTerminal(), inner = TestTerminal();
      await t.pumpWidget(
        TerminalScope(
          terminal: outer,
          child: Column(
            children: [
              Builder(
                builder: (context) {
                  TerminalScope.of(context).copyToClipboard('outer');
                  return Text('outer');
                },
              ),
              TerminalScope(
                terminal: inner,
                child: Builder(
                  builder: (context) {
                    TerminalScope.of(context).copyToClipboard('inner');
                    return Link(
                      'Docs',
                      uri: Uri.parse('https://example.com'),
                      autofocus: true,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
      await t.press('enter');
      expect(outer.copied, ['outer']);
      expect(inner.copied, ['inner']);
      expect(inner.openedUrls, ['https://example.com']);
      expect(outer.openedUrls, isEmpty);
      expect(t.terminal.copied, isEmpty);
    });
  });
}
