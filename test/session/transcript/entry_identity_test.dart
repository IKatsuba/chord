import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/permission_review.dart';
import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord_tui/chord_tui.dart'
    show SelectionChildDelegate, SelectionSource, TextSpan;
import 'package:test/test.dart';

import 'fold.dart';

void main() {
  test(
    'const fallback token is independent and stable, appended occurrences never alias',
    () {
      const entry = UserEntry('t', 'same');
      final fallback = entry.identity;
      expect(fallback, isNot(isA<Entry>()));
      expect(entry.identity, same(fallback));
      final entries = appended([], [entry, entry]);
      expect(entries[0].identity, isNot(same(entries[1].identity)));
      expect(entries[0].identity, isNot(same(fallback)));
      expect(entries[1].identity, isNot(same(fallback)));
      final appendedAgain = appended(entries, [entries[0], entry]);
      expect(appendedAgain.map((e) => e.identity).toSet(), hasLength(4));
      final afterRemoval = appended([], [entries[0]]);
      expect(afterRemoval.single.identity, isNot(same(entries[0].identity)));
      expect(appendedAgain[0], same(entries[0]));
      expect(appendedAgain[1], same(entries[1]));
    },
  );

  test(
    'writer clone is exhaustive and preserves all payload fields and references',
    () {
      final run = TextRun.empty.plus('streamed');
      final review = const PermissionReview('caution', 'reason');
      final option = acp.PermissionOption.fromJson({
        'optionId': 'a',
        'name': 'Allow',
        'kind': 'allow_once',
      });
      final plan = [
        acp.PlanEntry.fromJson({
          'content': 'work',
          'priority': 'high',
          'status': 'in_progress',
        }),
      ];
      final call = ToolCall(
        'tool',
        title: 'Bash',
        terminals: [
          const Terminal(
            'term',
            output: 'text',
            exitCode: 1.5,
            signal: 'SIGTERM',
            truncated: true,
          ),
        ],
      );
      final kinds = <Entry>[
        const UserEntry('t', 'user'),
        AssistantEntry('t', run, messageId: 'message'),
        ThoughtEntry('t', run, messageId: 'thought'),
        ToolEntry('t', call),
        const NotedEntry('t', 'config', 'failed', failed: true),
        const ReportEntry('t', 'status', [(label: 'Model', text: 'x')]),
        PermissionEntry('t', title: 'request', option: option, review: review),
        const CancelledEntry('t'),
        const StoppedEntry('t', 'limit'),
        const ErrorEntry('t', 'error', code: -1),
        const WarningEntry('t', 'warning'),
        FinishedPlanEntry('t', plan),
      ];
      final entries = appended([], kinds);
      expect(entries.map(describedEntry), kinds.map(describedEntry));
      for (var i = 0; i < kinds.length; i++) {
        expect(entries[i].runtimeType, kinds[i].runtimeType);
        expect(entries[i].identity, isNot(same(kinds[i].identity)));
        expect(identical(entries[i], kinds[i]), isFalse);
        final replacement = replacedAt(entries, i, kinds[i]);
        expect(replacement[i].identity, same(entries[i].identity));
        expect(describedEntry(replacement[i]), describedEntry(kinds[i]));
        for (var j = 0; j < kinds.length; j++) {
          if (j != i) expect(replacement[j], same(entries[j]));
        }
      }
      expect((entries[1] as AssistantEntry).text, same(run));
      expect((entries[3] as ToolEntry).call, same(call));
      expect((entries[6] as PermissionEntry).review, same(review));
      expect((entries[6] as PermissionEntry).option, same(option));
      expect((entries.last as FinishedPlanEntry).entries, same(plan));
    },
  );

  test(
    'streaming replacements preserve tokens, new runs and local notes issue correctly',
    () {
      var state = fold([const PromptAction('t', 'p', 0), say('t', 'first')]);
      final user = state.entries.first, reply = state.entries.last;
      state = reduceTranscript(state, say('t', ' more'));
      expect(state.entries.first, same(user));
      expect(state.entries.last.identity, same(reply.identity));
      expect(state.entries.last, isNot(same(reply)));
      state = reduceTranscript(state, think('t', 'thought'));
      state = reduceTranscript(state, say('t', 'new reply'));
      expect(state.entries.map((e) => e.identity).toSet(), hasLength(4));
      state = noted(state, 'note', 'config', 'pending');
      final note = state.entries.last.identity;
      state = noted(state, 'note', 'config', 'done');
      expect(state.entries.last.identity, same(note));
      expect(reduceTranscript(state, say('t', '')), same(state));
    },
  );

  test(
    'raw duplicate canonical entries are rejected, writer occurrences satisfy delegate identity',
    () {
      const entry = UserEntry('t', 'same');
      SelectionChildDelegate delegate(List<Entry> entries) =>
          SelectionChildDelegate(
            itemCount: entries.length,
            idAt: (i) => entries[i].identity,
            indexOfId: (id) {
              final i = entries.indexWhere((e) => e.identity == id);
              return i < 0 ? null : i;
            },
            sourceAt: (i) => SelectionSource.text(
              id: entries[i].identity,
              revision: entries[i],
              text: const TextSpan('same'),
            ),
          );
      expect(() => delegate([entry, entry]), throwsArgumentError);
      expect(delegate(appended([], [entry, entry])).itemCount, 2);
    },
  );
}
