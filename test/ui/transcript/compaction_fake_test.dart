// The window declares compactions and draws them, on the original's fake
// agent (tests/fixtures/fake_agent/scenarios/compaction.ts), which sends a
// compaction by id only to a client that declared `session.compaction`. The
// original's Transcript_test.tsx compaction case, with Claude's compaction of
// an idle session beside it.
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
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/dev.dart' show shellWord;
import '../../fixtures/fake_harness.dart';
import '../app/window_fake_test.dart' show launch, sent, until;

/// Why the fake's `compactfail` compaction failed, as Claude says it.
const compactError = 'Not enough messages to compact.';

Future<(StartConnection, Directory)> _open(
  WidgetTester t,
  Size size, {
  List<String> flags = const [],
}) async {
  final directory = Directory.systemTemp.createTempSync('chord-compaction-');
  final connection = StartConnection(
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
  await t.pumpWidget(
    StartWindow(launch: launch, connection: connection),
    size: size,
  );
  await until(() => connection.app.value.start.phase == StartPhase.connected);
  return (connection, directory);
}

Iterable<model.Compaction> _compactions(StartConnection connection) => [
  for (final entry in connection.app.value.transcript.entries)
    if (entry is model.CompactionEntry) entry.compaction,
];

void main() {
  group('compactions in the window', skip: fakeAgentSkip, () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('a compaction reads as compacting, then compacted with its '
          'summary behind ctrl+o, and a failed one says why at $size', (
        t,
      ) async {
        final (connection, _) = await _open(t, size);
        await t.type('compact');
        await t.press('enter');
        await until(
          () => _compactions(
            connection,
          ).any((c) => c.status == 'in_progress' && c.summary.isNotEmpty),
        );
        await t.pump();
        // Within a turn the spinner says it, and the transcript draws
        // nothing.
        expect(t.screen.text, contains('Compacting conversation… ('));
        expect(t.screen.text, isNot(contains('✻ Compacting')));
        expect(t.screen.text, isNot(contains('Working…')));

        await until(() => connection.app.value.transcript.turn is model.Idle);
        await t.pump();
        expect(
          t.screen.text,
          contains('⎿  Conversation compacted (ctrl+o for history)'),
        );
        expect(t.screen.text, isNot(contains('Compacting conversation')));
        expect(t.screen.text, isNot(contains('Next: commit')));

        await t.press('ctrl+o');
        expect(t.screen.text, contains('Next: commit the change.'));
        expect(t.screen.text, isNot(contains('for history')));
        await t.press('ctrl+o');
        expect(t.screen.text, isNot(contains('Next: commit')));

        await sent(t, connection, 'compactfail');
        expect(t.screen.text, contains('⎿  Compaction failed: $compactError'));
      });

      testWidgets("Claude's compaction of an idle session is drawn in the "
          'transcript while it runs, then says it ran while idle at $size', (
        t,
      ) async {
        final (connection, directory) = await _open(
          t,
          size,
          flags: const ['--adapter', 'claude'],
        );
        Directory(p.join(directory.path, '.fake-gate')).createSync();
        await sent(t, connection, 'idlecompact');
        await until(() => _compactions(connection).isNotEmpty);
        await t.pump();
        // No turn runs, so no spinner: the transcript says it.
        expect(
          t.screen.text,
          contains('✻ Compacting conversation while idle…'),
        );
        expect(connection.app.value.transcript.turn, isA<model.Idle>());

        File(
          p.join(directory.path, '.fake-gate', 'release'),
        ).writeAsStringSync('');
        await until(
          () => _compactions(connection).single.status == 'completed',
        );
        await t.pump();
        expect(
          t.screen.text,
          contains('⎿  Conversation compacted while idle (ctrl+o for history)'),
        );
        expect(t.screen.text, isNot(contains('Compacting conversation')));
      });

      testWidgets('a prompt sent while an idle compaction runs waits behind '
          'it, and the spinner says it at $size', (t) async {
        final (connection, directory) = await _open(
          t,
          size,
          flags: const ['--adapter', 'claude'],
        );
        Directory(p.join(directory.path, '.fake-gate')).createSync();
        await sent(t, connection, 'idlecompact');
        await until(() => _compactions(connection).isNotEmpty);
        await t.type('text');
        await t.press('enter');
        await until(() => connection.app.value.transcript.turn is! model.Idle);
        await t.pump();
        expect(t.screen.text, contains('Compacting conversation… ('));
        expect(t.screen.text, isNot(contains('✻ Compacting')));

        File(
          p.join(directory.path, '.fake-gate', 'release'),
        ).writeAsStringSync('');
        await until(
          () =>
              connection.app.value.transcript.turn is model.Idle &&
              _compactions(connection).single.status == 'completed',
        );
        await t.pump();
        expect(t.screen.text, contains('Conversation compacted while idle'));
        expect(t.screen.text, contains('Hello, world.'));
      });
    }
  });
}
