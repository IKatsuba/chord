import 'package:chord/cli.dart';
import 'package:chord/ui/start.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const launch = Launch(
  name: 'fake',
  agent: null,
  agentCommand: 'fake --acp',
  version: '0.0.1',
  directory: '/workspace/demo',
);

const header = ' chord v0.0.1 · fake · /workspace/demo';
const hint = ' ctrl+c or ctrl+d to quit';

StartState after(List<StartEvent> events) =>
    events.fold(StartState.idle, reduceStart);

final starting = after([const StartRequested()]);
final connected = after([const StartRequested(), const SessionOpened('s1')]);

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at ${size.width}x${size.height}', () {
      Future<List<String>> shown(WidgetTester t, StartState state) async {
        await t.pumpWidget(
          StartWindow(launch: launch, state: ValueNotifier(state)),
          size: size,
        );
        return t.screen.lines;
      }

      void blankFrom(List<String> lines, int row) => expect(
        lines.skip(row).every((line) => line.isEmpty),
        isTrue,
        reason: 'rows from $row are blank',
      );

      testWidgets('starting says so, dim, above the hint', (t) async {
        final lines = await shown(t, starting);
        expect(lines.take(3), [header, ' Starting fake…', hint]);
        blankFrom(lines, 3);
        for (var x = 1; x < lines[1].length; x++) {
          expect(t.screen.styleAt(x, 1).isDim, isTrue, reason: 'cell $x');
        }
      });

      testWidgets('connected says Connected, dim, and nothing more', (t) async {
        final lines = await shown(t, connected);
        expect(lines.take(3), [header, ' Connected', hint]);
        blankFrom(lines, 3);
        expect(t.screen.styleAt(1, 1).isDim, isTrue);
      });

      testWidgets('a failed start in the error style, its stderr below the '
          'hint', (t) async {
        final state = after([
          const StartRequested(),
          const StartFailed(
            'The agent exited.',
            lines: [
              'Traceback (most recent call last):',
              'RuntimeError: scripted start failure',
            ],
            cut: 3,
          ),
        ]);
        final lines = await shown(t, state);
        expect(lines.take(7), [
          header,
          ' fake did not start: The agent exited.',
          hint,
          ' The end of its stderr:',
          '   … +3 lines',
          '   Traceback (most recent call last):',
          '   RuntimeError: scripted start failure',
        ]);
        blankFrom(lines, 7);
        final error = ThemeData.fallback().error;
        expect(t.screen.styleAt(1, 1), error);
        expect(t.screen.styleAt(1, 3).isDim, isTrue);
        expect(t.screen.styleAt(3, 5).isDim, isFalse);
      });

      testWidgets('a failed start with no stderr has no details', (t) async {
        final state = after([
          const StartRequested(),
          const StartFailed('cannot start fake: not found'),
        ]);
        final lines = await shown(t, state);
        expect(lines.take(3), [
          header,
          ' fake did not start: cannot start fake: not found',
          hint,
        ]);
        blankFrom(lines, 3);
      });

      testWidgets('gone says the agent exited, its stderr below', (t) async {
        final state = after([
          const StartRequested(),
          const SessionOpened('s1'),
          const AgentExited('The agent exited.', lines: ['bye']),
        ]);
        final lines = await shown(t, state);
        expect(lines.take(5), [
          header,
          ' The agent exited.',
          hint,
          ' The end of its stderr:',
          '   bye',
        ]);
        blankFrom(lines, 5);
      });

      testWidgets('redraws as the state moves', (t) async {
        final state = ValueNotifier(starting);
        await t.pumpWidget(
          StartWindow(launch: launch, state: state),
          size: size,
        );
        expect(t.screen.lines[1], ' Starting fake…');
        state.value = connected;
        await t.pump();
        expect(t.screen.lines[1], ' Connected');
      });

      testWidgets('a long status ends in … on its own row, the hint kept', (
        t,
      ) async {
        final state = after([
          const StartRequested(),
          StartFailed('x' * 300, lines: ['y' * 300]),
        ]);
        final lines = await shown(t, state);
        expect(lines[1], endsWith('…'));
        expect(lines[1].length, size.width - 1);
        expect(lines[2], hint);
        expect(lines[4], endsWith('…'));
      });

      testWidgets("escapes in the agent's words are shown, not run", (t) async {
        final state = after([
          const StartRequested(),
          const StartFailed('bad\x1b[2Jworse', lines: ['\x1b]0;title\x07x']),
        ]);
        final lines = await shown(t, state);
        expect(lines[1], ' fake did not start: bad�[2Jworse');
        expect(lines[4], '   �]0;title�x');
      });

      testWidgets('both keys quit in every state, and nothing else is bound', (
        t,
      ) async {
        for (final key in ['ctrl+c', 'ctrl+d']) {
          final tester = WidgetTester();
          await tester.pumpWidget(
            StartWindow(launch: launch, state: ValueNotifier(starting)),
            size: size,
          );
          expect(
            [
              for (final b in tester.focusManager.activeBindings)
                '${b.chord}: ${b.description}',
            ],
            ['ctrl+c: quit', 'ctrl+d: quit'],
          );
          await tester.press(key);
          expect(tester.exitRequested, isTrue);
          tester.dispose();
        }
      });
    });
  }

  testWidgets('at a tiny height the details go first, the hint stays', (
    t,
  ) async {
    final state = after([
      const StartRequested(),
      const StartFailed('The agent exited.', lines: ['a', 'b']),
    ]);
    await t.pumpWidget(
      StartWindow(launch: launch, state: ValueNotifier(state)),
      size: const Size(80, 3),
    );
    expect(t.screen.lines, [
      header,
      ' fake did not start: The agent exited.',
      hint,
    ]);
    await t.press('ctrl+d');
    expect(t.exitRequested, isTrue);
  });

  group('tester status lifecycle', () {
    final phases = [
      starting,
      connected,
      after([
        const StartRequested(),
        const StartFailed('failed', lines: ['界😀é']),
      ]),
      after([
        const StartRequested(),
        const SessionOpened('s'),
        const AgentExited('gone'),
      ]),
    ];
    for (final state in phases) {
      for (final key in ['ctrl+c', 'ctrl+d']) {
        testWidgets('${state.phase} quits with $key even with one cell', (
          t,
        ) async {
          await t.pumpWidget(
            StartWindow(launch: launch, state: ValueNotifier(state)),
            size: const Size(1, 1),
          );
          await t.press('escape');
          expect(t.exitRequested, isFalse);
          await t.press(key);
          expect(t.exitRequested, isTrue);
        });
      }
    }

    testWidgets(
      'a thousand updates settle once and removal detaches the notifier',
      (t) async {
        final state = ValueNotifier(starting);
        addTearDown(state.dispose);
        await t.pumpWidget(
          StartWindow(launch: launch, state: state),
          size: const Size(120, 40),
        );
        for (var i = 0; i < 1000; i++) {
          state.value = StartState(
            phase: StartPhase.failed,
            reason: 'update $i 界😀é',
          );
        }
        await t.pump();
        expect(t.screen.lines[1], ' fake did not start: update 999 界😀é');
        await t.resize(const Size(80, 24));
        expect(t.screen.lines[2], hint);
        await t.pumpWidget(Text('replacement'));
        state.value = connected;
        await t.pump();
        expect(t.screen, shows('replacement'));
        expect(t.focusManager.activeBindings, isEmpty);
        await t.pumpWidget(StartWindow(launch: launch, state: state));
        expect(t.screen.lines[1], ' Connected');
        await t.press('ctrl+d');
        expect(t.exitRequested, isTrue);
      },
    );
  });
}
