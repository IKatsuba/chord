import 'package:chord/ui/transcript/scroll.dart' as port;
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('tester U3 scroll presentation boundaries', () {
    test(
      'covered row remains counted at zero one and resized view heights',
      () {
        for (final (content, view, top, expected) in [
          (0, 0, 0, 1),
          (1, 1, 0, 1),
          (100, 0, 0, 101),
          (100, 1, 0, 100),
          (100, 24, 10, 67),
          (100, 40, 10, 51),
          (10, 40, 0, 1),
          (100, 24, 76, 1),
        ]) {
          expect(
            port.rowsBelow(ScrollState(content: content, view: view, top: top)),
            expected,
          );
        }
        expect(
          port.indicator(
            const ScrollState(following: true, news: true),
            0,
            'end',
          ),
          isEmpty,
        );
      },
    );

    test('hint appears only with room for a trailing rule cell', () {
      const scroll = ScrollState(content: 50, view: 24, top: 0);
      for (final key in ['end', '界👩‍💻e\u0301']) {
        final text = port.indicator(scroll, 200, key).map((s) => s.text).join();
        final whole = text.substring(0, text.lastIndexOf(' ') + 1);
        final exact = cellWidth(whole);
        expect(
          port.indicator(scroll, exact, key).map((s) => s.text).join(),
          isNot(contains('jump to the bottom')),
        );
        final enough = port
            .indicator(scroll, exact + 1, key)
            .map((s) => s.text)
            .join();
        expect(enough, contains('$key to jump to the bottom'));
        expect(cellWidth(enough), exact + 1);
      }
    });

    test('news accents only its phrase at both widths and tiny widths', () {
      const scroll = ScrollState(content: 100, view: 24, news: true);
      for (final width in [0, 1, 80, 120]) {
        final segments = port.indicator(scroll, width, null);
        expect(segments.where((s) => s.accent).map((s) => s.text), [
          '↓ new output',
        ]);
        final line = segments.map((s) => s.text).join();
        expect(line, contains('77 lines below'));
        expect(line, isNot(contains('jump')));
        if (width >= 80) expect(cellWidth(line), width);
      }
    });

    test(
      'key configuration includes shifted aliases and reserves plain arrows',
      () {
        final keys = port.chordScrollKeys;
        expect(keys.pageUp, ['pageup', 'shift+pageup']);
        expect(keys.pageDown, ['pagedown', 'shift+pagedown']);
        expect(keys.lineUp, ['shift+up']);
        expect(keys.lineDown, ['shift+down']);
        expect(keys.top, ['home', 'shift+home']);
        expect(keys.bottom, ['end', 'shift+end']);
        final all = [
          ...keys.pageUp,
          ...keys.pageDown,
          ...keys.lineUp,
          ...keys.lineDown,
          ...keys.top,
          ...keys.bottom,
        ];
        expect(all.toSet(), hasLength(all.length));
        expect(all, isNot(contains('up')));
        expect(all, isNot(contains('down')));
      },
    );
  });
}
