// The window draws the original fake agent's subagents (its `subagent`,
// `subagentcall` and `claudesubagents` scenarios) as the original's
// Agents.tsx does: a lone block, a group's tree, a child's permission named
// by its way down, the line for one that outlived its turn, and the status
// line while one still runs.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/acp/connection.dart' show windowCapabilities;
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord/ui/theme/theme.dart' show themeData;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../../tool/dev.dart' show shellWord;
import '../../../fixtures/fake_harness.dart';
import '../../app/window_fake_test.dart' show launch, until;

void main() {
  group('subagents in the window', skip: fakeAgentSkip, () {
    late StartConnection connection;

    Future<void> open(
      WidgetTester t,
      Size size, [
      List<String> flags = const [],
    ]) async {
      final directory = Directory.systemTemp.createTempSync('chord-agents-');
      connection = StartConnection(
        command: fakeAgentCommand(null, flags).map(shellWord).join(' '),
        cwd: directory.path,
        agent: 'fake',
        open: fakeOpenerWith(capabilities: windowCapabilities()),
        owner: Owned(),
      )..start();
      addTearDown(() async {
        await connection.close();
        directory.deleteSync(recursive: true);
      });
      await until(
        () => connection.app.value.start.phase == StartPhase.connected,
      );
      await t.pumpWidget(
        TranscriptWindow(launch: launch, connection: connection),
        size: size,
      );
    }

    Future<void> idle(WidgetTester t) async {
      await until(() => connection.app.value.transcript.turn is model.Idle);
      await t.pump();
    }

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('a group, a child asking by its way down, and a lone '
          'background agent that ends after its turn at $size', (t) async {
        await open(t, size);
        await t.type('subagent');
        await t.press('enter');
        await until(
          () =>
              connection.app.value.transcript.turn is model.AwaitingPermission,
        );
        await t.pump();
        final asking = t.screen.text;
        // The asking child is an agent item: the background's summary line,
        // the last under the status line as the original's App draws it,
        // counts it by its parent (background.ts summaryGroups), the one
        // that failed having left.
        final lines = asking.split('\n');
        expect(lines.last.trim(), "background  ● main's agent asking");
        // At 80x24 the permission box and that line leave the header and the
        // tree's first row out of sight; the asking row and the last stay.
        if (size.height >= 40) {
          expect(asking, contains('⏺ Running 2 agents… (ctrl+o to expand)'));
          expect(asking, contains('├─ Agent(Find the session layer)'));
        } else {
          expect(asking, isNot(contains('Running 2 agents')));
          expect(asking, isNot(contains('├─ Agent(Find the session layer)')));
          expect(
            lines.first.trim(),
            '│  ⎿  Write(notes/routing.md) · waiting for permission',
          );
          expect(asking, contains('└─ Agent(Find where tool calls are drawn'));
        }
        expect(
          asking,
          contains('⎿  Write(notes/routing.md) · waiting for permission'),
        );
        expect(asking, contains('Agent(Find the session layer) asks'));
        // The asker in the accent, its name bold and the rest not.
        final row = t.screen.lines.indexWhere(
          (line) => line.contains('Agent(Find the session layer) asks'),
        );
        final at = t.screen.lines[row].indexOf(
          'Agent(Find the session layer) asks',
        );
        final accent = themeData('dark').accent.fg;
        expect(t.screen.styleAt(at, row).fg, accent);
        expect(t.screen.styleAt(at, row).isBold, isTrue);
        final asks = at + 'Agent(Find the session layer)'.length + 1;
        expect(t.screen.styleAt(asks, row).fg, accent);
        expect(t.screen.styleAt(asks, row).isBold, isFalse);
        expect(asking, contains('Waiting for permission…'));
        await t.press('enter');
        await idle(t);
        final done = t.screen.text;
        expect(
          done,
          contains('⏺ 2 agents ended · 1 failed (ctrl+o to expand)'),
        );
        expect(done, contains('│  ⎿  Done'));
        // The child's answer is part of its work, folded with it.
        expect(done, isNot(contains('Allowed Write')));
        expect(done, contains('⎿  Failed'));
        expect(done, contains('⏺ Agent(Run the whole test suite)'));
        // Out of sight, perhaps: the status line says one still runs.
        if (connection.app.value.transcript.entries
            .whereType<model.ItemEndedEntry>()
            .isEmpty) {
          expect(done, contains('1 agent still running'));
        }
        await until(
          () => connection.app.value.transcript.entries
              .whereType<model.ItemEndedEntry>()
              .isNotEmpty,
        );
        await t.pump();
        expect(
          t.screen.text,
          contains(
            '✓ Run bun dev test and report what fails. · agent · done in',
          ),
        );
        expect(t.screen.text, contains('⎿  Done (1 tool use ·'));
        expect(t.screen.text, isNot(contains('still running')));
      });

      testWidgets('a lone subagent folds to its ending, and ctrl+o opens its '
          'task and work at $size', (t) async {
        await open(t, size);
        await t.type('subagentcall');
        await t.press('enter');
        await idle(t);
        expect(t.screen.text, contains('⏺ Agent(sleeper)'));
        expect(t.screen.text, contains('⎿  Done (1 tool use ·'));
        await t.press('ctrl+o');
        expect(t.screen.text, contains('⏺ Agent(sleeper)'));
      });
    }

    testWidgets("Claude's subagents are named by their title, its launches "
        'drawn as messages', (t) async {
      await open(t, const Size(120, 40), const ['--adapter', 'claude']);
      await t.type('claudesubagents');
      await t.press('enter');
      await until(
        () =>
            connection.app.value.transcript.turn is model.AwaitingPermission ||
            connection.app.value.transcript.turn is model.Idle,
      );
      await t.pump();
      expect(t.screen.text, contains('Agent('));
      if (connection.app.value.transcript.turn is model.AwaitingPermission) {
        expect(t.screen.text, contains(') asks'));
        await t.press('enter');
      }
      await idle(t);
      expect(t.screen.text, isNot(contains('subagent_')));
    });

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('a launch with code folds after its box, and opens whole '
          'under ctrl+o at $size', (t) async {
        await open(t, size, const ['--adapter', 'claude']);
        await t.type('claudecodeprompt');
        await t.press('enter');
        await idle(t);
        final lines = t.screen.lines;
        final head = lines.indexWhere(
          (line) => line.contains('→ to Agent(Check the build)'),
        );
        expect(head, isNot(-1), reason: t.screen.text);
        expect(lines[head + 1], startsWith('   ⎿  Run this first.'));
        expect(lines[head + 2], isEmpty);
        expect(lines[head + 3], contains('sh'));
        expect(lines[head + 4], contains('bun test'));
        expect(lines[head + 6], isEmpty);
        expect(
          lines[head + 7],
          startsWith('      … +15 lines (ctrl+o to expand)'),
        );
        expect(t.screen.text, isNot(contains('[copy]')));
        expect(t.screen.text, contains('⏺ Agent(Check the build)'));
        printOnFailure(t.screen.text);
        await t.press('ctrl+o');
        expect(t.screen.text, isNot(contains('more lines')));
        expect(t.screen.text, isNot(contains('+15 lines')));
      });
    }
  });
}
