// The background's summary line as the original's Background.tsx draws it:
// the label dim, or bold with the ❯ while it has the list's keys; a group
// asking in the warning colour, failed in the error one, done in the
// success one, the rest dim; wrapped between groups under the first.
import 'package:chord/ui/background/background.dart';
import 'package:chord/ui/background/summary_line.dart';
import 'package:chord/ui/theme/theme.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

BackgroundItem _item(BackgroundKind kind, ItemStatus status) => BackgroundItem(
  kind: kind,
  id: 'x',
  key: 1,
  name: 'x',
  startedAt: 0,
  status: status,
);

final _items = [
  _item(BackgroundKind.task, const ItemAsking(AskingOn.permission, 0)),
  _item(BackgroundKind.monitor, const ItemEnded(BackgroundGroup.failed, 0)),
  _item(BackgroundKind.monitor, const ItemRunning()),
  _item(BackgroundKind.task, const ItemEnded(BackgroundGroup.done, 0)),
];

void main() {
  final palette = paletteOf('dark', true);
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('its groups in their colours, the ❯ while focused at $size', (
      t,
    ) async {
      Future<List<String>> draw(bool focused) async {
        await t.pumpWidget(
          Column(
            children: [
              SummaryLine(items: _items, focused: focused, palette: palette),
            ],
          ),
          size: size,
        );
        return [
          for (final row in t.screen.lines)
            if (row.trim().isNotEmpty) row.trimRight(),
        ];
      }

      final rows = await draw(false);
      expect(
        rows.map((r) => r.trim()).join(' '),
        'background  ● 1 task asking · ✗ 1 monitor failed · 1 monitor '
        'running · ✓ 1 task done',
      );
      expect(rows.first, startsWith('    background  ● 1 task asking'));
      expect(rows.length, summaryLineCount(_items, size.width.toInt()));
      expect(t.screen.styleAt(4, 0).isDim, isTrue);
      final asking = rows.first.indexOf('●');
      expect(t.screen.styleAt(asking, 0).fg, colorOf(palette.warning!));
      final failed = rows.first.indexOf('✗');
      if (failed >= 0) {
        expect(t.screen.styleAt(failed, 0).fg, colorOf(palette.error!));
      }
      await draw(true);
      expect(t.screen.lines.first, startsWith('  ❯ background'));
      expect(t.screen.styleAt(4, 0).isBold, isTrue);
      expect(t.screen.styleAt(2, 0).fg, colorOf(palette.permission!));
      // Nothing to count: nothing drawn.
      await t.pumpWidget(
        SummaryLine(items: const [], focused: true, palette: palette),
        size: size,
      );
      expect(t.screen.text.trim(), isEmpty);
      expect(summaryLineCount(const [], 80), 0);
    });
  }

  group('CTUI-36 tester: summary lifetime and selection', () {
    testWidgets('zero and narrow room resize restores current summary counts', (
      t,
    ) async {
      final items = ValueNotifier<List<BackgroundItem>>(_items);
      addTearDown(items.dispose);
      final widget = ListenableBuilder(
        listenable: items,
        builder: (_) =>
            SummaryLine(items: items.value, focused: true, palette: palette),
      );
      for (final size in const [Size(0, 0), Size(1, 1), Size(12, 24)]) {
        await t.pumpWidget(widget, size: size);
      }
      for (var i = 0; i < 1000; i++) {
        items.value = [_item(BackgroundKind.monitor, const ItemRunning())];
      }
      await t.resize(const Size(80, 24));
      await t.pump();
      expect(t.screen.text, contains('❯ background  1 monitor running'));
      expect(t.screen.text, isNot(contains('task')));
      await t.resize(const Size(120, 40));
      await t.pump();
      expect(t.screen.text, contains('1 monitor running'));
      items.value = [];
      await t.pump();
      expect(t.screen.text.trim(), isEmpty);
    });

    testWidgets('dragging over the summary selects none of its furniture', (
      t,
    ) async {
      final selection = SelectionController();
      addTearDown(selection.dispose);
      await t.pumpWidget(
        SelectionArea(
          controller: selection,
          selectionStyle: const Style(inverse: true),
          child: SummaryLine(items: _items, focused: false, palette: palette),
        ),
        size: const Size(120, 40),
      );
      for (final (kind, at) in [
        (MouseEventKind.press, const Offset(4, 0)),
        (MouseEventKind.move, const Offset(100, 1)),
        (MouseEventKind.release, const Offset(100, 1)),
      ]) {
        t.host.handleMouse(
          MouseEvent(kind, position: at, button: MouseButton.primary),
        );
      }
      expect(selection.snapshot()?.text ?? '', '');
    });
  });
}
