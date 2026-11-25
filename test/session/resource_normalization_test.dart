// The original's tests/session/resource_normalization_test.ts: Codex and
// Claude limits as plain windows, never account identity.
import 'package:chord/session/budgets.dart';
import 'package:chord/session/resource_normalization.dart';
import 'package:test/test.dart';

const _account = {
  'account': {'type': 'chatgpt', 'email': 'excluded@example.test'},
};
const _bucket = {
  'primary': {
    'usedPercent': 12.345,
    'windowDurationMins': 60,
    'resetsAt': 1800000000,
  },
  'secondary': null,
};

Map<String, Object?> _json(ProviderLimits limits) => limits.toJson();

Map<String, Object?> _unknown(String name) => {
  'name': name,
  'usedPercent': null,
  'windowSeconds': null,
  'resetsAt': null,
  'models': null,
};

void main() {
  test('Codex windows keep the provider bucket names, map over legacy, and '
      'no account fields', () {
    final result = normalizeCodex(_account, {
      'rateLimits': _bucket,
      'rateLimitsByLimitId': {'codex': _bucket, 'codex_other': _bucket},
    });
    expect(_json(result), {
      'agent': 'codex',
      'windows': [
        for (final name in ['codex.primary', 'codex_other.primary'])
          {
            'name': name,
            'usedPercent': 12.345,
            'windowSeconds': 3600,
            'resetsAt': '2027-01-15T08:00:00.000Z',
            'models': null,
          },
      ],
    });
    expect('${_json(result)}', isNot(contains('excluded@example.test')));
  });

  test('Codex legacy, empty map, malformed windows or buckets and '
      'unsupported auth', () {
    final legacy = _json(
      normalizeCodex(_account, {
        'rateLimits': _bucket,
        'rateLimitsByLimitId': null,
      }),
    );
    expect((legacy['windows']! as List).single['name'], 'primary');
    expect(
      _json(
        normalizeCodex(_account, {
          'rateLimits': _bucket,
          'rateLimitsByLimitId': <String, Object?>{},
        }),
      ),
      {'agent': 'codex', 'windows': <Object?>[]},
    );
    final malformed = _json(
      normalizeCodex(_account, {
        'rateLimits': {
          'primary': {...?_bucket['primary'], 'usedPercent': 101},
          'secondary': _bucket['primary'],
        },
        'rateLimitsByLimitId': null,
      }),
    );
    expect((malformed['windows']! as List).first, _unknown('primary'));
    expect((malformed['windows']! as List).last['usedPercent'], 12.345);
    expect(
      _json(
        normalizeCodex(_account, {
          'rateLimits': _bucket,
          'rateLimitsByLimitId': {'codex': 'bad'},
        }),
      ),
      {'agent': 'codex', 'unavailable': 'Malformed rate-limit snapshot.'},
    );
    expect(
      normalizeCodex({
        'account': {'type': 'apiKey'},
      }, <String, Object?>{}),
      isA<ProviderUnavailable>(),
    );
    expect(
      normalizeCodex(_account, {'rateLimitsByLimitId': 'bad'}),
      isA<ProviderUnavailable>(),
    );
  });

  test('Claude names its windows, skips absent ones and keeps model scope, '
      'without session costs', () {
    final result = normalizeClaude({
      'rate_limits_available': true,
      'session': {'total_cost_usd': 1000},
      'rate_limits': {
        'five_hour': {'utilization': 0, 'resets_at': null},
        'seven_day': {'utilization': 100, 'resets_at': '2026-10-28T13:00:00Z'},
        'seven_day_opus': null,
        'model_scoped': [
          {'display_name': 'Opus', 'utilization': 25.125, 'resets_at': null},
        ],
      },
    });
    expect(_json(result), {
      'agent': 'claude',
      'windows': [
        {
          'name': 'five_hour',
          'usedPercent': 0,
          'windowSeconds': 18000,
          'resetsAt': null,
          'models': null,
        },
        {
          'name': 'seven_day',
          'usedPercent': 100,
          'windowSeconds': 604800,
          'resetsAt': '2026-10-28T13:00:00.000Z',
          'models': null,
        },
        {
          'name': 'model_scoped',
          'usedPercent': 25.125,
          'windowSeconds': 604800,
          'resetsAt': null,
          'models': ['Opus'],
        },
      ],
    });
    expect('${_json(result)}', isNot(contains('total_cost')));
  });

  test('Claude resets with an offset, with or without fractions, read in Z '
      'form', () {
    final result = normalizeClaude({
      'rate_limits_available': true,
      'rate_limits': {
        'five_hour': {
          'utilization': 42,
          'resets_at': '2026-10-29T14:40:00.454167+00:00',
        },
        'seven_day': {
          'utilization': 7,
          'resets_at': '2026-11-04T01:00:00+00:00',
        },
        'model_scoped': [
          {
            'display_name': 'Opus',
            'utilization': 3.5,
            'resets_at': '2026-11-04T03:00:00+02:00',
          },
        ],
      },
    });
    expect(
      [
        for (final window in _json(result)['windows']! as List)
          window['resetsAt'],
      ],
      [
        '2026-10-29T14:40:00.454Z',
        '2026-11-04T01:00:00.000Z',
        '2026-11-04T01:00:00.000Z',
      ],
    );
  });

  test('a malformed Claude reset still reads as an unknown window', () {
    expect(
      _json(
        normalizeClaude({
          'rate_limits_available': true,
          'rate_limits': {
            'five_hour': {
              'utilization': 1,
              'resets_at': '2026-10-29 14:40:00+00:00',
            },
            'seven_day': {
              'utilization': 1,
              'resets_at': '2026-10-29T14:40:00+0000',
            },
          },
        }),
      ),
      {
        'agent': 'claude',
        'windows': [_unknown('five_hour'), _unknown('seven_day')],
      },
    );
  });

  test('Claude unavailable, malformed and empty sources', () {
    expect(
      normalizeClaude({'rate_limits_available': false, 'rate_limits': null}),
      isA<ProviderUnavailable>(),
    );
    expect(normalizeClaude(<String, Object?>{}), isA<ProviderUnavailable>());
    expect(
      _json(
        normalizeClaude({
          'rate_limits_available': true,
          'rate_limits': <String, Object?>{},
        }),
      ),
      {'agent': 'claude', 'windows': <Object?>[]},
    );
    expect(
      _json(
        normalizeClaude({
          'rate_limits_available': true,
          'rate_limits': {
            'five_hour': {'utilization': -1, 'resets_at': 'malformed'},
            'model_scoped': 'invalid',
          },
        }),
      ),
      {
        'agent': 'claude',
        'windows': [_unknown('five_hour'), _unknown('model_scoped')],
      },
    );
  });

  test('Codex keeps genuine zero while unknown duration and reset stay '
      'null', () {
    expect(
      _json(
        normalizeCodex(_account, {
          'rateLimits': {
            'primary': {
              'usedPercent': 0,
              'windowDurationMins': null,
              'resetsAt': null,
            },
            'secondary': null,
          },
          'rateLimitsByLimitId': null,
        }),
      ),
      {
        'agent': 'codex',
        'windows': [
          {
            'name': 'primary',
            'usedPercent': 0,
            'windowSeconds': null,
            'resetsAt': null,
            'models': null,
          },
        ],
      },
    );
  });

  test('the quota map accepts 64 buckets and refuses 65 rather than '
      'silently clipping', () {
    Map<String, Object?> limits(int length) => {
      'rateLimits': _bucket,
      'rateLimitsByLimitId': {
        for (var index = 0; index < length; index++) 'bucket$index': _bucket,
      },
    };
    final accepted = normalizeCodex(_account, limits(64)) as ProviderWindows;
    expect(accepted.windows, hasLength(64));
    expect(accepted.windows.last.name, 'bucket63.primary');
    expect(_json(normalizeCodex(_account, limits(65))), {
      'agent': 'codex',
      'unavailable': 'The quota map exceeds the supported bound.',
    });
  });

  test('malformed Claude availability never lets otherwise valid usage '
      'become a limit', () {
    for (final availability in [null, 'true', 1]) {
      expect(
        _json(
          normalizeClaude({
            'rate_limits_available': availability,
            'rate_limits': {
              'five_hour': {'utilization': 0, 'resets_at': null},
            },
          }),
        ),
        {
          'agent': 'claude',
          'unavailable': 'Malformed experimental usage snapshot.',
        },
        reason: '$availability',
      );
    }
  });

  for (final (raw, reset) in [
    ('2027-01-01T00:15:00.123456+05:30', '2026-12-31T18:45:00.123Z'),
    ('2026-12-31T23:15:00-03:30', '2027-01-01T02:45:00.000Z'),
  ]) {
    test('normalizes $raw across the year boundary in fixed and model '
        'windows', () {
      final result = normalizeClaude({
        'rate_limits_available': true,
        'rate_limits': {
          'five_hour': {'utilization': 0, 'resets_at': raw},
          'seven_day_sonnet': {'utilization': 100, 'resets_at': raw},
          'model_scoped': [
            {'display_name': 'Sonnet', 'utilization': 12.5, 'resets_at': raw},
          ],
        },
      });
      expect(
        [
          for (final window in _json(result)['windows']! as List)
            window['resetsAt'],
        ],
        [reset, reset, reset],
      );
    });
  }

  test('malformed resets leave fixed and model windows unknown without '
      'losing a valid sibling', () {
    for (final raw in <Object?>[
      '',
      '2026-02-30T14:40:00+00:00',
      '2026-10-29T14:40:00',
      '2026-10-29T14:40:00+00:60',
      1800000000,
    ]) {
      expect(
        _json(
          normalizeClaude({
            'rate_limits_available': true,
            'rate_limits': {
              'five_hour': {'utilization': 16, 'resets_at': raw},
              'seven_day': {'utilization': 25, 'resets_at': null},
              'model_scoped': [
                {'display_name': 'Sonnet', 'utilization': 16, 'resets_at': raw},
              ],
            },
          }),
        ),
        {
          'agent': 'claude',
          'windows': [
            _unknown('five_hour'),
            {
              'name': 'seven_day',
              'usedPercent': 25,
              'windowSeconds': 604800,
              'resetsAt': null,
              'models': null,
            },
            _unknown('model_scoped'),
          ],
        },
        reason: '$raw',
      );
    }
    // A reset left out is no reset given.
    expect(
      _json(
        normalizeClaude({
          'rate_limits_available': true,
          'rate_limits': {
            'five_hour': {'utilization': 16},
          },
        }),
      ),
      {
        'agent': 'claude',
        'windows': [_unknown('five_hour')],
      },
    );
  });
}
