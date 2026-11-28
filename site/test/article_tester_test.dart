import 'package:chord_site/article.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../web/gallery.dart';
import 'fake_host.dart';

void main() {
  group('CHD-638 tester: entered article state across layout boundaries', () {
    for (final from in const [Size(109, 40), Size(150, 40)]) {
      testWidgets('an entered draft survives both rails and a help overlay '
          'from $from', (t) async {
        final host = FakeHost('/chord_tui/text_area');
        addTearDown(host.popped.close);
        await t.pumpWidget(
          Site(host: host, gallery: siteGallery),
          size: from,
        );
        await t.press('tab');
        const draft = '界🙂e\u0301 sp12[]{}?';
        await t.type(draft);
        var suffix = '';
        for (final size in const [
          Size(110, 40),
          Size(149, 40),
          Size(150, 40),
          Size(205, 56),
          Size(55, 52),
          Size(80, 24),
          Size(109, 40),
        ]) {
          await t.resize(size);
          await t.type('x');
          suffix += 'x';
          expect(t.screen, shows('$draft$suffix'));
        }
        await t.press('f1');
        await t.type('unreached');
        await t.resize(const Size(150, 40));
        await t.press('f1');
        await t.type('!');
        expect(t.screen, shows('$draft$suffix!'));
        expect(t.screen, isNot(shows('unreached')));
        expect(host.pushed, isEmpty);
        expect(host.opened, isEmpty);
        expect(t.terminal.copied, isEmpty);
      });
    }

    testWidgets('a folded index resized away keeps its draft and restores '
        'entry', (t) async {
      final host = FakeHost('/chord_tui/text_area');
      addTearDown(host.popped.close);
      await t.pumpWidget(
        Site(host: host, gallery: siteGallery),
        size: const Size(55, 52),
      );
      await t.press('tab');
      await t.type('kept');
      await t.press('esc');
      await t.press('p');
      await t.press('down');
      expect(t.screen, shows('❯ 06  DIFF'));
      await t.resize(const Size(110, 40));
      expect(t.screen, isNot(shows('❯ 06  DIFF')));
      await t.press('tab');
      await t.type('!');
      expect(t.screen, shows('kept!'));
      await t.resize(const Size(109, 40));
      await t.press('esc');
      await t.press('p');
      expect(t.screen, shows('❯ 05  TEXT AREA'));
      await t.press('esc');
      await t.press('tab');
      await t.type('?');
      expect(t.screen, shows('kept!?'));
      expect(host.pushed, isEmpty);
    });
  });

  group('CHD-638 tester: article copy ownership lifetime', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('copy targets change with scroll and feedback timers end '
          'on removal at $size', (t) async {
        const first = '界🙂e\u0301\x1b[31m first';
        const second = 'second\nline';
        await t.pumpWidget(
          ArticlePage(
            pages: (names: ['OVERVIEW'], open: (_) {}),
            page: 0,
            heading: const [],
            sections: [
              (
                head: 'first',
                children: [
                  const CodeBlock(label: 'first.dart', source: first),
                  const SizedBox(height: 60),
                ],
              ),
              (
                head: 'second',
                children: [
                  const CodeBlock(label: 'second.dart', source: second),
                ],
              ),
            ],
          ),
          size: size,
        );
        expect(t.screen, shows('COPY c'));
        await t.press('c');
        expect(t.terminal.copied, [first]);
        expect(t.screen, shows('COPIED'));
        await t.press('end');
        expect(t.screen, shows('second.dart'));
        await t.press('c');
        expect(t.terminal.copied, [first, second]);
        await t.pumpWidget(Text('removed'));
        await t.pump(const Duration(milliseconds: 2100));
        expect(t.screen.text, 'removed');
        expect(t.terminal.copied, [first, second]);
      });
    }
  });
}
