import 'package:chord/session/conversation.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/sessions.dart';
import 'package:chord/ui/app/state.dart';
import 'package:test/test.dart';

final earlier = EarlierSession(
  resume: const Resume(sessionId: 'saved', cwd: 'project'),
  lastUsedAt: '2000-01-01T00:00:00Z',
  prompt: 'Saved prompt',
);
ResumeListedAction listed(
  Object asked, {
  List<EarlierSession>? sessions,
  String? error,
}) => ResumeListedAction(
  asked,
  id: 'local-report',
  sessions: sessions ?? [earlier],
  cwd: 'project',
  agent: 'fake',
  now: 946771200000,
  error: error,
);

void main() {
  test(
    'fresh read claims an identity and drops older, cleared and closing completions',
    () {
      final first = Object(), second = Object();
      final a = reduceWindow(const AppState(), ResumeAskedAction(first));
      final b = reduceWindow(a, ResumeAskedAction(second));
      expect(reduceWindow(b, listed(first)), same(b));
      final ready = reduceWindow(b, listed(second));
      expect(ready.resumeAsked, isNull);
      expect(ready.resumePicker?.sessions.single, same(earlier));
      expect(ready.resumePicker?.everywhere, isFalse);
      expect(reduceWindow(ready, listed(second)), same(ready));
      final cleared = reduceApp(a, const Cleared());
      expect(reduceWindow(cleared, listed(first)), same(cleared));
      final closing = reduceApp(a, const Closing());
      expect(reduceWindow(closing, listed(first)), same(closing));
      expect(reduceWindow(closing, ResumeAskedAction(second)), same(closing));
      expect(closing.resumeAsked, isNull);
      expect(closing.resumePicker, isNull);
    },
  );
  test(
    'empty, failed and newly busy reads report locally with original precedence',
    () {
      for (final (sessions, error, contains) in [
        (
          <EarlierSession>[],
          null,
          'No earlier fake session to resume, here or in any other directory.',
        ),
        (
          [earlier],
          'Could not read the earlier sessions: denied',
          'Could not read the earlier sessions: denied',
        ),
      ]) {
        final asked = Object();
        final state = reduceWindow(const AppState(), ResumeAskedAction(asked));
        final next = reduceWindow(
          state,
          listed(asked, sessions: sessions, error: error),
        );
        final report = next.transcript.entries.whereType<ReportEntry>().single;
        expect(report.command, 'resume');
        expect(report.rows.single.text, contains);
        expect(next.resumeAsked, isNull);
        expect(next.resumePicker, isNull);
      }
      final asked = Object();
      final before = reduceWindow(const AppState(), ResumeAskedAction(asked));
      final busy = reduceApp(
        before,
        const Transcribed(PromptAction('live', 'work', 1.25)),
      );
      final result = reduceWindow(busy, listed(asked, error: 'read failed'));
      final text = result.transcript.entries
          .whereType<ReportEntry>()
          .single
          .rows
          .single
          .text;
      expect(
        text,
        'A turn is running. Wait for it to end, or press Esc to interrupt it, then /resume.',
      );
      expect(result.resumePicker, isNull);
      expect(
        resumeRefusal(busy.transcript, cancelKey: null),
        'A turn is running. Wait for it to end, then /resume.',
      );
      expect(resumeRefusal(Transcript.empty), isNull);
    },
  );
  test(
    'scope snapshot remounts and closing retains draft while ending selection',
    () {
      final asked = Object();
      final state = reduceWindow(
        reduceWindow(
          const AppState(draft: 'kept draft'),
          ResumeAskedAction(asked),
        ),
        listed(asked),
      );
      final flipped = reduceWindow(
        state,
        const ResumeScopeToggledAction(2000.5),
      );
      expect(flipped.resumePicker?.opening, same(asked));
      expect(flipped.resumePicker?.everywhere, isTrue);
      expect(flipped.resumePicker?.openedAt, 2000.5);
      expect(state.resumePicker?.everywhere, isFalse);
      expect(flipped.resumePicker?.sessions.single, same(earlier));
      expect(
        () => flipped.resumePicker!.sessions.clear(),
        throwsUnsupportedError,
      );
      final closed = reduceWindow(flipped, const ResumePickerClosedAction());
      expect(closed.resumePicker, isNull);
      expect(closed.draft, 'kept draft');
      expect(
        reduceWindow(closed, const ResumePickerClosedAction()),
        same(closed),
      );
    },
  );
  test(
    'permission priority suspends rather than discards the saved snapshot',
    () {
      final asked = Object();
      final ready = reduceWindow(
        reduceWindow(const AppState(), ResumeAskedAction(asked)),
        listed(asked),
      );
      expect(resumePickerShown(ready), isTrue);
      const wait = PermissionWait('permission');
      final working = reduceApp(
        ready,
        const Transcribed(PromptAction('turn', 'work', 1)),
      );
      final pending = reduceApp(
        working,
        const Transcribed(PermissionRequestedAction('turn', wait, at: 1.5)),
      );
      expect(resumePickerShown(pending), isFalse);
      expect(pending.resumePicker, same(ready.resumePicker));
      final answered = reduceApp(
        pending,
        const Transcribed(ResultAction('turn', TurnAnswered('end_turn'))),
      );
      expect(resumePickerShown(answered), isTrue);
      expect(answered.resumePicker, same(ready.resumePicker));
      expect(resumePickerShown(reduceApp(ready, const Closing())), isFalse);
    },
  );
}
