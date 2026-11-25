import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/transcript/agents/subagents.dart';
import 'package:chord_tui/chord_tui.dart' show cellWidth, unbounded;
import 'package:test/test.dart';

ToolEntry _tool(String id, {String? guardian}) => ToolEntry(
  't',
  ToolCall(
    id,
    title: 'Read $id',
    kind: 'read',
    status: 'in_progress',
    guardian: guardian,
  ),
);
SubagentEntry _agent(String id) => SubagentEntry('t', Subagent(id, title: id));

void main() {
  group('tester subagent presentation boundaries', () {
    test(
      'wide graphemes survive every row boundary without losing title or counts',
      () {
        const title = '界👩‍💻e\u0301界👩‍💻e\u0301 long-title';
        const agent = Subagent('a', title: title);
        for (final width in [120, 66, 70, 30, 12, 2, 1, 0, unbounded]) {
          final rows = groupRow(agent, width);
          final text = rows.map((r) => r.map((s) => s.text).join()).join();
          expect(
            text.replaceAll(RegExp(r'\s+'), ''),
            'Agent($title)·0tooluses'.replaceAll(RegExp(r'\s+'), ''),
            reason: 'width=$width',
          );
          for (final row in rows) {
            final text = row.map((s) => s.text).join();
            expect(
              cellWidth(text),
              lessThanOrEqualTo(width < 2 ? 2 : width),
              reason: 'width=$width text=$text',
            );
          }
        }
      },
    );

    test('title and count spans stay distinct after wrapping', () {
      const title = 'A very long title 界👩‍💻e\u0301';
      for (final width in [120, 66, 70, 30, 12]) {
        final rows = groupRow(const Subagent('a', title: title), width);
        final titleOnly = [
          for (final row in rows) rowSpan(row, counts: false).toPlainText(),
        ].join();
        final countsOnly = [
          for (final row in rows) rowSpan(row, counts: true).toPlainText(),
        ].join();
        expect(
          titleOnly.replaceAll(' ', ''),
          'Agent($title)'.replaceAll(' ', ''),
        );
        expect(countsOnly.replaceAll(' ', ''), '·0tooluses');
      }
    });

    test('only the matching child wait selects an earlier call', () {
      final agent = Subagent('child', entries: [_tool('first'), _tool('last')]);
      const other = PermissionWait(
        'other',
        subagentId: 'sibling',
        toolCallId: 'first',
      );
      const own = PermissionWait(
        'own',
        subagentId: 'child',
        toolCallId: 'first',
      );
      final unmarked = (rowLine(agent, const [other]) as RowCall).line;
      expect(unmarked.headline.arg, 'last');
      expect(unmarked.waiting, isFalse);
      final selected = (rowLine(agent, const [other, own]) as RowCall).line;
      expect(selected.headline.arg, 'first');
      expect(selected.waiting, isTrue);
      expect(
        rowLine(agent.copyWith(state: SubagentState.completed), const [own]),
        isA<RowEnded>(),
      );
    });

    test(
      'plan breaks adjacent groups at start middle and end exactly once',
      () {
        final entries = [_agent('one'), _agent('two')];
        final plan = [
          acp.PlanEntry.fromJson({
            'content': 'Step',
            'priority': 'medium',
            'status': 'pending',
          }),
        ];
        for (final at in [0, 1, 2]) {
          final work = workOf(
            Subagent('parent', entries: entries, plan: plan, planAt: at),
          );
          expect(work.whereType<WorkPlan>(), hasLength(1));
          expect(
            work
                .whereType<WorkAgents>()
                .expand((g) => g.agents)
                .map((a) => a.id),
            ['one', 'two'],
          );
          expect(work.whereType<WorkAgents>().length, at == 1 ? 2 : 1);
          expect(work.indexWhere((i) => i is WorkPlan), at == 0 ? 0 : 1);
        }
      },
    );

    test('hidden Guardian calls do not split groups or count as tool use', () {
      final entries = [
        _agent('one'),
        _tool('hidden', guardian: 'approved'),
        _agent('two'),
      ];
      expect(agentGroup(entries, 0)!.map((a) => a.id), ['one', 'two']);
      expect(agentGroup(entries, 2), isEmpty);
      final parent = Subagent('parent', entries: entries);
      expect(toolUses(parent), 2);
      expect(workOf(parent), hasLength(1));
    });
  });
}
