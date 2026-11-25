import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/theme/theme.dart';
import 'package:chord/ui/transcript/selection.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final (themeIndex, theme) in [
      ThemeData.dark(),
      ThemeData.light(),
      ThemeData.plain(),
    ].indexed) {
      testWidgets(
        'shell rows retain multiline gaps tones and copy exclusions $size $themeIndex',
        (t) async {
          const entry = model.ShellEntry(
            's',
            model.ShellRun(
              command: 'printf a\nprintf b',
              running: false,
              stdout: 'one\n\nthree\n',
              stderr: 'warning\n',
              code: 3,
            ),
          );
          final source = entrySelectionSource(
            entry,
            id: 's',
            revision: 0,
            width: size.width,
          );
          final selection = SelectionController();
          addTearDown(selection.dispose);
          await t.pumpWidget(
            Theme(
              data: theme,
              child: ChordThemeScope(
                child: SelectionArea(
                  controller: selection,
                  selectionStyle: const Style(inverse: true),
                  child: TranscriptEntry(entry, selectionSource: source),
                ),
              ),
            ),
            size: size,
          );
          expect(t.screen.lines.take(8), [
            '',
            '! printf a',
            '  printf b',
            '  ⎿  one',
            '',
            '     three',
            '     warning',
            '     Exit code 3',
          ]);
          expect(t.screen.styleAt(5, 6), theme.error);
          expect(source.codeBlocks, isEmpty);
          t.host.handleMouse(
            const MouseEvent(
              MouseEventKind.press,
              position: Offset(2, 1),
              button: MouseButton.primary,
            ),
          );
          t.host.handleMouse(
            const MouseEvent(
              MouseEventKind.move,
              position: Offset(11, 6),
              button: MouseButton.primary,
            ),
          );
          t.host.handleMouse(
            const MouseEvent(
              MouseEventKind.release,
              position: Offset(11, 6),
              button: MouseButton.primary,
            ),
          );
          expect(
            selection.snapshot()!.text,
            'printf a\nprintf b\none\n\nthree\nwarning',
          );
        },
      );
    }
    testWidgets(
      'actual shell row shows more than ten lines and wraps without copying wraps $size',
      (t) async {
        final command = 'printf ${'word ' * 35}end';
        final run = model.ShellRun(
          command: command,
          running: false,
          stdout: List.generate(12, (i) => 'line ${i + 1}').join('\n'),
        );
        final entry = model.ShellEntry('s', run);
        final source = entrySelectionSource(
          entry,
          id: 's',
          revision: 0,
          width: size.width,
        );
        final selection = SelectionController();
        addTearDown(selection.dispose);
        await t.pumpWidget(
          SelectionArea(
            controller: selection,
            selectionStyle: const Style(inverse: true),
            child: TranscriptEntry(entry, selectionSource: source),
          ),
          size: size,
        );
        expect(t.screen, shows('line 12'));
        expect(t.screen.text, isNot(contains('more lines')));
        final lastRow = t.screen.lines.indexWhere(
          (line) => line.contains('line 12'),
        );
        t.host.handleMouse(
          const MouseEvent(
            MouseEventKind.press,
            position: Offset(2, 1),
            button: MouseButton.primary,
          ),
        );
        t.host.handleMouse(
          MouseEvent(
            MouseEventKind.move,
            position: Offset(11, lastRow),
            button: MouseButton.primary,
          ),
        );
        t.host.handleMouse(
          MouseEvent(
            MouseEventKind.release,
            position: Offset(11, lastRow),
            button: MouseButton.primary,
          ),
        );
        expect(selection.snapshot()!.text, '$command\n${run.stdout}');
      },
    );
    testWidgets(
      'running stop hint revisions share authoritative geometry $size',
      (t) async {
        const entry = model.ShellEntry(
          's',
          model.ShellRun(command: 'sleep', running: true),
        );
        final cache = TranscriptSources('session');
        final first = cache.source(entry, width: size.width);
        final next = cache.source(
          entry,
          width: size.width,
          shellStopKey: 'esc',
        );
        expect(first.revision, isNot(next.revision));
        await t.pumpWidget(
          TranscriptEntry(entry, selectionSource: next, shellStopKey: 'esc'),
          size: size,
        );
        expect(t.screen, shows('Running… (esc to stop)'));
      },
    );
    testWidgets(
      'lazy real transcript retains shell entry and its offscreen source $size',
      (t) async {
        final scroll = ScrollController(follow: Follow.bottom),
            selection = SelectionController();
        addTearDown(scroll.dispose);
        addTearDown(selection.dispose);
        final entries = List<model.Entry>.generate(
          100,
          (i) => model.ShellEntry(
            's$i',
            model.ShellRun(
              command: 'command $i',
              running: false,
              stdout: 'output $i',
            ),
          ),
        );
        await t.pumpWidget(
          SelectionArea(
            controller: selection,
            selectionStyle: const Style(inverse: true),
            child: Transcript(
              transcript: model.Transcript.empty.withEntries(entries),
              controller: scroll,
              selectionNamespace: 'session',
            ),
          ),
          size: size,
        );
        expect(t.screen, shows('output 99'));
        scroll.toTop();
        await t.pump();
        expect(t.screen, shows('command 0'));
        scroll.toBottom();
        await t.pump();
        expect(t.screen, shows('output 99'));
        expect(selection.visibleCodeBlocks(), isEmpty);
      },
    );
  }
}
