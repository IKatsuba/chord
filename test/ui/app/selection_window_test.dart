import 'dart:async';

import 'package:chord/cli.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const selectionLaunch = Launch(
  name: 'fixture',
  agent: null,
  agentCommand: 'unused',
  version: '0.0.1',
  directory: '.',
);
StartConnection selectionConnection([List<model.Entry>? entries]) =>
    StartConnection(command: 'unused', cwd: '.')
      ..app.value = AppState(
        start: const StartState(
          phase: StartPhase.connected,
          sessionId: 'selection',
        ),
        transcript: model.Transcript(
          entries: appended(
            [],
            entries ??
                [
                  const model.UserEntry('u', 'request text'),
                  model.AssistantEntry('a', TextRun.empty.plus('reply words')),
                ],
          ),
        ),
      );

MouseEvent primary(MouseEventKind kind, Offset at) =>
    MouseEvent(kind, position: at, button: MouseButton.primary);
Offset cellOf(WidgetTester t, String text, {bool end = false}) {
  final row = t.screen.lines.indexWhere((line) => line.contains(text));
  expect(row, greaterThanOrEqualTo(0), reason: t.screen.text);
  final line = t.screen.lines[row], index = line.indexOf(text);
  return Offset(
    cellWidth(line.substring(0, index)) + (end ? cellWidth(text) - 1 : 0),
    row,
  );
}

Future<void> select(WidgetTester t, String text) async {
  final start = cellOf(t, text), end = cellOf(t, text, end: true);
  await t.mouse(primary(MouseEventKind.press, start));
  await t.mouse(primary(MouseEventKind.move, end));
  await t.mouse(primary(MouseEventKind.release, end));
}

class RecordingTerminal extends Terminal {
  final copies = <String>[];
  final events = StreamController<TerminalState>.broadcast(sync: true);
  var enters = 0, leaves = 0;
  @override
  Size get size => const Size(120, 40);
  @override
  Stream<String> get input => const Stream.empty();
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  Stream<TerminalState> get states => events.stream;
  @override
  void enter() => enters++;
  @override
  Future<void> leave() async {
    leaves++;
  }

  @override
  void write(String data) => throw StateError('No terminal drawing expected');
  @override
  void copyToClipboard(String text) => copies.add(text);

  /// The program status reports, a clear as null.
  final statuses = <ProgramStatus?>[];
  @override
  void setProgramStatus(ProgramStatus status) => statuses.add(status);
  @override
  void clearProgramStatus({String? id}) => statuses.add(null);

  /// The notifications, as `notify` was called.
  final notified = <(String, NotificationChannel, String)>[];
  @override
  void notify(
    String message, {
    required NotificationChannel channel,
    String title = '',
  }) => notified.add((message, channel, title));

  /// The user variables set, as `setUserVariable` was called.
  final userVariables = <(String, String)>[];
  @override
  void setUserVariable(String name, String value) =>
      userVariables.add((name, value));
}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'auto sent retains highlight, explicit copy clears and keeps draft focus $size',
      (t) async {
        final connection = selectionConnection();
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
        final focus = t.focusManager.primaryFocus;
        final at = cellOf(t, 'reply');
        await select(t, 'reply');
        expect(writes, ['reply']);
        expect(t.screen, shows("sent 5 chars to the terminal's clipboard"));
        expect(t.screen.styleAt(at.x, at.y).bg, const IndexedColor(66));
        expect(t.focusManager.primaryFocus, same(focus));
        expect(connection.app.value.draft, isEmpty);
        await t.press('ctrl+c');
        expect(writes, ['reply', 'reply']);
        expect(t.screen.styleAt(at.x, at.y).bg, isNot(const IndexedColor(66)));
        expect(t.exitRequested, isFalse);
        expect(t.focusManager.primaryFocus, same(focus));
      },
    );

    testWidgets(
      'auto off exact header through transcript and draft boundaries reverse too $size',
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
        final header = cellOf(t, 'chord v0.0.1');
        final userEnd = cellOf(t, 'request text', end: true);
        for (final reverse in [false, true]) {
          await t.mouse(
            primary(MouseEventKind.press, reverse ? userEnd : header),
          );
          await t.mouse(
            primary(MouseEventKind.move, reverse ? header : userEnd),
          );
          await t.mouse(
            primary(MouseEventKind.release, reverse ? header : userEnd),
          );
          expect(writes, hasLength(reverse ? 1 : 0));
          expect(t.screen, shows('ctrl + c to copy'));
          await t.press('ctrl+shift+c');
          expect(
            writes.last,
            'chord v0.0.1\nfixture\n.\n? for shortcuts · /help\nrequest text',
          );
        }
        await t.type('draft text');
        final reply = cellOf(t, 'reply words'),
            draftEnd = cellOf(t, 'draft text', end: true);
        for (final reverse in [false, true]) {
          await t.mouse(
            primary(MouseEventKind.press, reverse ? draftEnd : reply),
          );
          await t.mouse(
            primary(MouseEventKind.move, reverse ? reply : draftEnd),
          );
          await t.mouse(
            primary(MouseEventKind.release, reverse ? reply : draftEnd),
          );
          await t.press('ctrl+shift+c');
          expect(writes.last, 'reply words\ndraft text');
        }
        expect(connection.app.value.draft, 'draft text');
      },
    );

    testWidgets(
      'pending selection copy ignores repeats and ordinary typing cancels late result $size',
      (t) async {
        final connection = selectionConnection();
        addTearDown(connection.close);
        final result = Completer<copy.CopyResult>();
        var calls = 0;
        late bool Function() cancelled;
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copy: (_, token) {
              calls++;
              cancelled = () => token.isCancelled;
              return result.future;
            },
          ),
          size: size,
        );
        await select(t, 'reply');
        await t.press('ctrl+c ctrl+shift+c');
        expect(calls, 1);
        await t.type('X');
        expect(cancelled(), isTrue);
        result.complete(const copy.CopyResult.sent());
        await t.pump();
        expect(connection.app.value.draft, 'X');
        expect(t.screen.text, isNot(contains('sent 5 chars')));
        expect(t.screen.text, isNot(contains('could not copy')));
      },
    );

    testWidgets(
      'failure retains retry, empty paste clears before normal editor behavior $size',
      (t) async {
        final connection = selectionConnection();
        addTearDown(connection.close);
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copy: (text, _) {
              writes.add(text);
              return const copy.CopyResult.failed('recorded failure');
            },
          ),
          size: size,
        );
        await select(t, 'reply');
        expect(
          t.screen,
          shows('could not copy: recorded failure · ctrl + c to try again'),
        );
        await t.press('ctrl+c');
        expect(writes, ['reply', 'reply']);
        await t.paste('');
        expect(connection.app.value.draft, isEmpty);
        expect(t.screen.text, isNot(contains('could not copy')));
        await t.press('ctrl+c');
        expect(writes, hasLength(2));
        expect(connection.app.value.quitArmed, isTrue);
      },
    );

    testWidgets(
      'borrowed terminal is synchronous sent and adapter override owns no lifecycle $size',
      (t) async {
        final connection = selectionConnection();
        addTearDown(connection.close);
        final terminal = RecordingTerminal();
        addTearDown(terminal.events.close);
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            terminal: terminal,
          ),
          size: size,
        );
        await select(t, 'reply');
        expect(terminal.copies, ['reply']);
        expect(t.screen, shows("sent 5 chars to the terminal's clipboard"));
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            terminal: terminal,
            copy: (text, _) {
              writes.add(text);
              return const copy.CopyResult.copied();
            },
          ),
          size: size,
        );
        await select(t, 'reply');
        expect(terminal.copies, hasLength(1));
        expect(writes, ['reply']);
        expect(t.screen, shows('copied 5 chars to clipboard'));
        expect((terminal.enters, terminal.leaves), (0, 0));
      },
    );
  }
}
