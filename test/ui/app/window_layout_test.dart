import 'package:chord/cli.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const launch = Launch(
  name: 'fixture',
  agent: null,
  agentCommand: 'unused',
  version: '0.0.1',
  directory: 'project/package',
);
const agent = AgentState(
  models: {
    'currentModelId': 'model',
    'availableModels': [
      {'modelId': 'model', 'name': 'Fixture model'},
    ],
  },
);

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'compact header scrolls with transcript and keeps prompt/status at $size',
      (t) async {
        final connection = StartConnection(command: 'unused', cwd: '.');
        addTearDown(connection.close);
        connection.app.value = const AppState(
          start: StartState(phase: StartPhase.connected),
          agent: agent,
        );
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: connection),
          size: size,
        );
        expect(t.screen.lines[0], contains('chord v0.0.1'));
        expect(t.screen.lines[1], contains('fixture · Fixture model'));
        expect(t.screen.lines[2], contains('project/package'));
        expect(t.screen.lines[3], contains('? for shortcuts'));
        expect(t.screen.styleAt(8, 0).isBold, isTrue);
        expect(t.screen.lines.last, contains('Fixture model'));
        await t.type('draft');
        final promptRow = t.screen.lines.indexWhere(
          (line) => line.startsWith('╭'),
        );
        connection.app.value = AppState(
          start: const StartState(phase: StartPhase.connected),
          agent: agent,
          transcript: model.Transcript(
            entries: [
              for (var i = 0; i < 100; i++) model.UserEntry('t$i', 'row $i'),
            ],
          ),
        );
        await t.pump();
        expect(t.screen, isNot(shows('chord v')));
        expect(t.screen, shows('row 99'));
        expect(
          t.screen.lines.indexWhere((line) => line.startsWith('╭')),
          promptRow,
        );
        await t.press('home');
        expect(t.screen.lines[0], contains('chord v0.0.1'));
        expect(t.screen, shows('lines below'));
        expect(connection.app.value.scroll.following, isFalse);
        await t.press('end');
        expect(t.screen, isNot(shows('lines below')));
        expect(connection.app.value.scroll.following, isTrue);
        expect(t.screen, shows('│ › draft'));
      },
    );
    testWidgets(
      'window keys use fresh controller context and controlled details at $size',
      (t) async {
        final connection = StartConnection(command: 'unused', cwd: '.');
        addTearDown(connection.close);
        connection.app.value = AppState(
          start: const StartState(phase: StartPhase.connected),
          transcript: model.Transcript(
            entries: [
              model.ThoughtEntry('turn', TextRun.empty.plus('private thought')),
            ],
          ),
        );
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: connection),
          size: size,
        );
        expect(t.screen, isNot(shows('private thought')));
        await t.press('ctrl+o');
        expect(connection.app.value.expanded, isTrue);
        expect(t.screen, shows('private thought'));
        await t.paste('界👩‍💻é');
        await t.press('left');
        expect(connection.app.value.draft, '界👩‍💻é');
        expect(connection.app.value.cursor, 2);
        await t.press('ctrl+d');
        expect(t.exitRequested, isFalse);
        await t.press('ctrl+c');
        expect(connection.app.value.draft, '');
        expect(connection.app.value.cursor, 0);
        expect(t.exitRequested, isFalse);
        await t.press('ctrl+c');
        expect(connection.app.value.quitArmed, isTrue);
        expect(t.screen.lines.last, contains('Press ctrl+c again to quit'));
        await t.press('ctrl+c');
        expect(t.exitRequested, isTrue);
      },
    );
  }

  group('tester: live window controller and layout edges', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'fresh draft context survives footer changes and Ctrl+D at $size',
        (t) async {
          final connection = StartConnection(command: 'unused', cwd: '.');
          addTearDown(connection.close);
          connection.app.value = const AppState(
            start: StartState(phase: StartPhase.connected),
          );
          await t.pumpWidget(
            TranscriptWindow(launch: launch, connection: connection),
            size: size,
          );
          await t.paste('界👩‍💻e\u0301');
          await t.press('left');
          await t.type('?');
          expect(connection.app.value.draft, '界👩‍💻?e\u0301');
          expect(connection.app.value.cursor, 3);
          connection.app.value = reduceApp(
            connection.app.value,
            const Queued('queue', 'queued'),
          );
          await t.pump();
          await t.press('ctrl+d');
          expect(t.exitRequested, isFalse);
          expect(connection.app.value.draft, '界👩‍💻?e\u0301');
          expect(connection.app.value.cursor, 3);
          await t.press('ctrl+c');
          expect(connection.app.value.draft, '');
          expect(connection.app.value.cursor, 0);
          await t.paste('界\\尾');
          await t.press('left enter');
          expect(connection.app.value.draft, '界\n尾');
          expect(connection.app.value.cursor, 2);
          expect(connection.app.value.transcript.entries, isEmpty);
        },
      );

      testWidgets(
        'a thousand transcript updates retain draft and resize anchoring at $size',
        (t) async {
          final connection = StartConnection(command: 'unused', cwd: '.');
          addTearDown(connection.close);
          connection.app.value = const AppState(
            start: StartState(phase: StartPhase.connected),
            agent: agent,
          );
          await t.pumpWidget(
            TranscriptWindow(launch: launch, connection: connection),
            size: size,
          );
          await t.paste('👩‍💻e\u0301界');
          await t.press('left');
          for (var i = 0; i < 1000; i++) {
            connection.app.value = AppState(
              start: const StartState(phase: StartPhase.connected),
              agent: agent,
              transcript: model.Transcript(
                entries: [model.UserEntry('turn', 'latest $i')],
              ),
            );
          }
          await t.pump();
          expect(t.screen, shows('latest 999'));
          await t.press('right');
          expect(connection.app.value.draft, '👩‍💻e\u0301界');
          expect(connection.app.value.cursor, 3);
          await t.resize(const Size(20, 12));
          await t.resize(size);
          expect(t.screen, shows('latest 999'));
          expect(t.screen, shows('│ › 👩‍💻e\u0301界'));
        },
      );
    }

    for (final size in [const Size(0, 0), const Size(1, 1)]) {
      testWidgets('tiny window $size recovers its controller after resize', (
        t,
      ) async {
        final connection = StartConnection(command: 'unused', cwd: '.');
        addTearDown(connection.close);
        connection.app.value = const AppState(
          start: StartState(phase: StartPhase.connected),
        );
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: connection),
          size: size,
        );
        await t.resize(const Size(80, 24));
        await t.paste('界🙂e\u0301');
        expect(connection.app.value.draft, '界🙂e\u0301');
        expect(connection.app.value.cursor, 3);
        expect(t.screen, shows('│ › 界🙂e\u0301'));
      });
    }
  });
}
