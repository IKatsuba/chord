// The agents list under the status line, sharing a short window with each
// kind of request as the original does (design CTUI-35 section 6, "The
// room"): the request's choices and the status line stay in sight, the
// list folds to its floor or shares with a plan's Note, and comes back to
// its limit once the request is answered.
import 'package:chord/session/conversation.dart';
import 'package:chord/session/questions.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/wheel.dart' show wheelPermission;
import '../../fixtures/forms.dart';
import '../../session/conversation_fake.dart';
import 'editor_window_test.dart' show EditorTerminal, settle;
import 'front_routing_test.dart' show window;

/// The window with three children: `parser`, then `docs` and `other`.
Future<StartConnection> _three(WidgetTester t, Size size) async {
  final w = await window(t, size, EditorTerminal());
  for (final (index, name) in ['docs', 'other'].indexed) {
    final session = ScriptedSession();
    w.connection.agents.openChild(
      ChildInfo(
        id: 'a${index + 2}',
        name: name,
        runtime: 'fake',
        openedAt: 0,
        colour: index + 1,
      ),
      (emit, key) {
        w.connection.fold.dispatch(AgentOpened(key));
        return Conversation(
          ({required onTraffic, required cancellationToken}) async => session,
        )..listen(emit);
      },
    );
  }
  await settle(t);
  return w.connection;
}

/// Main's transcript with [turn], [planAsks] and [asking].
void _ask(
  StartConnection connection, {
  model.TurnState turn = const model.Working('t', 0),
  List<model.PlanAsk> planAsks = const [],
  List<model.ElicitationWait> asking = const [],
}) {
  final old = connection.app.value;
  connection.app.value = AppState(
    start: old.start,
    transcript: model.Transcript(
      entries: old.transcript.entries,
      turn: turn,
      planAsks: planAsks,
      asking: asking,
    ),
  );
}

/// The list's lines, under the status line.
List<String> _list(WidgetTester t) {
  final lines = t.screen.lines;
  final first = lines.indexWhere((line) => line.startsWith('    main '));
  return first < 0 ? const [] : lines.sublist(first);
}

const _plan = model.PlanAsk(
  't',
  model.PlanWait('plan', model.PlanAgent.cursor, toolCallId: 'c'),
);

const _questions = Questions(QuestionsAgent.claude, [
  Question(
    id: 'q',
    text: 'Which language?',
    options: [
      QuestionOption(value: 'dart', title: 'Dart'),
      QuestionOption(value: 'ts', title: 'TypeScript'),
      QuestionOption(value: 'go', title: 'Go'),
    ],
    multiSelect: false,
    required: true,
  ),
]);

/// The rows the list draws whole, its four agents.
const _whole = [
  '    main    fake  ◦ idle 0s',
  '    parser  fake  ◦ idle 0s',
  '    docs    fake  ◦ idle 0s',
  '    other   fake  ◦ idle 0s',
];

/// The list back at its limit once nothing is asked.
Future<void> _answered(WidgetTester t, StartConnection connection) async {
  _ask(connection, turn: const model.Idle());
  await t.pump();
  await t.pump();
  expect(_list(t), _whole);
  expect(t.screen, shows('Starting fake…'));
}

void main() {
  _testerRoomResizes();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    final short = size.height == 24;

    testWidgets('with no request the list is whole under the status line, '
        'at $size', (t) async {
      await _three(t, size);
      expect(_list(t), _whole);
      final lines = t.screen.lines;
      expect(lines[lines.length - 5], '  Starting fake…');
    });

    testWidgets('a plan box as asked leaves the list whole, at $size', (
      t,
    ) async {
      final connection = await _three(t, size);
      _ask(connection, planAsks: const [_plan]);
      await t.pump();
      await t.pump();
      expect(t.screen, shows('❯ 1. Yes, accept the plan'));
      expect(t.screen, shows('2. No, keep planning'));
      expect(t.screen, shows('Starting fake…'));
      expect(_list(t), _whole);
      await _answered(t, connection);
    });

    // The Note at 3 and at 5 lines at 80 columns (the port's Note wraps
    // by cells, 68 a line): at 80x24, three lines keep two rows and the
    // list whole; five keep three rows, the list two agents and
    // `… +2 more`, as the original's captures show.
    for (final (words, lines) in const [(35, 3), (58, 5)]) {
      testWidgets('a Note of $lines lines shares the rows with the list as '
          'the original does, at $size', (t) async {
        final connection = await _three(t, size);
        _ask(connection, planAsks: const [_plan]);
        await t.pump();
        await t.press('down');
        await t.press('down');
        await t.type(List.filled(words, 'word').join(' '));
        await t.pump();
        await t.pump();
        expect(t.screen, shows('Starting fake…'));
        expect(t.screen, shows('Enter to keep planning with this note'));
        final note = t.screen.lines.indexWhere(
          (line) => line.contains('❯ Note'),
        );
        if (short && lines == 5) {
          expect(_list(t), [..._whole.take(2), '    … +2 more']);
          expect(t.screen.lines[note], contains('↑ 3 lines above'));
          // The rule and two lines of the Note, then the gap above the
          // hint.
          expect(t.screen.lines[note + 1], contains('word word'));
          expect(t.screen.lines[note + 2], contains('word'));
          expect(t.screen.lines[note + 3], isNot(contains('word')));
        } else if (short) {
          expect(_list(t), _whole);
          expect(t.screen.lines[note], contains('↑ 2 lines above'));
          // The rule and one line of the Note.
          expect(t.screen.lines[note + 1], contains('word word'));
          expect(t.screen.lines[note + 2], isNot(contains('word')));
        } else {
          expect(_list(t), _whole);
          expect(t.screen.lines[note], isNot(contains('↑ ')));
        }
        _ask(
          connection,
          planAsks: [_plan.answered(const model.PlanAccepted())],
        );
        await t.pump();
        await _answered(t, connection);
      });
    }

    testWidgets("a permission body gives way only past the list's floor, "
        'at $size', (t) async {
      final connection = await _three(t, size);
      _ask(
        connection,
        turn: model.AwaitingPermission('t', 0, [wheelPermission()]),
      );
      await t.pump();
      await t.pump();
      expect(t.screen, shows('❯ 1. Allow once'));
      expect(t.screen, shows('3. Deny'));
      expect(t.screen, shows('Esc to reject'));
      expect(t.screen, shows('Starting fake…'));
      expect(_list(t), [_whole.first, '    … +3 more']);
      expect(t.screen, shows(short ? '↓ 58 lines below' : '↓ 42 lines below'));
      await _answered(t, connection);
    });

    testWidgets('a permission over a held form hides the form as the '
        'original does; answered, the held form shares the rows with the list, '
        'at $size', (t) async {
      final connection = await _three(t, size);
      const form = model.FormWait(
        'f',
        'Set up the deploy target',
        schema: formSchema,
        between: true,
      );
      _ask(
        connection,
        turn: model.AwaitingPermission('t', 0, [wheelPermission()]),
        asking: const [form],
      );
      await t.pump();
      await t.pump();
      // The original asks no form while a permission is asked (askedInput).
      expect(t.screen, isNot(shows('Set up the deploy target')));
      expect(t.screen, shows('❯ 1. Allow once'));
      expect(t.screen, shows('3. Deny'));
      expect(t.screen, shows('Esc to reject'));
      expect(t.screen, shows('Starting fake…'));
      expect(_list(t), [_whole.first, '    … +3 more']);
      expect(t.screen, shows(short ? '↓ 58 lines below' : '↓ 42 lines below'));

      _ask(connection, asking: const [form]);
      await t.pump();
      await t.pump();
      expect(t.screen, shows('main asks for input · between turns'));
      expect(t.screen, shows('ctrl+x a to answer'));
      expect(t.screen, shows('Starting fake…'));
      if (short) {
        // Both give way together: the form folds and the list folds.
        expect(t.screen, shows('… 5 more lines'));
        expect(_list(t), [..._whole.take(2), '    … +2 more']);
      } else {
        expect(t.screen, shows('Accept   Decline'));
        expect(_list(t), _whole);
      }
      await _answered(t, connection);
    });

    testWidgets('a fitting permission leaves the list whole, at $size', (
      t,
    ) async {
      final connection = await _three(t, size);
      _ask(
        connection,
        turn: model.AwaitingPermission('t', 0, [
          wheelPermission(fitting: true),
        ]),
      );
      await t.pump();
      await t.pump();
      expect(t.screen, shows('❯ 1. Allow once'));
      expect(_list(t), _whole);
      await _answered(t, connection);
    });

    testWidgets('a form with the keys gives no row; the list gives them, at '
        '$size', (t) async {
      final connection = await _three(t, size);
      _ask(
        connection,
        asking: const [
          model.FormWait('f', 'Set up the deploy target', schema: formSchema),
        ],
      );
      await t.pump();
      await t.pump();
      expect(t.screen, shows('fake asks for input'));
      expect(t.screen, shows('Accept   Decline'));
      expect(t.screen, shows('Type to fill in'));
      expect(t.screen, shows('Starting fake…'));
      expect(_list(t), short ? [..._whole.take(2), '    … +2 more'] : _whole);
      await _answered(t, connection);
    });

    testWidgets('a question box with the keys is drawn whole beside the '
        'list, at $size', (t) async {
      final connection = await _three(t, size);
      _ask(
        connection,
        asking: const [
          model.FormWait(
            'q',
            'Which language?',
            schema: {'type': 'object', 'properties': {}},
            questions: _questions,
          ),
        ],
      );
      await t.pump();
      await t.pump();
      expect(t.screen, shows('1. Dart'));
      expect(t.screen, shows('3. Go'));
      expect(t.screen, shows('Starting fake…'));
      expect(_list(t), _whole);
      await _answered(t, connection);
    });

    testWidgets('a held link keeps its hint and the list, at $size', (t) async {
      final connection = await _three(t, size);
      _ask(
        connection,
        turn: const model.Idle(),
        asking: const [
          model.LinkWait(
            'l',
            'Sign in to continue',
            'https://example.com/login',
            between: true,
          ),
        ],
      );
      await t.pump();
      await t.pump();
      expect(t.screen, shows('2. Decline'));
      expect(t.screen, shows('ctrl+x a to answer'));
      expect(t.screen, shows('Starting fake…'));
      expect(_list(t), _whole);
      await _answered(t, connection);
    });
  }
}

void _testerRoomResizes() {
  group('CTUI-35 tester: room across frames and resize', () {
    for (final initial in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('permission and held form recover their rows from $initial', (
        t,
      ) async {
        final connection = await _three(t, initial);
        const form = model.FormWait(
          'resize-form',
          'Set up the deploy target',
          schema: formSchema,
          between: true,
        );
        _ask(
          connection,
          turn: model.AwaitingPermission('t', 0, [wheelPermission()]),
          asking: const [form],
        );
        for (final size in [
          initial,
          const Size(80, 24),
          const Size(120, 40),
          initial,
        ]) {
          await t.resize(size);
          await t.pump();
          await t.pump();
          expect(t.screen, isNot(shows('Set up the deploy target')));
          expect(t.screen, shows('❯ 1. Allow once'));
          expect(t.screen, shows('3. Deny'));
          expect(_list(t), [_whole.first, '    … +3 more']);
        }
        _ask(connection, asking: const [form]);
        for (final size in [const Size(80, 24), const Size(120, 40), initial]) {
          await t.resize(size);
          await t.pump();
          await t.pump();
          expect(t.screen, shows('main asks for input · between turns'));
          expect(t.screen, shows('ctrl+x a to answer'));
          expect(
            _list(t),
            size.height == 24 ? [..._whole.take(2), '    … +2 more'] : _whole,
          );
        }
        await _answered(t, connection);
        await t.resize(const Size(80, 24));
        await t.pump();
        expect(_list(t), _whole);
      });
    }
  });
}
