import 'package:chord_site/pages/chord.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fake_host.dart';

const _shots = ['start', 'edit', 'permission'];
const _lengths = {'start': Duration(seconds: 9), 'edit': Duration(seconds: 75)};

/// A line without the scrollbar's column.
String _bare(String line) => line.replaceAll('┃', '').trimRight();

int _row(WidgetTester t, Pattern text) =>
    t.screen.lines.indexWhere((l) => l.contains(text));

Future<int> _seek(WidgetTester t, Pattern text) async {
  for (var i = 0; i < 200 && _row(t, text) < 0; i++) {
    await t.press('down');
  }
  return _row(t, text);
}

Future<FakeHost> _chord(WidgetTester t, Size size) async {
  final host = FakeHost('/chord');
  await t.pumpWidget(
    Site(host: host, recordings: _shots, lengths: _lengths),
    size: size,
  );
  await t.pump();
  return host;
}

void main() {
  test('sections stack below 139 columns', () {
    expect(chordStackWidth, 139);
    expect(chordPlateWidth, 84);
    expect([for (final s in chordSections) s.key], ['p', 'a', 'l', 's']);
  });

  for (final size in const [Size(205, 56), Size(120, 40), Size(80, 24)]) {
    testWidgets('the kicker, APP., the lede, the band and the four live '
        'sections, at $size', (t) async {
      await _chord(t, size);
      expect(t.screen, shows('01 / THE APP'));
      expect(t.screen, shows(RegExp('[█▀▄]')));
      for (final text in [
        'One window, every agent you run',
        'LIVE  ✦  NO AGENT BEHIND IT  ✦  TYPE, ANSWER, APPROVE',
        for (final (i, s) in chordSections.indexed) ...[
          '0${i + 1}  ${s.title}',
          '→ TRY IT  ${s.key.toUpperCase()}',
          'FIG. 0${i + 1} LIVE · PRESS ${s.key.toUpperCase()}',
        ],
        '05 / WHOLE FLOWS, RECORDED',
      ]) {
        expect(await _seek(t, text), greaterThanOrEqualTo(0), reason: text);
      }
    });
  }

  for (final (size, stacked) in const [
    (Size(205, 56), false),
    (Size(139, 40), false),
    (Size(138, 40), true),
    (Size(117, 40), true),
  ]) {
    testWidgets(
      'a plate sits ${stacked ? 'under its text' : 'beside its '
                'text, at the right margin'} at ${size.width}',
      (t) async {
        await _chord(t, size);
        final fig = await _seek(t, 'FIG. 01');
        final x = t.screen.lines[fig].indexOf('FIG. 01');
        final title = _row(t, '01  THE PROMPT');
        if (stacked) {
          expect(fig, greaterThan(title + 4));
          expect(x, 4 + 2);
        } else {
          // The plate's cream starts 84 columns before the right margin.
          expect(x, size.width - 1 - 4 - chordPlateWidth + 2);
          expect(fig, lessThanOrEqualTo(title + 2));
        }
      },
    );
  }

  testWidgets('p, a, l and s enter their plates; the help row lists them', (
    t,
  ) async {
    await _chord(t, const Size(205, 56));
    expect(
      t.screen.lines.last,
      startsWith(' p/a/l/s try  tab next  up/down scroll'),
    );
    for (final (i, s) in chordSections.indexed) {
      await t.press(s.key);
      await t.pump();
      final leaves = s.ownsEscape ? 'CTRL+Q LEAVES' : 'ESC LEAVES';
      expect(t.screen, shows('FIG. 0${i + 1} LIVE · ${s.name}'));
      expect(t.screen, shows(leaves));
      await t.press(s.ownsEscape ? 'ctrl+q' : 'esc');
      expect(t.screen, isNot(shows(leaves)));
    }
  });

  testWidgets('Tab goes round the plates, the index and the page; Enter '
      'enters a focused plate and Esc gives the page back', (t) async {
    final host = await _chord(t, const Size(205, 80));
    int enterTag() => _row(t, '⏎ ENTER');
    for (var i = 0; i < 4; i++) {
      await t.press('tab');
      expect(enterTag(), _row(t, 'FIG. 0${i + 1}'), reason: 'plate ${i + 1}');
    }
    await t.press('tab');
    expect(enterTag(), -1);
    expect(await _seek(t, '⏎ PLAY'), greaterThan(0));
    await t.press('tab');
    expect(t.screen, isNot(shows('⏎ PLAY')));
    expect(enterTag(), -1, reason: 'the page');
    await t.press('shift+tab');
    expect(await _seek(t, '⏎ PLAY'), greaterThan(0));
    await t.press('shift+tab');
    await t.pump();
    expect(enterTag(), _row(t, 'FIG. 04'));
    await t.press('enter');
    expect(t.screen, shows('CTRL+Q LEAVES'));
    await t.press('ctrl+q');
    // Left, the plate keeps the focus it was entered from.
    expect(enterTag(), _row(t, 'FIG. 04'));
    await t.press('esc');
    expect(enterTag(), -1);
    expect(host.pushed, isEmpty);
  });

  testWidgets('the flows index: numbered caps rows with their lengths; the '
      'arrows pick one and Enter plays it', (t) async {
    final host = await _chord(t, const Size(205, 80));
    await _seek(t, 'the title page above');
    for (var i = 0; i < 6; i++) {
      await t.press('down');
    }
    final start = _row(t, 'the title page above');
    final line = t.screen.lines[start];
    expect(line, contains('01  START'));
    expect(line, contains('the title page above the agent picker'));
    expect(_bare(line), endsWith('0:09'));
    expect(_bare(t.screen.lines[_row(t, '02  EDIT')]), endsWith('1:15'));
    for (var i = 0; i < 5; i++) {
      await t.press('tab');
    }
    expect(_bare(t.screen.lines[_row(t, '01  START')]), endsWith('⏎ PLAY'));
    await t.press('down');
    expect(_bare(t.screen.lines[_row(t, '02  EDIT')]), endsWith('⏎ PLAY'));
    await t.press('enter');
    expect(host.pushed, ['/chord/edit']);
  });

  testWidgets('a tap on a flow opens it', (t) async {
    final host = await _chord(t, const Size(120, 80));
    final y = await _seek(t, '03  PERMISSION');
    await t.mouse(
      MouseEvent(
        MouseEventKind.press,
        position: Offset(10, y),
        button: MouseButton.primary,
      ),
    );
    expect(host.pushed, ['/chord/permission']);
  });

  testWidgets('on a phone a flow\'s description drops under its name', (
    t,
  ) async {
    await _chord(t, const Size(55, 80));
    await _seek(t, '01  START');
    for (var i = 0; i < 4; i++) {
      await t.press('down');
    }
    final y = _row(t, '01  START');
    expect(t.screen.lines[y], isNot(contains('title page')));
    expect(t.screen.lines[y + 1].trim(), startsWith('the title page'));
  });

  testWidgets('the prompt\'s room grows with the draft, up to 8 rows', (
    t,
  ) async {
    await _chord(t, const Size(205, 56));
    await t.press('p');
    int height() {
      final top = _row(t, 'FIG. 01');
      final bottom = _row(t, 'FIG. 02');
      return bottom - top;
    }

    final one = height();
    await t.type('one');
    for (var i = 0; i < 9; i++) {
      await t.press('shift+enter');
    }
    await t.pump();
    expect(height(), one + 4, reason: '4 more rows, then no more');
  });
}
