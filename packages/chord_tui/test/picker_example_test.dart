import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../example/picker.dart';

void main() {
  testerEdges();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('choose by number and by Enter at $size', (t) async {
      await t.pumpWidget(const PickerExample(), size: size);
      expect(t.screen.lines[2], 'Filter:');
      expect(t.screen.lines[3], startsWith('❯   1.  Choice 1'));
      expect(t.screen, shows(RegExp(r'… \+\d+ more')));
      await t.press('3');
      expect(t.screen, shows('Chosen: choice 3'));
      await t.press('/');
      await t.type('21');
      await t.press('enter');
      await t.press('enter');
      expect(t.screen, shows('Chosen: choice 21'));
      await t.press('esc');
      expect(t.screen, shows('Chosen: canceled'));
    });
  }

  testWidgets('the keys show on the first frame and in the editor', (t) async {
    await t.pumpWidget(const PickerExample(), size: const Size(200, 40));
    final help = t.screen.lines.last;
    expect(help, contains('up/k Previous choice'));
    expect(help, contains('enter Choose highlighted item'));
    expect(help, contains('1 Choose item 1'));
    await t.press('/');
    expect(t.screen.lines.last, contains('enter/escape Finish editing filter'));
  });

  testWidgets('with no rows for choices a number chooses nothing', (t) async {
    await t.pumpWidget(const PickerExample(), size: const Size(80, 3));
    await t.press('4');
    await t.press('enter');
    await t.resize(const Size(80, 24));
    expect(t.screen, shows('Chosen: nothing yet'));
  });

  testWidgets('a short window keeps the status and the keys', (t) async {
    await t.pumpWidget(const PickerExample(), size: const Size(80, 4));
    expect(t.screen.lines, [
      'Filter:',
      '❯ ↓ 1.  Choice 1',
      'Chosen: nothing yet',
      startsWith('up/k Previous choice'),
    ]);
    await t.resize(const Size(80, 3));
    expect(t.screen.lines, [
      'Filter:',
      'Chosen: nothing yet',
      '/ Edit filter  escape Cancel picker  ctrl+q Quit',
    ]);
  });

  testWidgets('a resize across the short layout keeps the query', (t) async {
    await t.pumpWidget(const PickerExample(), size: const Size(80, 24));
    await t.press('/');
    await t.type('2');
    await t.press('enter');
    await t.press('down');
    String lit() =>
        t.screen.lines.firstWhere((l) => l.startsWith('❯')).substring(4);
    final chosen = lit();
    await t.resize(const Size(80, 4));
    await t.resize(const Size(80, 24));
    expect(t.screen, shows('Filter: 2'));
    expect(lit(), chosen);
    await t.press('enter');
    expect(t.screen, shows('Chosen: choice 20'));
  });
}

void testerEdges() {
  group('tester: Picker example retained editor and selection', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('editing mode survives empty and short windows at $size', (
        t,
      ) async {
        await t.pumpWidget(const PickerExample(), size: size);
        await t.press('/');
        await t.paste('21');
        for (final next in const [
          Size.zero,
          Size(1, 1),
          Size(80, 3),
          Size(80, 4),
        ]) {
          await t.resize(next);
        }
        await t.resize(size);
        expect(t.screen, shows('Filter: 21'));
        await t.press('esc');
        expect(t.screen, shows('Chosen: nothing yet'));
        await t.press('enter');
        expect(t.screen, shows('Chosen: choice 21'));
        await t.press('ctrl+q');
        expect(t.exitRequested, isTrue);
      });
    }
  });
}
