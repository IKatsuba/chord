// `/cost` in a window with agents: the session's own rows, then the
// window's table, main and each agent, a closed one's kept part too.
import 'dart:async';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/schema.dart';
import 'package:chord/acp/connection.dart' show Traffic, ChordTraffic;
import 'package:chord/cli.dart';
import 'package:chord/session/leaving.dart';
import '../../session/start_connection_children_test.dart'
    show Scripted, Openers;
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/turn_costs.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'editor_window_test.dart' show EditorTerminal, plainLaunch, settle;
import 'front_routing_test.dart' show window;
import '../../fixtures/fake_harness.dart';
import '../../fixtures/runtimes.dart';

void main() {
  frontTests();
  testerMainRetirementCostTests();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets("/cost names main, a child and a closed agent's kept part, "
        'at $size', (t) async {
      final w = await window(t, size, EditorTerminal());
      final fold = w.connection.fold;
      fold.app.value = reduceApp(
        fold.app.value,
        const Connected('m', AgentState.empty),
      );
      fold.heard(
        w.child,
        const Transcribed(
          UsageAction(
            'c1',
            TurnFigures(turnId: 'c1', usage: {'inputTokens': 1200}),
          ),
        ),
      );
      // An agent that closed: its session kept, under its own id.
      fold
        ..dispatch(const AgentOpened(50))
        ..heard(50, const Connected('docs-session', AgentState.empty))
        ..dispatch(const SpendClosing(50, name: 'docs', runtime: 'codex'))
        ..dispatch(const SessionClosed(50, mainKey))
        ..dispatch(const SpendClosed(50));
      await t.pump();
      expect(fold.app.value.start.phase, StartPhase.connected);
      await t.type('/cost');
      await t.press('enter');
      await settle(t);
      expect(t.screen, shows('parser'));
      expect(t.screen, shows('docs'));
      expect(t.screen, shows('Total'));
    });
  }
}

void frontTests() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets("/cost with a child picked names the child's own runtime, at "
        '$size', (t) async {
      final w = await window(t, size, EditorTerminal(), childRuntime: 'codex');
      w.connection.fold.dispatch(SessionShown(w.child));
      await t.pump();
      await t.type('/cost');
      await t.press('enter');
      await settle(t);
      expect(
        t.screen,
        shows('codex has not reported what this session has used.'),
      );
    });
  }

  testWidgets("/cost after main's /clear counts its earlier session as "
      'main, before /clear', (t) async {
    final runtimes = TestRuntimes();
    final connection = StartConnection(
      command: runtimes.commandOf('fake'),
      env: runtimes.env,
      cwd: runtimes.home.path,
      agent: 'fake',
      open: runtimes.opener,
    )..start();
    addTearDown(() async {
      await connection.close();
      runtimes.dispose();
    });
    await t.pumpWidget(
      TranscriptWindow(launch: plainLaunch, connection: connection),
      size: const Size(120, 40),
    );
    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 500 && !done(); i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      expect(done(), isTrue);
    }

    await until(() => connection.app.value.start.phase == StartPhase.connected);
    await t.type('hello');
    await t.press('enter');
    await until(() => connection.app.value.spent != null);
    await until(() => connection.app.value.transcript.turn is Idle);
    await t.type('/clear');
    await t.press('enter');
    await until(
      () =>
          connection.app.value.start.phase == StartPhase.connected &&
          connection.app.value.spent == null,
    );
    await until(() => connection.fold.windowed.value.kept.isNotEmpty);
    expect(connection.fold.windowed.value.kept.single.main, isTrue);
    await t.type('/cost');
    await t.press('enter');
    await settle(t);
    expect(t.screen, shows('before /clear'));
    expect(t.screen, shows('Total'));
  }, skip: fakeAgentSkip);
}

final class _TesterSpendAgent extends Scripted {
  _TesterSpendAgent(this.tokens, {super.closeAnswer});
  final int tokens;
  final reply = Completer<PromptResponse>();
  var prompts = 0;
  void Function(Traffic)? traffic;

  @override
  Future<PromptResponse> prompt(
    PromptRequest request, {
    CancellationToken? cancellationToken,
  }) {
    prompts++;
    traffic?.call(
      ChordTraffic({
        'jsonrpc': '2.0',
        'id': prompts,
        'method': 'session/prompt',
        'params': request.toJson(),
      }),
    );
    return reply.future;
  }

  @override
  Future<void> cancel(
    String sessionId, {
    Iterable<String> subagents = const [],
  }) async {
    if (!reply.isCompleted) {
      reply.complete(
        PromptResponse.fromJson({
          'stopReason': 'cancelled',
          'usage': {'inputTokens': tokens},
        }),
      );
    }
    await super.cancel(sessionId, subagents: subagents);
  }
}

void testerMainRetirementCostTests() {
  group('tester: main late accounting reaches the cost table', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'late usage survives failing old close and sums with fresh main at $size',
        (t) async {
          final failedClose = Completer<void>();
          failedClose.future.ignore();
          final first = _TesterSpendAgent(11, closeAnswer: failedClose);
          final second = _TesterSpendAgent(7);
          final open = Openers([first, second]);
          final catalog = TestRuntimes(
            fakes: const {},
            scripted: {
              'scripted-main':
                  ({
                    required command,
                    env,
                    required cwd,
                    required onTraffic,
                    required onPermission,
                    relay,
                    cancellationToken,
                  }) async {
                    final agent = await open.call(
                      command: command,
                      env: env,
                      cwd: cwd,
                      onTraffic: onTraffic,
                      onPermission: onPermission,
                      relay: relay,
                      cancellationToken: cancellationToken,
                    );
                    (agent as _TesterSpendAgent).traffic = onTraffic;
                    return agent;
                  },
            },
          );
          final connection = StartConnection(
            command: catalog.commandOf('scripted-main'),
            env: catalog.env,
            cwd: catalog.home.path,
            agent: 'main-runtime',
            open: catalog.opener,
            owner: Owned(),
          )..start();
          addTearDown(() async {
            if (!failedClose.isCompleted) failedClose.complete();
            await connection.close().catchError((Object _) {});
            catalog.dispose();
          });
          await t.pumpWidget(
            TranscriptWindow(
              launch: const Launch(
                name: 'main-runtime',
                agent: null,
                agentCommand: 'scripted-main',
                version: '0.0.1',
                directory: '.',
              ),
              connection: connection,
            ),
            size: size,
          );
          Future<void> ready(bool Function() done) async {
            for (var step = 0; step < 500 && !done(); step++) {
              await t.pump(const Duration(milliseconds: 20));
            }
            expect(done(), isTrue);
          }

          await ready(() => first.asked != null);
          first.session.complete(
            NewSessionResponse.fromJson({'sessionId': 'old-main'}),
          );
          await ready(
            () => connection.app.value.start.phase == StartPhase.connected,
          );
          await t.type('running old turn');
          await t.press('enter');
          await ready(() => first.prompts == 1);
          await t.type('/clear');
          await t.press('enter');
          await ready(() => second.asked != null);
          second.session.complete(
            NewSessionResponse.fromJson({'sessionId': 'fresh-main'}),
          );
          failedClose.completeError(StateError('old close failed after usage'));
          await ready(
            () =>
                connection.state.value.sessionId == 'fresh-main' &&
                connection.fold.windowed.value.kept.isNotEmpty,
          );
          final kept = connection.fold.windowed.value.kept.single;
          expect(kept.sessionId, 'old-main');
          expect(kept.spent!.turns.values, [
            {'inputTokens': 11},
          ]);
          expect(connection.app.value.spent, isNull);
          await t.type('fresh turn');
          await t.press('enter');
          await ready(() => second.prompts == 1);
          second.reply.complete(
            PromptResponse.fromJson({
              'stopReason': 'end_turn',
              'usage': {'inputTokens': 7},
            }),
          );
          await ready(
            () =>
                connection.app.value.spent != null &&
                connection.app.value.transcript.turn is Idle,
          );
          await t.type('/cost');
          await t.press('enter');
          await settle(t);
          expect(t.screen, shows('before /clear'));
          expect(t.screen.text, matches(RegExp(r'Total\s+not reported\s+18')));
          expect(connection.app.value.spent!.turns.values, [
            {'inputTokens': 7},
          ]);
        },
      );
    }
  });
}
