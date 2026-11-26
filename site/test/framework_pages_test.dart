import 'package:chord_site/pages/chord_tui.dart';
import 'package:chord_site/pages/framework_text.dart';
import 'package:chord_site/site.dart';
import 'package:chord_site/sources.g.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../web/gallery.dart';
import 'fake_host.dart';

const _sizes = [Size(120, 40), Size(80, 24)];

int _row(WidgetTester t, Pattern text) =>
    t.screen.lines.indexWhere((l) => l.contains(text));

Future<int> _seek(WidgetTester t, Pattern text) async {
  for (var i = 0; i < 400 && _row(t, text) < 0; i++) {
    await t.press('down');
  }
  return _row(t, text);
}

Future<FakeHost> _open(WidgetTester t, String path, Size size) async {
  final host = FakeHost(path);
  await t.pumpWidget(
    Site(host: host, gallery: siteGallery),
    size: size,
  );
  await t.pump();
  return host;
}

void main() {
  test('the index names Overview and the nine, in the gallery\'s order', () {
    expect(articleNames(siteGallery), [
      'OVERVIEW',
      'DEMO',
      'MARKDOWN',
      'PICKER',
      'FORM',
      'TEXT AREA',
      'DIFF',
      'DIALOG',
      'LAYERS',
      'MOUSE',
    ]);
    for (final e in siteGallery.entries) {
      expect(exampleLedes, contains(e.name));
      expect(exampleKeys, contains(e.name));
    }
  });

  for (final size in _sizes) {
    testWidgets('the overview: TUI., the lede, its four sections and the '
        'pager, at $size', (t) async {
      await _open(t, '/chord_tui', size);
      expect(t.screen, shows(RegExp('[█▀▄]')));
      for (final text in [
        'The Flutter way, for the terminal',
        '01  WHAT IT IS',
        'If you know Flutter you know the names',
        '02  THE EXAMPLE',
        "FIG. 1 README'S EXAMPLE · TAB TO ENTER",
        '▸ Run checks',
        'example/main.dart',
        '03  TESTING',
        'test/dialog_test.dart',
        '04  WHERE NEXT',
        'GALLERY →  3',
        'API DOCS ↗  d',
        'SOURCE ↗  s',
        pubAddCommand,
        '01 DEMO →  ]',
      ]) {
        expect(await _seek(t, text), greaterThanOrEqualTo(0), reason: text);
      }
    });
  }

  testWidgets('the overview\'s keys: d and s open the docs and the source, '
      'listed in the panel only; Tab enters README\'s example', (t) async {
    final host = await _open(t, '/chord_tui', const Size(120, 40));
    expect(t.screen.lines.last, isNot(contains('API docs')));
    await t.press('d');
    await t.press('s');
    expect(host.opened, [apiDocsUrl, frameworkSourceUrl]);
    await t.press('f1');
    expect(t.screen, shows(RegExp(r'd\s+API docs')));
    expect(t.screen, shows(RegExp(r's\s+source')));
    await t.press('f1');
    await t.press('tab');
    await t.press('ctrl+o');
    await _seek(t, 'Run checks');
    expect(t.screen, shows('▾ Run checks'));
  });

  testWidgets('the overview\'s install card copies dart pub add', (t) async {
    await _open(t, '/chord_tui', const Size(120, 40));
    await t.press('end');
    final row = await _seek(t, pubAddCommand);
    expect(t.screen.lines[row], contains('COPY c'));
    await t.press('c');
    expect(t.terminal.copied, [pubAddCommand]);
  });

  for (final entry in siteGallery.entries) {
    for (final size in _sizes) {
      testWidgets('${entry.name}: its name, lede, live plate, keys and '
          'source, at $size', (t) async {
        await _open(t, '/chord_tui/${entry.name}', size);
        final title = entry.title.toUpperCase();
        // The title, alone on its row, over its orange rule.
        String bare(int y) => t.screen.lines[y].replaceAll('┃', '').trim();
        var name = -1;
        for (var i = 0; i < 60 && name < 0; i++) {
          for (var y = 0; y < t.screen.lines.length - 1; y++) {
            if (bare(y) == title && bare(y + 1) == '━' * title.length) {
              name = y;
            }
          }
          if (name < 0) await t.press('down');
        }
        expect(name, greaterThan(0));
        expect(
          t.screen.text.replaceAll(RegExp(r'\s+'), ' '),
          contains(exampleLedes[entry.name]!.split(' ').take(5).join(' ')),
        );
        for (final text in [
          'FIG. 1 EXAMPLE/${entry.name.toUpperCase()}.DART · TAB TO ENTER',
          '02  KEYS',
          'enter the example',
          'leave it',
          for (final row in exampleKeys[entry.name]!) row.words,
          '03  SOURCE',
          'example/${entry.name}.dart',
        ]) {
          expect(await _seek(t, text), greaterThanOrEqualTo(0), reason: text);
        }
        await t.press('end');
        expect(t.screen, shows('example/${entry.name}.dart on GitHub ↗'));
      });
    }

    testWidgets('${entry.name}: every key its Keys section lists is bound '
        'in the example', (t) async {
      late List<Binding> bindings;
      await t.pumpWidget(
        Column(
          children: [
            Expanded(
              child: Site(
                host: FakeHost('/chord_tui/${entry.name}'),
                gallery: siteGallery,
              ),
            ),
            KeyHelp.builder(
              builder: (context, b, _) {
                bindings = b;
                return const SizedBox(height: 1);
              },
            ),
          ],
        ),
        size: const Size(120, 41),
      );
      await t.pump();
      await t.press('tab');
      await t.pump();
      final bound = {for (final b in bindings) b.chord.toString()};
      for (final row in exampleKeys[entry.name]!) {
        if (!row.bound) continue;
        for (final key in row.keys) {
          // As the framework writes a key: esc is escape.
          final first = key.split(' ');
          final written = [
            KeyCombo.parse(first.first).toString(),
            ...first.skip(1),
          ].join(' ');
          expect(bound, contains(written), reason: key);
        }
      }
    });

    testWidgets('${entry.name}: s opens its file on GitHub from the page, '
        'and is the example\'s once entered', (t) async {
      final host = await _open(
        t,
        '/chord_tui/${entry.name}',
        const Size(120, 40),
      );
      await t.press('s');
      expect(host.opened, [exampleSourceUrl(entry.name)]);
      await t.press('tab');
      await t.press('s');
      expect(host.opened, hasLength(1));
    });
  }

  test('the sources the pages show are the files', () {
    expect(exampleSources.keys, [
      'main',
      for (final e in siteGallery.entries) e.name,
    ]);
  });
}
