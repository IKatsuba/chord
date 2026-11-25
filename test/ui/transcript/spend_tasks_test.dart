// Task agents in the window's spend and `/cost`'s table: the original's
// tests/ui/transcript/spend_test.ts and spend_table_test.ts cases for
// tasks, and the table `bun dev chord --fake --qa` showed in ../chord after
// `task`, `tasktwo` and `/cost`.
import 'package:chord/session/tasks.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/turn_costs.dart';
import 'package:chord/session/usage.dart';
import 'package:chord/session/waits.dart';
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/transcript/spend.dart';
import 'package:chord/ui/transcript/spend_table.dart';
import 'package:test/test.dart';

Cost _usd(num amount) => (amount: amount, currency: 'USD');

/// A session's spend: one turn of [amount] and [tokens].
Spent? _spent(num amount, [num? tokens]) => addTurn(
  null,
  't',
  tokens == null ? const {} : {'totalTokens': tokens},
  SpentTurn(TurnCost(cost: _usd(amount))),
);

/// The table's lines as text.
List<String> _lines(List<SpendPart> parts, int width) => [
  for (final row in spendTable(parts, width)) row.text,
];

/// A task's block in its parent's transcript, as chord's updates leave it.
List<TranscriptAction> _task(
  String id,
  String name, {
  TaskSpent? spent,
  bool ended = false,
}) => [
  UpdateAction(
    't',
    taskUpdate(
      id,
      SubagentState.running,
      task: TaskStart(id: id, name: name, runtime: 'fake', prompt: 'x'),
    ),
  ),
  if (ended)
    UpdateAction('t', taskUpdate(id, SubagentState.completed, spent: spent)),
];

/// main's transcript after `task` and `tasktwo`: one task reported, two at
/// work.
Transcript _transcript() => [
  PromptAction('t', 'task', 0),
  ..._task(
    'fix',
    'Fix the tokenizer',
    ended: true,
    spent: const TaskSpent(
      tokens: {'totalTokens': 2000},
      cost: (amount: 0.0125, currency: 'USD'),
    ),
  ),
  ..._task('build', 'Watch the build'),
  ..._task('deploy', 'Watch the deploy'),
].fold(Transcript.empty, reduceTranscript);

/// Each part by its name and own cost, with what is under it.
List<Object?> _shape(List<SpendPart> parts) => [
  for (final part in parts)
    [
      part.name,
      part.figure?.cost?.amount,
      if (part.parts.isNotEmpty) _shape(part.parts),
    ],
];

/// The window: main on [agent] at [key], and [children].
WindowAgents<String> _tab(
  int key,
  String agent, [
  List<Child<String>> children = const [],
]) => WindowAgents(
  main: MainAgent(key, agent, agent, const AgentWait()),
  children: children,
  picked: key,
  opened: children.length,
  nextKey: key + children.length + 1,
);

void main() {
  test("a task's figure is what its block keeps", () {
    final figure = taskFigure(
      const TaskSpent(
        tokens: {'inputTokens': 600, 'outputTokens': 250},
        cost: (amount: 0.0125, currency: 'USD'),
        estimated: true,
      ),
    )!;
    expect(
      (figure.cost, figure.estimated, figure.tokens),
      (_usd(0.0125), Estimated.all, 850),
    );
    expect(taskFigure(null), isNull);
    expect(taskFigure(const TaskSpent()), isNull);
  });

  test("a session's parts: its own, then each task it started, one at "
      'work running, one done ended', () {
    final parts = sessionParts(
      'main',
      SpendKind.main,
      SpendSession(spent: _spent(0.05, 8000), transcript: _transcript()),
      agent: 'fake',
    );
    expect(
      [
        for (final part in parts)
          (
            part.name,
            part.kind,
            part.figure?.cost?.amount,
            part.running,
            part.ended,
          ),
      ],
      [
        ('main', SpendKind.main, 0.05, false, false),
        ('Fix the tokenizer', SpendKind.task, 0.0125, false, true),
        ('Watch the build', SpendKind.task, null, true, false),
        ('Watch the deploy', SpendKind.task, null, true, false),
      ],
    );
  });

  test('a sum counts a task once it has ended and not while it works', () {
    final summed = sum(const [
      SpendPart(
        name: 'main',
        kind: SpendKind.main,
        figure: Figure(cost: (amount: 0.025, currency: 'USD'), tokens: 4000),
        parts: [
          SpendPart(
            name: 'Fix the tokenizer',
            kind: SpendKind.task,
            ended: true,
            figure: Figure(
              cost: (amount: 0.0125, currency: 'USD'),
              tokens: 2000,
            ),
          ),
          // At work: its figure comes when it ends, so it is not counted.
          SpendPart(
            name: 'Watch the build',
            kind: SpendKind.task,
            running: true,
          ),
          // Ended with nothing reported: named, not read as zero.
          SpendPart(name: 'Quiet', kind: SpendKind.task, ended: true),
        ],
      ),
    ]);
    expect(summed.cost, closeTo(0.0375, 1e-9));
    expect(summed.tokens, 6000);
    expect(summed.missing, ['Quiet']);
  });

  test("the window's spend: main's tasks under it, a closed agent's kept "
      'with it', () {
    final spend = windowSpend(
      _tab(1, 'fake'),
      {1: SpendSession(spent: _spent(0.05), transcript: _transcript())},
      [
        KeptSpend(
          part: SpendPart(
            name: 'docs',
            kind: SpendKind.agent,
            ended: true,
            figure: Figure(cost: _usd(0.02)),
            parts: taskParts([
              const Subagent(
                'index',
                state: SubagentState.completed,
                task: TaskInfo(
                  name: 'Index',
                  runtime: 'fake',
                  spent: TaskSpent(cost: (amount: 0.03, currency: 'USD')),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
    expect(_shape(spend), [
      [
        'main',
        0.05,
        [
          ['Fix the tokenizer', 0.0125],
          ['Watch the build', null],
          ['Watch the deploy', null],
        ],
      ],
      [
        'docs',
        0.02,
        [
          ['Index', 0.03],
        ],
      ],
    ]);
  });

  test('the table is for a window of more than one session, a task '
      'counted', () {
    const main = SpendPart(name: 'main', kind: SpendKind.main, agent: 'fake');
    expect(manySessions(const [main]), isFalse);
    expect(
      manySessions(const [
        SpendPart(
          name: 'main',
          kind: SpendKind.main,
          parts: [
            SpendPart(name: 'Fix it', kind: SpendKind.task, running: true),
          ],
        ),
      ]),
      isTrue,
    );
    expect(
      manySessions(const [
        main,
        SpendPart(name: 'Fix it', kind: SpendKind.task, running: true),
      ]),
      isTrue,
    );
  });

  test("/cost's table after `task` and `tasktwo`, as the original "
      'captured it: the tasks under main, the running ones counted when '
      'they end', () {
    final spend = windowSpend(_tab(1, 'fake'), {
      1: SpendSession(spent: _spent(0.05, 8000), transcript: _transcript()),
    }, const []);
    expect(_lines(spend, 112), [
      'This session            Cost  Tokens',
      r'main                 $0.0500   8,000',
      r'  Fix the tokenizer  $0.0125   2,000  task agent, ended',
      '  Watch the build          —       —  task agent, running: counted '
          'when it ends',
      '  Watch the deploy         —       —  task agent, running: counted '
          'when it ends',
      r'Total                $0.0625  10,000  2 running',
    ]);
    // At 80 columns, `tasktwo` alone: the note wraps in its cell. The
    // window gives the table its columns less eight.
    final two = windowSpend(_tab(1, 'fake'), {
      1: SpendSession(
        spent: _spent(0.0125, 2000),
        transcript: [
          PromptAction('t', 'tasktwo', 0),
          ..._task('build', 'Watch the build'),
          ..._task('deploy', 'Watch the deploy'),
        ].fold(Transcript.empty, reduceTranscript),
      ),
    }, const []);
    expect(_lines(two, 72), [
      'This session           Cost  Tokens',
      r'main                $0.0125   2,000',
      '  Watch the build         —       —  task agent, running: counted when',
      '                                     it ends',
      '  Watch the deploy        —       —  task agent, running: counted when',
      '                                     it ends',
      r'Total               $0.0125   2,000  2 running',
    ]);
  });

  test("the original's window table: a task beside main, then an agent", () {
    const window = [
      SpendPart(
        name: 'main',
        kind: SpendKind.main,
        agent: 'fake',
        figure: Figure(cost: (amount: 0.025, currency: 'USD'), tokens: 4000),
      ),
      SpendPart(
        name: 'Fix the tokenizer',
        kind: SpendKind.task,
        ended: true,
        figure: Figure(cost: (amount: 0.0125, currency: 'USD'), tokens: 2000),
      ),
      SpendPart(
        name: 'fake',
        kind: SpendKind.agent,
        runtime: 'fake',
        figure: Figure(cost: (amount: 0.0125, currency: 'USD'), tokens: 2000),
      ),
    ];
    expect(_lines(window, 114), [
      'This session          Cost  Tokens',
      r'main               $0.0250   4,000',
      r'Fix the tokenizer  $0.0125   2,000  task agent, ended',
      r'fake               $0.0125   2,000  agent',
      r'Total              $0.0500   8,000',
    ]);
  });

  test("each task sits under the session that started it, a closed agent's "
      "and a cleared session's too, every row its own spend", () {
    const window = [
      SpendPart(
        name: 'main',
        kind: SpendKind.main,
        agent: 'fake',
        figure: Figure(cost: (amount: 0.01, currency: 'USD')),
        parts: [
          SpendPart(
            name: 'Fix it',
            kind: SpendKind.task,
            ended: true,
            figure: Figure(cost: (amount: 0.005, currency: 'USD')),
          ),
        ],
      ),
      SpendPart(
        name: 'main',
        kind: SpendKind.main,
        ended: true,
        figure: Figure(cost: (amount: 0.005, currency: 'USD')),
        parts: [
          SpendPart(
            name: 'Watch the build',
            kind: SpendKind.task,
            running: true,
          ),
        ],
      ),
      SpendPart(
        name: 'docs',
        kind: SpendKind.agent,
        ended: true,
        figure: Figure(cost: (amount: 0.02, currency: 'USD')),
        parts: [
          SpendPart(
            name: 'Index',
            kind: SpendKind.task,
            ended: true,
            figure: Figure(cost: (amount: 0.03, currency: 'USD')),
          ),
        ],
      ),
    ];
    expect(_lines(window, 112), [
      'This session          Cost  Tokens',
      r'main               $0.0100       —',
      r'  Fix it           $0.0050       —  task agent, ended',
      r'before /clear      $0.0050       —',
      '  Watch the build        —       —  task agent, running: counted when '
          'it ends',
      r'docs               $0.0200       —  agent, closed',
      r'  Index            $0.0300       —  task agent, ended',
      r'Total              $0.0700       —  1 running',
    ]);
  });
}
