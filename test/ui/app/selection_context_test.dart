import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/conversation.dart';
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

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'queued words are excluded while adjacent reply remains eligible $size',
      (t) async {
        final connection = selectionConnection();
        addTearDown(connection.close);
        final old = connection.app.value;
        connection.app.value = AppState(
          start: old.start,
          transcript: model.Transcript(
            entries: old.transcript.entries,
            turn: const model.Working('t', 0),
          ),
          queue: const [QueuedPrompt('q', 'queued furniture')],
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
        await select(t, 'queued furniture');
        await t.press('ctrl+shift+c');
        expect(writes, isEmpty);
        await select(t, 'reply');
        await t.press('ctrl+shift+c');
        expect(writes, ['reply']);
        expect(connection.app.value.queue.single.text, 'queued furniture');
      },
    );
    testWidgets(
      'virtual history copies every crossed never-mounted source exactly once $size',
      (t) async {
        final entries = <model.Entry>[
          for (var i = 0; i < 100; i++)
            model.UserEntry('t$i', 'history item $i'),
          const model.ReportEntry('tail', 'status', []),
        ];
        final connection = selectionConnection(entries);
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
        await t.press('home');
        final start = cellOf(t, 'history item 0');
        await t.mouse(primary(MouseEventKind.press, start));
        await t.press('end');
        expect(t.screen, isNot(shows('history item 0')));
        final end = cellOf(t, 'history item 99', end: true);
        await t.mouse(primary(MouseEventKind.move, end));
        await t.mouse(primary(MouseEventKind.release, end));
        await t.press('ctrl+shift+c');
        expect(writes, [
          [for (var i = 0; i < 100; i++) 'history item $i'].join('\n'),
        ]);
      },
    );
    testWidgets(
      'synchronous adapter input cancels its own old generation before a deferred effect $size',
      (t) async {
        final connection = selectionConnection();
        addTearDown(connection.close);
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copy: (text, token) {
              t.host.handleKey(const KeyEvent('z'));
              if (!token.isCancelled) writes.add(text);
              return const copy.CopyResult.sent();
            },
          ),
          size: size,
        );
        await select(t, 'reply');
        expect(connection.app.value.draft, 'z');
        expect(writes, isEmpty);
        expect(t.screen, isNot(shows('sent 5 chars')));
        expect(t.exitRequested, isFalse);
      },
    );
    testWidgets(
      'explicit copy reads replacement source text rather than cached release text $size',
      (t) async {
        final connection = selectionConnection();
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
        await select(t, 'reply');
        final old = connection.app.value;
        connection.app.value = AppState(
          start: old.start,
          transcript: model.Transcript(
            entries: replacedAt(
              old.transcript.entries,
              1,
              model.AssistantEntry('a', TextRun.empty.plus('fresh words')),
            ),
          ),
        );
        await t.pump();
        await t.press('ctrl+c');
        expect(writes, ['fresh']);
        expect(t.exitRequested, isFalse);
      },
    );
    testWidgets(
      'resize and borrowed terminal suspension cancel pending copy without a late note $size',
      (t) async {
        final connection = selectionConnection();
        addTearDown(connection.close);
        final terminal = RecordingTerminal();
        addTearDown(terminal.events.close);
        final pending = <Completer<copy.CopyResult>>[];
        final tokens = <CancellationToken>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            terminal: terminal,
            copy: (_, token) {
              tokens.add(token);
              final result = Completer<copy.CopyResult>();
              pending.add(result);
              return result.future;
            },
          ),
          size: size,
        );
        await select(t, 'reply');
        expect(tokens.single.isCancelled, isFalse);
        await t.resize(Size(size.width - 1, size.height));
        expect(tokens.single.isCancelled, isTrue);
        pending.single.complete(const copy.CopyResult.sent());
        await t.pump();
        expect(t.screen, isNot(shows('sent 5 chars')));
        await select(t, 'reply');
        terminal.events.add(TerminalState.suspended);
        await t.pump();
        expect(tokens.last.isCancelled, isTrue);
        pending.last.complete(const copy.CopyResult.sent());
        await t.pump();
        expect(t.screen, isNot(shows('sent 5 chars')));
        expect(terminal.copies, isEmpty);
        expect((terminal.enters, terminal.leaves), (0, 0));
      },
    );
    testWidgets(
      'pending prefix CtrlC clears draft while a miss never replays suffix $size',
      (t) async {
        final connection = selectionConnection();
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
        await t.type('draft');
        await select(t, 'reply');
        await t.press('ctrl+x');
        expect(t.focusManager.pendingChord, [KeyCombo.parse('ctrl+x')]);
        await t.press('ctrl+c');
        expect(writes, isEmpty);
        expect(connection.app.value.draft, isEmpty);
        expect(t.exitRequested, isFalse);
        await select(t, 'reply');
        await t.press('ctrl+x');
        await t.press('z');
        expect(connection.app.value.draft, isEmpty);
        expect(t.focusManager.pendingChord, isEmpty);
        await t.press('ctrl+shift+c');
        expect(writes, isEmpty);
      },
    );
    testWidgets(
      'permission diff opts in while request text stays excluded and copy precedes picker $size',
      (t) async {
        final connection = selectionConnection();
        addTearDown(connection.close);
        final old = connection.app.value;
        connection.app.value = AppState(
          start: old.start,
          transcript: model.Transcript(
            turn: model.AwaitingPermission('turn', 0, [
              model.PermissionWait(
                'permission',
                title: 'Request furniture',
                kind: 'edit',
                content: [
                  acp.ToolCallContent.fromJson({
                    'type': 'diff',
                    'path': 'file.txt',
                    'newText': 'eligible proposal\n',
                  }),
                ],
                options: [
                  acp.PermissionOption.fromJson({
                    'optionId': 'allow',
                    'name': 'Allow once',
                    'kind': 'allow_once',
                  }),
                ],
              ),
            ]),
          ),
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
        await select(t, 'Request furniture');
        await t.press('ctrl+shift+c');
        expect(writes, isEmpty);
        final focus = t.focusManager.primaryFocus;
        await select(t, 'eligible proposal');
        await t.press('ctrl+c');
        expect(writes, ['eligible proposal']);
        expect(t.focusManager.primaryFocus, same(focus));
        expect(
          connection.app.value.transcript.turn,
          isA<model.AwaitingPermission>(),
        );
        expect(t.exitRequested, isFalse);
      },
    );
  }
}
