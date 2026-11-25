// The non-team cases of the original's tests/ui/app/rename_test.ts.
import 'package:chord/ui/app/rename.dart';
import 'package:test/test.dart';

void main() {
  group('tester: original rename notes', () {
    test('each unavailable target is refused in the original words', () {
      expect(refusedNote(RenameRefusal.starting, 'unused'), (
        text: 'The session is not open yet; rename it once it is.',
        failed: true,
      ));
      expect(refusedNote(RenameRefusal.exited, 'parser'), (
        text: 'parser has exited; its session cannot be renamed.',
        failed: true,
      ));
      expect(refusedNote(RenameRefusal.task, 'main'), (
        text: 'main is a task; it keeps the title it was given.',
        failed: true,
      ));
    });

    test('no title explains usage and a present title is normalized', () {
      expect(unnamedNote(null), (
        text: 'Name the session: /rename <title>',
        failed: false,
      ));
      expect(unnamedNote('Fix\nthe   parser'), (
        text: 'Name the session: /rename <title>. Now: Fix the parser',
        failed: false,
      ));
    });

    test(
      'progress, agent success, local success and refusal match the original',
      () {
        expect(renamingNote('Parser test tidy-up'), (
          text: 'Renaming to Parser test tidy-up…',
          failed: false,
        ));
        expect(renamedNote('Parser test tidy-up', 'claude', true), (
          text: 'Renamed to Parser test tidy-up',
          failed: false,
        ));
        expect(renamedNote('Parser test tidy-up', 'cursor', false), (
          text:
              'Renamed to Parser test tidy-up in chord only: cursor takes no title, and its own may replace it',
          failed: false,
        ));
        expect(refusedByAgentNote('claude', 'Session title cannot be empty'), (
          text:
              'Could not rename: claude refused it: Session title cannot be empty',
          failed: true,
        ));
      },
    );

    test('agent title and refusal text lose escapes and become one line', () {
      expect(
        renamedNote('\x1b[31mRed\x1b[0m\ntitle', 'claude', true).text,
        'Renamed to Red title',
      );
      expect(
        refusedByAgentNote('fake', '\x1b[31mNo\x1b[0m\n\t界🙂e\u0301').text,
        'Could not rename: fake refused it: No 界🙂e\u0301',
      );
    });
  });
}
