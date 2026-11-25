import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_window_test.dart';

const pickHint = '↑ ↓ another block · c copy · esc done';
model.AssistantEntry reply(String text, [String turn = 'reply']) =>
    model.AssistantEntry(turn, TextRun.empty.plus(text));
const pickBody =
    'selectable prose\n\n```ts\nfirst code\n```\n\n> ```console\n> quoted code\n> ```\n\n```dart\nopen code';
Future<void> pressBounded(WidgetTester t, String keys) async {
  for (final combo in Chord.parse(keys).combos) {
    final before = t.inputLayoutPasses;
    t.host.handleKey(combo.toEvent());
    expect(
      t.inputLayoutPasses - before,
      lessThanOrEqualTo(2),
      reason: combo.toString(),
    );
  }
  await t.pump();
}

Future<void> clickAt(WidgetTester t, Offset at) async {
  await t.mouse(primary(MouseEventKind.press, at));
  await t.mouse(primary(MouseEventKind.release, at));
}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'real newest-visible pick skips open fence, copies quote, moves/clamps and keeps focus $size',
      (t) async {
        final connection = selectionConnection([reply(pickBody)]);
        addTearDown(connection.close);
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copyOnSelect: false,
            copy: (text, _) {
              writes.add(text);
              return const copy.CopyResult.sent();
            },
          ),
          size: size,
        );
        final focus = t.focusManager.primaryFocus;
        expect(
          t.screen.lines.where((line) => line.contains('[copy]')),
          hasLength(1),
        );
        await pressBounded(t, 'ctrl+x b');
        expect(t.screen, shows(pickHint));
        final quote = cellOf(t, '┌─ console');
        expect(t.screen.styleAt(quote.x, quote.y), ThemeData.dark().accent);
        await pressBounded(t, 'c');
        expect(writes, ['quoted code']);
        expect(t.screen, isNot(shows(pickHint)));
        await pressBounded(t, 'ctrl+x b up up');
        final frame = cellOf(t, '┌─ ts');
        expect(t.screen.styleAt(frame.x, frame.y), ThemeData.dark().accent);
        await pressBounded(t, 'c');
        expect(writes, ['quoted code', 'first code']);
        expect(t.focusManager.primaryFocus, same(focus));
        expect(connection.app.value.draft, isEmpty);
        expect(t.exitRequested, isFalse);
        await clickAt(t, cellOf(t, '[copy]'));
        expect(writes.last, 'first code');
        expect(writes, hasLength(3));
        await pressBounded(t, 'ctrl+x b esc');
        expect(t.screen, isNot(shows(pickHint)));
        expect(t.exitRequested, isFalse);
      },
    );
    testWidgets(
      'newest listed offscreen source reveals its quoted container without visiting intervening entries $size',
      (t) async {
        final connection = selectionConnection([
          reply('> ```dart\n> distant code\n> ```'),
          for (var i = 0; i < 100; i++) model.UserEntry('u$i', 'history $i'),
          reply('last plain text', 'last'),
        ]);
        addTearDown(connection.close);
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copy: (text, _) {
              writes.add(text);
              return const copy.CopyResult.sent();
            },
          ),
          size: size,
        );
        expect(t.screen, isNot(shows('distant code')));
        final focus = t.focusManager.primaryFocus;
        await pressBounded(t, 'ctrl+x b');
        expect(t.screen, shows('distant code'));
        expect(t.screen, shows(pickHint));
        await pressBounded(t, 'c');
        expect(writes, ['distant code']);
        expect(t.focusManager.primaryFocus, same(focus));
      },
    );
    testWidgets(
      'picked code copies fresh revision and removed target falls back only on next move $size',
      (t) async {
        final connection = selectionConnection([reply('```\nold code\n```')]);
        addTearDown(connection.close);
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copy: (text, _) {
              writes.add(text);
              return const copy.CopyResult.sent();
            },
          ),
          size: size,
        );
        await pressBounded(t, 'ctrl+x b');
        var app = connection.app.value;
        connection.app.value = AppState(
          start: app.start,
          transcript: model.Transcript(
            entries: replacedAt(
              app.transcript.entries,
              0,
              reply('```\nfresh code\n```'),
            ),
          ),
        );
        await pressBounded(t, 'c');
        expect(writes, ['fresh code']);
        app = connection.app.value;
        connection.app.value = AppState(
          start: app.start,
          transcript: model.Transcript(
            entries: appended(app.transcript.entries, [
              reply('```\nnewest code\n```', 'newest'),
            ]),
          ),
        );
        await t.pump();
        await pressBounded(t, 'ctrl+x b');
        app = connection.app.value;
        connection.app.value = AppState(
          start: app.start,
          transcript: model.Transcript(entries: [app.transcript.entries.first]),
        );
        await pressBounded(t, 'up c');
        expect(writes, ['fresh code', 'fresh code']);
      },
    );
    testWidgets(
      'button rejects revision changed while held then copies current full source $size',
      (t) async {
        final connection = selectionConnection([reply('```ts\nold code\n```')]);
        addTearDown(connection.close);
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copy: (text, _) {
              writes.add(text);
              return const copy.CopyResult.sent();
            },
          ),
          size: size,
        );
        final at = cellOf(t, '[copy]');
        await t.mouse(primary(MouseEventKind.press, at));
        final app = connection.app.value;
        connection.app.value = AppState(
          start: app.start,
          transcript: model.Transcript(
            entries: replacedAt(
              app.transcript.entries,
              0,
              reply('```ts\nnew code\n\ntail\n```'),
            ),
          ),
        );
        await t.mouse(primary(MouseEventKind.release, at));
        expect(writes, isEmpty);
        await clickAt(t, cellOf(t, '[copy]'));
        expect(writes, ['new code\n\ntail']);
      },
    );
    testWidgets(
      'closed empty block ends picking and button clears range without copying $size',
      (t) async {
        final connection = selectionConnection([
          reply('selectable prose\n\n```\n```'),
        ]);
        addTearDown(connection.close);
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copyOnSelect: false,
            copy: (text, _) {
              writes.add(text);
              return const copy.CopyResult.sent();
            },
          ),
          size: size,
        );
        expect(t.screen, shows('[copy]'));
        await pressBounded(t, 'ctrl+x b c');
        expect(writes, isEmpty);
        expect(t.screen, isNot(shows(pickHint)));
        expect(t.screen, isNot(shows('sent 0 chars')));
        await select(t, 'selectable');
        final at = cellOf(t, 'selectable');
        expect(t.screen.styleAt(at.x, at.y).bg, const IndexedColor(66));
        await clickAt(t, cellOf(t, '[copy]'));
        expect(writes, isEmpty);
        expect(t.screen.styleAt(at.x, at.y).bg, isNot(const IndexedColor(66)));
        expect(t.screen, isNot(shows('ctrl + c to copy')));
        expect(t.screen, isNot(shows('sent 0 chars')));
      },
    );
    testWidgets(
      'current plain Plan/PlanRecord/Tool and user fence text never manufacture code targets $size',
      (t) async {
        final plan = [
          acp.PlanEntry.fromJson({
            'content': '```plain plan```',
            'priority': 'high',
            'status': 'pending',
          }),
        ];
        final tool = model.ToolCall(
          'tool',
          title: 'Read',
          status: 'completed',
          content: [
            acp.ToolCallContent.fromJson({
              'type': 'content',
              'content': {'type': 'text', 'text': '```\nplain tool text\n```'},
            }),
          ],
        );
        final connection = selectionConnection([
          const model.UserEntry('u', '```plain user```'),
          model.FinishedPlanEntry('p', plan),
          model.ToolEntry('t', tool),
        ]);
        addTearDown(connection.close);
        final app = connection.app.value;
        connection.app.value = AppState(
          start: app.start,
          transcript: model.Transcript(
            entries: app.transcript.entries,
            plan: plan,
          ),
        );
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copy: (text, _) {
              writes.add(text);
              return const copy.CopyResult.sent();
            },
          ),
          size: size,
        );
        expect(t.screen, isNot(shows('[copy]')));
        await pressBounded(t, 'ctrl+x b');
        expect(t.screen, shows('No code block to pick'));
        expect(writes, isEmpty);
        expect(connection.app.value.draft, isEmpty);
      },
    );
    // CTUI-72: as the original's Status.tsx, the pick's note is not one
    // that stands alone: the facts on the right stay beside it.
    testWidgets('no code block to pick keeps the facts on the right $size', (
      t,
    ) async {
      final connection = selectionConnection();
      addTearDown(connection.close);
      final app = connection.app.value;
      connection.app.value = AppState(
        start: app.start,
        transcript: model.Transcript(
          entries: app.transcript.entries,
          usage: const model.Usage(10000, 1000000),
        ),
      );
      await t.pumpWidget(
        TranscriptWindow(launch: selectionLaunch, connection: connection),
        size: size,
      );
      final facts = t.screen.lines.last.trimRight();
      expect(facts, endsWith('1% context used'), reason: t.screen.text);
      await pressBounded(t, 'ctrl+x b');
      final line = t.screen.lines.last.trimRight();
      expect(
        line,
        startsWith('  No code block to pick'),
        reason: t.screen.text,
      );
      expect(line, endsWith('1% context used'));
    });
  }
}
