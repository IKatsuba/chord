import 'dart:async';

import 'package:chord/session/sessions.dart';
import 'package:chord/ui/start.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

import 'cli_resume_test.dart' show ResumeTerminal, saved;

class _HeldLeaveTerminal extends ResumeTerminal {
  _HeldLeaveTerminal(super.size);
  final leaving = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> leave() async {
    await super.leave();
    leaving.complete();
    await release.future;
  }
}

void main() {
  group('CTUI-26 U6 tester: startup awaits terminal restoration', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      for (final cancel in [false, true]) {
        test(
          '${cancel ? 'Ctrl+D cancellation' : 'selection'} returns only after leave completes $size',
          () async {
            final terminal = _HeldLeaveTerminal(size)
              ..keys = cancel ? '\x04' : '\r';
            final sessions = earlierSessions([saved('local')], agent: 'claude');
            var returned = false;
            final choosing =
                selectStartupResume(
                  sessions: sessions,
                  agent: 'claude',
                  version: 'fixture',
                  directory: 'project',
                  cwd: 'project',
                  home: null,
                  terminal: terminal,
                  environment: const {'NO_COLOR': '1'},
                ).then((result) {
                  returned = true;
                  return result;
                });
            try {
              await terminal.leaving.future.timeout(const Duration(seconds: 5));
              expect(terminal.entered, 1);
              expect(terminal.left, 1);
              expect(returned, isFalse);
              terminal.release.complete();
              final selected = await choosing.timeout(
                const Duration(seconds: 5),
              );
              expect(selected?.resume.sessionId, cancel ? isNull : 'local');
              expect(returned, isTrue);
              expect(terminal.left, 1);
            } finally {
              if (!terminal.release.isCompleted) terminal.release.complete();
              await terminal.events.close();
            }
          },
        );
      }
    }
  });
}
