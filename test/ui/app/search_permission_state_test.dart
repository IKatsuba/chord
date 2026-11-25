import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/search.dart';
import 'package:test/test.dart';

const wait = PermissionWait('ask', toolCallId: 'call', title: 'Approve notes');
const search = Search(query: 'alpha', match: 0);
AppState searching() => const AppState(
  draft: 'saved 界😀',
  cursor: 3,
  search: search,
  transcript: Transcript(turn: Working('turn', 100.25)),
);
void main() {
  _testerPermissionSearchRecovery();
  test(
    'permission fold closes search while preserving draft/cursor and numeric facts',
    () {
      final before = searching();
      final next = reduceApp(
        before,
        const Transcribed(PermissionRequestedAction('turn', wait, at: 123.75)),
      );
      expect(next.search, isNull);
      expect((next.draft, next.cursor), (before.draft, before.cursor));
      expect((next.transcript.turn as AwaitingPermission).since, 100.25);
      final answered = reduceApp(
        next,
        const Transcribed(PermissionSettledAction('turn', 'ask', Rejected())),
      );
      expect(answered.search, isNull);
      expect((answered.draft, answered.cursor), (before.draft, before.cursor));
    },
  );
  test(
    'between-turn held request keeps query until attending the real request',
    () {
      final next = reduceApp(
        const AppState(draft: 'saved', cursor: 2, search: search),
        const Transcribed(
          PermissionRequestedAction('turn', wait, between: true),
        ),
      );
      expect(heldBack(next), isTrue);
      expect(next.search, same(search));
      final attended = reduceWindow(next, const AttendRequestAction());
      expect(attended.search, isNull);
      expect(attended.attended, 'ask');
      expect((attended.draft, attended.cursor), (next.draft, next.cursor));
    },
  );
}

void _testerPermissionSearchRecovery() {
  test(
    'tester: active ask closes search and later held/settled facts cannot reopen it',
    () {
      var state = reduceApp(
        searching(),
        const Transcribed(PermissionRequestedAction('turn', wait, at: 125.5)),
      );
      expect(state.search, isNull);
      state = reduceApp(
        state,
        const Transcribed(PermissionSettledAction('turn', 'ask', Rejected())),
      );
      state = reduceApp(
        state,
        const Transcribed(
          PermissionRequestedAction(
            'turn',
            PermissionWait('later', toolCallId: 'other', title: 'Later ask'),
            between: true,
            at: 126.75,
          ),
        ),
      );
      expect(state.search, isNull);
      expect((state.draft, state.cursor), ('saved 界😀', 3));
      state = reduceWindow(state, const AttendRequestAction());
      expect(state.search, isNull);
      expect(state.attended, 'later');
      state = reduceApp(
        state,
        const Transcribed(PermissionSettledAction('turn', 'later', Rejected())),
      );
      expect(state.search, isNull);
      expect((state.draft, state.cursor), ('saved 界😀', 3));
    },
  );
}
