// The original's tests/ui/transcript/agents/subagents_test.ts, without
// chord's own task agents (M4): the group, the block folded, the row, the
// asker row and the status line's words.
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/transcript/agents/subagents.dart';
import 'package:chord/ui/transcript/tools/tools.dart';
import 'package:test/test.dart';

const _t = 't1';

Entry tool(String id, String title, [String? status]) =>
    ToolEntry(_t, ToolCall(id, title: title, status: status));

Entry entryOf(Subagent subagent) => SubagentEntry(_t, subagent);

final find = Subagent(
  'a1',
  title: 'Find the session layer',
  description: 'Find where chord hands each session/update to its listeners.',
  entries: [
    tool('c1', 'Search sessionUpdate in src', 'completed'),
    AssistantEntry(_t, TextRun.empty.plus('Looking.')),
    tool('c2', 'Read src/acp/connection.ts', 'completed'),
    entryOf(const Subagent('a3', title: 'Read the transport tests')),
    tool('c3', 'Read src/session/session.ts', 'failed'),
    tool('c4', 'Write notes/routing.md', 'pending'),
  ],
);

const draw = Subagent(
  'a2',
  title: 'Find where tool calls are drawn on screen and how they fold',
);

String said(WorkLine line) =>
    '${line.headline.name}(${line.headline.arg})${line.failed ? ' failed' : ''}${line.waiting ? ' waiting' : ''}';

List<String> lines(Subagent subagent, int width) => [
  for (final runs in groupRow(subagent, width))
    runs.map((run) => run.text).join(),
];

void main() {
  test(
    'subagents spawned back to back are one group, drawn from the first',
    () {
      final entries = [
        tool('x', 'Read x'),
        entryOf(find),
        entryOf(draw),
        AssistantEntry(_t, TextRun.empty.plus('Out.')),
        entryOf(const Subagent('b')),
      ];
      expect(agentGroup(entries, 0), isNull);
      expect([for (final s in agentGroup(entries, 1)!) s.id], ['a1', 'a2']);
      expect(agentGroup(entries, 2), isEmpty);
      expect([for (final s in agentGroup(entries, 4)!) s.id], ['b']);
    },
  );

  test('a running block shows its latest three calls and counts the rest', () {
    final fold = blockFold(find, const []) as FoldWork;
    expect(
      [for (final line in fold.lines) said(line)],
      [
        'Agent(Read the transport tests)',
        'Read(src/session/session.ts) failed',
        'Write(notes/routing.md)',
      ],
    );
    expect(fold.more, 2);
    // Its words are not a tool use; its own subagent is one.
    expect(toolUses(find), 5);
  });

  test('a block with no call yet is starting, whatever it has said', () {
    expect(
      blockFold(
        Subagent('a', entries: [AssistantEntry(_t, TextRun.empty.plus('Hm.'))]),
        const [],
      ),
      isA<FoldStarting>(),
    );
    expect(rowLine(const Subagent('a'), const []), isA<RowStarting>());
  });

  test('an ended block says how, with its tool uses and time', () {
    FoldEnded ended(SubagentState state, [num? endedAt]) =>
        blockFold(
              Subagent(
                'a',
                state: state,
                startedAt: 1000,
                endedAt: endedAt,
                entries: [tool('c', 'Read a.ts', 'completed')],
              ),
              const [],
            )
            as FoldEnded;
    expect(
      (
        ended(SubagentState.completed, 42500).text,
        ended(SubagentState.completed, 42500).failed,
      ),
      ('Done (1 tool use · 41s)', false),
    );
    expect(
      ended(SubagentState.failed, 126000).text,
      'Failed (1 tool use · 2m 5s)',
    );
    expect(ended(SubagentState.failed, 126000).failed, isTrue);
    // A past that kept no time has none, rather than one made up.
    expect(ended(SubagentState.cancelled).text, 'Cancelled (1 tool use)');
    expect(endedLine(find), isNull);
  });

  test('the marker takes a call tone, and every end its word', () {
    expect(
      [for (final s in SubagentState.values) agentTone(s)],
      [
        Tone.running,
        Tone.done,
        Tone.failed,
        Tone.pending,
        Tone.failed,
        Tone.pending,
        Tone.pending,
      ],
    );
    expect(
      [for (final s in SubagentState.values) endingOf(s)?.word],
      [
        null,
        'Done',
        'Failed',
        'Cancelled',
        'Disconnected',
        'Ended',
        'Untracked',
      ],
    );
    expect(
      endNote(const Subagent('a', state: SubagentState.ended))?.text,
      'The agent did not say how it ended.',
    );
    expect(
      endNote(const Subagent('a', state: SubagentState.failed, error: 'Boom')),
      (text: 'Boom', failed: true),
    );
  });

  test('the call a permission waits on is marked, and is the row line ahead '
      'of any later', () {
    const wait = PermissionWait('p', toolCallId: 'c2', subagentId: 'a1');
    final row = rowLine(find, const [wait]) as RowCall;
    expect(said(row.line), 'Read(src/acp/connection.ts) waiting');
    final latest = rowLine(find, const []) as RowCall;
    expect(said(latest.line), 'Write(notes/routing.md)');
    // Another subagent's wait marks nothing here.
    const other = PermissionWait('p', toolCallId: 'c2', subagentId: 'zz');
    expect(
      said((rowLine(find, const [other]) as RowCall).line),
      'Write(notes/routing.md)',
    );
  });

  test('the group header runs, then finishes, or says what went wrong', () {
    const done = Subagent('x', state: SubagentState.completed);
    Subagent at(SubagentState state) => Subagent('s', state: state);
    expect(groupHeader([find, done]), (
      text: 'Running 2 agents…',
      tone: Tone.running,
    ));
    expect(groupHeader([done, done, done]), (
      text: '3 agents finished',
      tone: Tone.done,
    ));
    expect(
      groupHeader([at(SubagentState.cancelled), at(SubagentState.failed)]),
      (text: '2 agents ended · 1 failed, 1 cancelled', tone: Tone.failed),
    );
    expect(groupHeader([done, at(SubagentState.cancelled)]), (
      text: '2 agents ended · 1 cancelled',
      tone: Tone.pending,
    ));
    expect(
      groupHeader([
        at(SubagentState.cancelled),
        at(SubagentState.ended),
        at(SubagentState.untracked),
        at(SubagentState.disconnected),
        at(SubagentState.failed),
      ]).text,
      '5 agents ended · 1 failed, 1 disconnected, 1 untracked, 1 ended, 1 cancelled',
    );
  });

  test('a row that does not fit wraps after a ` · `, inside its title at its '
      'spaces where it must, and drops nothing', () {
    final timed = Subagent(
      draw.id,
      title: draw.title,
      state: SubagentState.completed,
      startedAt: 0,
      endedAt: 28000,
      entries: [tool('c', 'Read a.ts'), tool('d', 'Read b.ts')],
    );
    expect(groupRow(timed, 120), [
      [
        const RowRun('Agent', RunStyle.bold),
        RowRun('(${draw.title})', RunStyle.plain),
        const RowRun(' · 2 tool uses · 28s', RunStyle.dim, counts: true),
      ],
    ]);
    expect(lines(timed, 66), ['Agent(${draw.title})', '· 2 tool uses · 28s']);
    expect(lines(timed, 70), ['Agent(${draw.title}) ·', '2 tool uses · 28s']);
    expect(lines(timed, 30), [
      'Agent(Find where tool calls',
      'are drawn on screen and how',
      'they fold) · 2 tool uses · 28s',
    ]);
    expect(lines(timed, 12), [
      'Agent(Find',
      'where tool',
      'calls are',
      'drawn on',
      'screen and',
      'how they',
      'fold) ·',
      '2 tool uses',
      '· 28s',
    ]);
    expect(lines(const Subagent('a'), 20), ['Agent · 0 tool uses']);
  });

  test("a child's permission names the way down to it, whole", () {
    const child = Subagent('a1', title: 'Find the session layer');
    const grandchild = Subagent('a3', title: 'Read the transport tests');
    expect(askerRow(const []), isEmpty);
    expect(askerRow(const [child]), [
      (text: 'Agent', bold: true),
      (text: '(Find the session layer)', bold: false),
      (text: ' asks', bold: false),
    ]);
    expect(
      askerRow(const [child, grandchild]).map((p) => p.text).join(),
      'Agent(Find the session layer) › Agent(Read the transport tests) asks',
    );
  });

  test("a subagent's work keeps its plan where it first came, and groups its "
      'own subagents', () {
    final subagent = Subagent(
      'a',
      entries: [
        tool('c1', 'Read a.ts'),
        entryOf(const Subagent('g1')),
        entryOf(const Subagent('g2')),
        tool('c2', 'Read b.ts'),
      ],
      plan: const [],
      planAt: 1,
    );
    expect(
      [for (final item in workOf(subagent)) item.runtimeType.toString()],
      ['WorkEntry', 'WorkAgents', 'WorkEntry'],
    );
  });

  test('the status line counts the subagents still at work', () {
    expect(stillRunning(0), isNull);
    expect(stillRunning(1), '1 agent still running');
    expect(stillRunning(3), '3 agents still running');
  });

  test("a call's references in the order sent, each once, an unknown one "
      'left out', () {
    final entries = [entryOf(find), entryOf(draw)];
    expect(
      [
        for (final s in linkedSubagents([
          {'type': 'session', 'sessionId': 'a2'},
          {'type': 'session', 'sessionId': 'a3'},
          {'type': 'session', 'sessionId': 'a2'},
          {'type': 'session', 'sessionId': 'nobody'},
          {'type': 'content'},
        ], entries))
          s.id,
      ],
      ['a2', 'a3'],
    );
  });
}
