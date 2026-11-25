// /mcp in the window: the command opens the panel over the transcript with
// the servers the launch's directory gave, and Esc closes it.
import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/mcp.dart';
import 'package:chord/server/server.dart' show serveChord;
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/place.dart' show SessionStart;
import 'package:chord/session/questions.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_window_test.dart' show selectionConnection;
import 'window_fake_test.dart' as live;
import '../../fixtures/fake_harness.dart' show fakeAgentSkip;
import '../../fixtures/runtimes.dart';
import '../../../tool/children.dart';

Future<StartConnection> _window(WidgetTester t, Size size) async {
  final c = selectionConnection(const []);
  addTearDown(c.close);
  await t.pumpWidget(
    TranscriptWindow(
      launch: const Launch(
        name: 'fake',
        agent: null,
        agentCommand: 'fake',
        version: '0.0.1',
        directory: '.',
        mcpServers: [
          DefinedServer({
            'name': 'files',
            'command': 'files-mcp',
            'args': ['.'],
            'env': <Object?>[],
          }, '.mcp.json'),
        ],
        mcpIgnored: [Ignored('~/.config/chord/settings.json', 1)],
      ),
      connection: c,
    ),
    size: size,
  );
  return c;
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  // CTUI-112 review: a picked child is named by its own runtime, as the
  // original passes shownAgent, not by main's.
  group("chord's line names the agent shown", () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('a picked child of another runtime than main, at $size', (
        t,
      ) async {
        final server = await serveChord();
        addTearDown(server.close);
        final f = childrenFixture(const []);
        addTearDown(f.close);
        f.connection.server = server;
        await Future<void>.delayed(Duration.zero);
        f.sessions['parser']!.chordServerPassed = {
          'type': 'http',
          'name': 'chord',
          'url': server.url,
          'headers': <Object?>[],
        };
        await t.pumpWidget(
          TranscriptWindow(
            launch: const Launch(
              name: 'claude',
              agent: null,
              agentCommand: 'claude',
              version: '0.0.1',
              directory: 'project',
            ),
            connection: f.connection,
          ),
          size: size,
        );
        f.connection.fold.dispatch(SessionShown(f.keys['parser']!));
        final app = f.connection.app;
        app.value = reduceWindow(app.value, const McpOpenedAction());
        await _settle(t);
        final text = t.screen.text.replaceAll(RegExp(r'[│\s]+'), ' ');
        expect(text, contains("chord's server gives fake list_agents"));
        expect(text, contains('send_message to main only'));
        expect(text, isNot(contains('gives claude')));
      });
    }
  });

  // CTUI-112: on the fake, as the original lists it, chord's own server is
  // the first row, its line under the table, and no "No MCP servers".
  group("chord's own server on the fake", skip: fakeAgentSkip, () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('/mcp lists chord itself first and what it gives, at '
          '$size', (t) async {
        final server = await serveChord();
        final runtimes = TestRuntimes();
        final c = StartConnection(
          command: runtimes.commandOf('fake'),
          env: runtimes.env,
          cwd: runtimes.home.path,
          agent: 'fake',
          open: runtimes.opener,
        );
        final fold = c.fold;
        c
          ..server = server
          ..window = AgentsHost(
            runtimeNames: const ['fake'],
            startupOf: (runtime) => runtime == 'fake'
                ? SessionStart(command: runtimes.commandOf('fake'))
                : null,
            openChildSession: c.openChild,
            agents: c.agents,
            opened: (key) => fold.dispatch(AgentOpened(key)),
            closed: (key, front) => fold.dispatch(SessionClosed(key, front)),
            keepClosing: (key, {from, required name, runtime}) => fold.dispatch(
              SpendClosing(key, from: from, name: name, runtime: runtime),
            ),
            keptClosed: (key) => fold.dispatch(SpendClosed(key)),
            server: server,
            transcriptOf: (key) => fold.stateOf(key)?.transcript,
          );
        addTearDown(() async {
          await c.close();
          await server.close();
          runtimes.dispose();
        });
        c.start();
        await t.pumpWidget(
          TranscriptWindow(
            launch: const Launch(
              name: 'fake',
              agent: null,
              agentCommand: 'fake',
              version: '0.0.1',
              directory: '.',
            ),
            connection: c,
          ),
          size: size,
        );
        for (var i = 0; i < 750 && c.conversation.session == null; i++) {
          await t.pump(const Duration(milliseconds: 20));
        }
        expect(c.conversation.session?.chordServerPassed, isNotNull);
        await t.type('/mcp');
        await t.press('enter');
        await _settle(t);
        final text = t.screen.text;
        expect(text, contains(server.url));
        expect(text, contains('chord itself'));
        expect(text, contains("chord's server gives fake list_agents"));
        expect(text, isNot(contains('No MCP servers were passed')));
      });
    }
  });

  group('tester: CTUI-34 MCP request and process ownership', () {
    test('every request covers the panel without clearing its open intent', () {
      const permission = PermissionWait('permission');
      const plan = PlanAsk(
        'turn',
        PlanWait('plan', PlanAgent.cursor, toolCallId: 'call'),
      );
      for (final transcript in const [
        Transcript(turn: AwaitingPermission('turn', 0, [permission])),
        Transcript(
          turn: AwaitingPermission('turn', 0, [permission], between: true),
        ),
        Transcript(asking: [FormWait('form', 'Input')]),
        Transcript(
          asking: [
            LinkWait('link', 'Sign in', 'https://example.com', between: true),
          ],
        ),
        Transcript(
          asking: [
            FormWait(
              'questions',
              'Questions',
              questions: Questions(QuestionsAgent.codex, []),
            ),
          ],
        ),
        Transcript(planAsks: [plan]),
      ]) {
        final covered = AppState(mcpPanel: true, transcript: transcript);
        expect(covered.mcpShown, isFalse);
        expect(covered.mcpPanel, isTrue);
        expect(AppState(mcpPanel: covered.mcpPanel).mcpShown, isTrue);
      }
      expect(
        const AppState(
          mcpPanel: true,
          transcript: Transcript(
            planAsks: [
              PlanAsk(
                'turn',
                PlanWait('plan', PlanAgent.cursor, toolCallId: 'call'),
                answer: PlanCancelled(),
              ),
            ],
          ),
        ).mcpShown,
        isTrue,
      );
    });

    testWidgets(
      'two open panels keep cancellation, late replies and close keys separate',
      (t) async {
        const size = Size(80, 24);
        final secondTester = WidgetTester();
        addTearDown(secondTester.dispose);
        final first = await live.connected(t, size);
        final second = await live.connected(secondTester, size);
        for (final (tester, connection) in [
          (t, first),
          (secondTester, second),
        ]) {
          await tester.pumpWidget(
            TranscriptWindow(launch: live.launch, connection: connection),
            size: size,
          );
          await tester.type('/mcp');
          await tester.press('enter');
          await _settle(tester);
        }
        first.conversation.send('slow');
        await live.until(
          () => first.app.value.transcript.entries
              .whereType<AssistantEntry>()
              .isNotEmpty,
        );
        first.conversation.interrupt();
        second.conversation.send('late');
        second.conversation.send('text');
        await live.until(
          () =>
              first.app.value.transcript.turn is Idle &&
              second.app.value.transcript.turn is Idle &&
              second.app.value.transcript.entries
                      .whereType<AssistantEntry>()
                      .length ==
                  2,
        );
        await t.pump();
        await secondTester.pump();
        expect(
          first.app.value.transcript.entries.whereType<CancelledEntry>(),
          isNotEmpty,
        );
        expect(
          second.app.value.transcript.entries
              .whereType<AssistantEntry>()
              .first
              .text
              .toString(),
          'Answered. Late, after the answer.',
        );
        expect(first.app.value.mcpShown, isTrue);
        expect(second.app.value.mcpShown, isTrue);
        await t.press('esc');
        expect(first.app.value.mcpPanel, isFalse);
        expect(second.app.value.mcpPanel, isTrue);
        await secondTester.press('esc');
        expect(second.app.value.mcpPanel, isFalse);
      },
      skip: fakeAgentSkip,
    );

    testWidgets(
      'a hung turn cannot keep an unmounted panel or its fake alive',
      (t) async {
        const size = Size(80, 24);
        final c = await live.connected(t, size, flags: ['--hang', 'turn']);
        await t.pumpWidget(
          TranscriptWindow(launch: live.launch, connection: c),
          size: size,
        );
        await t.type('/mcp');
        await t.press('enter');
        await _settle(t);
        c.conversation.send('text');
        await live.until(() => c.app.value.transcript.turn is Working);
        await t.pump(const Duration(milliseconds: 100));
        expect(c.app.value.mcpShown, isTrue);
        await t.pumpWidget(const SizedBox());
        await c.close().timeout(const Duration(seconds: 10));
        expect(
          t.focusManager.activeBindings.where(
            (binding) => binding.description == 'Close the MCP servers',
          ),
          isEmpty,
        );
      },
      skip: fakeAgentSkip,
    );

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'a live permission owns Esc then restores the open panel $size',
        (t) async {
          final c = await live.connected(t, size, flags: ['--step-ms', '0']);
          await t.pumpWidget(
            TranscriptWindow(launch: live.launch, connection: c),
            size: size,
          );
          await t.type('/mcp');
          await t.press('enter');
          await _settle(t);
          expect(c.app.value.mcpShown, isTrue);
          expect(c.conversation.send('permission'), isTrue);
          await live.until(
            () => c.app.value.transcript.turn is AwaitingPermission,
          );
          await t.pump();
          expect(c.app.value.mcpShown, isFalse);
          expect(c.app.value.mcpPanel, isTrue);
          expect(t.screen.text, isNot(contains('MCP servers')));
          await t.press('esc');
          await live.until(() => c.app.value.transcript.turn is Idle);
          await t.pump();
          expect(c.app.value.mcpShown, isTrue);
          expect(t.screen, shows('MCP servers'));
          await t.press('esc');
          expect(c.app.value.mcpPanel, isFalse);
        },
        skip: fakeAgentSkip,
      );

      testWidgets(
        'an agent exit while the panel is open leaves Esc usable $size',
        (t) async {
          final c = await live.connected(t, size, flags: ['--step-ms', '0']);
          await t.pumpWidget(
            TranscriptWindow(launch: live.launch, connection: c),
            size: size,
          );
          await t.type('/mcp');
          await t.press('enter');
          await _settle(t);
          expect(c.app.value.mcpShown, isTrue);
          c.conversation.send('crash');
          await live.until(
            () => c.app.value.transcript.entries
                .whereType<ErrorEntry>()
                .isNotEmpty,
          );
          await t.pump();
          await t.resize(
            size.width == 120 ? const Size(80, 24) : const Size(120, 40),
          );
          await t.press('esc');
          expect(c.app.value.mcpPanel, isFalse);
          expect(t.screen.text, isNot(contains('MCP servers')));
        },
        skip: fakeAgentSkip,
      );
    }
  });

  test('a request put to the person takes the panel\'s place until it is '
      'answered', () {
    const open = AppState(mcpPanel: true);
    expect(open.mcpShown, isTrue);
    for (final transcript in const [
      Transcript(asking: [FormWait('f1', 'Which?')]),
      Transcript(asking: [FormWait('q1', 'Questions', between: true)]),
    ]) {
      final asked = AppState(mcpPanel: true, transcript: transcript);
      expect(asked.mcpShown, isFalse);
      expect(asked.mcpPanel, isTrue);
    }
  });

  test('the panel opens, closes, and gives way while chord closes', () {
    final open = reduceWindow(const AppState(), const McpOpenedAction());
    expect(open.mcpShown, isTrue);
    expect(const AppState(closing: true, mcpPanel: true).mcpShown, isFalse);
    expect(reduceWindow(open, const McpClosedAction()).mcpShown, isFalse);
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('/mcp is offered, lists the servers, and Esc closes it, at '
        '$size', (t) async {
      final c = await _window(t, size);
      await t.type('/mc');
      await _settle(t);
      expect(
        t.screen.text,
        contains('Show the MCP servers chord passed to the agent'),
      );
      await t.type('p');
      await t.press('enter');
      await _settle(t);
      expect(c.app.value.mcpShown, isTrue);
      final text = t.screen.text;
      expect(text, contains('MCP servers'));
      expect(text, contains('files-mcp .'));
      expect(text, contains('.mcp.json'));
      expect(text, contains('1 server in ~/.config/chord/settings.json'));
      expect(text, contains('Esc to close'));
      await t.press('esc');
      await _settle(t);
      expect(c.app.value.mcpShown, isFalse);
      expect(t.screen.text, isNot(contains('Command or URL')));
    });
  }

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('/mcp opens while the agent starts, saying nothing has been '
        'passed yet, at $size', (t) async {
      final hanging = Completer<Agent>();
      final c = StartConnection(
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
      addTearDown(c.close);
      addTearDown(() {
        hanging.future.ignore();
        hanging.completeError(StateError('over'));
      });
      await t.pumpWidget(
        TranscriptWindow(
          launch: const Launch(
            name: 'fake',
            agent: null,
            agentCommand: 'fake',
            version: '0.0.1',
            directory: '.',
          ),
          connection: c,
        ),
        size: size,
      );
      await t.type('/mcp');
      await t.press('enter');
      await _settle(t);
      expect(c.app.value.mcpShown, isTrue);
      expect(
        t.screen.text,
        contains('fake is starting: chord has not passed it MCP servers yet.'),
      );
      expect(t.screen.text, contains('Esc to close'));
      // A prompt for the agent still waits for it.
      await t.press('esc');
      await t.type('hello');
      await t.press('enter');
      await _settle(t);
      expect(c.app.value.draft, 'hello');
    });
  }

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('with vim on, one Esc closes /mcp and leaves vim and the '
        'draft alone, at $size', (t) async {
      final c = await _window(t, size);
      c.app.value = c.app.value.withVim(true);
      await t.pump();
      await t.type('/mcp');
      await t.press('enter');
      await _settle(t);
      expect(c.app.value.mcpShown, isTrue);
      final mode = c.app.value.vim!.mode;
      await t.type('hjx');
      await t.press('esc');
      await _settle(t);
      expect(c.app.value.mcpShown, isFalse);
      expect(c.app.value.vim!.mode, mode);
      expect(c.app.value.draft, '');
    });
  }
}
