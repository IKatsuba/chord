import 'package:chord/ui/app/start_layout.dart';
import 'package:chord/ui/app/startup_choice.dart';
import 'package:chord/ui/pickers/mcp.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('tester: start model boundaries', () {
    test('explicit empty CLI values still bypass agent choice', () {
      expect(
        chooseAgentAtStart(named: '', stdinTTY: true, stdoutTTY: true),
        isFalse,
      );
      expect(
        chooseAgentAtStart(agentCommand: '', stdinTTY: true, stdoutTTY: true),
        isFalse,
      );
      expect(
        chooseAgentAtStart(resume: '', stdinTTY: true, stdoutTTY: true),
        isFalse,
      );
      expect(
        chooseAgentAtStart(resume: false, stdinTTY: true, stdoutTTY: true),
        isFalse,
      );
      expect(chooseAgentAtStart(stdinTTY: false, stdoutTTY: false), isFalse);
    });

    test(
      'zero-sized windows reserve a safe list without moving art policy',
      () {
        for (final framed in [false, true]) {
          for (final lines in [0, 1, 1000]) {
            final view = startLayout(
              columns: 0,
              rows: 0,
              lines: lines,
              framed: framed,
              hintRows: 1,
            );
            expect(view, (
              step: StartStep.none,
              listRows: 1,
              top: 0,
              column: 1,
            ));
          }
        }
      },
    );

    test(
      'directory cutting preserves original slash and trailing-slash rules',
      () {
        for (final (path, width, expected) in [
          ('/root/alpha/beta/', 4, '…ta/'),
          ('/root/alpha/beta/', 8, '…/beta/'),
          ('/root/alpha/beta/', 12, '…/beta/'),
          ('/root/alpha/beta', 12, '…/alpha/beta'),
          ('abcdefgh/', 4, '…gh/'),
          ('longprefix/界👩‍💻/e\u0301', 4, '…/e\u0301'),
          ('longprefix/界👩‍💻/e\u0301', 8, '…/界👩‍💻/e\u0301'),
        ]) {
          // Same-data answers from the original cutPath.
          expect(cutPath(path, width), expected);
          expect(cellWidth(cutPath(path, width)), lessThanOrEqualTo(width));
        }
      },
    );
  });
}
