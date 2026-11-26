import 'dart:convert';

import 'package:chord_site/pages/recording.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fake_host.dart';

/// A recording of [cols] by [rows] whose first row names its size.
String _recording(int cols, int rows) => jsonEncode({
  'version': 1,
  'cols': cols,
  'rows': rows,
  'frames': [
    {
      'at': 0,
      'rows': [
        'recorded at ${cols}x$rows',
        for (var i = 1; i < rows; i++) 'row $i',
      ],
      'label': null,
    },
    {
      'at': 400,
      'rows': [
        'typed at ${cols}x$rows',
        for (var i = 1; i < rows; i++) 'row $i',
      ],
      'label': 'typed the prompt',
    },
  ],
});

final _files = {
  'permission.120x36.rec.json': _recording(120, 36),
  'permission.80x20.rec.json': _recording(80, 20),
};

const _names = ['permission', 'start'];

void main() {
  test('the largest recording that fits is chosen, else the smallest', () {
    expect(recordingSizeFor(120, 36), (cols: 120, rows: 36));
    expect(recordingSizeFor(119, 36), (cols: 80, rows: 20));
    expect(recordingSizeFor(80, 20), (cols: 80, rows: 20));
    expect(recordingSizeFor(43, 33), (cols: 80, rows: 20));
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('/chord lists the screens with their captions, $size', (
      t,
    ) async {
      final host = FakeHost('/chord');
      await t.pumpWidget(
        Site(host: host, recordings: _names),
        size: size,
      );
      expect(t.screen, shows('One terminal for every coding agent.'));
      expect(t.screen, shows('1. start'));
      expect(t.screen, shows('2. permission'));
      expect(t.screen, shows('the permission prompt'));
      await t.press('2');
      expect(host.pushed, ['/chord/permission']);
      expect(host.titles.last, 'permission · chord');
    });

    testWidgets('a recording page plays the size that fits, $size', (t) async {
      final host = FakeHost('/chord/permission', _files);
      await t.pumpWidget(
        Site(host: host, recordings: _names),
        size: size,
      );
      expect(t.screen, shows('loading permission…'));
      await t.pump();
      final big = size.width >= 120;
      expect(host.fetched, [
        big ? 'permission.120x36.rec.json' : 'permission.80x20.rec.json',
      ]);
      // Two header rows at every width: the recording right under them.
      expect(t.screen.lines[1], startsWith('──'));
      expect(
        t.screen.lines[2],
        big ? 'recorded at 120x36' : 'recorded at 80x20',
      );
      // The bar sits one cell in, in line with the help row under it.
      expect(t.screen.lines[size.height - 2], startsWith(' ▶ 0:00 / 0:'));
      // The whole row fits 80 columns.
      expect(
        t.screen.lines.last,
        ' space Play/pause  right/l Next  left/h Previous  r Restart  '
        'escape up  ? keys',
      );
      await t.press('right');
      expect(t.screen.lines[2], startsWith('typed at'));
      expect(t.screen, shows('step 1 of 1 · typed the prompt'));
      await t.press('esc');
      expect(host.pushed, ['/chord']);
    });
  }

  testWidgets('ten screens keep their names in one column', (t) async {
    await t.pumpWidget(
      Site(
        host: FakeHost('/chord'),
        recordings: const [
          'start', 'team', 'proposal', 'edit', 'permission', //
          'subagents', 'agents', 'resume', 'codeblocks', 'fork',
        ],
      ),
      size: const Size(120, 40),
    );
    final lines = t.screen.lines;
    final first = lines.firstWhere((l) => l.contains('1.  start'));
    final tenth = lines.firstWhere((l) => l.contains('10. fork'));
    expect(tenth.indexOf('fork'), first.indexOf('start'));
  });

  testWidgets('a recording that cannot be fetched says so', (t) async {
    final host = FakeHost('/chord/start', _files);
    await t.pumpWidget(Site(host: host, recordings: _names));
    await t.pump();
    expect(t.screen, shows("couldn't load start"));
    expect(t.screen.lines.last, contains('escape up'));
  });

  testWidgets('a step frame holds long enough to be read', (t) async {
    final host = FakeHost('/chord/permission', {
      'permission.120x36.rec.json': jsonEncode({
        'version': 1,
        'cols': 120,
        'rows': 36,
        'frames': [
          {
            'at': 0,
            'rows': ['typed'],
            'label': 'typed the prompt',
          },
          {
            'at': 200,
            'rows': ['answered'],
            'label': null,
          },
        ],
      }),
    });
    await t.pumpWidget(
      Site(host: host, recordings: _names),
      size: const Size(120, 40),
    );
    await t.pump();
    expect(t.screen, shows(RegExp(r'▶ 0:00 / 0:01')));
  });

  testWidgets('the phone key row pans a clipped recording', (t) async {
    final host = FakeHost('/chord/permission', _files);
    await t.pumpWidget(
      Site(host: host, recordings: _names),
      size: const Size(43, 37),
    );
    await t.pump();
    final first = t.screen.lines[2];
    final row = t.screen.lines[35];
    await t.mouse(
      MouseEvent(
        MouseEventKind.press,
        position: Offset(row.indexOf('→'), 35),
        button: MouseButton.primary,
      ),
    );
    expect(t.screen.lines[2], isNot(first));
    expect(first.substring(1), startsWith(t.screen.lines[2].substring(0, 5)));
  });

  testWidgets('a phone shows the small recording clipped', (t) async {
    final host = FakeHost('/chord/permission', _files);
    await t.pumpWidget(
      Site(host: host, recordings: _names),
      size: const Size(43, 37),
    );
    await t.pump();
    expect(host.fetched, ['permission.80x20.rec.json']);
    expect(t.screen.lines[2], endsWith('›'));
  });

  for (final size in const [Size(120, 40), Size(80, 24), Size(43, 37)]) {
    testWidgets('install says the three ways, $size', (t) async {
      await t.pumpWidget(Site(host: FakeHost('/install')), size: size);
      expect(t.screen, shows('npm install -g @chorded/chord'));
      expect(t.screen, shows('brew install ikatsuba/tap/chord'));
      expect(t.screen, shows('dart compile exe bin/chord.dart'));
      // The shim is npm's: it is said under npm, before Homebrew.
      final lines = t.screen.lines;
      final shim = lines.indexWhere((l) => l.contains('A small shim'));
      expect(
        shim,
        greaterThan(lines.indexWhere((l) => l.contains('npm install'))),
      );
      expect(shim, lessThan(lines.indexWhere((l) => l.contains('Homebrew'))));
    });
  }
}
