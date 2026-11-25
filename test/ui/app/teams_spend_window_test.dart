// `/cost` with a team run in the window: the run as one row under its
// team's name, its lead and members named in its note, a member closed
// while the run goes on kept in that row, and a run whose lead closed too
// kept as one row of its own, ended. The original's
// tests/ui/agents/TeamsSpend_test.tsx's window cases, on scripted sessions.
import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/launch_connection.dart' show spendClosingOf;
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/turn_costs.dart';
import 'package:chord/session/waits.dart' show idle;
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../session/conversation_fake.dart';
import 'editor_window_test.dart' show EditorTerminal, settle;

/// The window over a main that never starts, with run `bugfix` open, its
/// members `tester` and `coder` under it; each child on a scripted
/// session. The keys of main's children by name.
Future<({StartConnection connection, Map<String, int> keys})> _window(
  WidgetTester t,
  Size size, {
  bool second = false,
}) async {
  final hanging = Completer<Agent>();
  final connection = StartConnection(
    command: 'fake',
    cwd: '.',
    agent: 'fake',
    owner: Owned(),
    open:
        ({
          required command,
          env,
          required cwd,
          required onTraffic,
          required onPermission,
          relay,
          cancellationToken,
        }) => hanging.future,
  )..start();
  addTearDown(connection.close);
  addTearDown(() {
    hanging.future.ignore();
    hanging.completeError(StateError('over'));
  });
  int open(String name, {String? team, String? lead, String? id}) =>
      connection.agents.openChild(
        ChildInfo(
          id: id ?? 'id-$name',
          name: name,
          runtime: 'fake',
          openedAt: 0,
          team: team,
          lead: lead,
        ),
        (emit, key) {
          connection.fold.dispatch(AgentOpened(key));
          final session = ScriptedSession()..id = 'session-${id ?? name}';
          return Conversation(
            ({required onTraffic, required cancellationToken}) async => session,
          )..listen(emit);
        },
      )!;
  connection.fold.heard(mainKey, const Connected('m', AgentState.empty));
  final keys = {
    'bugfix': open('bugfix', team: 'bugfix'),
    'tester': open('tester', team: 'bugfix', lead: 'id-bugfix'),
    'coder': open('coder', team: 'bugfix', lead: 'id-bugfix'),
    if (second) ...{
      'bugfix 2': open('bugfix 2', team: 'bugfix'),
      'tester 2': open(
        'tester',
        team: 'bugfix',
        lead: 'id-bugfix 2',
        id: 'id-tester 2',
      ),
      'coder 2': open(
        'coder',
        team: 'bugfix',
        lead: 'id-bugfix 2',
        id: 'id-coder 2',
      ),
    },
  };
  await t.pumpWidget(
    TranscriptWindow(
      launch: const Launch(
        name: 'fake',
        agent: null,
        agentCommand: 'fake',
        version: '0.0.1',
        directory: '.',
      ),
      connection: connection,
      terminal: EditorTerminal(),
    ),
    size: size,
  );
  await settle(t);
  return (connection: connection, keys: keys);
}

/// Session [key]'s turn [turnId] cost [amount] USD, over [tokens].
ConversationEvent _cost(String turnId, num amount, [int tokens = 1000]) =>
    Transcribed(
      UsageAction(
        turnId,
        TurnFigures(
          turnId: turnId,
          usage: {'inputTokens': tokens},
          cost: TurnCost(
            cost: (amount: amount, currency: 'USD'),
            estimated: false,
          ),
        ),
      ),
    );

/// The screen's line that holds [text].
String _line(WidgetTester t, String text) =>
    t.screen.lines.firstWhere((line) => line.contains(text), orElse: () => '');

/// Child [key] begins closing as the window keeps it, and is let go;
/// its close settles too when [settled].
Future<void> _close(
  StartConnection connection,
  int key,
  String name, {
  bool settled = true,
}) async {
  final fold = connection.fold;
  fold.dispatch(
    spendClosingOf(connection.agents.agents, key, name: name, runtime: 'fake'),
  );
  await connection.agents.closeChild(key);
  fold.dispatch(SessionClosed(key, mainKey));
  if (settled) fold.dispatch(SpendClosed(key));
}

void main() {
  group('CTUI-37 tester: finished runs across closes', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'two complete runs retain every figure across repeated /cost and settled closes at $size',
        (t) async {
          final w = await _window(t, size, second: true);
          final fold = w.connection.fold;
          fold.heard(mainKey, _cost('main-turn', 0.07));
          for (final (name, amount) in [
            ('bugfix', 0.01),
            ('tester', 0.02),
            ('coder', 0.03),
            ('bugfix 2', 0.04),
            ('tester 2', 0.05),
            ('coder 2', 0.06),
          ]) {
            fold.heard(w.keys[name]!, _cost('finished-$name', amount));
          }
          await t.pump();
          Future<void> report() async {
            await t.type('/cost');
            await t.press('enter');
            await settle(t);
            expect(
              t.screen.lines.lastWhere(
                (row) => row.trimLeft().startsWith('Total '),
                orElse: () => t.screen.text,
              ),
              contains(r'$0.2800'),
              reason: t.screen.text,
            );
            final rows = t.screen.lines;
            final head = rows.lastIndexWhere(
              (row) => row.contains('This session'),
            );
            expect(head, greaterThanOrEqualTo(0), reason: t.screen.text);
            final text = rows
                .skip(head)
                .map((row) => row.trim())
                .join(' ')
                .replaceAll(RegExp(r' +'), ' ');
            for (final figure in [
              r'lead $0.0100',
              r'tester $0.0200',
              r'coder $0.0300',
              r'lead $0.0400',
              r'tester $0.0500',
              r'coder $0.0600',
            ]) {
              expect(text, contains(figure), reason: t.screen.text);
            }
            for (final name in ['lead', 'tester', 'coder']) {
              expect(text, isNot(contains('$name not reported')));
            }
          }

          await report();
          await report();
          for (final name in [
            'coder',
            'tester 2',
            'bugfix 2',
            'tester',
            'coder 2',
            'bugfix',
          ]) {
            await _close(w.connection, w.keys[name]!, name.split(' ').first);
          }
          await settle(t);
          await report();
          await report();
          await t.resize(const Size(1, 1));
          await t.resize(size);
          expect(
            t.screen.lines.lastWhere(
              (row) => row.trimLeft().startsWith('Total '),
              orElse: () => t.screen.text,
            ),
            contains(r'$0.2800'),
          );
        },
      );
    }
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets("an ended run lists its agents as the original's /cost "
        'does: those whose close settled in that order, then those still '
        'closing, its lead first, at $size', (t) async {
      final w = await _window(t, size, second: true);
      final fold = w.connection.fold;
      fold
        ..heard(w.keys['bugfix']!, _cost('l1', 0.05, 8000))
        ..heard(w.keys['coder']!, _cost('c1', 0.025, 4000))
        ..heard(w.keys['bugfix 2']!, _cost('l2', 0.025, 4000))
        ..heard(w.keys['coder 2']!, _cost('c2', 0.025, 4000));
      // The first run's coder closed by x earlier, its close settled.
      await _close(w.connection, w.keys['coder']!, 'coder');
      // /clear drops main's children, a lead's members first; the second
      // run's lead and coder settle, the rest are still closing.
      await _close(w.connection, w.keys['tester']!, 'tester', settled: false);
      await _close(w.connection, w.keys['bugfix']!, 'bugfix', settled: false);
      await _close(w.connection, w.keys['tester 2']!, 'tester', settled: false);
      await _close(w.connection, w.keys['coder 2']!, 'coder', settled: false);
      await _close(
        w.connection,
        w.keys['bugfix 2']!,
        'bugfix 2',
        settled: false,
      );
      fold
        ..dispatch(SpendClosed(w.keys['bugfix 2']!))
        ..dispatch(SpendClosed(w.keys['coder 2']!));
      await t.pump();
      await t.type('/cost');
      await t.press('enter');
      await settle(t);
      // As the original's captures (docs/design/evidence/CTUI-37/
      // 10-cost-after-clear-original-120x40.txt) read them, each note
      // whole once its wrapped lines are joined.
      final screen = t.screen.lines
          .map((line) => line.trim())
          .join(' ')
          .replaceAll(RegExp(r' +'), ' ');
      expect(
        screen,
        contains(
          r'team run, ended: coder $0.0250 · lead $0.0500 · tester not '
          'reported',
        ),
        reason: t.screen.lines.join('\n'),
      );
      expect(
        screen,
        contains(
          r'team run, ended: lead $0.0250 · coder $0.0250 · tester not '
          'reported',
        ),
      );
      if (size.width == 120) {
        expect(
          t.screen,
          shows(
            r'$0.0750  12,000  team run, ended: coder '
            r'$0.0250 · lead $0.0500 · tester not reported',
          ),
        );
        expect(
          t.screen,
          shows(
            r'$0.0500   8,000  team run, ended: lead '
            r'$0.0250 · coder $0.0250 · tester not reported',
          ),
        );
      }
    });
  }

  test('the sessions still closing are read in the original object order: '
      'own keys ascending, then retired ones as they began', () {
    ClosingSession of(String name) => (
      session: SessionState.starting,
      from: null,
      name: name,
      runtime: null,
      main: false,
      team: null,
      lead: null,
      member: false,
    );
    expect(
      [
        for (final each in closingInOrder({
          5: of('tester'),
          -2: of('retired b'),
          3: of('lead'),
          -1: of('retired a'),
          4: of('coder'),
        }))
          each.name,
      ],
      ['lead', 'coder', 'tester', 'retired b', 'retired a'],
    );
  });

  test("a closing team agent is kept under its run: its lead as lead, a "
      "member by its name, each with its run's lead", () {
    final agents = WindowAgents<String>(
      main: const MainAgent(1, 'fake', 'm', idle),
      children: [
        for (final (key, name, team, lead) in [
          (2, 'bugfix', 'bugfix', null),
          (3, 'tester', 'bugfix', 'l'),
          (4, 'docs', null, null),
        ])
          Child(
            ChildInfo(
              id: key == 2 ? 'l' : 'id-$name',
              name: name,
              runtime: 'fake',
              openedAt: 0,
              team: team,
              lead: lead,
            ),
            key,
            name,
            idle,
          ),
      ],
      picked: 1,
      nextKey: 5,
    );
    final lead = spendClosingOf(agents, 2, name: 'bugfix', runtime: 'fake');
    expect(
      (lead.name, lead.team, lead.lead, lead.member),
      ('lead', 'bugfix', 'l', true),
    );
    final member = spendClosingOf(agents, 3, name: 'tester');
    expect(
      (member.name, member.team, member.lead, member.member),
      ('tester', 'bugfix', 'l', true),
    );
    // A cleared member's retired session is placed by the member it was.
    final retired = spendClosingOf(agents, -1, from: 3, name: 'tester');
    expect((retired.key, retired.from, retired.lead), (-1, 3, 'l'));
    final plain = spendClosingOf(agents, 4, name: 'docs');
    expect(
      (plain.name, plain.team, plain.lead, plain.member),
      ('docs', null, null, false),
    );
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('/cost draws the run as one row named by its team, its lead '
        'and members in its note, a member closed while it runs kept in it, '
        'at $size', (t) async {
      final w = await _window(t, size);
      final fold = w.connection.fold;
      fold
        ..heard(w.keys['bugfix']!, _cost('l1', 0.025))
        ..heard(w.keys['tester']!, _cost('t1', 0.0125))
        ..heard(w.keys['coder']!, _cost('c1', 0.0125));
      // coder closes while the run goes on: kept in the run's row.
      final coder = w.keys['coder']!;
      fold.dispatch(
        spendClosingOf(
          w.connection.agents.agents,
          coder,
          name: 'coder',
          runtime: 'fake',
        ),
      );
      await w.connection.agents.closeChild(coder);
      fold
        ..dispatch(SessionClosed(coder, mainKey))
        ..dispatch(SpendClosed(coder));
      await t.pump();
      await t.type('/cost');
      await t.press('enter');
      await settle(t);
      final run = _line(t, 'team run:');
      expect(
        run.trimLeft(),
        startsWith('bugfix '),
        reason: t.screen.lines.join('\n'),
      );
      expect(run, contains(r'$0.0500'));
      expect(t.screen, shows(r'team run: lead $0.0250'));
      expect(t.screen, shows(r'coder $0.0125'));
      expect(t.screen, isNot(shows('agent, closed')));
      expect(t.screen, shows('Total'));
    });

    testWidgets('a run whose lead closed too is kept as one row of its own, '
        'ended, at $size', (t) async {
      final w = await _window(t, size);
      final fold = w.connection.fold;
      fold
        ..heard(w.keys['bugfix']!, _cost('l1', 0.025))
        ..heard(w.keys['tester']!, _cost('t1', 0.0125));
      // The run closes whole: its members first, then its lead.
      for (final name in ['tester', 'coder', 'bugfix']) {
        final key = w.keys[name]!;
        fold.dispatch(
          spendClosingOf(
            w.connection.agents.agents,
            key,
            name: name,
            runtime: 'fake',
          ),
        );
        await w.connection.agents.closeChild(key);
        fold
          ..dispatch(SessionClosed(key, mainKey))
          ..dispatch(SpendClosed(key));
      }
      await t.pump();
      await t.type('/cost');
      await t.press('enter');
      await settle(t);
      final run = _line(t, 'team run, ended:');
      expect(
        run.trimLeft(),
        startsWith('bugfix '),
        reason: t.screen.lines.join('\n'),
      );
      expect(run, contains(r'$0.0375'));
      // Kept in the order its agents closed, its lead last.
      expect(t.screen, shows(r'team run, ended: tester $0.0125'));
      expect(t.screen, shows(r'lead $0.0250'));
    });
  }
}
