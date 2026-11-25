// A task agent's block in its parent's transcript, as the original's
// ui/transcript/agents/subagents.ts and Agents.tsx draw it and its
// tests/ui/app/tasks_test.ts and Tasks_test.tsx check it: the captured
// `task` and `tasktwo` blocks, cell for cell with their styles, from
// `bun dev chord --fake --qa` in ../chord (docs/design/evidence/CTUI-35/
// tasks/); the parts a task never reported left out; the effort a refused
// one leaves it on; its stop line.
import 'package:characters/characters.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/conversation.dart'
    show ConversationEvent, Transcribed;
import 'package:chord/session/elicitations.dart'
    show ElicitationReply, PendingElicitation;
import 'package:chord/session/permissions.dart' show PendingPermission;
import 'package:chord/session/tasks.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/theme/theme.dart';
import 'package:chord/ui/transcript/agents/agents.dart';
import 'package:chord/ui/transcript/agents/subagents.dart';
import 'package:chord/ui/transcript/tools/tools.dart' show Headline;
import 'package:chord/ui/transcript/transcript.dart' show TranscriptEntry;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const _fix = TaskStart(
  id: 'task-1',
  name: 'Fix the tokenizer',
  runtime: 'fake',
  prompt: 'taskchild',
  model: 'fake-small',
);

/// [update] for the task [id], at [at].
UpdateAction _of(String id, Map<String, Object?> update, {num? at}) =>
    UpdateAction(
      't1',
      acp.SessionUpdate.fromJson(update),
      at: at,
      subagentId: id,
    );

UpdateAction _call(String id, String call, String title, String kind) =>
    _of(id, {
      'sessionUpdate': 'tool_call',
      'toolCallId': call,
      'title': title,
      'kind': kind,
      'status': 'in_progress',
    });

UpdateAction _done(String id, String call) => _of(id, {
  'sessionUpdate': 'tool_call_update',
  'toolCallId': call,
  'status': 'completed',
});

UpdateAction _task(
  SubagentState state, {
  String id = 'task-1',
  TaskStart? start,
  TaskSpent? spent,
  TaskStop? stoppedWith,
  num? at,
}) => UpdateAction(
  't1',
  taskUpdate(id, state, task: start, spent: spent, stoppedWith: stoppedWith),
  at: at,
);

Transcript _fold(List<TranscriptAction> actions) =>
    actions.fold(Transcript.empty, reduceTranscript);

/// The `task` scenario at its permission: the task's search and read done,
/// its edit waiting on the person.
List<TranscriptAction> _asking() => [
  PromptAction('t1', 'task', 0),
  _task(SubagentState.running, start: _fix, at: 1000),
  _call('task-1', 'search-1', 'Search tokenize in src/parse', 'search'),
  _done('task-1', 'search-1'),
  _call('task-1', 'read-1', 'Read src/parse/tokenize.ts', 'read'),
  _done('task-1', 'read-1'),
  _of('task-1', {
    'sessionUpdate': 'tool_call',
    'toolCallId': 'edit-1',
    'title': 'Edit src/parse/tokenize.ts',
    'kind': 'edit',
    'status': 'pending',
  }),
  PermissionRequestedAction(
    't1',
    PermissionWait(
      'perm-1',
      toolCallId: 'edit-1',
      title: 'Edit src/parse/tokenize.ts',
      kind: 'edit',
      subagentId: 'task-1',
      options: [
        acp.PermissionOption.fromJson({
          'optionId': 'allow',
          'name': 'Allow',
          'kind': 'allow_once',
        }),
        acp.PermissionOption.fromJson({
          'optionId': 'deny',
          'name': 'Deny',
          'kind': 'reject_once',
        }),
      ],
    ),
    at: 2000,
  ),
];

/// The `task` scenario once the task has reported: five tool uses, what its
/// agent said it spent, twelve seconds.
List<TranscriptAction> _ended({TaskSpent? spent}) => [
  PromptAction('t1', 'task', 0),
  _task(SubagentState.running, start: _fix, at: 1000),
  for (final (n, kind) in const [
    (1, 'search'),
    (2, 'read'),
    (3, 'edit'),
    (4, 'other'),
    (5, 'other'),
  ]) ...[
    _call('task-1', 'call-$n', 'Step $n', kind),
    _done('task-1', 'call-$n'),
  ],
  _task(
    SubagentState.completed,
    spent:
        spent ??
        const TaskSpent(
          tokens: {'totalTokens': 2000},
          cost: (amount: 0.0125, currency: 'USD'),
        ),
    at: 13000,
  ),
];

/// `tasktwo`: two tasks spawned back to back, neither at work yet.
List<TranscriptAction> _two() => [
  PromptAction('t1', 'tasktwo', 0),
  _task(
    SubagentState.running,
    id: 'build',
    start: const TaskStart(
      id: 'build',
      name: 'Watch the build',
      runtime: 'fake',
      prompt: 'taskwait',
    ),
  ),
  _task(
    SubagentState.running,
    id: 'deploy',
    start: const TaskStart(
      id: 'deploy',
      name: 'Watch the deploy',
      runtime: 'fake',
      prompt: 'taskwait',
    ),
  ),
];

/// The first group in [state], as the transcript mounts it.
List<Subagent> _group(Transcript state) {
  final at = state.entries.indexWhere((entry) => entry is SubagentEntry);
  return agentGroup(state.entries, at)!;
}

/// [state]'s first group drawn as the window's transcript body insets it,
/// so its rows read as the original's captures do.
Future<void> _draw(WidgetTester t, Size size, Transcript state) => t.pumpWidget(
  Theme(
    data: themeData('dark'),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Align(
        alignment: Alignment.topLeft,
        child: Agents(_group(state), turn: state.turn, open: false),
      ),
    ),
  ),
  size: size,
);

/// The drawn rows, from the block's first, without the gap above it.
List<String> _rows(WidgetTester t) => [
  for (final row in t.screen.lines.skipWhile((row) => row.trim().isEmpty))
    row.trimRight(),
]..removeWhere((row) => row.isEmpty);

/// How a cell is drawn, as the captures give it.
enum _Look { plain, bold, dim }

/// Row [y]'s cells from [x], run by run, each its text and look.
void _expectRuns(WidgetTester t, int y, int x, List<(String, _Look)> runs) {
  final s = t.screen;
  for (final (text, look) in runs) {
    for (final char in text.characters) {
      final style = s.styleAt(x, y);
      final reason = '"$char" at $x in "${s.lines[y]}"';
      expect(s.lines[y].characters.elementAt(x), char, reason: reason);
      expect(style.isBold, look == _Look.bold, reason: '$reason bold');
      expect(style.isDim, look == _Look.dim, reason: '$reason dim');
      x += cellWidth(char);
    }
  }
}

/// The screen row whose text starts with [start] after its margin.
int _rowOf(WidgetTester t, String start) {
  final at = t.screen.lines.indexWhere(
    (row) => row.trimLeft().startsWith(start),
  );
  expect(at, greaterThanOrEqualTo(0), reason: t.screen.text);
  return at;
}

final class _Parent implements TaskParent {
  var state = _fold([PromptAction('t1', 'go', 0)]);

  @override
  void relay(ConversationEvent event) {
    if (event is Transcribed) state = reduceTranscript(state, event.action);
  }

  @override
  void deliver(MessageFrom from, String text) {}

  @override
  void ahead(MessageFrom from, String text) {}

  @override
  void ended() {}
}

final class _Session implements TaskSession {
  @override
  void start() {}

  @override
  bool send(String text) => true;

  @override
  void interrupt() {}

  @override
  void choose(String id, String optionId) {}

  @override
  void reject(String id) {}

  @override
  void answer(String id, ElicitationReply reply) {}

  @override
  Future<void> close() async {}

  @override
  PendingPermission? permissionRequest(String id) => null;

  @override
  PendingElicitation? elicitationRequest(String id) => null;
}

void main() {
  _testerTaskGroupEdges();
  group('the headline', () {
    test("a task's says its runtime, model and effort after its title, "
        'dim; the box row its runtime alone', () {
      const subagent = Subagent(
        'task-1',
        title: 'Fix the tokenizer',
        task: TaskInfo(
          name: 'Fix the tokenizer',
          runtime: 'codex',
          model: 'gpt-5.3-codex',
          effort: 'high',
        ),
      );
      final full = agentHeadline(subagent);
      expect(
        (full.name, full.arg, full.note),
        ('Agent', 'Fix the tokenizer', ' · codex · gpt-5.3-codex · high'),
      );
      final short = agentHeadline(subagent, full: false);
      expect(
        (short.name, short.arg, short.note),
        ('Agent', 'Fix the tokenizer', ' · codex'),
      );
      // The runtime's own subagents say none.
      expect(agentHeadline(const Subagent('own', title: 'Look')).note, isNull);
    });

    test('a part the task never reported is left out, not shown empty', () {
      Headline of(TaskInfo task) =>
          agentHeadline(Subagent('t', title: 'Watch the build', task: task));
      expect(
        of(const TaskInfo(name: 'Watch the build', runtime: 'fake')).note,
        ' · fake',
      );
      expect(
        of(
          const TaskInfo(
            name: 'Watch the build',
            runtime: 'fake',
            effort: 'low',
          ),
        ).note,
        ' · fake · low',
      );
      expect(
        of(
          const TaskInfo(
            name: 'Watch the build',
            runtime: 'fake',
            model: '',
            effort: '',
          ),
        ).note,
        ' · fake',
      );
    });
  });

  group('the ended line', () {
    test('says its tool uses, tokens, cost and time', () {
      final ended = endedLine(_group(_fold(_ended())).single)!;
      expect(ended.text, r'Done (5 tool uses · 2.0k tokens · $0.0125 · 12s)');
      expect(ended.failed, isFalse);
    });

    test("chord's estimate is marked; what was not reported is left out", () {
      String said(TaskSpent? spent) =>
          endedLine(_group(_fold(_ended(spent: spent))).single)!.text;
      expect(
        said(
          const TaskSpent(
            tokens: {'inputTokens': 800, 'outputTokens': 50},
            cost: (amount: 0.0047, currency: 'USD'),
            estimated: true,
          ),
        ),
        r'Done (5 tool uses · 850 tokens · ~$0.0047 · 12s)',
      );
      expect(
        said(const TaskSpent(tokens: {'totalTokens': 1240000})),
        'Done (5 tool uses · 1.2M tokens · 12s)',
      );
      expect(
        said(const TaskSpent(cost: (amount: 0.0125, currency: 'USD'))),
        r'Done (5 tool uses · $0.0125 · 12s)',
      );
      // An ending update with no spend leaves the counts chord has.
      expect(said(const TaskSpent()), 'Done (5 tool uses · 12s)');
    });

    test("a task whose record has gone says only how long", () {
      final state = _fold([
        PromptAction('t1', 'go', 0),
        _task(SubagentState.running, start: _fix, at: 1000),
        UpdateAction(
          't1',
          acp.SessionUpdate.fromJson({
            'sessionUpdate': 'subagent_update',
            'sessionId': 'task-1',
            'state': {'state': 'completed'},
            '_meta': {
              'chord/task': {
                'name': 'Fix the tokenizer',
                'runtime': 'fake',
                'workLost': true,
              },
            },
          }),
          at: 4000,
        ),
      ]);
      expect(endedLine(_group(state).single)!.text, 'Done (3s)');
    });
  });

  test("tasks and the runtime's own subagents never share a group", () {
    const own = SubagentEntry('t1', Subagent('own', title: 'Look'));
    SubagentEntry task(String id) => SubagentEntry(
      't1',
      Subagent(
        id,
        title: id,
        task: TaskInfo(name: id, runtime: 'fake'),
      ),
    );
    final entries = [task('a'), task('b'), own];
    expect(agentGroup(entries, 0)!.map((agent) => agent.id), ['a', 'b']);
    expect(agentGroup(entries, 1), isEmpty);
    expect(agentGroup(entries, 2)!.map((agent) => agent.id), ['own']);
    expect(agentGroup([own, task('a')], 1)!.map((agent) => agent.id), ['a']);
  });

  test("a group row says the task's runtime dim before chord's counts", () {
    final [build, _] = _group(_fold(_two()));
    expect(groupRow(build, 115), [
      [
        const RowRun('Agent', RunStyle.bold),
        const RowRun('(Watch the build)', RunStyle.plain),
        const RowRun(' · fake', RunStyle.dim),
        const RowRun(' · 0 tool uses', RunStyle.dim, counts: true),
      ],
    ]);
    // Narrow, it wraps after a ` · `, nothing cut.
    expect(
      [
        for (final row in groupRow(build, 26))
          row.map((run) => run.text).join(),
      ],
      ['Agent(Watch the build) ·', 'fake · 0 tool uses'],
    );
  });

  test("a task's box names it by its runtime, not its model", () {
    final state = _fold(_asking());
    expect(
      askerRow(_group(state)).map((piece) => piece.text).join(),
      'Agent(Fix the tokenizer) · fake asks',
    );
    expect(
      [for (final piece in askerRow(_group(state))) piece.bold],
      [true, false, false, false],
    );
  });

  test("a refused effort: the block names the effort the runtime's own "
      'left it on', () {
    final parent = _Parent();
    final task = TaskAgent(
      const TaskStart(
        id: 'task-1',
        name: 'Tune the parser',
        runtime: 'fake',
        prompt: 'x',
        model: 'fake-small',
      ),
      parent,
      () => 1000,
    )..begin(_Session());
    final before = agentHeadline(_group(parent.state).single);
    expect(before.note, ' · fake · fake-small');
    // max was refused; the agent says it is on medium, its own.
    task.startedOn('medium');
    final after = agentHeadline(_group(parent.state).single);
    expect(
      '${after.name}(${after.arg})${after.note}',
      'Agent(Tune the parser) · fake · fake-small · medium',
    );
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      testWidgets('the captured `task` block: runtime and model after its '
          'title, its work, the edit waiting', (t) async {
        await _draw(t, size, _fold(_asking()));
        expect(_rows(t), [
          ' ⏺ Agent(Fix the tokenizer) · fake · fake-small',
          '   ⎿  Search(tokenize in src/parse)',
          '      Read(src/parse/tokenize.ts)',
          '      Edit(src/parse/tokenize.ts) · waiting for permission',
        ]);
        final y = _rowOf(t, '⏺ Agent');
        _expectRuns(t, y, 3, [
          ('Agent', _Look.bold),
          ('(Fix the tokenizer)', _Look.plain),
          (' · fake · fake-small', _Look.dim),
        ]);
        _expectRuns(t, y + 1, 3, [
          ('⎿', _Look.dim),
          ('  ', _Look.plain),
          ('Search', _Look.bold),
          ('(tokenize in src/parse)', _Look.plain),
        ]);
        _expectRuns(t, y + 2, 6, [
          ('Read', _Look.bold),
          ('(src/parse/tokenize.ts)', _Look.plain),
        ]);
        _expectRuns(t, y + 3, 6, [
          ('Edit', _Look.bold),
          ('(src/parse/tokenize.ts)', _Look.plain),
          (' · waiting for permission', _Look.dim),
        ]);
      });

      testWidgets("the captured `task` block's end: its counts, tokens, "
          'cost and time, dim, the marker done', (t) async {
        await _draw(t, size, _fold(_ended()));
        expect(_rows(t), [
          ' ⏺ Agent(Fix the tokenizer) · fake · fake-small',
          r'   ⎿  Done (5 tool uses · 2.0k tokens · $0.0125 · 12s)',
        ]);
        final y = _rowOf(t, '⏺ Agent');
        expect(t.screen.styleAt(1, y).fg, themeData('dark').success.fg);
        _expectRuns(t, y + 1, 3, [
          ('⎿', _Look.dim),
          ('  ', _Look.plain),
          (r'Done (5 tool uses · 2.0k tokens · $0.0125 · 12s)', _Look.dim),
        ]);
      });

      testWidgets('the captured `tasktwo` group: each row its runtime, '
          'the tree behind │', (t) async {
        await _draw(t, size, _fold(_two()));
        expect(_rows(t), [
          ' ⏺ Running 2 agents… (ctrl+o to expand)',
          '   ├─ Agent(Watch the build) · fake · 0 tool uses',
          '   │  ⎿  Initializing…',
          '   └─ Agent(Watch the deploy) · fake · 0 tool uses',
          '      ⎿  Initializing…',
        ]);
        final y = _rowOf(t, '⏺ Running');
        _expectRuns(t, y, 3, [
          ('Running 2 agents…', _Look.plain),
          (' (ctrl+o to expand)', _Look.dim),
        ]);
        for (final (row, glyph, name) in const [
          (1, '├─', '(Watch the build)'),
          (3, '└─', '(Watch the deploy)'),
        ]) {
          _expectRuns(t, y + row, 3, [
            (glyph, _Look.dim),
            (' ', _Look.plain),
            ('Agent', _Look.bold),
            (name, _Look.plain),
            (' · fake · 0 tool uses', _Look.dim),
          ]);
        }
        // The tree's rail, in the dim border colour, as the original's
        // left border is drawn.
        final rail = t.screen.styleAt(3, y + 2);
        expect(t.screen.lines[y + 2].characters.elementAt(3), '│');
        expect(rail.fg, themeData('dark').border.fg);
        _expectRuns(t, y + 2, 6, [
          ('⎿', _Look.dim),
          ('  ', _Look.plain),
          ('Initializing…', _Look.dim),
        ]);
      });

      testWidgets('a group row too wide wraps behind the tree, nothing '
          'cut', (t) async {
        final long = _fold([
          PromptAction('t1', 'tasktwo', 0),
          for (final id in ['a', 'b'])
            _task(
              SubagentState.running,
              id: id,
              start: TaskStart(
                id: id,
                name: 'Watch the build and the deploy and the docs site $id',
                runtime: 'fake',
                prompt: 'taskwait',
                model: 'fake-small-with-a-long-name',
              ),
            ),
        ]);
        await _draw(t, size, long);
        final rows = _rows(t);
        final first = rows.indexWhere((row) => row.contains('├─'));
        final second = rows.indexWhere((row) => row.contains('└─'));
        // Each line after a row's first stands behind the tree's `│`.
        for (var at = first + 1; at < second; at++) {
          expect(rows[at].substring(0, 4), '   │', reason: rows[at]);
        }
        final said = rows.join(' ').replaceAll(RegExp(r'[│├└─⎿\s]+'), ' ');
        expect(said, contains('fake-small-with-a-long-name'));
        expect(said, contains('0 tool uses'));
      });
    });
  }

  group('the stop line', () {
    Transcript stopped(TaskStop? by) => _fold([
      PromptAction('t1', 'go', 0),
      _task(SubagentState.running, start: _fix, at: 2),
      const ResultAction('t1', TurnAnswered('end_turn')),
      _task(SubagentState.cancelled, stoppedWith: by, at: 3002),
    ]);

    test('a task stopped after its turn gets a task line, saying who '
        'stopped it', () {
      for (final (by, person, esc, agent) in [
        (TaskStop.x, true, false, null),
        (TaskStop.esc, false, true, null),
        (const TaskStop.agent('main'), false, false, 'main'),
        (null, false, false, null),
      ]) {
        final line = stopped(by).entries.whereType<ItemEndedEntry>().single;
        expect(
          (
            line.item,
            line.name,
            line.end,
            line.byPerson,
            line.byEsc,
            line.byAgent,
            line.startedAt,
            line.endedAt,
          ),
          (
            ItemKind.task,
            'Fix the tokenizer',
            ItemEnd.stopped,
            person,
            esc,
            agent,
            2,
            3002,
          ),
          reason: '$by',
        );
      }
    });

    test('one stopped while its turn runs is said by its own block', () {
      final state = _fold([
        PromptAction('t1', 'go', 0),
        _task(SubagentState.running, start: _fix),
        _task(SubagentState.cancelled, stoppedWith: TaskStop.esc),
      ]);
      expect(state.entries.whereType<ItemEndedEntry>(), isEmpty);
    });

    testWidgets('reads `■ <name> · task · stopped with esc after 3s`, '
        'dim', (t) async {
      Future<String> drawn(TaskStop? by) async {
        await t.pumpWidget(
          Theme(
            data: themeData('dark'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: TranscriptEntry(
                stopped(by).entries.whereType<ItemEndedEntry>().single,
              ),
            ),
          ),
          size: const Size(120, 40),
        );
        return t.screen.lines.firstWhere((row) => row.contains('■')).trim();
      }

      expect(
        await drawn(TaskStop.x),
        '■ Fix the tokenizer · task · stopped with x after 3s',
      );
      expect(
        await drawn(TaskStop.esc),
        '■ Fix the tokenizer · task · stopped with esc after 3s',
      );
      expect(
        await drawn(const TaskStop.agent('main')),
        '■ Fix the tokenizer · task · stopped by main after 3s',
      );
      expect(
        await drawn(null),
        '■ Fix the tokenizer · task · stopped after 3s',
      );
      final y = _rowOf(t, '■');
      final x = t.screen.lines[y].indexOf('stopped');
      expect(t.screen.styleAt(x, y).isDim, isTrue);
    });
  });

  testWidgets('a task whose record has gone says so where its work would '
      'be, opened', (t) async {
    const lost = Subagent(
      'task-1',
      title: 'Fix the tokenizer',
      state: SubagentState.completed,
      task: TaskInfo(
        name: 'Fix the tokenizer',
        runtime: 'fake',
        workLost: true,
      ),
    );
    await t.pumpWidget(
      Theme(
        data: themeData('dark'),
        child: Agents(const [lost], turn: const Idle(), open: true),
      ),
      size: const Size(120, 40),
    );
    expect(t.screen.text, contains(workLostNote));
  });
}

void _testerTaskGroupEdges() {
  group('CTUI-35 tester: task group cell edges', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'Unicode task groups survive zero, one and narrow room then recover at $size',
        (t) async {
          final transcript = _fold([
            PromptAction('t1', 'tasktwo', 0),
            for (final id in ['a', 'b'])
              _task(
                SubagentState.running,
                id: id,
                start: TaskStart(
                  id: id,
                  name: '界🙂e\u0301 $id',
                  runtime: 'fake',
                  prompt: 'job',
                  model: 'long-model-name',
                  effort: 'high',
                ),
              ),
          ]);
          for (final small in [
            const Size(0, 0),
            const Size(1, 1),
            const Size(12, 24),
          ]) {
            await _draw(t, small, transcript);
            expect(t.screen.text, isNot(contains('\x1b')));
          }
          await _draw(t, size, transcript);
          expect(t.screen, shows('界🙂e\u0301 a'));
          expect(t.screen, shows('界🙂e\u0301 b'));
          expect(t.screen, shows('long-model-name'));
          expect(t.screen, shows(' · high · '));
          expect(t.screen, shows('Running 2 agents'));
        },
      );
    }
  });
}
