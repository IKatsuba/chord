// The window's intents go to the agent in front at the press, and what
// comes back later goes to the agent that asked, in the launch it asked
// in, never to whoever is picked when it lands.
import 'dart:async';
import 'dart:io';

import 'package:chord/acp/connection.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'package:chord/images.dart';
import 'image_paste_window_test.dart' show pixel;
import 'package:chord/cli.dart' show Launch;
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/transcript/types.dart'
    show NotedEntry, ShellEntry;
import 'package:chord/files.dart' show listFiles;
import 'package:chord/shell.dart';
import 'package:chord/ui/app/terminal.dart' show WalkFiles;
import '../../session/settings_test.dart' show select, value;

import '../../session/conversation_fake.dart';
import 'editor_window_test.dart' show EditorTerminal, plainLaunch, settle;

/// The window over a main that never starts, with one child on a scripted
/// session behind it.
Future<({StartConnection connection, int child, ScriptedSession session})>
window(
  WidgetTester t,
  Size size,
  Terminal terminal, {
  RunShell runShell = runShell,
  AgentState childState = AgentState.empty,
  String? settingsFile,
  String childRuntime = 'fake',
  WalkFiles walkFiles = listFiles,
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
  final session = ScriptedSession()..state = childState;
  final child = connection.agents.openChild(
    ChildInfo(id: 'a1', name: 'parser', runtime: childRuntime, openedAt: 0),
    (emit, key) {
      connection.fold.dispatch(AgentOpened(key));
      return Conversation(
        ({required onTraffic, required cancellationToken}) async => session,
      )..listen(emit);
    },
  )!;
  await t.pumpWidget(
    TranscriptWindow(
      launch: settingsFile == null
          ? plainLaunch
          : Launch(
              name: 'fake',
              agent: null,
              agentCommand: 'fake',
              version: '0.0.1',
              directory: '.',
              settingsFile: settingsFile,
            ),
      connection: connection,
      terminal: terminal,
      runShell: runShell,
      walkFiles: walkFiles,
    ),
    size: size,
  );
  await settle(t);
  return (connection: connection, child: child, session: session);
}

void show(StartConnection connection, int key) =>
    connection.fold.dispatch(SessionShown(key));

void main() {
  group('tester: status follows an agent-reported title', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'a hidden child title reaches its own status after switching at $size',
        (t) async {
          final w = await window(t, size, EditorTerminal());
          w.session.say({
            'sessionUpdate': 'session_info_update',
            'title': ' \x1b[31mParser\x1b[0m\n e\u0301🙂 ',
          });
          await settle(t);
          show(w.connection, w.child);
          await t.pump();
          await t.type('/status');
          await t.press('enter');
          await settle(t);
          expect(t.screen, shows('Title:     Parser e\u0301🙂'));
          await t.resize(
            size == const Size(120, 40)
                ? const Size(80, 24)
                : const Size(120, 40),
          );
          expect(t.screen, shows('Title:     Parser e\u0301🙂'));
          show(w.connection, mainKey);
          await t.pump();
          expect(t.screen.text, isNot(contains('Title:     Parser')));
          show(w.connection, w.child);
          await t.pump();
          expect(t.screen, shows('Title:     Parser e\u0301🙂'));
        },
      );
    }
  });

  testerTargetedResultTests();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('a prompt goes to the agent in front when sent, at $size', (
      t,
    ) async {
      final w = await window(t, size, EditorTerminal());
      show(w.connection, w.child);
      await t.pump();
      await t.type('for the parser');
      await t.press('enter');
      await settle(t);
      expect(
        [for (final turn in w.session.turns) turn.text],
        ['for the parser'],
      );
      expect(w.connection.fold.stateOf(mainKey)!.transcript.entries, isEmpty);
    });

    testWidgets('typed keys split by a switch land each in the agent in '
        'front when pressed, at $size', (t) async {
      final w = await window(t, size, EditorTerminal());
      final fold = w.connection.fold;
      await t.type('ab');
      show(w.connection, w.child);
      await t.pump();
      expect(fold.app.value.draft, '');
      await t.type('cd');
      show(w.connection, mainKey);
      await t.pump();
      await t.type('e');
      expect(fold.stateOf(mainKey)!.draft, 'abe');
      expect(fold.stateOf(w.child)!.draft, 'cd');
    });

    testWidgets("a hidden agent's draft is in the field once it is picked, "
        'and stays through the next frames, at $size', (t) async {
      final w = await window(t, size, EditorTerminal());
      final fold = w.connection.fold;
      fold.dispatch(
        SessionActed(w.child, const DraftEditedAction('hidden 999', 3)),
      );
      await t.type('main');
      show(w.connection, w.child);
      await t.pump();
      await t.pump();
      await t.resize(Size(size.width - 2, size.height));
      await t.resize(size);
      expect(fold.app.value.draft, 'hidden 999');
      expect(fold.app.value.cursor, 3);
      expect(t.screen, shows('hidden 999'));
      expect(fold.stateOf(mainKey)!.draft, 'main');
      show(w.connection, mainKey);
      await t.pump();
      expect(fold.app.value.draft, 'main');
      expect(fold.stateOf(w.child)!.draft, 'hidden 999');
    });

    testWidgets("the editor's text goes to the agent that opened it, after "
        'a switch, at $size', (t) async {
      final release = Completer<void>();
      final w = await window(
        t,
        size,
        EditorTerminal(saved: 'edited', release: release.future),
      );
      final fold = w.connection.fold;
      show(w.connection, w.child);
      await t.pump();
      await t.type('child draft');
      await t.press('ctrl+g');
      await settle(t);
      show(w.connection, mainKey);
      await t.pump();
      await t.type('main draft');
      release.complete();
      await settle(t);
      expect(fold.stateOf(w.child)!.draft, 'edited');
      expect(fold.stateOf(mainKey)!.draft, 'main draft');
      expect(fold.app.value.draft, 'main draft');
    });

    testWidgets("the editor's text after its agent's clear is dropped, at "
        '$size', (t) async {
      final release = Completer<void>();
      final w = await window(
        t,
        size,
        EditorTerminal(saved: 'edited', release: release.future),
      );
      final fold = w.connection.fold;
      show(w.connection, w.child);
      await t.pump();
      await t.type('before');
      await t.press('ctrl+g');
      await settle(t);
      // A new launch of the same agent.
      w.connection.agents.conversationOf(w.child)!.clear().ignore();
      await settle(t);
      release.complete();
      await settle(t);
      expect(fold.stateOf(w.child)!.draft, isNot('edited'));
    });

    testWidgets("a hidden agent's clear gives its queued prompts back to its "
        'own draft, the front untouched, at $size', (t) async {
      final w = await window(t, size, EditorTerminal());
      final fold = w.connection.fold;
      final conversation = w.connection.agents.conversationOf(w.child)!;
      // A turn running, and a prompt queued behind it.
      expect(conversation.send('first'), isTrue);
      await settle(t);
      expect(conversation.send('queued one'), isTrue);
      await settle(t);
      expect(fold.stateOf(w.child)!.queue, hasLength(1));
      await t.type('main typing');
      conversation.clear().ignore();
      await settle(t);
      expect(fold.stateOf(w.child)!.draft, contains('queued one'));
      expect(fold.stateOf(mainKey)!.draft, 'main typing');
      expect(fold.app.value.draft, 'main typing');
    });

    testWidgets("an agent's `!` command output stays its own after a "
        'switch, at $size', (t) async {
      final runs = <(String, ShellOptions, Completer<ShellEnd>)>[];
      final w = await window(
        t,
        size,
        EditorTerminal(),
        runShell: (command, options) {
          final done = Completer<ShellEnd>();
          runs.add((command, options, done));
          return _Shell(done);
        },
      );
      final fold = w.connection.fold;
      show(w.connection, w.child);
      await t.pump();
      await t.type('!printf parser');
      await t.press('enter');
      await settle(t);
      show(w.connection, mainKey);
      await t.pump();
      final (_, options, done) = runs.single;
      options.onOutput!(ShellStream.stdout, 'from the parser');
      done.complete(const ShellEnd(code: 0));
      await settle(t);
      final run = fold
          .stateOf(w.child)!
          .transcript
          .entries
          .whereType<ShellEntry>()
          .single
          .run;
      expect(run.stdout, contains('from the parser'));
      expect(run.running, isFalse);
      expect(run.code, 0);
      expect(
        fold.stateOf(mainKey)!.transcript.entries.whereType<ShellEntry>(),
        isEmpty,
      );
      // Its held output goes with the child's next prompt, not main's.
      expect(fold.stateOf(w.child)!.held, hasLength(1));
      expect(fold.stateOf(mainKey)!.held, isEmpty);
      expect(t.screen, isNot(shows('from the parser')));
    });

    for (final how in ['closed', 'cleared']) {
      testWidgets("an agent's running `!` command stops once it is $how, "
          'and nothing it says lands, at $size', (t) async {
        final shells = <_Shell>[];
        final outputs = <ShellOptions>[];
        final w = await window(
          t,
          size,
          EditorTerminal(),
          runShell: (command, options) {
            outputs.add(options);
            final shell = _Shell(Completer());
            shells.add(shell);
            return shell;
          },
        );
        final fold = w.connection.fold;
        show(w.connection, w.child);
        await t.pump();
        await t.type('!sleep 100');
        await t.press('enter');
        await settle(t);
        show(w.connection, mainKey);
        await t.pump();
        if (how == 'closed') {
          fold.dispatch(SessionClosed(w.child, mainKey));
        } else {
          w.connection.agents.conversationOf(w.child)!.clear().ignore();
        }
        await settle(t);
        expect(shells.single.stops, 1);
        outputs.single.onOutput?.call(ShellStream.stdout, 'too late');
        await settle(t);
        for (final key in [mainKey, w.child]) {
          final state = fold.stateOf(key);
          if (state == null) continue;
          for (final entry
              in state.transcript.entries.whereType<ShellEntry>()) {
            expect(entry.run.stdout, isNot(contains('too late')));
          }
        }
        expect(t.screen, isNot(shows('too late')));
      });
    }

    testWidgets('a setting refused after a switch notes the agent asked, at '
        '$size', (t) async {
      final gate = Completer<void>();
      final w = await window(
        t,
        size,
        EditorTerminal(),
        childState: AgentState(
          configOptions: [
            select('effort', 'thought_level', [
              value('low'),
              value('high'),
            ], current: 'low'),
          ],
        ),
      );
      w.session.change = (kind, id, value) => gate.future;
      final fold = w.connection.fold;
      show(w.connection, w.child);
      await t.pump();
      await t.type('/effort high');
      await t.press('enter');
      await settle(t);
      show(w.connection, mainKey);
      await t.pump();
      gate.completeError(StateError('no effort today'));
      await settle(t);
      List<NotedEntry> notes(int key) => [
        ...fold.stateOf(key)!.transcript.entries.whereType<NotedEntry>(),
      ];
      expect(notes(w.child).last.text, contains('no effort today'));
      expect(notes(mainKey), isEmpty);
    });

    testWidgets('/rename on a picked child renames it, its note in its own '
        'view, at $size', (t) async {
      final w = await window(t, size, EditorTerminal());
      final fold = w.connection.fold;
      show(w.connection, w.child);
      await t.pump();
      await t.type('/rename  the   parser ');
      await t.press('enter');
      await settle(t);
      expect(w.connection.agents.conversationOf(w.child)!.title, 'the parser');
      final note = fold
          .stateOf(w.child)!
          .transcript
          .entries
          .whereType<NotedEntry>()
          .single;
      expect(note.command, 'rename the parser');
      expect(note.text, startsWith('Renamed to the parser'));
      expect(t.screen, shows('Renamed to the parser'));
      expect(
        fold.stateOf(mainKey)!.transcript.entries.whereType<NotedEntry>(),
        isEmpty,
      );
    });

    // CTUI-113: /status gives the shown agent's title, as the original's
    // reads the front conversation's.
    testWidgets('/status on a picked child says its title, not given until '
        'a rename, at $size', (t) async {
      final w = await window(t, size, EditorTerminal());
      show(w.connection, w.child);
      await t.pump();
      await t.type('/status');
      await t.press('enter');
      await settle(t);
      expect(t.screen, shows('Title:     not given'));
      await t.type('/rename  the   parser ');
      await t.press('enter');
      await settle(t);
      await t.type('/status');
      await t.press('enter');
      await settle(t);
      expect(t.screen, shows('Title:     the parser'));
    });

    testWidgets('/rename on main before it starts is refused where typed, at '
        '$size', (t) async {
      final w = await window(t, size, EditorTerminal());
      await t.type('/rename x');
      await t.press('enter');
      await settle(t);
      expect(
        w.connection.fold.app.value.transcript.entries
            .whereType<NotedEntry>()
            .single
            .text,
        'The session is not open yet; rename it once it is.',
      );
    });

    testWidgets("a saved setting's note goes to the agent that asked, after "
        'a switch, at $size', (t) async {
      final dir = Directory.systemTemp.createTempSync('chord-routing-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final w = await window(
        t,
        size,
        EditorTerminal(),
        settingsFile: '${dir.path}/settings.json',
      );
      final fold = w.connection.fold;
      show(w.connection, w.child);
      await t.pump();
      await t.type('/vim');
      await t.press('enter');
      show(w.connection, mainKey);
      await settle(t);
      bool noted(int key) => fold
          .stateOf(key)!
          .transcript
          .entries
          .whereType<NotedEntry>()
          .any((e) => e.command == 'vim');
      expect(noted(w.child), isTrue);
      expect(noted(mainKey), isFalse);
    });

    testWidgets('an editor that fails to start after a switch leaves the '
        'front alone, at $size', (t) async {
      final release = Completer<void>();
      final w = await window(t, size, _FailingEditor(release.future));
      show(w.connection, w.child);
      await t.pump();
      await t.press('ctrl+g');
      await settle(t);
      show(w.connection, mainKey);
      await t.pump();
      release.complete();
      await settle(t);
      expect(w.connection.fold.app.value.editorFailed, isNull);
      expect(t.screen, isNot(shows('The editor did not start')));
    });
  }
}

/// A command the test ends.
final class _Shell extends ShellProcess {
  _Shell(this._done);
  final Completer<ShellEnd> _done;
  var stops = 0;
  @override
  Future<ShellEnd> get ended => _done.future;
  @override
  void stop() {
    stops++;
    if (!_done.isCompleted) _done.complete(const ShellEnd(stopped: true));
  }
}

/// A terminal whose editor fails to start once [release] completes.
final class _FailingEditor extends EditorTerminal {
  _FailingEditor(this._released);
  final Future<void> _released;
  @override
  Future<int> runEditor(
    String path, {
    String? command,
    String? workingDirectory,
  }) async {
    await _released;
    throw StateError('no editor');
  }
}

void testerTargetedResultTests() {
  group('tester: delayed image and setting launch guards', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      for (final outcome in ['switch', 'clear', 'close']) {
        testWidgets(
          'clipboard image after $outcome belongs only to its live launch at $size',
          (t) async {
            final terminal = EditorTerminal();
            final w = await window(t, size, terminal);
            w.session.images = true;
            final image = Completer<ImageRead>();
            await t.pumpWidget(
              TranscriptWindow(
                launch: plainLaunch,
                connection: w.connection,
                terminal: terminal,
                readClipboard: () => image.future,
              ),
              size: size,
            );
            show(w.connection, w.child);
            await t.pump();
            await t.type('child ');
            await t.press('ctrl+v');
            show(w.connection, mainKey);
            await t.pump();
            await t.type('main untouched');
            if (outcome == 'clear') {
              w.connection.agents.conversationOf(w.child)!.clear().ignore();
              await settle(t);
            } else if (outcome == 'close') {
              w.connection.fold.dispatch(SessionClosed(w.child, mainKey));
              await t.pump();
            }
            image.complete(ImageReadDone(pixel));
            await settle(t);
            final fold = w.connection.fold;
            expect(fold.stateOf(mainKey)!.draft, 'main untouched');
            expect(fold.stateOf(mainKey)!.images, isEmpty);
            if (outcome == 'switch') {
              expect(fold.stateOf(w.child)!.draft, contains('[Image #1]'));
              expect(fold.stateOf(w.child)!.images, hasLength(1));
              show(w.connection, w.child);
              await t.pump();
              await t.pump();
              expect(t.screen, shows('[Image #1]'));
            } else if (outcome == 'clear') {
              expect(fold.stateOf(w.child)!.images, isEmpty);
              expect(
                fold.stateOf(w.child)!.draft,
                isNot(contains('[Image #1]')),
              );
            } else {
              expect(fold.stateOf(w.child), isNull);
            }
          },
        );
      }

      testWidgets('setting refusal after child clear is discarded at $size', (
        t,
      ) async {
        final gate = Completer<void>();
        final w = await window(
          t,
          size,
          EditorTerminal(),
          childState: AgentState(
            configOptions: [
              select('effort', 'thought_level', [
                value('low'),
                value('high'),
              ], current: 'low'),
            ],
          ),
        );
        final old = ScriptedSession()..state = w.session.state;
        final fresh = ScriptedSession()..state = w.session.state;
        var opens = 0;
        final target = w.connection.agents.openChild(
          const ChildInfo(
            id: 'fresh-test',
            name: 'fresh-test',
            runtime: 'scripted',
            openedAt: 0,
          ),
          (emit, key) {
            w.connection.fold.dispatch(AgentOpened(key));
            return Conversation(
              ({required onTraffic, required cancellationToken}) async =>
                  opens++ == 0 ? old : fresh,
            )..listen(emit);
          },
        )!;
        await settle(t);
        old.change = (kind, id, value) => gate.future;
        show(w.connection, target);
        await t.pump();
        await t.type('/effort high');
        await t.press('enter');
        await settle(t);
        w.connection.agents.conversationOf(target)!.clear().ignore();
        await settle(t);
        show(w.connection, mainKey);
        await t.pump();
        gate.completeError(StateError('obsolete setting refusal'));
        await settle(t);
        expect(opens, 2);
        for (final key in [mainKey, target]) {
          expect(
            w.connection.fold
                .stateOf(key)!
                .transcript
                .entries
                .whereType<NotedEntry>()
                .any((note) => note.text.contains('obsolete setting refusal')),
            isFalse,
          );
        }
      });
    }
  });
}
