// /cost and /context: the original's tests/ui/transcript/reports_test.ts
// cases for one session.
import 'dart:convert';
import 'dart:io';

import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/turn_costs.dart';
import 'package:chord/session/usage.dart';
import 'package:chord/ui/transcript/reports.dart';
import 'package:chord/ui/transcript/spend.dart';
import 'package:test/test.dart';

const _facts = CostFacts(agent: 'fake', since: 0, now: 65000);

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

SpentTurn _usd(num amount, {bool estimated = false, String? model}) =>
    SpentTurn(
      TurnCost(cost: (amount: amount, currency: 'USD'), estimated: estimated),
      model,
    );

CostFacts _with({
  String agent = 'fake',
  Spent? spent,
  String? running,
  bool time = true,
  List<({String id, String name})>? models,
  String? current,
}) => CostFacts(
  agent: agent,
  spent: spent,
  running: running,
  since: time ? 0 : null,
  now: 65000,
  models: models == null ? null : (available: models, current: current),
);

void main() {
  group('tester: CTUI-29 report accounting boundaries', () {
    test('fractional token counts retain the original Intl precision', () {
      final rows = costReport(
        _with(
          time: false,
          spent: const Spent(
            turns: {
              't': {'inputTokens': 1000.5, 'thoughtTokens': 0.25},
            },
          ),
        ),
      );
      expect(rows, contains((label: 'Tokens in:', text: '1,000.5')));
      expect(rows, contains((label: 'Thinking:', text: '0.25')));
      expect(contextReport('fake', const Usage(12.5, 100)), [
        (label: 'Used:', text: '12.5 of 100 tokens (13%)'),
        (label: 'Free:', text: '87.5 tokens (87%)'),
      ]);
    });

    test(
      'foreign historical cost remains explicit while reported zero USD is still counted',
      () {
        final spent = Spent(
          turns: const {
            't': {'inputTokens': 999, 'totalTokens': 0},
          },
          costs: {
            'before': const SpentTurn(
              TurnCost(
                cost: (amount: 2, currency: 'EUR'),
                estimated: true,
                before: (until: null),
              ),
            ),
            'zero': _usd(0),
            'unknown': const SpentTurn(TurnCost(uncounted: true)),
          },
        );
        final figure = sessionFigure(spent)!;
        expect(figure.cost, (amount: 0, currency: 'USD'));
        expect(figure.estimated, Estimated.none);
        expect(figure.uncounted, 2);
        expect(figure.tokens, 0);
        final rows = costReport(_with(time: false, spent: spent));
        expect(rows, contains((label: 'Total cost:', text: r'$0.0000')));
        expect(
          rows,
          contains((label: 'Before:', text: '€2.00 as last reported')),
        );
        expect(rows, contains((label: 'Not counted:', text: '2 turns')));
      },
    );

    test(
      'a new selected model does not rename the unpriced last cumulative total',
      () {
        const spent = Spent(
          total: {'inputTokens': 10},
          totalModel: 'old',
          costs: {'t': SpentTurn(TurnCost(uncounted: true), 'old')},
        );
        final rows = costReport(
          _with(
            agent: 'dirac',
            time: false,
            spent: spent,
            current: 'new',
            models: [
              (id: 'old', name: 'Old Model'),
              (id: 'new', name: 'New Model'),
            ],
          ),
        );
        expect(rows.first.text, contains('no price for Old Model'));
        expect(rows.first.text, isNot(contains('New Model')));
        expect(rows.where((row) => row.label == 'Not counted:'), isEmpty);
        expect(
          rows.last.text,
          "dirac reports these as the session's running total; chord shows the last it sent.",
        );
      },
    );
  });
  test("the session's tokens are each turn's added up", () {
    expect(
      sessionTokens(
        const Spent(
          turns: {
            'a': {'inputTokens': 10, 'outputTokens': 2, 'cachedReadTokens': 3},
            'b': {'inputTokens': 5, 'outputTokens': 1},
          },
        ),
      ),
      {'inputTokens': 15, 'outputTokens': 3, 'cachedReadTokens': 3},
    );
    expect(sessionTokens(const Spent()), isNull);
    expect(sessionTokens(null), isNull);
  });

  test('a cost reads as Claude Code writes one', () {
    expect(formatCost((amount: 0.0125, currency: 'USD')), r'$0.0125');
    expect(formatCost((amount: 1.234, currency: 'USD')), r'$1.23');
    expect(formatCost((amount: 3, currency: 'EUR')), '€3.00');
    expect(formatCost((amount: 3, currency: 'credits')), '3.00 credits');
    // A code with no sign of its own stands apart, as JS Intl writes it.
    expect(formatCost((amount: 3, currency: 'XYZ')), 'XYZ\u00a03.00');
    expect(formatCost((amount: 0.03, currency: 'XYZ')), 'XYZ\u00a00.0300');
    // A sign shared with another currency is told apart, as JS Intl does.
    expect(formatCost((amount: 3, currency: 'CAD')), 'CA\$3.00');
    expect(formatCost((amount: 3, currency: 'AUD')), 'A\$3.00');
    expect(formatCost((amount: 3, currency: 'CNY')), 'CN¥3.00');
    // Grouped in thousands, as JS Intl writes them.
    expect(formatCost((amount: 1234.5, currency: 'EUR')), '€1,234.50');
    expect(
      formatCost((amount: 12345.5, currency: 'XYZ')),
      'XYZ\u00a012,345.50',
    );
    expect(formatCost((amount: 1000000, currency: 'CAD')), 'CA\$1,000,000.00');
  });

  test(
    'every currency the original knows is written as its Intl writes it',
    () {
      final probe =
          jsonDecode(
                File(
                  'test/fixtures/currency/original_probe.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final costs = (probe['costs'] as Map).cast<String, List<Object?>>();
      expect(costs, hasLength(greaterThan(300)));
      for (final MapEntry(key: code, value: written) in costs.entries) {
        expect(
          formatCost((amount: 3, currency: code)),
          written[0],
          reason: code,
        );
        expect(
          formatCost((amount: 0.03, currency: code)),
          written[1],
          reason: code,
        );
      }
    },
  );

  test('/cost lines up tokens, cost and time', () {
    expect(
      _text(
        costReport(
          _with(
            spent: Spent(
              turns: const {
                'a': {
                  'inputTokens': 1000,
                  'outputTokens': 200,
                  'cachedReadTokens': 800,
                },
                'b': {
                  'inputTokens': 1000,
                  'outputTokens': 200,
                  'cachedReadTokens': 800,
                },
              },
              costs: {'a': _usd(0.0125), 'b': _usd(0.0125)},
            ),
          ),
        ),
      ),
      [
        r'Total cost:   $0.0250',
        'Tokens in:    2,000',
        'Tokens out:   400',
        'Cache read:   1,600',
        'Session time: 1m 5s',
      ],
    );
  });

  test('/cost says what the agent left out, and draws no zeros', () {
    expect(_text(costReport(_facts)), [
      'fake has not reported what this session has used.',
      'Session time: 1m 5s',
    ]);
    expect(
      _text(
        costReport(
          _with(
            spent: const Spent(
              turns: {
                'a': {'inputTokens': 9},
              },
            ),
          ),
        ),
      ),
      [
        'Total cost:   not reported by fake',
        'Tokens in:    9',
        'Session time: 1m 5s',
      ],
    );
    expect(
      _text(
        costReport(_with(time: false, spent: Spent(costs: {'a': _usd(0.5)}))),
      ),
      [r'Total cost: $0.5000', 'Tokens:     not reported by fake'],
    );
    expect(
      _text(
        costReport(
          _with(
            time: false,
            spent: const Spent(
              turns: {
                'a': {'totalTokens': 7},
              },
            ),
          ),
        ),
      ),
      ['Total cost: not reported by fake', 'Tokens:     7'],
    );
  });

  test('/context agrees with the status line on what is used', () {
    expect(_text(contextReport('fake', const Usage(4000, 1000000))), [
      'Used: 4,000 of 1,000,000 tokens (1%)',
      'Free: 996,000 tokens (99%)',
    ]);
    expect(_text(contextReport('fake', null)), [
      'fake has not reported how full its context window is.',
    ]);
  });

  test("a cost and a context chord worked out read as chord's estimate", () {
    expect(
      _text(
        costReport(
          _with(
            time: false,
            spent: Spent(
              turns: const {
                'a': {'inputTokens': 1000},
              },
              costs: {'a': _usd(0.0042, estimated: true)},
            ),
          ),
        ),
      ),
      [r"Total cost: $0.0042 (chord's estimate)", 'Tokens in:  1,000'],
    );
    expect(
      _text(
        contextReport('fake', const Usage(4000, 1000000, estimated: ['size'])),
      ),
      [
        "Used: 4,000 of 1,000,000 tokens (1%) (chord's estimate)",
        "Free: 996,000 tokens (99%) (chord's estimate)",
      ],
    );
    expect(_text(contextReport('fake', const Usage(4000, 0))), [
      'fake has not reported how full its context window is.',
    ]);
  });

  test('/cost says the turn running is counted when it ends, until any of '
      'its spend has come', () {
    final earlier = Spent(
      turns: const {
        'a': {
          'inputTokens': 1000,
          'outputTokens': 200,
          'cachedReadTokens': 800,
        },
      },
      costs: {'a': _usd(0.025, estimated: true)},
    );
    expect(_text(costReport(_with(spent: earlier, running: 'b'))), [
      r"Total cost:   $0.0250 (chord's estimate)",
      'This turn:    counted when it ends',
      'Tokens in:    1,000',
      'Tokens out:   200',
      'Cache read:   800',
      'Session time: 1m 5s',
    ]);
    expect(_text(costReport(_with(running: 'a'))), [
      'fake has not reported what this session has used.',
      'This turn:    counted when it ends',
      'Session time: 1m 5s',
    ]);
    expect(
      _text(costReport(_with(spent: earlier, running: 'a'))),
      isNot(contains('This turn:    counted when it ends')),
    );
  });

  test("/cost's total is the whole session's, marked when part of it is "
      "chord's estimate, with an older record's sum and turns left out each "
      'a row of its own', () {
    final until = DateTime(2026, 10, 12, 12).millisecondsSinceEpoch;
    expect(
      _text(
        costReport(
          _with(
            time: false,
            spent: Spent(
              turns: const {
                'a': {'inputTokens': 48200},
              },
              costs: {
                'history-before': SpentTurn(
                  TurnCost(
                    cost: (amount: 0.04, currency: 'USD'),
                    before: (until: until),
                  ),
                ),
                'a': _usd(0.1, estimated: true),
                'b': _usd(0.044),
                'c': const SpentTurn(TurnCost(uncounted: true)),
              },
            ),
          ),
        ),
      ),
      [
        r"Total cost:    $0.1840 (part chord's estimate)",
        r'Before Oct 12: $0.0400 as last reported',
        'Not counted:   1 turn',
        'Tokens in:     48,200',
      ],
    );
  });

  group("/cost on an agent that gives running totals", () {
    const codex = [(id: 'gpt-5.3-codex', name: 'GPT-5.3 Codex')];

    test("its own cost: the rows as for any agent, its last total's tokens, "
        'and one line on how they were read', () {
      expect(
        _text(
          costReport(
            _with(
              agent: 'dirac',
              models: codex,
              current: 'gpt-5.3-codex',
              spent: Spent(
                total: const {
                  'inputTokens': 2000,
                  'outputTokens': 400,
                  'cachedReadTokens': 1600,
                },
                costs: {'a': _usd(0.0125), 'b': _usd(0.0125)},
              ),
            ),
          ),
        ),
        [
          r'Total cost:   $0.0250',
          'Tokens in:    2,000',
          'Tokens out:   400',
          'Cache read:   1,600',
          'Session time: 1m 5s',
          "dirac reports these as the session's running total; chord shows "
              'the last it sent.',
        ],
      );
    });

    test("no cost of its own, the model priced: chord's estimate, and why", () {
      expect(
        _text(
          costReport(
            _with(
              agent: 'dirac',
              time: false,
              models: codex,
              current: 'gpt-5.3-codex',
              spent: Spent(
                total: const {'totalTokens': 6000},
                totalModel: 'gpt-5.3-codex',
                costs: {
                  'a': _usd(0.0094, estimated: true, model: 'gpt-5.3-codex'),
                },
              ),
            ),
          ),
        ),
        [
          r"Total cost: $0.0094 (chord's estimate)",
          'Tokens:     6,000',
          "dirac reports these as the session's running total; chord shows "
              'the last it sent.',
          "dirac's provider reports no cost, so chord priced these tokens at "
              "GPT-5.3 Codex's price.",
        ],
      );
    });

    test('no cost, and no price for its model: both reasons in the cost '
        'cell, and no second line', () {
      expect(
        _text(
          costReport(
            _with(
              agent: 'dirac',
              time: false,
              models: const [(id: 'fake-large', name: 'Fake Large')],
              spent: const Spent(
                total: {'totalTokens': 6000},
                totalModel: 'fake-large',
              ),
            ),
          ),
        ),
        [
          "Total cost: not reported: dirac's provider reports none, and chord "
              'has no price for Fake Large',
          'Tokens:     6,000',
          "dirac reports these as the session's running total; chord shows "
              'the last it sent.',
        ],
      );
    });

    const mixed = [
      (id: 'gpt-5.3-codex', name: 'GPT-5.3 Codex'),
      (id: 'fake-large', name: 'Fake Large'),
      (id: 'fake-small', name: 'Fake Small'),
    ];
    SpentTurn unpriced(String model) =>
        SpentTurn(const TurnCost(uncounted: true), model);

    test("what was priced is chord's estimate, the turns left out are not "
        'counted, and the line names the model with no price', () {
      expect(
        _text(
          costReport(
            _with(
              agent: 'dirac',
              time: false,
              models: mixed,
              spent: Spent(
                total: const {'totalTokens': 6000},
                totalModel: 'fake-large',
                costs: {
                  'a': _usd(0.0047, estimated: true, model: 'gpt-5.3-codex'),
                  'b': unpriced('fake-large'),
                  'c': unpriced('fake-large'),
                },
              ),
            ),
          ),
        ),
        [
          r"Total cost:  $0.0047 (chord's estimate)",
          'Not counted: 2 turns',
          'Tokens:      6,000',
          "dirac reports these as the session's running total; chord shows "
              'the last it sent.',
          "dirac's provider reports no cost, so chord priced each answer's "
              'tokens at the price of the model that gave it; it has no price '
              'for Fake Large.',
        ],
      );
    });

    test('several models with no price are named in the order they first '
        'answered', () {
      final lines = _text(
        costReport(
          _with(
            agent: 'dirac',
            time: false,
            models: mixed,
            spent: Spent(
              total: const {'totalTokens': 6000},
              costs: {
                'a': unpriced('fake-small'),
                'b': _usd(0.0047, estimated: true, model: 'gpt-5.3-codex'),
                'c': unpriced('fake-large'),
                'd': unpriced('fake-small'),
              },
            ),
          ),
        ),
      );
      expect(
        lines[4],
        endsWith('it has no price for Fake Small and Fake Large.'),
      );
    });

    test('with no model priced at all, the cell says so and no turn is said '
        'not counted', () {
      expect(
        _text(
          costReport(
            _with(
              agent: 'dirac',
              time: false,
              models: mixed,
              spent: Spent(
                total: const {'totalTokens': 6000},
                totalModel: 'fake-large',
                costs: {
                  'a': unpriced('fake-large'),
                  'b': unpriced('fake-large'),
                },
              ),
            ),
          ),
        ),
        [
          "Total cost: not reported: dirac's provider reports none, and chord "
              'has no price for Fake Large',
          'Tokens:     6,000',
          "dirac reports these as the session's running total; chord shows "
              'the last it sent.',
        ],
      );
    });
  });

  test('a turn waiting between turns is no turn running', () {
    expect(runningTurn(const Idle()), isNull);
    expect(runningTurn(const Working('t', 0)), 't');
    expect(
      runningTurn(const AwaitingPermission('t', 0, [], between: true)),
      isNull,
    );
    expect(runningTurn(const AwaitingPermission('t', 0, [])), 't');
    expect(sessionFigure(null), isNull);
  });
  test('a count keeps up to three fraction digits, as Intl writes it', () {
    expect(
      _text(
        costReport(
          _with(
            time: false,
            spent: const Spent(
              turns: {
                't': {'inputTokens': 1000.5, 'thoughtTokens': 0.25},
              },
            ),
          ),
        ),
      ),
      [
        'Total cost: not reported by fake',
        'Tokens in:  1,000.5',
        'Thinking:   0.25',
      ],
    );
    expect(_text(contextReport('fake', const Usage(12.5, 100))), [
      'Used: 12.5 of 100 tokens (13%)',
      'Free: 87.5 tokens (87%)',
    ]);
    // Values the original's Intl rounds, probed with bun.
    expect(
      _text(
        costReport(
          _with(
            time: false,
            spent: const Spent(
              turns: {
                't': {'outputTokens': 0.0005, 'thoughtTokens': 2.0004},
              },
            ),
          ),
        ),
      ).skip(1),
      ['Tokens out: 0.001', 'Thinking:   2'],
    );
  });
  test("a decimal tie past the third digit rounds as intl does, not as the "
      "original's ICU", () {
    // bun's ICU rounds the decimal 1234567.8915 half-expand to …892; intl
    // rounds the double, which lies below the tie, to …891 (decisions.md,
    // "CTUI-29: fractional counts round as intl does").
    expect(
      _text(
        costReport(
          _with(
            time: false,
            spent: const Spent(
              turns: {
                't': {'inputTokens': 1234567.8915},
              },
            ),
          ),
        ),
      ).last,
      'Tokens in:  1,234,567.891',
    );
  });
}
