import 'dart:io';

import 'package:chord_site/live/permission.dart';
import 'package:chord_site/live/plan.dart';
import 'package:chord_site/live/prompt.dart';
import 'package:chord_site/live/start.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// [child] in a room of [size], as a live frame gives it, with the focus.
Widget room(Widget child) => Focus(autofocus: true, child: child);

void main() {
  for (final width in const [80, 50]) {
    group('$width columns', () {
      testWidgets('the prompt sends into the room above it and clears', (
        t,
      ) async {
        await t.pumpWidget(room(const LivePrompt()), size: Size(width, 8));
        expect(t.screen, shows('›'));
        await t.type('hello from the site');
        await t.press('enter');
        expect(t.screen.lines.first, 'hello from the site');
        expect(t.screen.lines.where((l) => l.contains('hello')), hasLength(1));
      });

      testWidgets('the permission prompt asks, answers in a line, and r asks '
          'again', (t) async {
        await t.pumpWidget(room(const LivePermission()), size: Size(width, 12));
        expect(t.screen, shows('Write notes.txt'));
        expect(t.screen, shows('Allow once'));
        await t.press('enter');
        expect(t.screen.lines.first, 'Allowed once  ·  r ask again');
        await t.press('r');
        await t.pump();
        expect(t.screen, shows('Write notes.txt'));
        await t.press('down');
        await t.press('down');
        await t.press('enter');
        expect(t.screen.lines.first, startsWith('Denied'));
      });

      testWidgets('the plan shows its checklist above the prompt, and '
          'ctrl+t stops the work', (t) async {
        await t.pumpWidget(room(const LivePlan()), size: Size(width, 14));
        expect(t.screen, shows('Read the code'));
        expect(t.screen, shows('Write the change'));
        expect(t.screen, shows('Run the tests'));
        expect(t.screen, shows('Working…'));
        await t.press('ctrl+t');
        expect(t.screen, isNot(shows('Working…')));
      });

      testWidgets('the start page picks an agent, answers in a line, and r '
          'asks again', (t) async {
        await t.pumpWidget(room(const LiveStart()), size: Size(width, 19));
        expect(t.screen, shows('Select agent'));
        // Three agents, all available: none reads as missing.
        expect(t.screen, shows('gemini'));
        expect(t.screen, isNot(shows('not on PATH')));
        await t.press('1');
        expect(t.screen.lines.first, 'Picked claude  ·  r ask again');
        expect(t.exitRequested, isFalse, reason: 'the site keeps running');
        await t.press('r');
        await t.pump();
        expect(t.screen, shows('Select agent'));
      });
    });
  }

  for (final key in ['esc', 'ctrl+c']) {
    testWidgets('$key cancels the start page into its answer line, never '
        'quitting the site', (t) async {
      await t.pumpWidget(room(const LiveStart()), size: const Size(80, 19));
      await t.press(key);
      expect(t.exitRequested, isFalse);
      expect(t.screen.lines.first, 'Canceled  ·  r ask again');
      await t.press('r');
      await t.pump();
      expect(t.screen, shows('Select agent'));
    });
  }

  test('the fixtures import nothing of dart:io', () {
    // A Wasm build has no dart:io: the live widgets must not need it.
    for (final file in ['answer', 'permission', 'plan', 'prompt', 'start']) {
      final source = File('lib/live/$file.dart').readAsStringSync();
      expect(source, isNot(contains("'dart:io'")), reason: file);
    }
  });
}
