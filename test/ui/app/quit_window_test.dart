import 'package:chord/cli.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/shortcuts/state.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

const statusAgent = AgentState(
  models: {
    'currentModelId': 'm',
    'availableModels': [
      {'modelId': 'm', 'name': 'Reported model'},
    ],
  },
);

const launch = Launch(
  name: 'fixture',
  agent: null,
  agentCommand: 'unused',
  version: '0.0.1',
  directory: '.',
);

void settled(FakeAsync async, Future<void> future) {
  var done = false;
  Object? error;
  future.then(
    (_) => done = true,
    onError: (Object caught) {
      error = caught;
      done = true;
    },
  );
  async.elapse(Duration.zero);
  expect(done, isTrue, reason: 'Widget operation did not settle');
  if (error != null) throw error!;
}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    test(
      'quit deadline is exactly 2000 ms, navigation keeps arming, and disposal cancels it at $size',
      () {
        fakeAsync((async) {
          final t = WidgetTester();
          final connection = StartConnection(command: 'unused', cwd: '.')
            ..app.value = const AppState(
              start: StartState(phase: StartPhase.connected),
              agent: statusAgent,
            );
          try {
            settled(
              async,
              t.pumpWidget(
                TranscriptWindow(launch: launch, connection: connection),
                size: size,
              ),
            );
            settled(async, t.press('ctrl+c'));
            expect(t.exitRequested, isFalse);
            expect(t.screen.lines.last, '  Press ctrl+c again to quit');
            async.elapse(const Duration(milliseconds: 1999));
            settled(async, t.press('home'));
            expect(connection.app.value.quitArmed, isTrue);
            async.elapse(const Duration(milliseconds: 1));
            settled(async, t.pump());
            expect(connection.app.value.quitArmed, isFalse);
            expect(t.screen, isNot(shows('Press ctrl+c again')));
            expect(t.screen.lines.last, contains('Reported model'));
            settled(async, t.press('ctrl+c'));
            expect(connection.app.value.quitArmed, isTrue);
            async.elapse(const Duration(milliseconds: 1999));
            settled(async, t.press('ctrl+c'));
            expect(t.exitRequested, isTrue);
          } finally {
            t.dispose();
            settled(async, connection.close());
          }
          expect(async.pendingTimers, isEmpty);
        });
      },
    );
    test(
      'spaces clear and disarm, Ctrl+D on draft is inert, and exit is requested once at $size',
      () {
        fakeAsync((async) {
          final t = WidgetTester();
          final connection = StartConnection(command: 'unused', cwd: '.')
            ..app.value = const AppState(
              start: StartState(phase: StartPhase.connected),
            );
          try {
            settled(
              async,
              t.pumpWidget(
                TranscriptWindow(launch: launch, connection: connection),
                size: size,
              ),
            );
            var exits = 0;
            t.host.owner.onExit = () => exits++;
            settled(async, t.press('ctrl+c'));
            settled(async, t.type('   '));
            settled(async, t.press('ctrl+d'));
            expect(exits, 0);
            expect(connection.app.value.draft, '   ');
            settled(async, t.press('ctrl+c'));
            expect(connection.app.value.draft, '');
            expect(connection.app.value.cursor, 0);
            expect(connection.app.value.quitArmed, isFalse);
            async.elapse(const Duration(milliseconds: 3000));
            expect(connection.app.value.quitArmed, isFalse);
            settled(async, t.press('ctrl+d ctrl+d ctrl+c'));
            expect(exits, 1);
          } finally {
            t.dispose();
            settled(async, connection.close());
          }
          expect(async.pendingTimers, isEmpty);
        });
      },
    );
    test(
      'quit arming closes help without interrupting running or queued work at $size',
      () {
        fakeAsync((async) {
          final t = WidgetTester();
          final connection = StartConnection(command: 'unused', cwd: '.')
            ..app.value = const AppState(
              start: StartState(phase: StartPhase.connected),
              transcript: model.Transcript(turn: model.Working('turn', 0)),
              queue: [QueuedPrompt('next', 'later')],
              shortcuts: ShortcutsState(help: true, panelOverflows: true),
            );
          final before = connection.app.value;
          try {
            settled(
              async,
              t.pumpWidget(
                TranscriptWindow(launch: launch, connection: connection),
                size: size,
              ),
            );
            settled(async, t.press('ctrl+c'));
            expect(connection.app.value.quitArmed, isTrue);
            expect(connection.app.value.shortcuts.help, isFalse);
            expect(connection.app.value.shortcuts.panelOverflows, isFalse);
            expect(connection.app.value.transcript, same(before.transcript));
            expect(connection.app.value.queue, same(before.queue));
            expect(t.exitRequested, isFalse);
          } finally {
            t.dispose();
            settled(async, connection.close());
          }
          expect(async.pendingTimers, isEmpty);
        });
      },
    );
  }
  test('a replaced connection is not disarmed by the old window deadline', () {
    fakeAsync((async) {
      final t = WidgetTester();
      final first = StartConnection(command: 'unused', cwd: '.')
        ..app.value = const AppState(
          start: StartState(phase: StartPhase.connected),
        );
      final second = StartConnection(command: 'unused', cwd: '.')
        ..app.value = const AppState(
          start: StartState(phase: StartPhase.connected),
        );
      final current = ValueNotifier(first);
      try {
        settled(
          async,
          t.pumpWidget(
            ListenableBuilder(
              listenable: current,
              builder: (_) =>
                  TranscriptWindow(launch: launch, connection: current.value),
            ),
          ),
        );
        settled(async, t.press('ctrl+c'));
        async.elapse(const Duration(milliseconds: 1500));
        current.value = second;
        settled(async, t.pump());
        settled(async, t.press('ctrl+c'));
        async.elapse(const Duration(milliseconds: 501));
        expect(second.app.value.quitArmed, isTrue);
        async.elapse(const Duration(milliseconds: 1499));
        expect(second.app.value.quitArmed, isFalse);
        expect(first.app.value.quitArmed, isTrue);
      } finally {
        t.dispose();
        current.dispose();
        settled(async, first.close());
        settled(async, second.close());
      }
      expect(async.pendingTimers, isEmpty);
    });
  });

  group('tester: quit deadline isolation', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      test('clear and rearm cannot inherit the previous deadline at $size', () {
        fakeAsync((async) {
          final t = WidgetTester();
          final connection = StartConnection(command: 'unused', cwd: '.')
            ..app.value = const AppState(
              start: StartState(phase: StartPhase.connected),
            );
          try {
            settled(
              async,
              t.pumpWidget(
                TranscriptWindow(launch: launch, connection: connection),
                size: size,
              ),
            );
            settled(async, t.press('ctrl+c'));
            async.elapse(const Duration(milliseconds: 1000));
            settled(async, t.paste('👩‍💻e\u0301'));
            settled(async, t.press('ctrl+c'));
            expect(connection.app.value.quitArmed, isFalse);
            expect(async.pendingTimers, isEmpty);
            settled(async, t.press('ctrl+c'));
            async.elapse(const Duration(milliseconds: 1000));
            settled(async, t.pump());
            expect(connection.app.value.quitArmed, isTrue);
            expect(t.screen.lines.last, '  Press ctrl+c again to quit');
            async.elapse(const Duration(milliseconds: 1000));
            settled(async, t.pump());
            expect(connection.app.value.quitArmed, isFalse);
            expect(t.exitRequested, isFalse);
          } finally {
            t.dispose();
            settled(async, connection.close());
          }
          expect(async.pendingTimers, isEmpty);
        });
      });
    }

    test('two windows own separate quit deadlines and exit requests', () {
      fakeAsync((async) {
        final first = WidgetTester();
        final second = WidgetTester();
        final a = StartConnection(command: 'unused', cwd: '.')
          ..app.value = const AppState(
            start: StartState(phase: StartPhase.connected),
          );
        final b = StartConnection(command: 'unused', cwd: '.')
          ..app.value = const AppState(
            start: StartState(phase: StartPhase.connected),
          );
        try {
          settled(
            async,
            first.pumpWidget(
              TranscriptWindow(launch: launch, connection: a),
              size: const Size(80, 24),
            ),
          );
          settled(
            async,
            second.pumpWidget(
              TranscriptWindow(launch: launch, connection: b),
              size: const Size(120, 40),
            ),
          );
          settled(async, first.press('ctrl+c'));
          async.elapse(const Duration(milliseconds: 1000));
          settled(async, second.press('ctrl+c'));
          async.elapse(const Duration(milliseconds: 1000));
          expect(a.app.value.quitArmed, isFalse);
          expect(b.app.value.quitArmed, isTrue);
          settled(async, second.press('ctrl+c'));
          expect(second.exitRequested, isTrue);
          expect(first.exitRequested, isFalse);
          async.elapse(const Duration(milliseconds: 3000));
          expect(a.app.value.quitArmed, isFalse);
        } finally {
          first.dispose();
          second.dispose();
          settled(async, a.close());
          settled(async, b.close());
        }
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}
