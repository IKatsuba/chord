import 'package:chord_site/article.dart';
import 'package:chord_site/site.dart';
import 'package:chord_site/sources.g.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../web/gallery.dart';
import 'fake_host.dart';

Future<FakeHost> _open(WidgetTester t, String path, Size size) async {
  final host = FakeHost(path);
  await t.pumpWidget(
    Site(host: host, gallery: siteGallery),
    size: size,
  );
  await t.pump();
  return host;
}

int _row(WidgetTester t, Pattern text) =>
    t.screen.lines.indexWhere((l) => l.contains(text));

Future<int> _seek(WidgetTester t, Pattern text) async {
  for (var i = 0; i < 300 && _row(t, text) < 0; i++) {
    await t.press('down');
  }
  return _row(t, text);
}

void main() {
  _backWhileEntered();
  _reviewFixes();
  _resizeKeepsDraft();
  test('the index shows from 110 columns, the margin from 150', () {
    expect(articleIndexWidth, 110);
    expect(articleMarginWidth, 150);
    expect((indexColumns, articleMeasure, marginColumns), (26, 72, 22));
  });

  for (final (size, rail) in const [
    (Size(192, 56), true),
    (Size(150, 50), true),
    (Size(120, 40), false),
  ]) {
    testWidgets(
      'the index column beside the article${rail ? ', and the '
                'margin' : ''}, at $size',
      (t) async {
        await _open(t, '/chord_tui/markdown', size);
        final head = _row(t, '02 / FRAMEWORK');
        final line = t.screen.lines[head];
        expect(line.indexOf('02 / FRAMEWORK'), 4);
        expect(line.indexOf('02 / FRAMEWORK / GALLERY'), 34);
        expect(t.screen, shows('[ ] PREVIOUS, NEXT'));
        // The current page: its number green, its name ink on cream.
        final current = _row(t, '02  MARKDOWN');
        expect(
          t.screen.styleAt(4, current),
          ThemeData.dark().accent.merge(Style.bold),
        );
        expect(
          t.screen.styleAt(8, current),
          ThemeData.dark().text.merge(const Style(bold: true, inverse: true)),
        );
        expect(
          t.screen.styleAt(8, _row(t, '03  PICKER')),
          ThemeData.dark().text,
        );
        expect(t.screen.styleAt(8, _row(t, '03  PICKER')).isInverse, isFalse);
        if (rail) {
          expect(t.screen.lines[head].indexOf('ON THIS PAGE'), 34 + 72 + 6);
          expect(t.screen, shows('{ } SECTIONS'));
        } else {
          expect(t.screen, isNot(shows('ON THIS PAGE')));
        }
        expect(t.screen, isNot(shows('PAGES ▾')));
      },
    );
  }

  for (final size in const [Size(80, 24), Size(54, 56)]) {
    testWidgets('below 110 the index folds into a bar; p lists the pages, '
        'at $size', (t) async {
      final host = await _open(t, '/chord_tui/markdown', size);
      final bar = t.screen.lines[5];
      expect(
        bar,
        startsWith('${' ' * (size.width < 60 ? 2 : 4)}02 / MARKDOWN'),
      );
      expect(bar.trimRight(), endsWith('PAGES ▾ p'));
      expect(t.screen.lines[6], startsWith('─' * (size.width - 1)));
      expect(t.screen, isNot(shows('[ ] PREVIOUS, NEXT')));
      await t.press('p');
      expect(t.screen, shows('❯ 02  MARKDOWN'));
      await t.press('down');
      await t.press('enter');
      expect(host.pushed, ['/chord_tui/picker']);
    });
  }

  testWidgets('Esc and p close the folded list without opening a page', (
    t,
  ) async {
    final host = await _open(t, '/chord_tui', const Size(80, 24));
    for (final close in ['esc', 'p']) {
      await t.press('p');
      expect(t.screen, shows('❯ 00  OVERVIEW'));
      await t.press(close);
      expect(t.screen, isNot(shows('❯ 00  OVERVIEW')));
    }
    expect(host.pushed, isEmpty);
  });

  testWidgets('[ and ] move through Overview and the nine examples', (t) async {
    final host = await _open(t, '/chord_tui', const Size(120, 40));
    await t.press('[');
    expect(host.pushed, isEmpty, reason: 'nothing before Overview');
    await t.press(']');
    expect(host.pushed, ['/chord_tui/demo']);
    await t.press(']');
    expect(host.pushed.last, '/chord_tui/markdown');
    await t.press('[');
    await t.press('[');
    expect(host.pushed.last, '/chord_tui');
    final last = await _open(t, '/chord_tui/mouse', const Size(120, 40));
    await t.press(']');
    expect(last.pushed, isEmpty, reason: 'nothing after Mouse');
    await t.press('end');
    expect(t.screen, shows('[  ← 08 LAYERS'));
    expect(t.screen, isNot(shows('→  ]')));
  });

  testWidgets('the pager names its neighbours in green, and a tap opens '
      'one', (t) async {
    final host = await _open(t, '/chord_tui/markdown', const Size(120, 40));
    await t.press('end');
    final row = _row(t, '[  ← 01 DEMO');
    expect(t.screen.lines[row], contains('03 PICKER →  ]'));
    expect(
      t.screen.styleAt(t.screen.lines[row].indexOf('03 PICKER'), row),
      ThemeData.dark().accent.merge(Style.bold),
    );
    final x = t.screen.lines[row].indexOf('03 PICKER');
    await t.mouse(
      MouseEvent(
        MouseEventKind.press,
        position: Offset(x, row),
        button: MouseButton.primary,
      ),
    );
    expect(host.pushed, ['/chord_tui/picker']);
  });

  testWidgets('{ and } go from head to head, and the margin marks the one '
      'the view is in', (t) async {
    await _open(t, '/chord_tui', const Size(192, 56));
    final dark = ThemeData.dark();
    int rail(String head) => _row(t, RegExp('\\d\\d $head'));
    expect(
      t.screen.styleAt(
        t.screen.lines[rail('WHAT IT IS')].lastIndexOf('WHAT'),
        rail('WHAT IT IS'),
      ),
      dark.text.merge(Style.bold),
    );
    await t.press('}');
    await t.pump();
    // The head lands on the view's top row, under the nav.
    expect(t.screen.lines[4], contains('02  THE EXAMPLE'));
    final y = rail('THE EXAMPLE');
    expect(
      t.screen.styleAt(t.screen.lines[y].lastIndexOf('THE EXAMPLE'), y),
      dark.text.merge(Style.bold),
    );
    final w = rail('WHAT IT IS');
    expect(
      t.screen.styleAt(t.screen.lines[w].lastIndexOf('WHAT'), w),
      dark.dim,
    );
    await t.press('{');
    await t.pump();
    expect(t.screen.lines[4], contains('01  WHAT IT IS'));
  });

  testWidgets('c copies the topmost code block whose header is in view, and '
      'only it says COPY c', (t) async {
    await _open(t, '/chord_tui', const Size(120, 40));
    final main = await _seek(t, 'example/main.dart');
    expect(t.screen.lines[main], contains('COPY c'));
    await t.press('c');
    expect(t.terminal.copied, [exampleSources['main']]);
    expect(t.screen.lines[_row(t, 'example/main.dart')], contains('COPIED'));
    final testing = await _seek(t, 'test/dialog_test.dart');
    // The block above has scrolled out of view: this one owns c now.
    expect(t.screen, isNot(shows('example/main.dart ')));
    expect(t.screen.lines[testing], contains('COPY c'));
    await t.press('c');
    expect(t.terminal.copied.last, testingSource);
  });
}

void _backWhileEntered() {
  testWidgets('back while an example is entered leaves it, and the next '
      'page has the shell keys again', (t) async {
    final host = FakeHost('/chord_tui/text_area');
    await t.pumpWidget(
      Site(host: host, gallery: siteGallery),
      size: const Size(120, 40),
    );
    await t.pump();
    await t.press('tab');
    host.popped.add('/install');
    await t.pump();
    await t.pump();
    expect(t.screen, shows('INSTALL'));
    await t.press('1');
    expect(host.pushed, ['/chord']);
  });
}

void _reviewFixes() {
  testWidgets('a draft in the text area survives the page list opening and '
      'closing over it', (t) async {
    final host = FakeHost('/chord_tui/text_area');
    await t.pumpWidget(
      Site(host: host, gallery: siteGallery),
      size: const Size(80, 40),
    );
    await t.pump();
    await t.press('tab');
    await t.type('draft');
    await t.press('esc');
    await t.press('p');
    expect(t.screen, shows('❯ 05  TEXT AREA'));
    // The open list keeps the keys from the page under it.
    await t.press(']');
    expect(host.pushed, isEmpty);
    await t.press('esc');
    expect(t.screen, isNot(shows('❯ 05  TEXT AREA')));
    await t.press('tab');
    await t.type('ed');
    expect(t.screen, shows('drafted'));
  });

  for (final entered in [false, true]) {
    testWidgets(
      'the wheel over the plate ${entered ? 'stays in the entered '
                'example' : 'scrolls the page'}',
      (t) async {
        final host = FakeHost('/chord_tui/mouse');
        await t.pumpWidget(
          Site(host: host, gallery: siteGallery),
          size: const Size(120, 40),
        );
        await t.pump();
        if (entered) await t.press('tab');
        final y = _row(t, 'Pointer events');
        final before = t.screen.lines[4];
        await t.mouse(
          MouseEvent(
            MouseEventKind.wheel,
            position: Offset(60, y + 2),
            scrollDelta: const Offset(0, 2),
          ),
        );
        await t.pump();
        if (entered) {
          expect(t.screen.lines[4], before, reason: 'the page did not move');
          expect(t.screen, shows('wheel'));
        } else {
          expect(t.screen.lines[4], isNot(before));
        }
      },
    );
  }
}

void _resizeKeepsDraft() {
  for (final (from, to) in const [
    (Size(117, 40), Size(80, 40)),
    (Size(80, 40), Size(117, 40)),
    (Size(160, 40), Size(54, 56)),
  ]) {
    testWidgets('a draft survives the index folding or unfolding, '
        '${from.width} to ${to.width} columns', (t) async {
      await t.pumpWidget(
        Site(host: FakeHost('/chord_tui/text_area'), gallery: siteGallery),
        size: from,
      );
      await t.pump();
      await t.press('tab');
      await t.type('draft');
      await t.press('esc');
      await t.resize(to);
      await t.press('tab');
      await t.type('ed');
      expect(t.screen, shows('drafted'));
      await t.press('esc');
      await t.resize(from);
      await t.press('tab');
      await t.type('!');
      expect(t.screen, shows('drafted!'));
    });
  }
}
