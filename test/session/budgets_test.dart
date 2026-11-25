// The checks of what get_budgets answers, as the original's
// tests/session/budgets_test.ts reads them.
import 'package:chord/session/budgets.dart';
import 'package:test/test.dart';

const Map<String, Object?> _window = {
  'name': 'primary',
  'usedPercent': 0,
  'windowSeconds': null,
  'resetsAt': null,
  'models': null,
};

Map<String, Object?> _answer(List<Object?> providers) => {
  'readAt': '2026-10-28T12:00:00Z',
  'providers': providers,
};

bool _windowPasses(Map<String, Object?> window) =>
    budgetsOf(
      _answer([
        {
          'agent': 'codex',
          'windows': [window],
        },
      ]),
    ) !=
    null;

void main() {
  group('CTUI-37 tester: strict budget reference boundaries', () {
    test('model IDs and list caps use the original UTF-16 boundaries', () {
      expect(
        _windowPasses({..._window, 'models': List.filled(128, 'm')}),
        isTrue,
      );
      expect(
        _windowPasses({..._window, 'models': List.filled(129, 'm')}),
        isFalse,
      );
      expect(
        _windowPasses({
          ..._window,
          'models': ['😀' * 64],
        }),
        isTrue,
      );
      expect(
        _windowPasses({
          ..._window,
          'models': ['😀' * 65],
        }),
        isFalse,
      );
      expect(
        _windowPasses({
          ..._window,
          'models': [''],
        }),
        isFalse,
      );
      expect(_windowPasses({..._window, 'future': true}), isFalse);
      for (final (text, accepted) in [
        ('x' * 500, true),
        ('x' * 501, false),
        ('', false),
      ]) {
        expect(
          budgetsOf(
                _answer([
                  {'agent': 'codex', 'unavailable': text},
                ]),
              ) !=
              null,
          accepted,
        );
      }
    });
  });

  test('real zero, full usage and unknown usage remain distinct without '
      'legacy fields', () {
    for (final used in [0, 100, null]) {
      final read = budgetsOf(
        _answer([
          {
            'agent': 'codex',
            'windows': [
              {..._window, 'usedPercent': used},
            ],
          },
        ]),
      );
      expect(
        (read!.providers.single as ProviderWindows).windows.single.usedPercent,
        used,
      );
    }
    final answer = _answer([
      {
        'agent': 'codex',
        'windows': [_window],
      },
    ]);
    expect(budgetsJson(budgetsOf(answer)!), answer);
    for (final obsolete in [
      'activeRuns',
      'preferences',
      'freshness',
      'warnings',
    ]) {
      expect(budgetsOf({...answer, obsolete: <Object?>[]}), isNull);
    }
    expect(
      budgetsOf(
        _answer([
          {'agent': 'claude', 'windows': <Object?>[], 'unavailable': 'x'},
        ]),
      ),
      isNull,
    );
  });

  test('provider and window count caps accept their boundary and reject '
      'overflow', () {
    final windows = List.filled(256, _window);
    expect(
      budgetsOf(
        _answer([
          {'agent': 'codex', 'windows': windows},
        ]),
      ),
      isNotNull,
    );
    expect(
      budgetsOf(
        _answer([
          {
            'agent': 'codex',
            'windows': [...windows, _window],
          },
        ]),
      ),
      isNull,
    );
    final providers = List.filled(128, {
      'agent': 'codex',
      'windows': <Object?>[],
    });
    expect(budgetsOf(_answer(providers)), isNotNull);
    expect(
      budgetsOf(
        _answer([
          ...providers,
          {'agent': 'claude', 'windows': <Object?>[]},
        ]),
      ),
      isNull,
    );
  });

  test('invalid percentages and durations cannot silently become known '
      'limits', () {
    for (final used in [-1, 101, double.infinity, double.nan]) {
      expect(_windowPasses({..._window, 'usedPercent': used}), isFalse);
    }
    for (final seconds in [0, -1, double.infinity, double.nan]) {
      expect(_windowPasses({..._window, 'windowSeconds': seconds}), isFalse);
    }
  });

  test('a window names every field, null for one not said; a time is UTC '
      'ISO', () {
    expect(_windowPasses({..._window}..remove('models')), isFalse);
    expect(_windowPasses({..._window, 'resetsAt': 'tomorrow'}), isFalse);
    expect(
      _windowPasses({..._window, 'resetsAt': '2026-10-28T12:00:00.000Z'}),
      isTrue,
    );
    expect(isoTime(DateTime.utc(2026, 10, 27, 13)), '2026-10-27T13:00:00.000Z');
  });

  // Recorded from the original's Budgets under bun (zod v4's
  // z.iso.datetime() with its defaults), as readAt and as a window's
  // resetsAt: a real Gregorian date, seconds required, Z only.
  test("a time is accepted exactly where the original's check accepts "
      'it', () {
    const table = {
      '2026-02-30T12:00:00Z': false,
      '2026-13-01T12:00:00Z': false,
      '2026-04-31T12:00:00Z': false,
      '2026-10-28T25:00:00Z': false,
      '2026-10-28T23:60:00Z': false,
      '2026-10-28T23:59:60Z': false,
      '2026-02-29T12:00:00Z': false,
      '2100-02-29T12:00:00Z': false,
      '2024-02-29T12:00:00Z': true,
      '2000-02-29T12:00:00Z': true,
      '2026-10-28T12:00Z': false,
      '2026-10-28T12:00:00Z': true,
      '2026-10-28T12:00:00.5Z': true,
      '2026-10-28T12:00:00.123456789Z': true,
      '2026-10-28T12:00:00+00:00': false,
      '2026-10-28T12:00:00': false,
      '2026-10-28 12:00:00Z': false,
      '2026-02-30T25:61:00Z': false,
      '2026-12-31T23:59:59.999Z': true,
      '0000-02-29T00:00:00Z': true,
    };
    for (final MapEntry(key: time, value: accepted) in table.entries) {
      expect(
        budgetsOf({'readAt': time, 'providers': <Object?>[]}) != null,
        accepted,
        reason: 'readAt $time',
      );
      expect(
        _windowPasses({..._window, 'resetsAt': time}),
        accepted,
        reason: 'resetsAt $time',
      );
    }
  });
}
