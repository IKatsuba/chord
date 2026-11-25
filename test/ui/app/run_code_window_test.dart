import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/prompt/bash.dart';
import 'package:chord/ui/prompt/prompt.dart';
import 'package:chord/ui/transcript/code_pick.dart' as pick;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_window_test.dart';
import 'code_pick_window_test.dart' show reply, pressBounded, clickAt;

const hint = '↑ ↓ another block · c copy · r put in the prompt · esc done';
const held = 'The prompt holds a draft · ctrl+c clears it';

void main() {
  test('whole raw script removes only column-zero prompt prefixes', () {
    expect(runCommand('\n\$ a\n \$ b\n\$ \n\$c\n'), '\na\n \$ b\n\n\$c\n');
    for (final language in [
      'sh',
      'bash',
      'SH',
      'Bash',
      'shell',
      'sh extra',
      '',
    ]) {
      final source = SelectionSource.markdown(
        id: Object(),
        revision: 0,
        text: '```$language\n\$ x\n```',
      );
      // Framework language descriptors contain the first word of fence info.
      expect(
        pick.runnableCode(source.codeBlocks.single),
        ['sh', 'bash', 'sh extra'].contains(language),
      );
    }
    expect(pick.pickHint(width: 80, run: 'r'), hint);
    expect(
      pick.pickHint(width: 40, run: 'r'),
      '↑ ↓ block · c copy · r prompt · esc done',
    );
    expect(pick.pickHint(width: 20, run: 'r'), '↑ ↓ block · c copy');
    final first = Object(), second = Object();
    var app = reduceWindow(const AppState(), DraftHeldAction(first));
    app = reduceWindow(app, DraftHeldAction(second));
    expect(reduceWindow(app, DraftHeldGoneAction(first)), same(app));
    expect(reduceWindow(app, DraftHeldGoneAction(second)).draftHeld, isNull);
  });
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'r fills multiline bash at end without running and consumes nonrunnable $size',
      (t) async {
        final c = selectionConnection([
          reply(
            '```sh\n\$ first\n \$ second\n\$ third\n```\n\n```ts\nuntouched\n```',
          ),
        ]);
        addTearDown(c.close);
        var calls = 0;
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: c,
            runShell: (_, _) {
              calls++;
              throw StateError('unexpected execution');
            },
          ),
          size: size,
        );
        final focus = t.focusManager.primaryFocus;
        await pressBounded(t, 'ctrl+x b r');
        expect(c.app.value.draft, isEmpty);
        expect(t.screen, shows('↑ ↓ another block · c copy · esc done'));
        await pressBounded(t, 'up');
        expect(t.screen, shows(hint));
        await pressBounded(t, 'r');
        expect(c.app.value.draft, 'first\n \$ second\nthird');
        expect(c.app.value.bash, isTrue);
        expect(c.app.value.cursor, endOf(c.app.value.draft));
        expect(t.screen, isNot(shows(hint)));
        expect(t.focusManager.primaryFocus, same(focus));
        await t.type('!');
        expect(c.app.value.draft, 'first\n \$ second\nthird!');
        expect(calls, 0);
      },
    );
    testWidgets(
      'run button refuses whitespace draft then inserts current full source $size',
      (t) async {
        final c = selectionConnection([
          reply('```bash\n\$ first\n\$ second\n```'),
        ]);
        addTearDown(c.close);
        await t.pumpWidget(
          TranscriptWindow(launch: selectionLaunch, connection: c),
          size: size,
        );
        await t.type(' ');
        final cursor = c.app.value.cursor;
        await clickAt(t, cellOf(t, '[run]'));
        expect(c.app.value.draft, ' ');
        expect(c.app.value.cursor, cursor);
        expect(c.app.value.bash, isFalse);
        expect(t.screen, shows(held));
        final warning = ThemeData.dark().warning;
        final at = cellOf(t, held);
        expect(t.screen.styleAt(at.x, at.y), warning);
        await t.pump(const Duration(milliseconds: 3050));
        expect(c.app.value.draftHeld, isNull);
        expect(t.screen, isNot(shows(held)));
        await t.press('ctrl+c');
        await clickAt(t, cellOf(t, '[run]'));
        expect(c.app.value.draft, 'first\nsecond');
        expect(c.app.value.bash, isTrue);
      },
    );
    testWidgets(
      'quoted empty runnable inserts mode and stale pointer does nothing $size',
      (t) async {
        final c = selectionConnection([
          reply('```sh\nold\n```\n\n> ```bash\n> ```'),
        ]);
        addTearDown(c.close);
        await t.pumpWidget(
          TranscriptWindow(launch: selectionLaunch, connection: c),
          size: size,
        );
        await pressBounded(t, 'ctrl+x b');
        expect(t.screen, shows(hint));
        await pressBounded(t, 'r');
        expect(c.app.value.bash, isTrue);
        expect(c.app.value.draft, isEmpty);
        await t.press('backspace');
        final at = cellOf(t, '[run]');
        await t.mouse(primary(MouseEventKind.press, at));
        c.app.value = AppState(
          start: c.app.value.start,
          transcript: c.app.value.transcript.withEntries(
            replacedAt(
              c.app.value.transcript.entries,
              0,
              reply('```sh\nnew\n```'),
            ),
          ),
        );
        await t.mouse(primary(MouseEventKind.release, at));
        expect(c.app.value.draft, isEmpty);
        expect(c.app.value.bash, isFalse);
        await clickAt(t, cellOf(t, '[run]'));
        expect(c.app.value.draft, 'new');
      },
    );
    // CTUI-72: as the original's Status.tsx DRAFT_HELD, the note is not
    // one that stands alone: the facts on the right stay beside it.
    testWidgets('a held draft keeps the facts on the right $size', (t) async {
      final c = selectionConnection([reply('```bash\n\$ first\n```')]);
      addTearDown(c.close);
      final app = c.app.value;
      c.app.value = AppState(
        start: app.start,
        transcript: model.Transcript(
          entries: app.transcript.entries,
          usage: const model.Usage(10000, 1000000),
        ),
      );
      await t.pumpWidget(
        TranscriptWindow(launch: selectionLaunch, connection: c),
        size: size,
      );
      await t.type(' ');
      await clickAt(t, cellOf(t, '[run]'));
      final line = t.screen.lines.last.trimRight();
      expect(line, startsWith('  $held'), reason: t.screen.text);
      expect(line, endsWith('1% context used'));
      final at = cellOf(t, held);
      expect(t.screen.styleAt(at.x, at.y), ThemeData.dark().warning);
    });
    // The held note outranks a copy's, which would stand alone: either
    // way round, the line says the draft is held, beside the facts.
    testWidgets('a held draft outranks a copy note $size', (t) async {
      final c = selectionConnection([reply('```bash\n\$ first\n```')]);
      addTearDown(c.close);
      final app = c.app.value;
      c.app.value = AppState(
        start: app.start,
        transcript: model.Transcript(
          entries: app.transcript.entries,
          usage: const model.Usage(10000, 1000000),
        ),
      );
      await t.pumpWidget(
        TranscriptWindow(
          launch: selectionLaunch,
          connection: c,
          copy: (_, _) => const copy.CopyResult.sent(),
        ),
        size: size,
      );
      await t.type(' ');
      // A copy, then the hold.
      await clickAt(t, cellOf(t, '[copy]'));
      expect(t.screen.lines.last, isNot(contains(held)));
      await clickAt(t, cellOf(t, '[run]'));
      var line = t.screen.lines.last.trimRight();
      expect(line, startsWith('  $held'), reason: t.screen.text);
      expect(line, endsWith('1% context used'));
      // The hold, then a copy.
      await clickAt(t, cellOf(t, '[copy]'));
      line = t.screen.lines.last.trimRight();
      expect(line, startsWith('  $held'), reason: t.screen.text);
      expect(line, endsWith('1% context used'));
    });
  }
}
