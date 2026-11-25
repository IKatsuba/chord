// ctrl+g in the window, from the original's guide ("ctrl+g opens the prompt
// in your editor"): what the editor saves comes back with the cursor at its
// end; one that fails leaves the prompt and says so in the status line.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/acp/connection.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/shortcuts/bindings.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// A terminal whose editor writes [saved] into the file and exits [code],
/// once [release] completes when one is given.
class EditorTerminal extends Terminal {
  EditorTerminal({this.saved, this.code = 0, this.release});
  final String? saved;
  final int code;
  final Future<void>? release;
  final drafts = <String>[];

  @override
  Size get size => const Size(120, 40);
  @override
  Stream<String> get input => const Stream.empty();
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  void write(String data) {}
  @override
  void enter() {}
  @override
  Future<void> leave() async {}

  @override
  Future<int> runEditor(
    String path, {
    String? command,
    String? workingDirectory,
  }) async {
    drafts.add(await File(path).readAsString());
    if (saved case final text?) await File(path).writeAsString(text);
    await release;
    return code;
  }
}

/// A connection whose agent never starts, closed with the test.
StartConnection connection() {
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
  return c;
}

const plainLaunch = Launch(
  name: 'fake',
  agent: null,
  agentCommand: 'fake',
  version: '0.0.1',
  directory: '.',
);

Future<StartConnection> window(
  WidgetTester t,
  Size size,
  Terminal terminal, {
  List<Object?> blocks = const [],
}) async {
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
      launch: Launch(
        name: 'fake',
        agent: null,
        agentCommand: 'fake',
        version: '0.0.1',
        directory: '.',
        keymap: readKeybindings(jsonEncode({'bindings': blocks})).keymap,
      ),
      connection: c,
      terminal: terminal,
    ),
    size: size,
  );
  return c;
}

/// Lets the editor's file work and the window's frame settle.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('ctrl+g opens the draft and what the editor saves comes '
        'back with the cursor at its end, at $size', (t) async {
      final terminal = EditorTerminal(saved: 'edited\nsecond line\n');
      final c = await window(t, size, terminal);
      await t.type('draft');
      await t.press('ctrl+g');
      await settle(t);
      expect(terminal.drafts, ['draft\n']);
      expect(c.app.value.draft, 'edited\nsecond line');
      expect(c.app.value.cursor, 'edited\nsecond line'.length);
    });

    testWidgets('an editor that fails leaves the draft and says so until '
        'the draft is touched, at $size', (t) async {
      final c = await window(t, size, EditorTerminal(saved: 'lost', code: 3));
      await t.type('kept');
      await t.press('ctrl+g');
      await settle(t);
      expect(c.app.value.draft, 'kept');
      String status() => t.screen.lines.lastWhere((l) => l.trim().isNotEmpty);
      expect(status(), contains('exited with code 3; the draft is unchanged'));
      await t.type('!');
      expect(status(), isNot(contains('the draft is unchanged')));
    });

    testWidgets('the editor follows the file, and a list open keeps the '
        'key it binds, at $size', (t) async {
      final terminal = EditorTerminal(saved: 'edited');
      final c = await window(
        t,
        size,
        terminal,
        blocks: [
          {
            'context': 'Chat',
            'bindings': {'ctrl+g': null, 'ctrl+e': 'chat:externalEditor'},
          },
          {
            'context': 'Autocomplete',
            'bindings': {'ctrl+e': 'autocomplete:dismiss'},
          },
        ],
      );
      await t.press('ctrl+g');
      await settle(t);
      expect(terminal.drafts, isEmpty);
      // The command list open: its dismiss takes ctrl+e, not the editor.
      await t.type('/');
      expect(t.screen.text, contains('/config'));
      await t.press('ctrl+e');
      await settle(t);
      expect(terminal.drafts, isEmpty);
      expect(t.screen.text, isNot(contains('/config')));
      // Closed, ctrl+e is the editor's.
      await t.press('ctrl+e');
      await settle(t);
      expect(terminal.drafts, ['/\n']);
      expect(c.app.value.draft, 'edited');
    });

    for (final code in [0, 3]) {
      testWidgets('an editor that ends after the window took another '
          'session gives it nothing, exit $code, at $size', (t) async {
        final release = Completer<void>();
        final terminal = EditorTerminal(
          saved: 'late',
          code: code,
          release: release.future,
        );
        final first = connection(), second = connection();
        final current = ValueNotifier(first);
        addTearDown(current.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: current,
            builder: (_) => TranscriptWindow(
              launch: plainLaunch,
              connection: current.value,
              terminal: terminal,
            ),
          ),
          size: size,
        );
        await t.type('mine');
        await t.press('ctrl+g');
        await settle(t);
        expect(terminal.drafts, ['mine\n']);
        // The same window, given another session while the editor runs.
        current.value = second;
        await settle(t);
        release.complete();
        await settle(t);
        expect(second.app.value.draft, isNot('late'));
        expect(second.app.value.editorFailed, isNull);
        expect(t.screen.text, isNot(contains('the draft is unchanged')));
      });
    }

    testWidgets('an editor that ends after the window went publishes '
        'nothing, at $size', (t) async {
      final release = Completer<void>();
      final terminal = EditorTerminal(saved: 'late', release: release.future);
      final c = connection();
      await t.pumpWidget(
        TranscriptWindow(
          launch: plainLaunch,
          connection: c,
          terminal: terminal,
        ),
        size: size,
      );
      await t.press('ctrl+g');
      await settle(t);
      await t.pumpWidget(const SizedBox(), size: size);
      release.complete();
      await settle(t);
      expect(c.app.value.draft, isNot('late'));
    });
  }
}
