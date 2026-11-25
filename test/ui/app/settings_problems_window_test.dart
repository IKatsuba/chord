// The settings files' problems and the starting values' refusals in the
// real window, on the original's fake agent.
@Tags(['fake_agent'])
library;

import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:chord/session/launch_connection.dart';

import 'package:chord/cli.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/starting.dart';
import 'package:chord/ui/start.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/dev.dart' show shellWord;
import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;
import 'selection_window_test.dart' show RecordingTerminal, select;

const _warnings = [
  '~/.config/chord/settings.json: unknown key "colour", ignored',
  '.chord/settings.json: "theme" is read only from '
      '~/.config/chord/settings.json, ignored',
];

void main() {
  group('tester: CTUI-29 settings reach StartWindow clipboard policy', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      for (final automatic in [false, true]) {
        testWidgets(
          'user copyOnSelect=$automatic governs drag release and CtrlC at $size',
          (t) async {
            final root = Directory.systemTemp.createTempSync(
              'settings-window-tester-',
            );
            final home = p.join(root.path, 'home');
            final work = p.join(root.path, 'project');
            final config = p.join(root.path, 'config');
            final state = p.join(root.path, 'state');
            Directory(work).createSync(recursive: true);
            for (final (path, data) in [
              (
                p.join(config, 'chord', 'settings.json'),
                {
                  'copyOnSelect': automatic,
                  'agents': {
                    'fake': {
                      'command': fakeAgentCommand(null, ['--step-ms', '0']),
                    },
                  },
                },
              ),
              (
                p.join(work, '.chord', 'settings.json'),
                {'copyOnSelect': !automatic},
              ),
            ]) {
              File(path)
                ..createSync(recursive: true)
                ..writeAsStringSync(jsonEncode(data));
            }
            final outcome = await runCli(
              ['fake'],
              stdout: StringBuffer(),
              stderr: StringBuffer(),
              cwd: work,
              home: home,
              environment: {
                'HOME': home,
                'XDG_CONFIG_HOME': config,
                'XDG_STATE_HOME': state,
              },
            );
            expect(outcome.code, 0);
            final launch = outcome.launch!;
            expect(launch.copyOnSelect, automatic);
            final terminal = RecordingTerminal();
            final pids = <int>[];
            final connection = startLaunchConnection(
              launch,
              cwd: work,
              open: fakeSessionOpener(pids.add),
              stateDirectory: () => state,
            );
            addTearDown(() async {
              await connection.close();
              expect(
                pids.where(
                  (pid) =>
                      Process.runSync('kill', ['-0', '$pid']).exitCode == 0,
                ),
                isEmpty,
              );
              await terminal.events.close();
              root.deleteSync(recursive: true);
            });
            await t.pumpWidget(
              StartWindow(
                launch: launch,
                connection: connection,
                terminal: terminal,
              ),
              size: size,
            );
            await fixture.until(
              () => connection.app.value.start.phase == StartPhase.connected,
            );
            await t.pump();
            await fixture.sent(t, connection, 'text');
            final focus = t.focusManager.primaryFocus;
            await select(t, 'Hello');
            expect(terminal.copies, automatic ? ['Hello'] : isEmpty);
            await t.press('ctrl+c');
            expect(terminal.copies, automatic ? ['Hello', 'Hello'] : ['Hello']);
            expect(t.exitRequested, isFalse);
            expect(t.focusManager.primaryFocus, same(focus));
            expect(connection.app.value.draft, isEmpty);
          },
          skip: fakeAgentSkip,
        );
      }
    }
  });
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('the problems lead the transcript, then the start\'s refusal, '
        'at $size', (t) async {
      final directory = Directory.systemTemp.createTempSync('chord-settings-');
      final pids = <int>[];
      final launch = Launch(
        name: 'fake',
        agent: null,
        agentCommand: 'fake',
        version: '0.0.1',
        directory: '/workspace/demo',
        warnings: _warnings,
        starting: const Starting(
          mode: StartingValue('yolo', from: 'set in .chord/settings.json'),
        ),
      );
      final connection = StartConnection(
        command: fakeAgentCommand().map(shellWord).join(' '),
        cwd: directory.path,
        agent: 'fake',
        open: fakeSessionOpener(pids.add),
        owner: Owned(),
        starting: launch.starting,
        warnings: launch.warnings,
      )..start();
      addTearDown(() async {
        await connection.close();
        directory.deleteSync(recursive: true);
      });
      await t.pumpWidget(
        StartWindow(launch: launch, connection: connection),
        size: size,
      );
      await fixture.until(
        () => connection.app.value.start.phase == StartPhase.connected,
      );
      await t.pump();
      final text = t.screen.lines.join('\n');
      final colour = text.indexOf('unknown key "colour"');
      final theme = text.indexOf('"theme" is read only');
      final refusal = text.indexOf('Could not start in yolo mode');
      expect(colour, greaterThanOrEqualTo(0), reason: text);
      expect(theme, greaterThan(colour));
      expect(refusal, greaterThan(theme));
      expect(
        t.screen.lines.join(' ').replaceAll(RegExp(r'\s+'), ' '),
        contains(
          'Could not start in yolo mode, set in .chord/settings.json: the '
          'agent offers default, acceptEdits, plan',
        ),
      );
    }, skip: fakeAgentSkip);
  }
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('a long path in a problem breaks after a slash as the '
        'original at $size', (t) async {
      const warning =
          '.chord/settings.json: "theme" is read only from '
          '/tmp/ctui29-look/cfg/chord/settings.json, ignored';
      final directory = Directory.systemTemp.createTempSync('chord-settings-');
      final launch = Launch(
        name: 'fake',
        agent: null,
        agentCommand: 'fake',
        version: '0.0.1',
        directory: '/workspace/demo',
        warnings: const [warning],
      );
      final connection = StartConnection(
        command: fakeAgentCommand().map(shellWord).join(' '),
        cwd: directory.path,
        agent: 'fake',
        open: fakeSessionOpener((_) {}),
        owner: Owned(),
        warnings: launch.warnings,
      )..start();
      addTearDown(() async {
        await connection.close();
        directory.deleteSync(recursive: true);
      });
      await t.pumpWidget(
        StartWindow(launch: launch, connection: connection),
        size: size,
      );
      await fixture.until(
        () => connection.app.value.start.phase == StartPhase.connected,
      );
      await t.pump();
      final lines = t.screen.lines.map((l) => l.trimRight()).toList();
      final at = lines.indexWhere((l) => l.contains('"theme"'));
      // ../chord at 80x24: docs/design/evidence/CTUI-29/u29b2a-window-o-80x24.txt.
      expect(
        lines.sublist(at, at + 2),
        size.width == 80
            ? [
                ' ⏺ .chord/settings.json: "theme" is read only from '
                    '/tmp/ctui29-look/cfg/chord/',
                '   settings.json, ignored',
              ]
            : [' ⏺ $warning', ''],
      );
    }, skip: fakeAgentSkip);
  }
}
