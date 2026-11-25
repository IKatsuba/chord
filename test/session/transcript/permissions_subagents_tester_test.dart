import 'package:chord/session/permission_review.dart';
import 'package:chord/session/transcript/permissions.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

const _review = PermissionReview('caution', 'Review only the named child');
ToolEntry _tool() => const ToolEntry(
  't',
  ToolCall('same', title: 'Read same', status: 'in_progress'),
);
Transcript _tree() => Transcript(
  turn: const Working('t', 1),
  entries: [
    _tool(),
    SubagentEntry(
      't',
      Subagent(
        'child',
        entries: [
          _tool(),
          SubagentEntry('t', Subagent('grandchild', entries: [_tool()])),
        ],
      ),
    ),
    SubagentEntry('t', Subagent('sibling', entries: [_tool()])),
  ],
);
Map<String, ToolCall> _calls(List<Entry> entries, [String on = 'root']) => {
  for (final e in entries)
    if (e is ToolEntry)
      on: e.call
    else if (e is SubagentEntry)
      ..._calls(e.subagent.entries, e.subagent.id),
};

void main() {
  group('tester nested permission review ownership', () {
    for (final target in ['child', 'grandchild']) {
      test('$target review never marks equal call ids in root or siblings', () {
        final before = _tree();
        final after = permissionRequested(
          before,
          't',
          PermissionWait(
            'p',
            toolCallId: 'same',
            subagentId: target,
            review: _review,
          ),
          at: 42,
        );
        final calls = _calls(after.entries);
        for (final entry in calls.entries) {
          expect(
            entry.value.review,
            entry.key == target ? same(_review) : isNull,
          );
        }
        expect(
          _calls(before.entries).values.map((c) => c.review),
          everyElement(isNull),
        );
        final wait = (after.turn as AwaitingPermission).permissions.single;
        expect(wait.at, 42);
        expect(wait.deadlineAt, isNull);
        expect(wait.subagentId, target);
      });
    }

    test('unknown child review cannot mutate any drawn call', () {
      final before = _tree();
      final after = permissionRequested(
        before,
        't',
        const PermissionWait(
          'p',
          toolCallId: 'same',
          subagentId: 'unknown',
          review: _review,
        ),
        at: 43,
      );
      expect(
        _calls(after.entries).values.map((c) => c.review),
        everyElement(isNull),
      );
      expect(after.entries, same(before.entries));
    });

    test(
      'askedBy and askedAt retain deadline and child across either copy order',
      () {
        const wait = PermissionWait(
          'p',
          toolCallId: 'same',
          deadlineAt: 100,
          review: _review,
        );
        for (final copied in [
          wait.askedBy('child').askedAt(42),
          wait.askedAt(42).askedBy('child'),
        ]) {
          expect(
            (copied.subagentId, copied.at, copied.deadlineAt),
            ('child', 42, 100),
          );
          expect(copied.review, same(_review));
        }
        final root = permissionRequested(
          _tree(),
          't',
          const PermissionWait('p', toolCallId: 'same'),
          at: 42,
        );
        expect((root.turn as AwaitingPermission).permissions.single.at, isNull);
      },
    );
  });
}
