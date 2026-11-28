import 'dart:async';
import 'dart:convert';

import 'package:chord_site/pages/home.dart';
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
      'rows': ['first at ${cols}x$rows'],
      'label': null,
    },
    {
      'at': 400,
      'rows': ['last at ${cols}x$rows'],
      'label': null,
    },
  ],
});

final files = {
  for (final s in homeRecordingSizes)
    'edit.${s.cols}x${s.rows}.rec.json': _recording(s.cols, s.rows),
};

/// The row of the first line containing [text], else -1.
int _row(WidgetTester t, Pattern text) =>
    t.screen.lines.indexWhere((l) => l.contains(text));

/// A line without the scrollbar's column.
String _bare(String line) => line.replaceAll('┃', '').trimRight();

/// Scrolls down a row at a time until [text] is in sight; its row.
Future<int> _seek(WidgetTester t, Pattern text) async {
  for (var i = 0; i < 200 && _row(t, text) < 0; i++) {
    await t.press('down');
  }
  return _row(t, text);
}

/// A host whose recordings come only when [release] is called.
class _SlowHost extends FakeHost {
  _SlowHost() : super('/', files);

  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<String?> recording(String file) async {
    await _gate.future;
    return super.recording(file);
  }
}

/// A host that answers each file when told to, with its recording or with
/// nothing.
class _HeldHost extends FakeHost {
  _HeldHost() : super('/', files);

  final _held = <String, Completer<String?>>{};

  void answer(String file, {bool found = true}) =>
      _held[file]!.complete(found ? files[file] : null);

  @override
  Future<String?> recording(String file) {
    fetched.add(file);
    return (_held[file] = Completer<String?>()).future;
  }
}

Future<FakeHost> _home(WidgetTester t, Size size) async {
  final host = FakeHost("/", files);
  await t.pumpWidget(Site(host: host), size: size);
  await t.pump();
  return host;
}

void main() {
  _burst();
  test('the plate plays the largest recording that fits inside it', () {
    // 192 columns leave 183 inside the margins and 181 inside the plate.
    expect(homeRecordingFor(181), (cols: 120, rows: 36));
    expect(homeRecordingFor(109), (cols: 80, rows: 20));
    expect(homeRecordingFor(69), (cols: 48, rows: 32));
    expect(homeRecordingFor(45), (cols: 48, rows: 32));
  });

  for (final size in const [
    Size(192, 56),
    Size(120, 40),
    Size(80, 24),
    Size(52, 52),
  ]) {
    group('at $size', () {
      final margin = size.width < narrowWidth ? 2 : 4;

      testWidgets('the giant CHORD. under two blank rows, at the margin', (
        t,
      ) async {
        await _home(t, size);
        final lines = t.screen.lines;
        expect(_bare(lines[4]), '');
        expect(_bare(lines[5]), '');
        // The C's leftmost pixels, on whichever of its rows they are.
        final glyphs = [
          for (final l in lines.sublist(6, 13))
            if (l.contains(RegExp('[█▀▄]'))) l.indexOf(RegExp('[█▀▄]')),
        ];
        expect(glyphs.reduce((a, b) => a < b ? a : b), margin);
      });

      testWidgets('the statement, then the paragraph and the buttons', (
        t,
      ) async {
        await _home(t, size);
        final statement = await _seek(t, 'A TERMINAL WINDOW');
        final line = t.screen.lines[statement];
        expect(line.indexOf('A TERMINAL'), margin);
        expect(t.screen.lines[statement + 1], contains('FOR CODING AGENTS.'));
        final content = size.width - 1 - 2 * margin;
        if (content - 50 < 60) {
          // Stacked: the paragraph under the statement, then the buttons,
          // side by side where they fit.
          final para = await _seek(t, 'Claude, Codex');
          expect(para, greaterThan(statement + 1));
          expect(t.screen.lines[para].indexOf('Claude'), margin);
          final install = await _seek(t, 'INSTALL  i');
          expect(t.screen.lines[install].indexOf(' INSTALL'), margin);
          expect(
            _bare(t.screen.lines[install]),
            endsWith('   WATCH IT RUN  w'),
          );
        } else {
          // Beside the statement: 44 columns and 6 between.
          expect(line.indexOf('Claude, Codex'), margin + 50);
          final buttons = await _seek(t, 'INSTALL  i');
          expect(t.screen.lines[buttons].indexOf(' INSTALL'), margin + 50);
          expect(
            _bare(t.screen.lines[buttons]),
            endsWith('   WATCH IT RUN  w'),
          );
        }
      });

      testWidgets('the band runs edge to edge, ink bold on green', (t) async {
        await _home(t, size);
        await _seek(t, 'THE TERMINAL IS THE PAGE');
        // The rows above and below the slogans too.
        await t.press('down');
        final row = _row(t, 'THE TERMINAL IS THE PAGE');
        expect(row, greaterThan(4));
        final face = ThemeData.dark().accent.merge(
          const Style(bold: true, inverse: true),
        );
        expect(t.screen.lines[row].indexOf('THE TERMINAL'), 2);
        for (final y in [row - 1, row, row + 1]) {
          expect(t.screen.styleAt(0, y), face, reason: 'row $y');
          expect(t.screen.styleAt(size.width - 2, y), face, reason: 'row $y');
        }
      });
    });
  }

  for (final (size, perRow) in const [
    (Size(192, 200), 4),
    (Size(120, 120), 4),
    (Size(80, 120), 2),
    (Size(52, 160), 1),
  ]) {
    testWidgets('the numbered columns, $perRow to a row at ${size.width}', (
      t,
    ) async {
      await _home(t, size);
      // The titles, past the nav and the INSTALL button.
      final rows = [
        for (final c in homeColumns)
          t.screen.lines.indexWhere(
            (l) => l.contains(c.title) && !l.contains('  i'),
            4,
          ),
      ];
      for (final (i, c) in homeColumns.indexed) {
        expect(t.screen.lines[rows[i]], contains(c.title));
        expect(rows[i], rows[i - i % perRow], reason: c.title);
      }
      if (perRow > 1) {
        // Four apart: the second column starts after the first and the gap.
        final line = t.screen.lines[rows[0]];
        final margin = size.width < narrowWidth ? 2 : 4;
        final content = size.width - 1 - 2 * margin;
        final width = (content - 4 * (perRow - 1) + perRow - 1) ~/ perRow;
        expect(line.indexOf(homeColumns[1].title), margin + width + 4);
      }
      // The descriptions wrap to different heights; the PRESS lines of a
      // row of columns still sit on one line.
      final press = [
        for (var n = 1; n <= homeColumns.length; n++) _row(t, '→ PRESS $n'),
      ];
      for (var i = 0; i < press.length; i++) {
        expect(press[i], greaterThan(0));
        expect(press[i], press[i - i % perRow], reason: 'PRESS ${i + 1}');
      }
    });
  }

  for (final size in const [Size(192, 56), Size(120, 40), Size(80, 24)]) {
    testWidgets('FIG. 1 opens paused on the last frame; w brings it up and '
        'plays it from the start, at $size', (t) async {
      final host = await _home(t, size);
      final margin = size.width < narrowWidth ? 2 : 4;
      final fits = homeRecordingFor(size.width - 1 - 2 * margin - 2);
      expect(host.fetched, ['edit.${fits.cols}x${fits.rows}.rec.json']);
      await _seek(t, 'last at');
      expect(t.screen, shows(RegExp(r'▶ EDIT · \d:\d\d · W PLAYS')));
      await t.press('home');
      await t.press('w');
      await t.pump();
      final caption = _row(t, '▶ EDIT');
      // The plate's top row comes to the view's top, unless the page ends
      // first; then the whole plate is in sight.
      if (_row(t, 'DRAWN BY WTERM') < 0) {
        expect(caption, 5);
      } else {
        expect(caption, greaterThan(4));
      }
      expect(t.screen, shows('SPACE PAUSES'));
      expect(t.screen, shows('first at'));
      expect(
        t.screen.styleAt(t.screen.lines[caption].indexOf('EDIT'), caption),
        ThemeData.dark().text.merge(const Style(bold: true, inverse: true)),
      );
    });
  }

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('w pressed while the recording loads plays it once it comes, '
        'at $size', (t) async {
      final host = _SlowHost();
      await t.pumpWidget(Site(host: host), size: size);
      await t.press('w');
      host.release();
      await t.pump();
      await t.pump();
      expect(t.screen, shows('SPACE PAUSES'));
      expect(t.screen, shows('first at'));
      // Space reaches the focused Playback and pauses it.
      await t.press('space');
      // The caption may sit above a Playback taller than the view.
      await t.press('home');
      await _seek(t, '▶ EDIT');
      expect(t.screen, shows(RegExp(r'▶ EDIT · \d:\d\d · W PLAYS')));
    });
  }

  for (final found in [false, true]) {
    testWidgets('w while a resized plate loads plays the new recording, after '
        'the old one ${found ? 'came' : 'failed'}', (t) async {
      final host = _HeldHost();
      await t.pumpWidget(Site(host: host), size: const Size(120, 60));
      host.answer('edit.80x20.rec.json', found: found);
      await t.pump();
      await t.resize(const Size(52, 60));
      expect(host.fetched.last, 'edit.48x32.rec.json');
      await t.press('w');
      host.answer('edit.48x32.rec.json');
      await t.pump();
      await t.pump();
      expect(t.screen, shows('SPACE PAUSES'));
      expect(t.screen, shows('first at 48x32'));
    });
  }

  testWidgets('a w meant for a load that fails does not carry to the next '
      'one', (t) async {
    final host = _HeldHost();
    await t.pumpWidget(Site(host: host), size: const Size(120, 60));
    await t.press('w');
    host.answer('edit.80x20.rec.json', found: false);
    await t.pump();
    await t.resize(const Size(52, 60));
    host.answer('edit.48x32.rec.json');
    await t.pump();
    await t.pump();
    await _seek(t, 'last at 48x32');
    expect(t.screen, shows('W PLAYS'));
  });

  testWidgets('w pressed before a recording that fails plays nothing later', (
    t,
  ) async {
    await t.pumpWidget(Site(host: FakeHost()), size: const Size(120, 120));
    await t.press('w');
    await t.pump();
    expect(t.screen, shows("▶ EDIT · COULDN'T LOAD"));
  });

  for (final (size, left, right) in const [
    // 120 columns: 80x20 and its frame fit in the margins.
    (Size(120, 60), 4, 114),
    // 52: 48x32 needs 50, the margins leave 47; edge to the scrollbar, 51.
    (Size(52, 80), 0, 50),
    // 48: 47 to the scrollbar, still short of 50; the Playback clips.
    (Size(48, 80), 0, 46),
  ]) {
    testWidgets('the plate keeps the margins while it fits, else runs to '
        'the scrollbar, at $size', (t) async {
      await _home(t, size);
      final caption = await _seek(t, 'last at') - 2;
      expect(t.screen.lines[caption], contains('▶ EDIT'));
      final cream = ThemeData.dark().text.merge(const Style(inverse: true));
      expect(t.screen.styleAt(left, caption).bg, isNull);
      expect(t.screen.styleAt(left, caption).isInverse, isTrue);
      expect(t.screen.styleAt(right, caption).isInverse, isTrue);
      if (left > 0) {
        expect(t.screen.styleAt(left - 1, caption).isInverse, isFalse);
      }
      expect(t.screen.styleAt(right + 1, caption), isNot(cream));
      final recorded = t.screen.lines[caption + 2];
      expect(recorded.indexOf('last at'), left + 1);
    });
  }

  testWidgets('an unfetchable recording says so in the plate', (t) async {
    await t.pumpWidget(Site(host: FakeHost()), size: const Size(120, 120));
    await t.pump();
    expect(t.screen, shows("▶ EDIT · COULDN'T LOAD"));
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the footer, the keys and the help row, at $size', (t) async {
      final host = await _home(t, size);
      expect(
        t.screen.lines.last,
        size.width < 100
            ? ' i install  w watch  1–4 go  up/down scroll  ? keys  m menu'
            : ' i install  w watch  1–4 go  up/down scroll  ? keys',
      );
      await t.press('end');
      await t.pump();
      final footer = _row(t, 'MIT  ·  MADE WITH CHORD_TUI  ·  DRAWN BY WTERM');
      expect(footer, greaterThan(0));
      expect(_bare(t.screen.lines[footer]), endsWith('?  ALL KEYS'));
      expect(t.screen.lines[footer - 1].trim(), startsWith('─'));
      expect(t.screen.styleAt(4, footer), ThemeData.dark().dim);
      await t.press('i');
      expect(host.pushed, ['/install']);
    });
  }

  testWidgets('a tap on a column and a digit open its section', (t) async {
    final host = await _home(t, const Size(120, 120));
    final row = _row(t, 'THE FRAMEWORK');
    final x = t.screen.lines[row].indexOf('THE FRAMEWORK');
    await t.mouse(
      MouseEvent(
        MouseEventKind.press,
        position: Offset(x, row),
        button: MouseButton.primary,
      ),
    );
    expect(host.pushed, ['/chord_tui']);
    final again = await _home(t, const Size(120, 120));
    await t.press('3');
    expect(again.pushed, ['/chord_tui/gallery']);
  });
}

void _burst() {
  // Ctrl+Q does nothing at home, so i leaves it.
  testWidgets('w, then i before the next frame, leaves home cleanly', (
    t,
  ) async {
    final host = FakeHost('/', files);
    await t.pumpWidget(Site(host: host), size: const Size(80, 24));
    await t.pump();
    t.host.handleKey(const KeyEvent('w'));
    t.host.handleKey(const KeyEvent('i'));
    await t.pump();
    await t.pump();
    expect(host.pushed, ['/install']);
    expect(t.screen, shows('brew install ikatsuba/tap/chord'));
  });
}
