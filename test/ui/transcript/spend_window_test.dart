// The window's spend and `/cost`'s table of it: the original's
// tests/ui/transcript/spend_test.ts, spend_table_test.ts and the window case
// of reports_test.ts, for the main session and long-lived agents. Cases of
// team runs and task agents come with their parts.
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/turn_costs.dart';
import 'package:chord/session/usage.dart';
import 'package:chord/session/waits.dart';
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/transcript/reports.dart';
import 'package:chord/ui/transcript/spend.dart';
import 'package:chord/ui/transcript/spend_table.dart';
import 'package:chord_tui/chord_tui.dart' show cellWidth;
import 'package:test/test.dart';

Cost _usd(num amount) => (amount: amount, currency: 'USD');

SpentTurn _cost(num amount, {bool estimated = false}) =>
    SpentTurn(TurnCost(cost: _usd(amount), estimated: estimated));

/// A session's spend from [turns], each its tokens and its own cost.
Spent? _spentOf(List<(String, TokenUsage, SpentTurn?)> turns) => turns.fold(
  null,
  (spent, turn) =>
      addTurn(spent, turn.$1, turn.$2, turn.$3 ?? const SpentTurn()),
);

/// The table's lines as text.
List<String> _lines(List<SpendPart> parts, int width) => [
  for (final row in spendTable(parts, width)) row.text,
];

/// The rows as the window lines them up: each label padded to the widest.
List<String> _text(List<ReportRow> rows) {
  final width = rows
      .where((row) => row.label.isNotEmpty)
      .fold(0, (n, row) => row.label.length + 1 > n ? row.label.length + 1 : n);
  return [
    for (final row in rows)
      row.label.isEmpty ? row.text : '${row.label.padRight(width)}${row.text}',
  ];
}

Child<String> _child(int key, String id, String name, {String? runtime}) =>
    Child(
      ChildInfo(
        id: id,
        name: name,
        runtime: runtime ?? 'fake',
        colour: key,
        openedAt: 0,
      ),
      key,
      name,
      idle,
    );

/// The window: main, [key] on [agent], and [children].
WindowAgents<String> _tab(
  int key,
  String agent,
  List<Child<String>> children,
) => WindowAgents(
  main: MainAgent(key, agent, agent, idle),
  children: children,
  picked: key,
  opened: children.length,
  nextKey:
      [
        key,
        ...children.map((child) => child.key),
      ].reduce((a, b) => a > b ? a : b) +
      1,
);

SpendSession _session(num cost, [String? sessionId]) => SpendSession(
  sessionId: sessionId,
  spent: _spentOf([('t', const {}, _cost(cost))]),
);

/// Each part by its name and own cost.
List<List<Object?>> _shape(List<SpendPart> parts) => [
  for (final part in parts) [part.name, part.figure?.cost?.amount],
];

/// The date of `Date.UTC(2026, 9, 12, 12)`.
final _oct12 = DateTime.utc(2026, 10, 12, 12).millisecondsSinceEpoch;

void main() {
  group('spend', () {
    test(
      'a sum adds what was reported, says how much chord estimated, and names '
      'what reported nothing rather than read it as zero',
      () {
        const parser = SpendPart(
          name: 'parser',
          kind: SpendKind.agent,
          runtime: 'codex',
          figure: Figure(
            cost: (amount: 0.412, currency: 'USD'),
            estimated: Estimated.all,
            tokens: 188400,
          ),
        );
        expect(sum([parser]).estimated, Estimated.all);
        final none = sum([]);
        expect(none.cost, isNull);
        expect(none.estimated, Estimated.none);
        expect(none.tokens, isNull);
        expect(none.missing, isEmpty);
        expect(none.providers, isEmpty);
        expect(none.uncounted, 0);
      },
    );

    test('a closed session counts once: not where it closed while it is open '
        'again, and where it closed last', () {
      KeptSpend closed(num amount) => KeptSpend(
        sessionId: 's1',
        part: SpendPart(
          name: 'main',
          kind: SpendKind.main,
          ended: true,
          figure: Figure(cost: _usd(amount)),
        ),
      );
      final kept = [closed(0.01), closed(0.03)];

      // Resumed in main, its whole spend is there.
      expect(
        _shape(
          windowSpend(_tab(1, 'fake', []), {1: _session(0.05, 's1')}, kept),
        ),
        [
          ['main', 0.05],
        ],
      );
      // Closed twice, the last close holds its whole spend.
      expect(_shape(windowSpend(const WindowAgents<String>(), {}, kept)), [
        ['main', 0.03],
      ]);
    });

    group('CHD-373 S3b tester: retained session identity and partial '
        'figures', () {
      test('same-named closed agents with distinct sessions both count, and a '
          'resumed session supersedes all older snapshots', () {
        KeptSpend parser(String sessionId, num amount) => KeptSpend(
          sessionId: sessionId,
          part: SpendPart(
            name: 'parser',
            kind: SpendKind.agent,
            figure: Figure(cost: _usd(amount)),
          ),
        );
        final kept = [
          parser('one', 0.01),
          parser('two', 0.02),
          parser('one', 0.03),
        ];

        expect(
          sum(windowSpend(const WindowAgents<String>(), {}, kept)).cost,
          closeTo(0.05, 1e-9),
        );

        final live = windowSpend(_tab(1, 'fake', []), {
          1: _session(0.04, 'one'),
        }, kept);

        expect(sum(live).cost, closeTo(0.06, 1e-9));
        expect(_shape(live), [
          ['main', 0.04],
          ['parser', 0.02],
        ]);
      });

      test('a zero estimate remains reported while missing and non-USD '
          'sessions remain unreported, with mixed token formats counted per '
          'turn', () {
        final sessions = {
          1: SpendSession(
            spent: _spentOf([
              ('one', const {'totalTokens': 10}, _cost(0, estimated: true)),
              (
                'two',
                const {'inputTokens': 2, 'outputTokens': 3},
                const SpentTurn(TurnCost(uncounted: true)),
              ),
              (
                'one',
                const {'totalTokens': 0, 'inputTokens': 99},
                _cost(0, estimated: true),
              ),
            ]),
          ),
          2: SpendSession(
            spent: _spentOf([
              (
                'euro',
                const {},
                const SpentTurn(TurnCost(cost: (amount: 2, currency: 'EUR'))),
              ),
            ]),
          ),
        };
        final parts = windowSpend(
          _tab(1, 'fake', [
            _child(2, 'o', 'other', runtime: 'other'),
            _child(3, 's', 'silent', runtime: 'silent'),
          ]),
          sessions,
          [],
        );
        final summed = sum(parts);

        expect(summed.cost, 0);
        expect(summed.estimated, Estimated.all);
        expect(summed.tokens, 5);
        expect(summed.uncounted, 2);
        expect(summed.missing, ['other', 'silent']);
        expect(summed.providers, isEmpty);
      });
    });
  });

  group('spend table', () {
    test('an estimate says whose prices, a figure nobody reported says so, '
        'and the total gathers both', () {
      final mixed = [
        SpendPart(
          name: 'main',
          kind: SpendKind.main,
          agent: 'fake',
          figure: Figure(cost: _usd(0.025), tokens: 4000),
        ),
        SpendPart(
          name: 'codex',
          kind: SpendKind.agent,
          runtime: 'codex',
          figure: Figure(
            cost: _usd(0.412),
            estimated: Estimated.all,
            models: const ['gpt-5.3-codex'],
            tokens: 188400,
          ),
        ),
        const SpendPart(
          name: 'gemini',
          kind: SpendKind.agent,
          runtime: 'gemini',
        ),
      ];

      expect(_lines(mixed, 114), [
        'This session          Cost   Tokens',
        'main               \$0.0250    4,000',
        "codex             ~\$0.4120  188,400  agent; chord's estimate from gpt-5.3-codex's price",
        'gemini        not reported        —  agent',
        "Total             ~\$0.4370  192,400  part chord's estimate; gemini not reported",
      ]);
      // Narrow, a note left fewer than 20 cells beside the figures goes below
      // them, from the cost column on the row's second line.
      expect(_lines(mixed, 50), [
        'This session          Cost   Tokens',
        'main               \$0.0250    4,000',
        'codex             ~\$0.4120  188,400',
        '              agent;',
        "              chord's estimate from",
        "              gpt-5.3-codex's price",
        'gemini        not reported        —',
        '              agent',
        'Total             ~\$0.4370  192,400',
        "              part chord's estimate;",
        '              gemini not reported',
      ]);
    });

    test('the table is for a window of more than one session, a closed one '
        'counted', () {
      const main = SpendPart(name: 'main', kind: SpendKind.main, agent: 'fake');

      expect(manySessions([main]), isFalse);
      expect(
        manySessions([
          main,
          const SpendPart(
            name: 'main',
            kind: SpendKind.main,
            agent: 'fake',
            ended: true,
          ),
        ]),
        isTrue,
      );
    });

    test("the Total says chord's estimate when all of it is, and part only "
        'when some is not', () {
      SpendPart estimated(String name, SpendKind kind) => SpendPart(
        name: name,
        kind: kind,
        runtime: 'codex',
        figure: Figure(
          cost: _usd(0.0047),
          estimated: Estimated.all,
          tokens: 2000,
        ),
      );

      expect(
        _lines([
          estimated('main', SpendKind.main),
          estimated('docs', SpendKind.agent),
        ], 114).last,
        "Total         ~\$0.0094   4,000  chord's estimate",
      );
    });

    test('a session that reported nothing but a turn left out still says '
        'that turn', () {
      expect(
        _text(
          costReport(
            CostFacts(
              agent: 'fake',
              now: 1,
              spent: Spent(
                costs: {'a': const SpentTurn(TurnCost(uncounted: true))},
              ),
            ),
          ),
        ),
        [
          'Total cost:  not reported by fake',
          'Not counted: 1 turn',
          'Tokens:      not reported by fake',
        ],
      );
    });

    group('CHD-473 tester: full cells at the note floor and nested '
        'accounting', () {
      const name = 'Long_closed_agent_name_that_needs_several_lines';
      final parts = [
        SpendPart(
          name: 'main',
          kind: SpendKind.main,
          figure: Figure(cost: _usd(0.01)),
        ),
        SpendPart(
          name: name,
          kind: SpendKind.agent,
          ended: true,
          figure: Figure(cost: _usd(0.02)),
        ),
      ];

      test('exactly twenty note cells stay beside figures; nineteen move to '
          'the second line at the cost edge', () {
        for (final width in [57, 58]) {
          final drawn = _lines(parts, width);
          final at = drawn.indexWhere((line) => line.startsWith('Long_'));
          final end = drawn.indexWhere((line) => line.startsWith('Total'));
          final block = drawn.sublist(at, end);
          final note = block
              .where((line) => line.contains('agent, closed'))
              .firstOrNull;

          expect(at, greaterThan(0));
          expect(note, isNotNull);
          expect(block[0], contains(r'$0.0200'));
          expect(
            RegExp(r'\$0\.0200').allMatches(block.join(' ')),
            hasLength(1),
          );
          expect(
            block
                .map((line) => RegExp(r'^(\S+)').firstMatch(line)?[1] ?? '')
                .join(),
            name,
          );

          if (width == 57) {
            expect(block[0], isNot(contains('agent, closed')));
            expect(block[1], note);
            expect(note!.indexOf('agent, closed'), 21);
          } else {
            expect(block[0], note);
            expect(note!.indexOf('agent, closed'), 38);
          }

          expect(drawn.every((line) => cellWidth(line) <= width), isTrue);
        }
      });

      test('every word of estimate, legacy and uncounted notes survives each '
          'width across the floor', () {
        final detailed = [
          SpendPart(
            name: 'main',
            kind: SpendKind.main,
            figure: Figure(cost: _usd(0.01)),
          ),
          SpendPart(
            name: name,
            kind: SpendKind.agent,
            ended: true,
            figure: Figure(
              cost: _usd(0.02),
              estimated: Estimated.all,
              models: const ['model-with-a-very-long-public-name'],
              before: (cost: _usd(0.01), until: _oct12),
              uncounted: 3,
            ),
          ),
        ];
        const expected =
            "agent, closed; chord's estimate from model-with-a-very-long-public-name's price; as last reported before Oct 12; 3 turns not counted";
        final spaces = RegExp(r'\s');

        for (var width = 42; width <= 120; width++) {
          final drawn = _lines(detailed, width);
          final at = drawn.indexWhere((line) => line.startsWith('Long_'));
          final end = drawn.indexWhere((line) => line.startsWith('Total'));
          final block = drawn.sublist(at, end);
          final nameWidth = width ~/ 3;
          final beside = width - nameWidth - 20 >= 20;
          final from = nameWidth + (beside ? 20 : 2);
          final notes = block
              .skip(beside ? 0 : 1)
              .map((line) => line.length > from ? line.substring(from) : '')
              .join();

          expect(
            notes.replaceAll(spaces, ''),
            expected.replaceAll(spaces, ''),
            reason: 'notes at $width',
          );
          expect(
            drawn.every((line) => cellWidth(line) <= width),
            isTrue,
            reason: 'width $width',
          );
          expect(drawn.join(), isNot(contains('…')));
          expect(
            RegExp(r'~\$0\.0200').allMatches(block.join(' ')),
            hasLength(1),
          );
        }
      });
    });

    test('an agent that gives running totals reads as any row; only with no '
        'cost of its own do its notes say its provider gives none (CHD-472)', () {
      SpendPart dirac(String name, Figure? figure) => SpendPart(
        name: name,
        kind: name == 'main' ? SpendKind.main : SpendKind.agent,
        agent: name == 'main' ? 'dirac' : null,
        runtime: name == 'main' ? null : 'dirac',
        figure: figure,
      );
      final table = _lines([
        dirac(
          'main',
          Figure(
            cost: _usd(0.025),
            tokens: 4000,
            totals: (model: null, unpriced: const []),
          ),
        ),
        dirac(
          'scout',
          Figure(
            cost: _usd(0.0094),
            estimated: Estimated.all,
            models: const ['gpt-5.3-codex'],
            tokens: 6000,
            totals: (model: 'gpt-5.3-codex', unpriced: const []),
          ),
        ),
        dirac(
          'docs',
          const Figure(
            tokens: 6000,
            totals: (model: 'fake-large', unpriced: []),
          ),
        ),
      ], 200);
      String row(String name) =>
          table.where((line) => line.trimLeft().startsWith(name)).firstOrNull ??
          '';

      expect(row('main').trimRight(), matches(RegExp(r'\$0\.0250\s+4,000$')));
      expect(
        row('scout'),
        matches(
          RegExp(
            r"~\$0\.0094\s+6,000 {2}agent; dirac's provider reports no cost; chord's estimate from gpt-5\.3-codex's price$",
          ),
        ),
      );
      expect(
        row('docs'),
        matches(
          RegExp(
            r"not reported\s+6,000 {2}agent; dirac's provider reports no cost; no price for fake-large$",
          ),
        ),
      );
    });

    test("the Total says once that dirac's provider reports no cost, however "
        'many dirac rows lack one, and still names any other agent that '
        'reported nothing (CHD-472)', () {
      const unpriced = Figure(
        tokens: 2000,
        totals: (model: 'fake-large', unpriced: []),
      );
      final total = _lines([
        const SpendPart(
          name: 'main',
          kind: SpendKind.main,
          agent: 'dirac',
          figure: unpriced,
        ),
        const SpendPart(
          name: 'dirac',
          kind: SpendKind.agent,
          runtime: 'dirac',
          figure: unpriced,
        ),
        const SpendPart(
          name: 'scout',
          kind: SpendKind.agent,
          runtime: 'dirac',
          figure: unpriced,
        ),
        const SpendPart(
          name: 'gemini',
          kind: SpendKind.agent,
          runtime: 'gemini',
        ),
      ], 200).where((line) => line.startsWith('Total')).firstOrNull;

      expect(
        total,
        matches(
          RegExp(
            r"^Total\s+not reported\s+6,000 {2}gemini not reported; dirac's provider reports no cost$",
          ),
        ),
      );
    });

    test('a dirac row with some answering models unpriced: the estimate of '
        'the rest, its note naming the models with no price (CHD-472)', () {
      final row = _lines([
        SpendPart(
          name: 'main',
          kind: SpendKind.main,
          agent: 'dirac',
          figure: Figure(
            cost: _usd(0.0047),
            estimated: Estimated.all,
            models: const ['gpt-5.3-codex'],
            tokens: 6000,
            uncounted: 2,
            totals: (model: 'fake-large', unpriced: const ['fake-large']),
          ),
        ),
      ], 200).where((line) => line.startsWith('main')).firstOrNull;

      expect(
        row,
        matches(
          RegExp(
            r"~\$0\.0047\s+6,000 {2}dirac's provider reports no cost; chord's estimate from its models' prices; no price for fake-large$",
          ),
        ),
      );
    });

    group('CHD-472 U2 tester: provider identity in mixed window totals', () {
      for (final width in [72, 114]) {
        test("dirac's missing provider is named once in Total with both priced "
            'and unpriced rows at $width cells', () {
          final parts = [
            SpendPart(
              name: 'main',
              kind: SpendKind.main,
              agent: 'fake',
              figure: Figure(cost: _usd(0.01), tokens: 100),
            ),
            const SpendPart(
              name: 'unpriced',
              kind: SpendKind.agent,
              runtime: 'dirac',
              figure: Figure(
                tokens: 4000,
                totals: (model: 'unpriced', unpriced: []),
              ),
            ),
            SpendPart(
              name: 'priced',
              kind: SpendKind.agent,
              runtime: 'dirac',
              figure: Figure(
                tokens: 2000,
                totals: (model: 'gpt-5.3-codex', unpriced: const []),
                cost: _usd(0.00469),
                estimated: Estimated.all,
                models: const ['gpt-5.3-codex'],
              ),
            ),
            const SpendPart(
              name: 'missing',
              kind: SpendKind.agent,
              runtime: 'fake',
              figure: Figure(tokens: 20),
            ),
          ];
          final output = _lines(parts, width);
          final spaces = RegExp(r'\s+');
          final total = output
              .sublist(output.indexWhere((row) => row.startsWith('Total')))
              .join(' ')
              .replaceAll(spaces, ' ');

          expect(
            RegExp("dirac's provider reports no cost").allMatches(total),
            hasLength(1),
          );
          expect(total, contains('missing not reported'));
          expect(total, isNot(contains('dirac not reported')));
          expect(total, contains('6,120'));
          expect(output.every((row) => cellWidth(row) <= width), isTrue);
          expect(
            output.join(' ').replaceAll(spaces, ' '),
            contains('no price for unpriced'),
          );
        });
      }
    });
  });

  test("/cost adds the window's table once it holds more than one session, "
      'and leaves it out for one', () {
    final main = SpendPart(
      name: 'main',
      kind: SpendKind.main,
      agent: 'fake',
      figure: Figure(cost: _usd(0.025)),
    );
    final spent = Spent(costs: {'a': _cost(0.025)});
    CostFacts facts(List<SpendPart> spend) => CostFacts(
      agent: 'fake',
      now: 65000,
      spent: spent,
      window: (spend: spend, width: 114),
    );

    expect(_text(costReport(facts([main]))), [
      r'Total cost: $0.0250',
      'Tokens:     not reported by fake',
    ]);
    expect(
      _text(
        costReport(
          facts([
            main,
            SpendPart(
              name: 'parser',
              kind: SpendKind.agent,
              runtime: 'fake',
              figure: Figure(cost: _usd(0.025)),
            ),
          ]),
        ),
      ).sublist(2),
      [
        '',
        'This session     Cost  Tokens',
        r'main          $0.0250       —',
        r'parser        $0.0250       —  agent',
        r'Total         $0.0500       —',
      ],
    );
  });
}
