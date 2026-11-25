import 'package:chord/session/sessions.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/resume.dart';
import 'resume_picker_test.dart' show frame, saved, snapshot;

void main() {
  group('CTUI-26 U5 tester: scope keys and empty geometry', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'scope remount starts at top and omitted navigation stays inert $size',
        (t) async {
          await t.pumpWidget(const ResumeFixture(['--many']), size: size);
          for (final key in [
            'home',
            'end',
            'pageup',
            'pagedown',
            'shift+up',
            'shift+down',
            'shift+pageup',
            'shift+pagedown',
          ]) {
            await t.press(key);
          }
          await t.press('enter');
          expect(t.screen, shows('Selected saved-0'));
          await t.press('j');
          await t.press('enter');
          expect(t.screen, shows('Selected saved-2'));
          await t.press('k');
          await t.press('enter');
          expect(t.screen, shows('Selected saved-0'));
          await t.press('down');
          await t.press('ctrl+a');
          await t.press('enter');
          expect(t.screen, shows('Selected saved-0'));
          await t.press('2');
          expect(t.screen, shows('Selected saved-1'));
          await t.press('ctrl+a');
          await t.press('enter');
          expect(t.screen, shows('Selected saved-0'));
        },
      );
    }

    for (final size in [
      const Size(0, 40),
      const Size(1, 40),
      const Size(80, 0),
      const Size(80, 1),
      const Size(0, 0),
    ]) {
      testWidgets(
        'no acceptance at empty geometry and no deferred acceptance after resize $size',
        (t) async {
          final item = saved('saved', '\u001b[31m界👩‍💻é\u001b[0m');
          final state = snapshot([item]);
          final chosen = <EarlierSession>[];
          await t.pumpWidget(frame(state, selected: chosen.add), size: size);
          await t.press('enter');
          await t.press('1');
          expect(chosen, isEmpty);
          await t.resize(const Size(80, 24));
          expect(chosen, isEmpty);
          await t.press('enter');
          expect(chosen.single, same(item));
          expect(t.screen, shows('界👩‍💻é'));
          await t.pumpWidget(const SizedBox());
          await t.press('enter');
          await t.press('1');
          expect(chosen, hasLength(1));
        },
      );
    }
  });
}
