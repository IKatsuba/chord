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
  'permission.48x32.rec.json': _recording(48, 32),
};

const _names = ['permission', 'start'];

void main() {
  _shortPages();
  test('the largest recording that fits with its frame, caption and bar '
      'is chosen; else 48x32 bare; else 48x32 clipped', () {
    // Pages at the design's grids: the window less the nav and help rows,
    // and a phone's key row.
    expect(recordingFitFor(205, 51), (
      cols: 120,
      rows: 36,
      framed: true,
      clipped: false,
    ));
    expect(recordingFitFor(182, 45), (
      cols: 120,
      rows: 36,
      framed: true,
      clipped: false,
    ));
    expect(recordingFitFor(122, 42), (
      cols: 120,
      rows: 36,
      framed: true,
      clipped: false,
    ));
    expect(recordingFitFor(121, 42), (
      cols: 80,
      rows: 20,
      framed: true,
      clipped: false,
    ));
    expect(recordingFitFor(117, 68), (
      cols: 80,
      rows: 20,
      framed: true,
      clipped: false,
    ));
    expect(recordingFitFor(55, 46), (
      cols: 48,
      rows: 32,
      framed: true,
      clipped: false,
    ));
    expect(recordingFitFor(51, 34), (
      cols: 48,
      rows: 32,
      framed: false,
      clipped: false,
    ));
    expect(recordingFitFor(43, 31), (
      cols: 48,
      rows: 32,
      framed: false,
      clipped: true,
    ));
  });

  // Windows where each size fits with its frame: the page is the window
  // less the nav's four rows and the help row, and a phone's key row.
  for (final (size, rec) in const [
    (Size(122, 47), '120x36'),
    (Size(82, 31), '80x20'),
    (Size(55, 52), '48x32'),
  ]) {
    testWidgets('a recording page plays $rec in its cream frame at $size', (
      t,
    ) async {
      final host = FakeHost('/chord/permission', _files);
      await t.pumpWidget(
        Site(host: host, recordings: _names),
        size: size,
      );
      expect(t.screen, shows('LOADING PERMISSION…'));
      await t.pump();
      expect(host.fetched, ['permission.$rec.rec.json']);
      final phone = size.width < 60;
      final caption = t.screen.lines.indexWhere((l) => l.contains('01 / '));
      expect(
        t.screen.lines[caption].trim(),
        phone ? '01 / PERMISSION' : '01 / THE APP / PERMISSION',
      );
      expect(
        t.screen.styleAt(t.screen.lines[caption].indexOf('01'), caption),
        ThemeData.dark().accent.merge(Style.bold),
      );
      // A blank row, the frame's cream row, then the recording, centred.
      final top = caption + 2;
      final cols = int.parse(rec.split('x').first);
      final left = (size.width - cols - 2) ~/ 2;
      expect(t.screen.styleAt(left, top).isInverse, isTrue, reason: 'frame');
      expect(t.screen.styleAt(left + cols + 1, top + 1).isInverse, isTrue);
      expect(t.screen.lines[top + 1].indexOf('recorded at $rec'), left + 1);
      // The bar under it after a blank, centred: the orange cell first.
      final bar = top + int.parse(rec.split('x').last) + 3;
      expect(t.screen.lines[bar].trim(), startsWith('▶  0:00 / 0:'));
      final cell = t.screen.lines[bar].indexOf('▶') - 1;
      expect(
        t.screen.styleAt(cell, bar),
        ThemeData.dark().accent.merge(const Style(bold: true, inverse: true)),
      );
      await t.press('right');
      expect(t.screen.lines[top + 1], contains('typed at'));
      expect(t.screen.lines[bar], contains(' · TYPED THE PROMPT'));
      if (!phone) expect(t.screen.lines[caption], endsWith('STEP 1 OF 1'));
      await t.press('esc');
      expect(host.pushed, ['/chord']);
    });
  }

  testWidgets('a 360 px phone drops the frame and caption, and 48x32 fits '
      'whole', (t) async {
    final host = FakeHost('/chord/permission', _files);
    await t.pumpWidget(
      Site(host: host, recordings: _names),
      size: const Size(51, 40),
    );
    await t.pump();
    expect(host.fetched, ['permission.48x32.rec.json']);
    expect(t.screen, isNot(shows('01 / PERMISSION')));
    expect(t.screen.lines[4].trim(), 'recorded at 48x32');
    expect(t.screen.lines[4 + 33].trim(), startsWith('▶  0:00'));
  });

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
    expect(t.screen, shows("COULDN'T LOAD START"));
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
      size: const Size(122, 47),
    );
    await t.pump();
    expect(t.screen, shows(RegExp(r'▶  0:00 / 0:01')));
  });

  testWidgets('the phone key row pans a clipped recording', (t) async {
    final host = FakeHost('/chord/permission', _files);
    await t.pumpWidget(
      Site(host: host, recordings: _names),
      size: const Size(43, 37),
    );
    await t.pump();
    final first = t.screen.lines[4];
    final row = t.screen.lines[35];
    await t.mouse(
      MouseEvent(
        MouseEventKind.press,
        position: Offset(row.indexOf('→'), 35),
        button: MouseButton.primary,
      ),
    );
    expect(t.screen.lines[4], isNot(first));
    expect(first.substring(1), startsWith(t.screen.lines[4].substring(0, 5)));
  });

  testWidgets('a phone shows the small recording clipped', (t) async {
    final host = FakeHost('/chord/permission', _files);
    await t.pumpWidget(
      Site(host: host, recordings: _names),
      size: const Size(43, 37),
    );
    await t.pump();
    expect(host.fetched, ['permission.48x32.rec.json']);
    expect(t.screen.lines[4], endsWith('›'));
  });
}

void _shortPages() {
  for (final size in const [Size(80, 24), Size(43, 37)]) {
    testWidgets('a page too short for 48x32 keeps its bar in sight, and '
        'shift+down pans to the recording\'s last row, at $size', (t) async {
      final host = FakeHost('/chord/permission', _files);
      await t.pumpWidget(
        Site(host: host, recordings: _names),
        size: size,
      );
      await t.pump();
      expect(host.fetched, ['permission.48x32.rec.json']);
      final pageEnd = size.height - 2 - (size.width < 60 ? 1 : 0);
      expect(t.screen.lines[pageEnd].trim(), startsWith('▶  0:00'));
      expect(t.screen, isNot(shows('row 31')));
      for (var i = 0; i < 32; i++) {
        await t.press('shift+down');
      }
      expect(t.screen, shows('row 31'));
      expect(t.screen.lines[pageEnd].trim(), startsWith('▶'));
    });
  }
}
