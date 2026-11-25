import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/shortcuts/state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/wheel.dart' show wheelPermission;
import 'selection_window_test.dart';
import 'code_pick_window_test.dart' show reply, pickHint, pressBounded;
import 'code_pick_coexistence_test.dart' show body;

void ask(StartConnection connection) {
  final old = connection.app.value;
  connection.app.value = AppState(
    start: old.start,
    draft: old.draft,
    cursor: old.cursor,
    scroll: old.scroll,
    transcript: model.Transcript(
      entries: old.transcript.entries,
      turn: model.AwaitingPermission('ask', 0, [wheelPermission()]),
    ),
  );
}

Future<void> bothDraft(WidgetTester t) async {
  await pressBounded(t, 'ctrl+x b');
  expect(t.screen, shows(pickHint));
  await select(t, 'draft');
  expect(t.screen, shows(pickHint));
  final at = cellOf(t, 'draft');
  expect(t.screen.styleAt(at.x, at.y).bg, const IndexedColor(66));
}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'permission/form: real selection copy and pick commands precede choices and interrupt $size',
      (t) async {
        final connection = selectionConnection([reply(body)]);
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
        await t.type('draft words');
        ask(connection);
        await t.pump();
        expect(connection.app.value.requestOverflows, isTrue);
        await pressBounded(t, 'down');
        expect(t.screen, shows('❯ 2. Always allow'));
        final turn = connection.app.value.transcript.turn,
            focus = t.focusManager.primaryFocus;
        await bothDraft(t);
        await pressBounded(t, 'ctrl+c');
        expect(writes, ['draft']);
        expect(connection.app.value.transcript.turn, same(turn));
        expect(t.screen, shows('❯ 2. Always allow'));
        expect(t.focusManager.primaryFocus, same(focus));
        await bothDraft(t);
        await pressBounded(t, 'up c');
        expect(writes, ['draft', 'first code']);
        expect(connection.app.value.transcript.turn, same(turn));
        expect(t.screen, shows('❯ 2. Always allow'));
        await bothDraft(t);
        await pressBounded(t, 'esc');
        expect(t.screen, isNot(shows(pickHint)));
        expect(connection.app.value.transcript.turn, same(turn));
        expect(t.exitRequested, isFalse);
      },
    );
    testWidgets(
      'request wheel preserves real draft range/pick, request key scroll clears both even clamped $size',
      (t) async {
        final connection = selectionConnection([reply(body)]);
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
        await t.type('draft words');
        ask(connection);
        await t.pump();
        expect(connection.app.value.requestOverflows, isTrue);
        await bothDraft(t);
        final row = cellOf(t, 'proposed line 1');
        await t.mouse(
          MouseEvent(
            MouseEventKind.wheel,
            position: row,
            scrollDelta: const Offset(0, 1),
          ),
        );
        expect(t.screen, shows(pickHint));
        var at = cellOf(t, 'draft');
        expect(t.screen.styleAt(at.x, at.y).bg, const IndexedColor(66));
        expect(t.screen.lines.any((line) => line.contains('above')), isTrue);
        await pressBounded(t, 'pagedown');
        expect(t.screen, isNot(shows(pickHint)));
        at = cellOf(t, 'draft');
        expect(t.screen.styleAt(at.x, at.y).bg, isNot(const IndexedColor(66)));
        expect(writes, isEmpty);
        await pressBounded(t, 'ctrl+shift+c');
        expect(writes, isEmpty);
      },
    );
    testWidgets(
      'overflowing help wheel and key distinguish independent wheel from mode-clearing scroll $size',
      (t) async {
        final connection = selectionConnection([reply(body)]);
        addTearDown(connection.close);
        final old = connection.app.value;
        connection.app.value = AppState(
          start: old.start,
          transcript: old.transcript,
          shortcuts: const ShortcutsState(help: true),
        );
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
        await t.type('draft words');
        await t.resize(Size(size.width, 12));
        expect(connection.app.value.shortcuts.panelOverflows, isTrue);
        await bothDraft(t);
        final row = cellOf(t, 'enter to send');
        await t.mouse(
          MouseEvent(
            MouseEventKind.wheel,
            position: row,
            scrollDelta: const Offset(0, 1),
          ),
        );
        expect(t.screen, shows(pickHint));
        var at = cellOf(t, 'draft');
        expect(t.screen.styleAt(at.x, at.y).bg, const IndexedColor(66));
        await pressBounded(t, 'pagedown');
        expect(t.screen, isNot(shows(pickHint)));
        expect(connection.app.value.shortcuts.help, isTrue);
        at = cellOf(t, 'draft');
        expect(t.screen.styleAt(at.x, at.y).bg, isNot(const IndexedColor(66)));
        expect(writes, isEmpty);
      },
    );
    testWidgets(
      'replacing session cancels real range/pick and old IDs cannot copy the replacement slot $size',
      (t) async {
        final first = selectionConnection([reply(body)]),
            second = selectionConnection([
              reply('```\nsecond session code\n```'),
            ]);
        addTearDown(first.close);
        addTearDown(second.close);
        final current = ValueNotifier(first);
        addTearDown(current.dispose);
        final writes = <String>[];
        copy.CopyResult record(String text, CancellationToken token) {
          writes.add(text);
          return const copy.CopyResult.sent();
        }

        await t.pumpWidget(
          ListenableBuilder(
            listenable: current,
            builder: (_) => TranscriptWindow(
              launch: selectionLaunch,
              connection: current.value,
              copyOnSelect: false,
              copy: record,
            ),
          ),
          size: size,
        );
        await pressBounded(t, 'ctrl+x b');
        await select(t, 'selectable');
        expect(t.screen, shows(pickHint));
        current.value = second;
        await t.pump();
        expect(t.screen, isNot(shows(pickHint)));
        await pressBounded(t, 'ctrl+shift+c');
        expect(writes, isEmpty);
        await pressBounded(t, 'ctrl+x b c');
        expect(writes, ['second session code']);
      },
    );
    testWidgets(
      'narrow actual column omits copy control but real pick keys remain available $size',
      (t) async {
        final connection = selectionConnection([reply('```ts\nx\n```')]);
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
        await t.resize(Size(17, size.height));
        expect(t.screen, isNot(shows('[copy]')));
        await pressBounded(t, 'ctrl+x b');
        expect(t.screen, shows('↑ ↓ block'));
        await pressBounded(t, 'c');
        expect(writes, ['x']);
      },
    );
  }
}
