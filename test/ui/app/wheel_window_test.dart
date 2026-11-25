import 'package:chord/session/conversation.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord/ui/shortcuts/keys.dart' as catalog;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'window_layout_test.dart' show launch;
import '../../../tool/wheel.dart' show wheelPreview, wheelDraft;

MouseEvent wheel(int x, int y, [int direction = -1]) => MouseEvent(
  MouseEventKind.wheel,
  position: Offset(x, y),
  scrollDelta: Offset(0, direction),
);
StartConnection seed({bool empty = false}) =>
    StartConnection(command: 'unused', cwd: '.')
      ..app.value = AppState(
        start: const StartState(phase: StartPhase.connected),
        transcript: model.Transcript(
          entries: [
            if (!empty)
              for (var i = 0; i < 100; i++)
                model.UserEntry('row$i', 'Named transcript row $i'),
          ],
        ),
      );

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final flags in <List<String>>[
      [],
      ['--help'],
      ['--permission'],
      ['--fitting'],
      ['--permission', '--help'],
      ['--permission', '--closing'],
      ['--help', '--closing'],
      ['--fitting', '--closing'],
      ['--help', '--tall-draft'],
      ['--help', '--tall-draft', '--closing'],
    ]) {
      testWidgets('whole fixture seeds draft and composes $flags at $size', (
        t,
      ) async {
        final c = seed();
        addTearDown(c.close);
        await t.pumpWidget(wheelPreview(c, flags), size: size);
        await t.pump();
        expect(c.app.value.draft, wheelDraft(flags));
        expect(t.screen, shows('unsubmitted draft'));
        expect(c.app.value.closing, flags.contains('--closing'));
        if (flags.contains('--help')) {
          expect(c.app.value.shortcuts.help, isTrue);
          expect(t.screen, shows('enter to send'));
          final row = t.screen.lines.indexWhere(
            (line) => line.contains('enter to send'),
          );
          final before = c.app.value.scroll.offset;
          final overflow = c.app.value.shortcuts.panelOverflows;
          if (flags.contains('--tall-draft')) {
            final lines = catalog.shortcuts.map(catalog.shortcutLine).toList();
            final rows = catalog.panelRows(
              lines,
              catalog.columnCount(lines, size.width),
            );
            // The anchor precedes the prompt's top padding and border; the
            // panel reserves its own top rule before fitting catalog rows.
            final promptTop = t.screen.lines.indexWhere(
              (line) => line.startsWith('╭'),
            );
            final room = promptTop - 2;
            expect(room, greaterThan(0));
            expect(overflow, rows.length > room, reason: t.screen.text);
            expect(overflow, size.width == 80, reason: t.screen.text);
            if (overflow) {
              expect(t.screen, shows('lines below · pagedown to scroll'));
            }
          }
          final focus = t.focusManager.primaryFocus;
          await t.mouse(wheel(3, row, overflow ? 1 : -1));
          expect(
            c.app.value.scroll.offset,
            flags.contains('--closing') || overflow ? before : before - 1,
          );
          if (overflow && !flags.contains('--closing')) {
            expect(t.screen, shows('1 line above'));
          }
          expect(c.app.value.draft, wheelDraft(flags));
          expect(t.focusManager.primaryFocus, same(focus));
        }
        if (flags.contains('--closing')) {
          final before = c.app.value.scroll;
          await t.mouse(wheel(0, 0));
          expect(c.app.value.scroll, before);
        }
        await t.press('ctrl+q');
        expect(t.exitRequested, isTrue);
      });
    }
    testWidgets(
      'root wheel one row everywhere preserves draft and focus at $size',
      (t) async {
        final c = seed();
        addTearDown(c.close);
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: c),
          size: size,
        );
        await t.type('draft');
        await t.press('left');
        final focus = t.focusManager.primaryFocus;
        final cursor = c.app.value.cursor;
        final prompt = t.screen.lines.indexWhere(
          (line) => line.startsWith('╭'),
        );
        for (final at in [
          Offset.zero,
          const Offset(2, 5),
          Offset(3, prompt + 1),
          Offset(size.width - 1, size.height - 1),
        ]) {
          final before = c.app.value.scroll.offset;
          await t.mouse(wheel(at.x, at.y));
          expect(c.app.value.scroll.offset, before - 1);
          expect(c.app.value.scroll.following, isFalse);
          await t.mouse(wheel(at.x, at.y, 1));
          expect(c.app.value.scroll.offset, before);
          expect(c.app.value.scroll.following, isTrue);
        }
        await t.press('home');
        expect(t.screen, shows('chord v0.0.1'));
        await t.mouse(wheel(1, 0, 1));
        expect(c.app.value.scroll.offset, 1);
        expect(c.app.value.draft, 'draft');
        expect(c.app.value.cursor, cursor);
        expect(t.focusManager.primaryFocus, same(focus));
        final before = c.app.value.scroll;
        await t.mouse(
          const MouseEvent(
            MouseEventKind.wheel,
            position: Offset.zero,
            scrollDelta: Offset(1, 0),
          ),
        );
        await t.mouse(
          const MouseEvent(
            MouseEventKind.press,
            position: Offset.zero,
            button: MouseButton.primary,
          ),
        );
        await t.mouse(
          const MouseEvent(
            MouseEventKind.release,
            position: Offset.zero,
            button: MouseButton.primary,
          ),
        );
        // The arrows are still the prompt's: ↓ sets the draft aside, as the
        // original's draft_kept does, and ↑ brings it back.
        await t.press('down');
        expect(c.app.value.draft, '');
        await t.press('up');
        expect(c.app.value.scroll, before);
        expect(c.app.value.draft, 'draft');
      },
    );
    testWidgets(
      'root queued reports observe closing before a redraw at $size',
      (t) async {
        final c = seed();
        addTearDown(c.close);
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: c),
          size: size,
        );
        final before = c.app.value.scroll.offset;
        var reports = 0;
        c.app.addListener(() {
          if (!c.app.value.closing) {
            reports++;
            c.app.value = reduceApp(c.app.value, const Closing());
          }
        });
        final chunk = InputParser().feed('\x1b[<64;1;1M\x1b[<64;1;1M');
        t.host.handleMouse(chunk.first as MouseEvent);
        final closed = c.app.value;
        t.host.handleMouse(chunk.last as MouseEvent);
        expect(c.app.value, same(closed));
        expect(c.app.value.scroll.offset, before - 1);
        expect(reports, 1);
        await t.pump();
        final text = t.screen.text;
        await t.mouse(wheel(0, 0, 1));
        expect(t.screen.text, text);
      },
    );
    testWidgets('empty transcript wheel leaves the screen unchanged at $size', (
      t,
    ) async {
      final c = seed(empty: true);
      addTearDown(c.close);
      await t.pumpWidget(
        TranscriptWindow(launch: launch, connection: c),
        size: size,
      );
      final text = t.screen.text;
      await t.mouse(wheel(0, 0));
      await t.mouse(wheel(size.width - 1, size.height - 1, 1));
      expect(t.screen.text, text);
    });
  }
  for (final closing in [false, true]) {
    testWidgets(
      'natural narrow help consumes wheel and honors closing=$closing',
      (t) async {
        final c = seed();
        addTearDown(c.close);
        final flags = ['--help', '--tall-draft', if (closing) '--closing'];
        await t.pumpWidget(wheelPreview(c, flags), size: const Size(40, 12));
        await t.pump();
        expect(c.app.value.shortcuts.panelOverflows, isTrue);
        expect(c.app.value.draft, wheelDraft(flags));
        final focus = t.focusManager.primaryFocus;
        final before = c.app.value.scroll;
        final text = t.screen.text;
        final body = t.screen.lines.indexWhere(
          (line) => line.contains('enter to send'),
        );
        expect(body, greaterThanOrEqualTo(0));
        await t.mouse(wheel(3, body, 1));
        expect(c.app.value.scroll, before);
        if (closing) {
          expect(t.screen.text, text);
        } else {
          expect(t.screen, shows('1 line above'));
          await t.mouse(wheel(3, body + 1));
          expect(t.screen, isNot(shows('1 line above')));
          expect(c.app.value.scroll, before);
        }
        expect(c.app.value.draft, wheelDraft(flags));
        expect(t.focusManager.primaryFocus, same(focus));
        await t.press('ctrl+q');
        expect(t.exitRequested, isTrue);
      },
    );
  }
}
