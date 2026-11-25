import 'package:chord/cli.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_window_test.dart' show cellOf, primary;
import 'vim_window_test.dart' as vim_fixture;

const launch = Launch(
  name: 'fixture',
  agent: null,
  agentCommand: 'unused',
  version: '0.0.1',
  directory: 'project/package',
);

/// The dark palette's selection, the window's default.
const _selection = IndexedColor(66);

Future<StartConnection> _window(WidgetTester t, Size size) async {
  final connection = StartConnection(command: 'unused', cwd: '.');
  addTearDown(connection.close);
  connection.app.value = AppState(
    start: const StartState(phase: StartPhase.connected),
    transcript: model.Transcript(
      entries: [for (var i = 0; i < 3; i++) model.UserEntry('t$i', 'row $i')],
    ),
  );
  await t.pumpWidget(
    TranscriptWindow(launch: launch, connection: connection),
    size: size,
  );
  return connection;
}

/// Where the prompt's draft starts on screen.
Offset _draftAt(WidgetTester t, String draft) =>
    cellOf(t, '› $draft') + const Offset(2, 0);

// The prompt reaches what the original's does of OpenTUI's textarea keys:
// cmd+a, cmd+z and cmd+shift+z beside its TEXTAREA list (CTUI-164).
void main() {
  _testerPromptSelectionCases();
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('the panel lists the three after cmd + ← → at $size', (
      t,
    ) async {
      await _window(t, size);
      await t.press('?');
      final lines = t.screen.lines;
      final row = lines.indexWhere((l) => l.contains('cmd + ← → to line'));
      expect(lines[row + 1], startsWith('  cmd + a to select all input '));
      expect(
        lines[row + 2],
        startsWith('  cmd + z to undo, with shift to redo '),
      );
      expect(
        t.screen,
        shows(
          size.height == 24
              ? '── ↓ 6 lines below · pagedown to scroll ──'
              : 'ctrl + d or ctrl + c twice to quit',
        ),
      );
    });

    testWidgets('cmd+a selects the draft in the palette\'s colour at $size', (
      t,
    ) async {
      final c = await _window(t, size);
      await t.type('alpha beta');
      await t.press('super+a');
      final at = _draftAt(t, 'alpha beta');
      for (var x = 0; x < 10; x++) {
        expect(t.screen.styleAt(at.x + x, at.y).bg, _selection, reason: '$x');
      }
      expect(t.screen.styleAt(at.x + 10, at.y).bg, isNot(_selection));
      await t.type('x');
      expect((c.app.value.draft, c.app.value.cursor), ('x', 1));
      expect(t.screen.styleAt(at.x, at.y).bg, isNot(_selection));
    });

    testWidgets('cmd+z and cmd+shift+z undo and redo with the hint at $size', (
      t,
    ) async {
      final c = await _window(t, size);
      expect(t.screen.lines.last, contains('? for shortcuts'));
      await t.type('a');
      expect(t.screen.lines.last, isNot(contains('? for shortcuts')));
      await t.press('super+z');
      expect(c.app.value.draft, '');
      expect(t.screen.lines.last, contains('? for shortcuts'));
      await t.press('shift+super+z');
      expect(c.app.value.draft, 'a');
      expect(t.screen.lines.last, isNot(contains('? for shortcuts')));
    });

    testWidgets('shift+backspace no longer deletes at $size', (t) async {
      final c = await _window(t, size);
      await t.type('ab');
      await t.press('shift+backspace');
      expect((c.app.value.draft, c.app.value.cursor), ('ab', 2));
    });

    testWidgets('ctrl+c with a selection clears the draft at $size', (t) async {
      final c = await _window(t, size);
      await t.type('ab');
      await t.press('super+a ctrl+c');
      expect(c.app.value.draft, '');
      await t.type('z');
      expect(c.app.value.draft, 'z');
    });

    testWidgets('a drag over the transcript drops the draft\'s at $size', (
      t,
    ) async {
      final c = await _window(t, size);
      await t.type('alpha');
      await t.press('super+a');
      final start = cellOf(t, 'row 1');
      final end = cellOf(t, 'row 1', end: true);
      await t.mouse(primary(MouseEventKind.press, start));
      await t.mouse(primary(MouseEventKind.move, end));
      await t.pump();
      final at = _draftAt(t, 'alpha');
      expect(t.screen.styleAt(at.x, at.y).bg, isNot(_selection));
      await t.mouse(primary(MouseEventKind.release, end));
      await t.pump();
      // The key clears the drag first; the draft takes the letter at its
      // end, nothing selected.
      await t.type('!');
      expect(c.app.value.draft, 'alpha!');
    });
  }
}

void _testerPromptSelectionCases() {
  group('tester CTUI-164: option A prompt selection', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'Unicode selection retains palette and undo through resize at $size',
        (t) async {
          const draft = '界👩‍💻e\u0301\nsecond';
          final c = await _window(t, size);
          await t.paste(draft);
          await t.press('super+a');
          await t.resize(const Size(1, 1));
          await t.resize(size);
          for (final (theme, colour) in [('light', 152), ('dark', 66)]) {
            c.app.value = c.app.value.withTheme(theme);
            await t.pump();
            final at = _draftAt(t, '界👩‍💻e\u0301');
            for (var x = 0; x < 5; x++) {
              expect(t.screen.styleAt(at.x + x, at.y).bg, IndexedColor(colour));
            }
          }
          await t.press('shift+backspace');
          expect(c.app.value.draft, draft);
          await t.paste('replacement');
          expect((c.app.value.draft, c.app.value.cursor), ('replacement', 11));
          await t.press('super+z');
          expect(c.app.value.draft, draft);
          await t.press('shift+super+z');
          expect(c.app.value.draft, 'replacement');
        },
      );

      testWidgets('line cuts keep the original select-all asymmetry at $size', (
        t,
      ) async {
        final c = await _window(t, size);
        await t.paste('alpha\n界e\u0301');
        await t.press('super+a ctrl+k');
        await t.type('X');
        expect(c.app.value.draft, 'X');
        await t.press('super+z');
        expect(c.app.value.draft, 'alpha\n界e\u0301');
        await t.press('super+a ctrl+u');
        await t.type('X');
        expect(c.app.value.draft, 'alpha\nX');
      });

      testWidgets(
        'select all supersedes a drag and clearing never copies at $size',
        (t) async {
          final c = StartConnection(command: 'unused', cwd: '.');
          addTearDown(c.close);
          c.app.value = AppState(
            start: const StartState(phase: StartPhase.connected),
            transcript: model.Transcript(
              entries: [const model.UserEntry('row', 'copyable row')],
            ),
          );
          final copied = <String>[];
          await t.pumpWidget(
            TranscriptWindow(
              launch: launch,
              connection: c,
              copy: (text, _) {
                copied.add(text);
                return const copy.CopyResult.sent();
              },
            ),
            size: size,
          );
          await t.type('draft');
          final start = cellOf(t, 'copyable row');
          final end = cellOf(t, 'copyable row', end: true);
          await t.mouse(primary(MouseEventKind.press, start));
          await t.mouse(primary(MouseEventKind.move, end));
          await t.mouse(primary(MouseEventKind.release, end));
          final priorCopies = copied.length;
          await t.press('super+a ctrl+c');
          expect(c.app.value.draft, isEmpty);
          expect(copied, hasLength(priorCopies));
          await t.type('fresh');
          expect(c.app.value.draft, 'fresh');
        },
      );

      testWidgets(
        'vim insert reaches select all and normal mode keeps its keys at $size',
        (t) async {
          final c = await vim_fixture.window(t, size, vim: true);
          await t.paste('界👩‍💻e\u0301');
          await t.press('super+a');
          await t.paste('Z');
          expect(c.app.value.draft, 'Z');
          await t.press('esc');
          expect(c.app.value.vim?.mode, VimMode.normal);
          await t.press('super+a');
          await t.press('i');
          await t.type('Q');
          expect(c.app.value.draft, 'QZ');
        },
      );
    }
  });
}
