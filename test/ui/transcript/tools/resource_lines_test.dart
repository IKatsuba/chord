// The Resources report under get_budgets, as the original's
// tests/ui/transcript/tools/resource_lines_test.ts reads it.
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/transcript/tools/resource_lines.dart';
import 'package:chord/ui/transcript/tools/tools.dart';
import 'package:test/test.dart';
import 'package:chord/ui/transcript/tools/tool.dart';
import 'package:chord_tui/chord_tui.dart' hide Folded;
import 'package:chord_tui/testing.dart';

Map<String, Object?> _budgets() => {
  'readAt': '2026-10-27T13:00:00.000Z',
  'providers': [
    {
      'agent': 'claude',
      'windows': [
        {
          'name': 'five_hour',
          'usedPercent': 12.345,
          'windowSeconds': 18000,
          'resetsAt': '2026-10-27T18:05:00.000Z',
          'models': null,
        },
        {
          'name': 'model_scoped',
          'usedPercent': 8,
          'windowSeconds': 604800,
          'resetsAt': '2026-11-02T09:00:00.000Z',
          'models': ['opus'],
        },
        {
          'name': 'codex.secondary',
          'usedPercent': null,
          'windowSeconds': null,
          'resetsAt': null,
          'models': <String>[],
        },
      ],
    },
    {'agent': 'gemini', 'windows': <Object?>[]},
    {'agent': 'codex', 'unavailable': 'Timed out after 10 s.'},
  ],
};

const _older = {
  'schemaVersion': 1,
  'observedAt': '2026-10-27T13:00:00Z',
  'pools': <Object?>[],
  'unbound': <Object?>[],
  'unavailable': <Object?>[],
  'activeRuns': <Object?>[],
  'warnings': <Object?>[],
  'preferences': <String, Object?>{},
};

void main() {
  group('CTUI-37 tester: resource report resize boundaries', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('read report retains all meanings after tiny room at $size', (
        t,
      ) async {
        await t.pumpWidget(
          Tool(
            ToolCall(
              'tester-resources',
              kind: 'read',
              status: 'completed',
              chord: ChordCall(
                tool: ChordTool.getBudgets,
                input: const {},
                answer: _budgets(),
              ),
            ),
            expanded: false,
          ),
          size: size,
        );
        for (final room in [const Size(0, 1), const Size(1, 1), size]) {
          await t.resize(room);
        }
        for (final fact in [
          'Resources',
          '12.345% used',
          'usage unknown',
          'models none',
          'no windows reported',
          'Timed out after 10 s.',
        ]) {
          expect(t.screen.text, contains(fact));
        }
      });
    }
  });

  test('a line per window, then providers with no windows or not read, in '
      'the answer order', () {
    expect(resourceLines(_budgets()), [
      'Read: 13:00:00 UTC · advisory snapshot',
      'claude · 5h: 12.345% used · reset 18:05 UTC · models unknown',
      'claude · 7d: 8% used · reset 2026-11-02 09:00 UTC · models opus',
      'claude · codex.secondary: usage unknown · reset unknown · models none',
      'gemini: no windows reported',
      'codex: unavailable · Timed out after 10 s.',
    ]);
  });

  test('no providers read and an answer of an older format', () {
    expect(
      resourceLines({
        'readAt': '2026-10-27T13:00:00.000Z',
        'providers': <Object?>[],
      }),
      ['Read: 13:00:00 UTC · advisory snapshot', 'No providers read.'],
    );
    expect(resourceLines(_older), ['Recorded in an older format; not shown.']);
  });

  test('a read-kind adapter cannot fold away any Resource report lines', () {
    final call = ToolCall(
      'resources',
      kind: 'read',
      status: 'completed',
      chord: ChordCall(
        tool: ChordTool.getBudgets,
        input: const {},
        answer: _budgets(),
      ),
    );
    final drawn = summary(call, false, width: 80);
    expect(headline(call).name, 'Resources');
    expect(headline(call).arg, isNull);
    expect(drawn.hidden, 0);
    expect(drawn.lines.join('\n'), contains('codex: unavailable'));
  });

  test('zero, a ninety-minute duration, and a reset on another day retain '
      'their meanings', () {
    expect(
      resourceLines({
        'readAt': '2026-10-28T00:00:00Z',
        'providers': [
          {
            'agent': 'codex',
            'windows': [
              {
                'name': 'primary',
                'usedPercent': 0,
                'windowSeconds': 5400,
                'resetsAt': '2026-10-27T23:59:00Z',
                'models': <String>[],
              },
            ],
          },
        ],
      }),
      [
        'Read: 00:00:00 UTC · advisory snapshot',
        'codex · 90m: 0% used · reset 2026-10-27 23:59 UTC · models none',
      ],
    );
  });

  test('an older-format answer stays one line in collapsed and expanded '
      'summaries', () {
    const call = ToolCall(
      'legacy-resources',
      status: 'completed',
      chord: ChordCall(tool: ChordTool.getBudgets, input: {}, answer: _older),
    );
    for (final expanded in [false, true]) {
      expect(summary(call, expanded).lines, [
        'Recorded in an older format; not shown.',
      ]);
    }
  });

  test('an answer whose time is no real one is of an older format, never a '
      'rolled-over date', () {
    expect(
      resourceLines({
        'readAt': '2026-02-30T25:61:00Z',
        'providers': <Object?>[],
      }),
      ['Recorded in an older format; not shown.'],
    );
    expect(
      resourceLines({
        'readAt': '2026-10-28T12:00:00Z',
        'providers': [
          {
            'agent': 'codex',
            'windows': [
              {
                'name': 'primary',
                'usedPercent': 1,
                'windowSeconds': 60,
                'resetsAt': '2026-04-31T12:00:00Z',
                'models': null,
              },
            ],
          },
        ],
      }),
      ['Recorded in an older format; not shown.'],
    );
  });
}
