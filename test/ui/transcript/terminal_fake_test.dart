// The window declares `_meta.terminal_output_delta` and draws a command's
// terminal under its call, on the original's fake agent
// (tests/fixtures/fake_agent/scenarios/shell.ts), whose `bash` plays Claude's
// adapter: the terminal named up front and its output as `_meta` only to a
// client that asks for it, a `console` block of text to any other.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/acp/connection.dart' show windowCapabilities;
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/start.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/dev.dart' show shellWord;
import '../../fixtures/fake_harness.dart';
import '../app/window_fake_test.dart' show launch, sent, until;

void main() {
  group('terminal output in the window', skip: fakeAgentSkip, () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets("Claude's command runs under its call with its terminal, "
          'then its output, at $size', (t) async {
        final directory = Directory.systemTemp.createTempSync('chord-bash-');
        final connection = StartConnection(
          command: fakeAgentCommand().map(shellWord).join(' '),
          cwd: directory.path,
          agent: 'fake',
          open: fakeOpenerWith(capabilities: windowCapabilities()),
          owner: Owned(),
        )..start();
        addTearDown(() async {
          await connection.close();
          directory.deleteSync(recursive: true);
        });
        await t.pumpWidget(
          StartWindow(launch: launch, connection: connection),
          size: size,
        );
        await until(
          () => connection.app.value.start.phase == StartPhase.connected,
        );
        List<model.Terminal> terminals() => [
          for (final entry in connection.app.value.transcript.entries)
            if (entry is model.ToolEntry) ...?entry.call.terminals,
        ];
        await t.type('bash');
        await t.press('enter');
        // Named up front, before it wrote anything.
        await until(() => terminals().isNotEmpty);
        await t.pump();
        expect(t.screen.text, contains('git status --short'));
        expect(t.screen.text, isNot(contains('notes.md')));

        await until(() => connection.app.value.transcript.turn is model.Idle);
        await t.pump();
        final [terminal] = terminals();
        expect(
          (terminal.output, terminal.exited, terminal.exitCode),
          (' M src/main.tsx\n?? notes.md\n', true, 0),
        );
        final lines = t.screen.lines;
        final call = lines.indexWhere((l) => l.contains('git status --short'));
        final first = lines.indexWhere((l) => l.contains('M src/main.tsx'));
        expect(first, call + 1, reason: t.screen.text);
        expect(lines[first], contains('⎿'));
        expect(lines[first + 1], contains('?? notes.md'));
        // Sent as the terminal, not as the reply's console block.
        expect(t.screen.text, isNot(contains('console')));
        expect(t.screen.text, contains('Two files changed.'));
        await sent(t, connection, 'text');
        expect(t.screen.text, contains('Hello, world.'));
      });
    }
  });
}
