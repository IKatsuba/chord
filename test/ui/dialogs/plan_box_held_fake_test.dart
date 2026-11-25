import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import '../app/window_fake_test.dart' as fixture;
import 'plan_box_fake_test.dart' show answered, asked;

// The plan's Note is the original's row edited at its end (CTUI-178):
// typing appends, backspace, shift+backspace and alt+backspace take a
// character, ctrl+w a word, ctrl+u the whole note, and no key moves a
// cursor or edits elsewhere; cmd with a letter types nothing.
void main() {
  _testerHeldNoteCases();
  group('the plan Note is edited at its end', skip: fakeAgentSkip, () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('no key moves its cursor at $size', (t) async {
        final c = await fixture.connected(t, size);
        await asked(t, c, 'cursorplan');
        await t.press('j');
        await t.press('j');
        await t.type('Keep it small');
        for (final keys in [
          'left',
          'ctrl+a',
          'super+left',
          'alt+b',
          'ctrl+k',
          'ctrl+z',
          'delete',
          'shift+left',
          'super+a',
          'super+z',
          'shift+super+z',
          'alt+d',
        ]) {
          await t.press(keys);
        }
        await t.type('!');
        expect(t.screen, shows('Keep it small!'));
        for (final keys in ['backspace', 'shift+backspace', 'alt+backspace']) {
          await t.press(keys);
        }
        expect(t.screen, shows('Keep it sma'));
        expect(t.screen.text, isNot(contains('Keep it smal')));
        await t.press('ctrl+w');
        await t.type('big');
        expect(t.screen, shows('Keep it big'));
        await t.press('ctrl+u');
        expect(t.screen, shows('Tell fake what to change'));
        await t.type('Fine');
        await t.press('enter');
        expect(
          await answered(t, c),
          'Plan answer: {"outcome":"rejected","reason":"Fine"}',
        );
      });
    }
  });
}

void _testerHeldNoteCases() {
  group('tester CTUI-164: held plan Note lifecycle', skip: fakeAgentSkip, () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'held aliases leave the Unicode Note at its end after resize at $size',
        (t) async {
          final c = await fixture.connected(t, size);
          await asked(t, c, 'cursorplan');
          await t.press('j j');
          await t.paste('界👩‍💻e\u0301 end');
          await t.press('left left left');
          for (final key in [
            'ctrl+b',
            'ctrl+f',
            'ctrl+left',
            'ctrl+right',
            'ctrl+backspace',
            'shift+delete',
            'ctrl+delete',
            'alt+delete',
            'alt+a',
            'alt+e',
            'shift+left',
            'shift+right',
            'super+a',
            'super+z',
            'shift+super+z',
            'ctrl+shift+d',
          ]) {
            await t.press(key);
          }
          await t.resize(const Size(40, 12));
          await t.resize(size);
          await t.type('!');
          await t.press('enter');
          // Ctrl+Backspace above removes the final code point, as every
          // backspace does in the original's end-only row.
          expect(
            await answered(t, c),
            'Plan answer: {"outcome":"rejected","reason":"界👩‍💻e\u0301 en!"}',
          );
        },
      );

      testWidgets(
        'closing a held Note leaves the next plan Note empty at $size',
        (t) async {
          final c = await fixture.connected(t, size);
          await asked(t, c, 'cursorplan');
          await t.press('j j');
          await t.type('discarded');
          await t.press('super+a shift+left esc');
          expect(await answered(t, c), 'Plan answer: {"outcome":"rejected"}');
          await asked(t, c, 'cursorplan');
          await t.press('j j');
          await t.type('fresh');
          await t.press('enter');
          expect(
            await answered(t, c),
            'Plan answer: {"outcome":"rejected","reason":"fresh"}',
          );
        },
      );
    }
  });
}
