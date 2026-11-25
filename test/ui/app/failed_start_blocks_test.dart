// Under the failed start's line, the original's SignInBlock or
// StartFailureBlock (../chord src/ui/app/App.tsx, SignIn.tsx,
// StartFailure.tsx): the pin, the ways in, the way on, the stderr's end.
import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'resume_window_test.dart' as resume;
import 'window_fake_test.dart' show until;

const _wayOn =
    "chord does not sign agents in. Sign in with memory's own CLI in a "
    'terminal, or set its API key where it offers one.';

/// Opens a window on an in-memory agent that [answer] plays, and waits for
/// its start to fail; the window's rows from the failure on.
Future<List<String>> _failed(
  WidgetTester t,
  Size size, {
  required void Function(MemoryAgentProcess process, Set<Object?> answered)
  answer,
  String? pinned,
}) async {
  late final MemoryAgentProcess process;
  process = MemoryAgentProcess(
    onSignal: (_) {
      if (process.exited) return;
      process.exit(const Exit(143, 'SIGTERM'));
      process.closeStdout();
      process.closeStderr();
    },
  );
  final answered = <Object?>{};
  final timer = Timer.periodic(
    const Duration(milliseconds: 5),
    (_) => answer(process, answered),
  );
  final connection = StartConnection(
    command: 'memory',
    cwd: '/w',
    agent: 'memory',
    owner: Owned(),
    pinned: pinned,
    open:
        ({
          required command,
          env,
          required cwd,
          required onTraffic,
          required onPermission,
          relay,
          cancellationToken,
        }) => connectAgent(
          process,
          onTraffic: onTraffic,
          onPermission: onPermission,
          relay: relay,
          cancellationToken: cancellationToken,
        ),
  )..start();
  addTearDown(() async {
    timer.cancel();
    await connection.close();
  });
  await t.pumpWidget(
    TranscriptWindow(launch: resume.launch, connection: connection),
    size: size,
  );
  await until(() => connection.app.value.start.phase == StartPhase.failed);
  await t.pump();
  final lines = t.screen.lines.map((l) => l.trimRight()).toList();
  return lines.sublist(lines.indexWhere((l) => l.contains('did not start')));
}

/// Answers initialize with [methods], then refuses session/new as
/// authRequired.
void Function(MemoryAgentProcess, Set<Object?>) _refusing(
  List<Map<String, Object?>> methods,
) => (process, answered) {
  for (final message in [...process.stdin.messages]) {
    final id = message['id'];
    if (id == null || !answered.add(id)) continue;
    process.send({
      'jsonrpc': '2.0',
      'id': id,
      if (message['method'] == 'initialize')
        'result': {'protocolVersion': 1, 'authMethods': methods}
      else
        'error': {'code': -32000, 'message': 'Authentication required'},
    });
  }
};

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('a sign-in needed shows the pin, the ways and the way on '
        'at $size', (t) async {
      final rows = await _failed(
        t,
        size,
        pinned: 'memory-acp@1.2.3',
        answer: _refusing([
          {'id': 'b', 'name': 'Browser', 'description': 'Opens a page'},
          {'id': 'k', 'name': 'Key'},
        ]),
      );
      expect(rows.take(5), [
        ' ⏺ memory did not start: Authentication required',
        '   ⎿  chord ran memory-acp@1.2.3, the version this chord pins.',
        '      memory offers these sign-ins:',
        '        Browser · Opens a page',
        '        Key',
      ]);
      expect(rows[5], startsWith('      chord does not sign agents in.'));
      expect(
        rows
            .skip(5)
            .takeWhile((l) => l.isNotEmpty)
            .map((l) => l.trim())
            .join(' '),
        _wayOn,
      );
    });

    testWidgets('a sign-in with no ways and no pin says only the way on '
        'at $size', (t) async {
      final rows = await _failed(t, size, answer: _refusing(const []));
      expect(rows[1], startsWith('   ⎿  chord does not sign agents in.'));
      expect(rows.join('\n'), isNot(contains('memory offers')));
      expect(rows.join('\n'), isNot(contains('chord ran')));
    });

    testWidgets('an agent that exits shows the pin and the end of its '
        'stderr at $size', (t) async {
      final rows = await _failed(
        t,
        size,
        pinned: 'memory-acp@1.2.3',
        answer: (process, answered) {
          if (!answered.add('exit')) return;
          process.writeStderr('first\nboom\n');
          process.closeStderr();
          process.exit(const Exit(3));
          process.closeStdout();
        },
      );
      expect(rows.take(5), [
        ' ⏺ memory did not start: it exited with code 3 before answering '
            'initialize.',
        '   ⎿  chord ran memory-acp@1.2.3, the version this chord pins.',
        '      The end of its stderr:',
        '        first',
        '        boom',
      ]);
    });
  }
}
