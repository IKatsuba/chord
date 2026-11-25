// `/cost`'s team rows: the original's tests/ui/transcript/spend_test.ts and
// spend_table_test.ts team cases. A team run is one part with its lead and
// members under it, its own figure only what is under it; a closed run whose
// lead closed too is one part of its own; a member's task is a row under the
// run naming its owner.
import 'package:chord/session/turn_costs.dart';
import 'package:chord/session/usage.dart';
import 'package:chord/session/waits.dart';
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/transcript/spend.dart';
import 'package:chord/ui/transcript/spend_table.dart';
import 'package:test/test.dart';

Cost _usd(num amount) => (amount: amount, currency: 'USD');

SpendPart _part(
  String name,
  SpendKind kind,
  num cost, {
  int? tokens,
  List<SpendPart> parts = const [],
  bool ended = false,
}) => SpendPart(
  name: name,
  kind: kind,
  figure: Figure(cost: _usd(cost), tokens: tokens),
  parts: parts,
  ended: ended,
);

/// The table's lines as text.
List<String> _lines(List<SpendPart> parts, int width) => [
  for (final row in spendTable(parts, width)) row.text,
];

/// CHD-378's C mock: main, a task, a team run, and an agent beside them.
final _window = [
  const SpendPart(
    name: 'main',
    kind: SpendKind.main,
    agent: 'fake',
    figure: Figure(cost: (amount: 0.025, currency: 'USD'), tokens: 4000),
  ),
  _part('Fix the tokenizer', SpendKind.task, 0.0125, tokens: 2000, ended: true),
  SpendPart(
    name: 'bugfix',
    kind: SpendKind.team,
    parts: [
      _part('lead', SpendKind.member, 0.025, tokens: 4000),
      _part('tester', SpendKind.member, 0.0125, tokens: 2000),
      _part('coder', SpendKind.member, 0.0125, tokens: 2000),
    ],
  ),
  const SpendPart(
    name: 'fake',
    kind: SpendKind.agent,
    runtime: 'fake',
    figure: Figure(cost: (amount: 0.0125, currency: 'USD'), tokens: 2000),
  ),
];

Child<String> _child(
  int key,
  String id,
  String name, {
  String? team,
  String? lead,
  String runtime = 'fake',
}) => Child(
  ChildInfo(
    id: id,
    name: name,
    runtime: runtime,
    colour: key,
    openedAt: 0,
    team: team,
    lead: lead,
  ),
  key,
  name,
  idle,
);

WindowAgents<String> _tab(List<Child<String>> children) => WindowAgents(
  main: const MainAgent(1, 'codex', 'codex', idle),
  children: children,
  picked: 1,
  opened: children.length,
  nextKey: 10,
);

SpendSession _session(num cost) => SpendSession(
  spent: addTurn(
    null,
    't',
    const {},
    SpentTurn(TurnCost(cost: _usd(cost), estimated: false)),
  ),
);

/// Each part by its name and own cost, with what is under it.
List<Object?> _shape(List<SpendPart> parts) => [
  for (final part in parts)
    [
      part.name,
      part.figure?.cost?.amount,
      if (part.parts.isNotEmpty) _shape(part.parts),
    ],
];

void main() {
  group('CTUI-37 tester: settled run accounting isolation', () {
    test('same-name ended runs stay separate under every close rotation', () {
      final kept = [
        for (final (run, costs) in [
          ('first', [1, 2, 3]),
          ('second', [4, 5, 6]),
        ])
          for (final (index, cost) in costs.indexed)
            KeptSpend(
              sessionId: '$run-$index',
              lead: run,
              team: 'bugfix',
              part: _part(
                ['lead', 'tester', 'coder'][index],
                SpendKind.member,
                cost,
                tokens: cost * 100,
                ended: true,
              ),
            ),
      ];
      for (var shift = 0; shift < kept.length; shift++) {
        final reordered = [...kept.skip(shift), ...kept.take(shift)];
        final parts = windowSpend(const WindowAgents<String>(), {}, reordered);
        expect(parts, hasLength(2));
        expect(
          parts.every((part) => part.name == 'bugfix' && part.ended),
          isTrue,
        );
        final costs = [
          for (final part in parts) sum([part]).cost,
        ]..sort();
        expect(costs, [6, 15]);
        expect(sum(parts).cost, 21);
        expect(sum(parts).tokens, 2100);
        expect(sum(parts).missing, isEmpty);
      }
    });

    test(
      'a resumed member replaces its kept figure and closes once at its newest value',
      () {
        final old = KeptSpend(
          sessionId: 'member-session',
          lead: 'run',
          team: 'bugfix',
          part: _part('tester', SpendKind.member, 1),
        );
        final newer = KeptSpend(
          sessionId: 'member-session',
          lead: 'run',
          team: 'bugfix',
          part: _part('tester', SpendKind.member, 3),
        );
        final live = windowSpend(
          _tab([
            _child(2, 'run', 'bugfix', team: 'bugfix'),
            _child(3, 'member', 'tester', team: 'bugfix', lead: 'run'),
          ]),
          {
            2: _session(2),
            3: SpendSession(
              sessionId: 'member-session',
              spent: _session(4).spent,
            ),
          },
          [old, newer],
        );
        expect(sum(live).cost, 6);
        expect(live.last.parts, hasLength(2));
        final closed = windowSpend(const WindowAgents<String>(), {}, [
          old,
          newer,
        ]);
        expect(sum(closed).cost, 3);
        expect(closed.single.parts.single.name, 'tester');
      },
    );
  });

  test("the window's table at 120 columns: main, a task, a team run with its "
      'members named, an agent beside them', () {
    expect(_lines(_window, 114), [
      'This session          Cost  Tokens',
      'main               \$0.0250   4,000',
      'Fix the tokenizer  \$0.0125   2,000  task agent, ended',
      'bugfix             \$0.0500   8,000  team run: lead \$0.0250 · tester '
          '\$0.0125 · coder \$0.0125',
      'fake               \$0.0125   2,000  agent',
      'Total              \$0.1000  16,000',
    ]);
  });

  test('at 80 columns the run\'s note wraps in its cell after a ` · `', () {
    expect(_lines(_window, 72), [
      'This session          Cost  Tokens',
      'main               \$0.0250   4,000',
      'Fix the tokenizer  \$0.0125   2,000  task agent, ended',
      'bugfix             \$0.0500   8,000  team run: lead \$0.0250 ·',
      '                                    tester \$0.0125 · coder \$0.0125',
      'fake               \$0.0125   2,000  agent',
      'Total              \$0.1000  16,000',
    ]);
  });

  test("a member's task is a row under the run naming its owner, and the "
      "run's row adds up its lead and members alone", () {
    final window = [
      _part(
        'main',
        SpendKind.main,
        0.01,
        parts: [_part('Fix it', SpendKind.task, 0.005, ended: true)],
      ),
      _part(
        'docs',
        SpendKind.agent,
        0.02,
        ended: true,
        parts: [_part('Index', SpendKind.task, 0.03, ended: true)],
      ),
      SpendPart(
        name: 'bugfix',
        kind: SpendKind.team,
        parts: [
          _part('lead', SpendKind.member, 0.025),
          _part(
            'tester',
            SpendKind.member,
            0.0125,
            parts: [_part('Run it', SpendKind.task, 0.001, ended: true)],
          ),
        ],
      ),
    ];
    expect(_lines(window, 112), [
      'This session     Cost  Tokens',
      'main          \$0.0100       —',
      '  Fix it      \$0.0050       —  task agent, ended',
      'docs          \$0.0200       —  agent, closed',
      '  Index       \$0.0300       —  task agent, ended',
      'bugfix        \$0.0375       —  team run: lead \$0.0250 · tester '
          '\$0.0125',
      '  Run it      \$0.0010       —  task agent of tester, ended',
      'Total         \$0.1035       —',
    ]);
  });

  test('an ended run says so', () {
    final ended = SpendPart(
      name: 'review',
      kind: SpendKind.team,
      ended: true,
      parts: [_part('lead', SpendKind.member, 0.002)],
    );
    expect(
      _lines([_part('main', SpendKind.main, 0.01), ended], 112)[2],
      'review        \$0.0020       —  team run, ended: lead \$0.0020',
    );
  });

  test("a team run has no figure of its own beside its agents', and counts "
      'as no session', () {
    final summed = sum([_window[2]]);
    expect(summed.cost, closeTo(0.05, 1e-9));
    expect(summed.missing, isEmpty);
    expect(manySessions([_window[2]]), isTrue);
    expect(
      manySessions([
        const SpendPart(
          name: 'bugfix',
          kind: SpendKind.team,
          parts: [SpendPart(name: 'lead', kind: SpendKind.member)],
        ),
      ]),
      isFalse,
    );
  });

  test("the window's spend: main, its long-lived agents, a team run with its "
      'lead and members, and what closed', () {
    final spend = windowSpend(
      _tab([
        _child(2, 'a', 'docs'),
        _child(3, 'l', 'bugfix', team: 'bugfix'),
        _child(4, 't', 'tester', team: 'bugfix', lead: 'l'),
      ]),
      {
        1: _session(0.15),
        2: _session(0.02),
        3: _session(0.025),
        4: _session(0.0125),
      },
      [
        KeptSpend(
          lead: 'l',
          part: _part('coder', SpendKind.member, 0.01, ended: true),
        ),
        // A main session `/clear` let go.
        KeptSpend(part: _part('main', SpendKind.main, 0.03, ended: true)),
        // A closed run whose lead closed too is one team part of its own.
        KeptSpend(
          lead: 'x',
          team: 'review',
          part: _part('lead', SpendKind.member, 0.002),
        ),
      ],
    );
    expect(_shape(spend), [
      ['main', 0.15],
      ['docs', 0.02],
      [
        'bugfix',
        null,
        [
          ['lead', 0.025],
          ['tester', 0.0125],
          ['coder', 0.01],
        ],
      ],
      ['main', 0.03],
      [
        'review',
        null,
        [
          ['lead', 0.002],
        ],
      ],
    ]);
    expect(
      sum(spend).cost,
      closeTo(0.15 + 0.02 + 0.025 + 0.0125 + 0.01 + 0.002 + 0.03, 1e-9),
    );
  });

  test("a team member's part names the agent it runs on, as main names its "
      'own', () {
    List<Object?> runtimes(List<SpendPart> parts) => [
      for (final part in parts)
        [
          part.name,
          part.runtime,
          if (part.parts.isNotEmpty) runtimes(part.parts),
        ],
    ];
    expect(
      runtimes(
        windowSpend(
          _tab([
            _child(2, 'a', 'docs', runtime: 'dirac'),
            _child(3, 'l', 'bugfix', team: 'bugfix', runtime: 'dirac'),
            _child(4, 't', 'tester', team: 'bugfix', lead: 'l'),
          ]),
          {},
          [],
        ),
      ),
      [
        ['main', null],
        ['docs', 'dirac'],
        [
          'bugfix',
          null,
          [
            ['lead', 'dirac'],
            ['tester', 'fake'],
          ],
        ],
      ],
    );
  });

  test('with main gone, a closed run is kept as one part', () {
    expect(
      _shape(
        windowSpend(const WindowAgents<String>(), {}, [
          KeptSpend(
            lead: 'l',
            team: 'bugfix',
            part: _part('lead', SpendKind.member, 0.002, ended: true),
          ),
          KeptSpend(
            lead: 'l',
            team: 'bugfix',
            part: _part('tester', SpendKind.member, 0.001, ended: true),
          ),
        ]),
      ),
      [
        [
          'bugfix',
          null,
          [
            ['lead', 0.002],
            ['tester', 0.001],
          ],
        ],
      ],
    );
  });
}
