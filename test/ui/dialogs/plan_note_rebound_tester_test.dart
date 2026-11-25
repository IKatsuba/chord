@Tags(['fake_agent'])
library;

import 'dart:convert';

import 'package:chord/ui/start.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import '../app/keymap_window_test.dart' show launchWith;
import '../app/window_fake_test.dart' as fixture;
import 'plan_box_fake_test.dart' show asked, answered;
import 'plan_note_scroll_fake_test.dart' show box;

void main() {
  group('tester CTUI-183: original rebound page keys', skip: fakeAgentSkip, () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('rebound keys page and name the Note without changing '
          'its complete answer at $size', (t) async {
        final c = await fixture.connected(t, size);
        await t.pumpWidget(
          StartWindow(
            launch: launchWith([
              {
                'context': 'Scroll',
                'bindings': {
                  'pageup': null,
                  'shift+pageup': null,
                  'pagedown': null,
                  'shift+pagedown': null,
                  'ctrl+p': 'scroll:pageUp',
                  'ctrl+n': 'scroll:pageDown',
                },
              },
            ]),
            connection: c,
          ),
          size: size,
        );
        await asked(t, c, 'cursorplan');
        await t.press('down down');
        final note = List.generate(
          160,
          (i) => 'row$i stays unchanged 界🙂e\u0301',
        ).join(' ');
        await t.paste(note);
        expect(box(t), contains('ctrl+p to scroll'));
        final tail = box(t);
        await t.press('pageup shift+pageup');
        expect(box(t), tail);
        for (
          var page = 0;
          page < 100 && !box(t).contains('Note  row0 ');
          page++
        ) {
          await t.press('ctrl+p');
        }
        expect(box(t), contains('Note  row0 '));
        expect(box(t), contains('ctrl+n to scroll'));
        await t.press('ctrl+n');
        expect(box(t), isNot(contains('Note  row0 ')));
        await t.press('up 2');
        expect(
          await answered(t, c),
          'Plan answer: ${jsonEncode({'outcome': 'rejected', 'reason': note})}',
        );
      });
    }
  });
}
