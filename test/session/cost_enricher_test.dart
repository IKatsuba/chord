// chord's estimate of a session's cost: the original's costFromTokens cases
// in tests/session/enrichers_test.ts.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/enrich.dart';
import 'package:chord/session/enrichers.dart';
import 'package:chord/session/prices.dart';
import 'package:test/test.dart';

const _session = 'session-1';

const _tokens = {
  'inputTokens': 1000,
  'outputTokens': 200,
  'cachedReadTokens': 800,
  'totalTokens': 2000,
};

Map<String, Object?> _model(String current) => {
  'id': 'model',
  'name': 'Model',
  'category': 'model',
  'type': 'select',
  'currentValue': current,
  'options': [
    {'value': current, 'name': current},
  ],
};

/// A relay running [costFromTokens] on a session `session/new` opened with
/// [configOptions], and a way to play prompts and updates through it.
class _Relay {
  _Relay({
    List<Map<String, Object?>>? configOptions,
    Map<String, Object?> extra = const {},
    bool totals = false,
    List<Enricher> chain = const [costFromTokens],
  }) : relay = enricherRelay(chain, totals: totals) {
    _ask(
      'session/new',
      {'cwd': '/'},
      {
        'sessionId': _session,
        'configOptions': configOptions ?? [_model('gpt-5.3-codex')],
        ...extra,
      },
    );
  }

  final EnricherRelay relay;
  var _id = 0;

  List<Message> _ask(String method, Object? params, Object? result) {
    _id += 1;
    relay.fromChord({
      'jsonrpc': '2.0',
      'id': _id,
      'method': method,
      'params': params,
    });
    return relay.fromAgent({'jsonrpc': '2.0', 'id': _id, 'result': result});
  }

  List<Message> update(Map<String, Object?> update) => relay.fromAgent({
    'jsonrpc': '2.0',
    'method': 'session/update',
    'params': {'sessionId': _session, 'update': update},
  });

  List<Message> prompt([Map<String, num>? usage]) => _ask(
    'session/prompt',
    {'sessionId': _session, 'prompt': []},
    {'stopReason': 'end_turn', 'usage': ?usage},
  );
}

List<Map<String, Object?>> _updates(List<Message> messages) => [
  for (final message in messages)
    if (message['method'] == 'session/update')
      (message['params'] as Map)['update'] as Map<String, Object?>,
];

num? _amount(List<Message> out) {
  final updates = _updates(out);
  if (updates.isEmpty || updates.first['sessionUpdate'] != 'usage_update') {
    return null;
  }
  return ((updates.first['cost'] as Map?)?['amount']) as num?;
}

Map<String, num> _times(int count) => {
  for (final MapEntry(:key, :value) in _tokens.entries) key: value * count,
};

double _price(String model, [int count = 1]) => turnCost(model, _times(count))!;

void main() {
  group('tester: CTUI-29 window estimation boundaries', () {
    test(
      'estimated windows follow model switches until an agent supplies its own',
      () {
        final relay = _Relay(chain: const [costFromTokens, windowFromModel]);
        final first = _updates(relay.prompt(_tokens)).single;
        expect(first['size'], contextWindow('gpt-5.3-codex'));
        relay.update({
          'sessionUpdate': 'config_option_update',
          'configOptions': [_model('claude-haiku-4-5')],
        });
        final next = _updates(relay.prompt(_tokens)).single;
        expect(next['size'], contextWindow('claude-haiku-4-5'));
        relay.update({
          'sessionUpdate': 'usage_update',
          'used': 15,
          'size': 12345,
        });
        relay.update({
          'sessionUpdate': 'config_option_update',
          'configOptions': [_model('gpt-5.3-codex')],
        });
        final own = _updates(relay.prompt(_tokens)).single;
        expect(own['size'], 12345);
        expect(((own['_meta'] as Map)['chord/filled'] as List), ['cost']);
      },
    );

    test(
      'a fractional positive window is authoritative and unrelated metadata is preserved',
      () {
        final relay = _Relay(chain: const [windowFromModel]);
        final out = _updates(
          relay.update({
            'sessionUpdate': 'usage_update',
            'used': 0,
            'size': 0.5,
            '_meta': {'unrelated': 'kept'},
          }),
        ).single;
        expect(out['size'], 0.5);
        expect(out['_meta'], {'unrelated': 'kept'});
        final missing = _updates(
          relay.update({
            'sessionUpdate': 'usage_update',
            'used': 0,
            'size': 0,
            '_meta': {'unrelated': 'kept'},
          }),
        ).single;
        expect(missing['size'], contextWindow('gpt-5.3-codex'));
        expect((missing['_meta'] as Map)['unrelated'], 'kept');
        expect((missing['_meta'] as Map)['chord/filled'], ['size']);
      },
    );
  });
  group('tester: CTUI-29 cost enrichment ownership', () {
    test(
      'the estimate precedes the unchanged answer and cannot double-count a repeated reply',
      () {
        final relay = _Relay();
        final out = relay.prompt(_tokens);
        expect(out, hasLength(2));
        expect(out.first['method'], 'session/update');
        expect((out.last['result'] as Map)['usage'], _tokens);
        expect(_amount(out), closeTo(_price('gpt-5.3-codex'), 1e-12));
        expect(_updates(relay.relay.fromAgent(out.last)), isEmpty);
        expect(
          _amount(relay.prompt(_tokens)),
          closeTo(_price('gpt-5.3-codex', 2), 1e-12),
        );
      },
    );

    test(
      'a refused prompt does not replace the last cumulative token baseline',
      () {
        final relay = _Relay(totals: true);
        relay.prompt(_times(1));
        relay.relay.fromChord({
          'jsonrpc': '2.0',
          'id': 'refused',
          'method': 'session/prompt',
          'params': {'sessionId': _session, 'prompt': []},
        });
        final out = relay.relay.fromAgent({
          'jsonrpc': '2.0',
          'id': 'refused',
          'error': {'code': -32603, 'message': 'no turn'},
        });
        expect(_updates(out), isEmpty);
        expect(
          _amount(relay.prompt(_times(3))),
          closeTo(_price('gpt-5.3-codex', 3), 1e-12),
        );
      },
    );

    test(
      'recall owns only its session and authoritative cost cannot suppress another session estimate',
      () {
        final relay = enricherRelay([costFromTokens], totals: true);
        var id = 0;
        List<Message> ask(
          String session,
          String method,
          Map<String, Object?> result,
        ) {
          final request = ++id;
          relay.fromChord({
            'jsonrpc': '2.0',
            'id': request,
            'method': method,
            'params': {'sessionId': session, 'cwd': '/', 'prompt': []},
          });
          return relay.fromAgent({
            'jsonrpc': '2.0',
            'id': request,
            'result': result,
          });
        }

        for (final session in ['one', 'two']) {
          ask(session, 'session/new', {
            'sessionId': session,
            'configOptions': [_model('gpt-5.3-codex')],
          });
        }
        relay.recall('one', [
          acp.SessionUpdate.fromJson({
            'sessionUpdate': 'usage_update',
            'used': 10,
            'size': 100,
            'cost': {'amount': 3, 'currency': 'USD'},
          }),
        ], total: _times(2));
        expect(
          _updates(
            ask('one', 'session/prompt', {
              'stopReason': 'end_turn',
              'usage': _times(3),
            }),
          ),
          isEmpty,
        );
        expect(
          _amount(
            ask('two', 'session/prompt', {
              'stopReason': 'end_turn',
              'usage': _times(1),
            }),
          ),
          closeTo(_price('gpt-5.3-codex'), 1e-12),
        );
        expect(
          _amount(
            ask('two', 'session/prompt', {
              'stopReason': 'end_turn',
              'usage': _times(2),
            }),
          ),
          closeTo(_price('gpt-5.3-codex', 2), 1e-12),
        );
      },
    );

    test(
      'an unpriced total still becomes the baseline for the next priced model',
      () {
        final relay = _Relay(
          configOptions: [_model('unpriced-model')],
          totals: true,
        );
        expect(_updates(relay.prompt(_times(2))), isEmpty);
        relay.update({
          'sessionUpdate': 'config_option_update',
          'configOptions': [_model('gpt-5.3-codex')],
        });
        expect(
          _amount(relay.prompt(_times(3))),
          closeTo(_price('gpt-5.3-codex'), 1e-12),
        );
      },
    );
  });
  group("chord's estimate on an agent whose answers give the session's "
      'running total', () {
    _Relay totals([String model = 'gpt-5.3-codex']) =>
        _Relay(configOptions: [_model(model)], totals: true);
    void switchTo(_Relay relay, String model) => relay.update({
      'sessionUpdate': 'config_option_update',
      'configOptions': [_model(model)],
    });

    test('each answer has what the total grew by priced, and added', () {
      final relay = totals();
      expect(
        _amount(relay.prompt(_times(1))),
        closeTo(_price('gpt-5.3-codex'), 1e-12),
      );
      expect(
        _amount(relay.prompt(_times(3))),
        closeTo(_price('gpt-5.3-codex', 3), 1e-12),
      );
    });

    for (final (first, then) in [
      ('gpt-5.3-codex', 'claude-haiku-4-5'),
      ('claude-haiku-4-5', 'gpt-5.3-codex'),
    ]) {
      test('after a switch from $first to $then, what grew since is priced '
          'at $then', () {
        final relay = totals(first);
        relay.prompt(_times(1));
        switchTo(relay, then);
        expect(
          _amount(relay.prompt(_times(2))),
          closeTo(_price(first) + _price(then), 1e-12),
        );
      });
    }

    test('a total that fell adds nothing, and the next grows from it', () {
      final relay = totals();
      relay.prompt(_times(3));
      expect(
        _amount(relay.prompt(_times(1))),
        closeTo(_price('gpt-5.3-codex', 3), 1e-12),
      );
      expect(
        _amount(relay.prompt(_times(2))),
        closeTo(_price('gpt-5.3-codex', 4), 1e-12),
      );
    });

    test('reopened from the record, it goes on from the estimate and the '
        'total the record kept', () {
      final relay = totals();
      relay.relay.recall(_session, [
        acp.SessionUpdate.fromJson({
          'sessionUpdate': 'usage_update',
          'used': 4000,
          'size': 400000,
          'cost': {'amount': _price('gpt-5.3-codex', 2), 'currency': 'USD'},
          '_meta': {
            'chord/filled': ['cost'],
          },
        }),
      ], total: _times(2));
      expect(
        _amount(relay.prompt(_times(3))),
        closeTo(_price('gpt-5.3-codex', 3), 1e-12),
      );
    });

    test("an agent whose answers are its turns' own adds each whole", () {
      final relay = _Relay();
      relay.prompt(_times(1));
      expect(
        _amount(relay.prompt(_times(3))),
        closeTo(_price('gpt-5.3-codex', 4), 1e-12),
      );
    });
  });

  test("each turn adds to the estimate, and an agent's own cost stops it", () {
    final relay = _Relay();
    final cost = turnCost('gpt-5.3-codex', _tokens)!;
    relay.prompt(_tokens);
    expect(_amount(relay.prompt(_tokens)), cost * 2);
    final own = _updates(
      relay.update({
        'sessionUpdate': 'usage_update',
        'used': 5000,
        'size': 400000,
      }),
    ).single;
    expect(own, {
      'sessionUpdate': 'usage_update',
      'used': 5000,
      'size': 400000,
      'cost': {'amount': cost * 2, 'currency': 'USD'},
      '_meta': {
        'chord/filled': ['cost'],
      },
    });
    relay.update({
      'sessionUpdate': 'usage_update',
      'used': 6000,
      'size': 400000,
      'cost': {'amount': 1, 'currency': 'USD'},
    });
    expect(_updates(relay.prompt(_tokens)), isEmpty);
  });

  test('a priced turn keeps the context the agent last gave', () {
    final relay = _Relay();
    relay.update({
      'sessionUpdate': 'usage_update',
      'used': 3000,
      'size': 128000,
    });
    final priced = _updates(relay.prompt(_tokens)).first;
    expect(
      [priced['used'], priced['size'], priced['_meta']],
      [
        3000,
        128000,
        {
          'chord/filled': ['cost'],
        },
      ],
    );
  });

  test('with no context given, the turn makes it, both marked filled', () {
    final priced = _updates(_Relay().prompt(_tokens)).first;
    expect(
      [priced['used'], priced['size'], priced['_meta']],
      [
        contextFrom(_tokens),
        0,
        {
          'chord/filled': ['used', 'cost'],
        },
      ],
    );
  });

  test('no estimate for a model the data does not know, a turn with no '
      'tokens, or no model', () {
    expect(
      _updates(_Relay(configOptions: [_model('fake-large')]).prompt(_tokens)),
      isEmpty,
    );
    expect(_updates(_Relay().prompt()), isEmpty);
    expect(_updates(_Relay(configOptions: []).prompt(_tokens)), isEmpty);
  });

  test("a model the older way, by session/new's models, is priced too", () {
    final relay = _Relay(
      configOptions: [],
      extra: {
        'models': {
          'currentModelId': 'claude-haiku-4-5',
          'availableModels': [
            {'modelId': 'claude-haiku-4-5', 'name': 'Haiku'},
          ],
        },
      },
    );
    expect(_updates(relay.prompt(_tokens)), hasLength(1));
  });

  test('a session reopened from its record goes on from the estimate it '
      'had', () {
    final relay = _Relay();
    final cost = turnCost('gpt-5.3-codex', _tokens)!;
    relay.relay.recall(_session, [
      acp.SessionUpdate.fromJson({
        'sessionUpdate': 'usage_update',
        'used': 2000,
        'size': 400000,
        'cost': {'amount': 0.5, 'currency': 'USD'},
        '_meta': {
          'chord/filled': ['cost'],
        },
      }),
    ]);
    expect(_amount(relay.prompt(_tokens)), 0.5 + cost);
  });
  test("a turn priced from its tokens goes ahead of its answer, marked as "
      "chord's, with the model's window", () {
    final out = _Relay(
      chain: const [costFromTokens, windowFromModel],
    ).prompt(_tokens);
    expect(out, hasLength(2));
    expect(out.last.containsKey('result'), isTrue);
    expect(_updates(out), [
      {
        'sessionUpdate': 'usage_update',
        'used': 2000,
        'size': 400000,
        'cost': {
          'amount': turnCost('gpt-5.3-codex', _tokens),
          'currency': 'USD',
        },
        '_meta': {
          'chord/filled': ['used', 'cost', 'size'],
        },
      },
    ]);
  });

  test("a usage_update with no window gets the model's, and one with a "
      'window keeps it', () {
    final relay = _Relay(chain: const [windowFromModel]);
    expect(
      _updates(
        relay.update({'sessionUpdate': 'usage_update', 'used': 10, 'size': 0}),
      ),
      [
        {
          'sessionUpdate': 'usage_update',
          'used': 10,
          'size': 400000,
          '_meta': {
            'chord/filled': ['size'],
          },
        },
      ],
    );
    expect(
      _updates(
        relay.update({'sessionUpdate': 'usage_update', 'used': 10, 'size': 64}),
      ),
      [
        {'sessionUpdate': 'usage_update', 'used': 10, 'size': 64},
      ],
    );
    final unknown = _Relay(
      configOptions: [_model('fake-large')],
      chain: const [windowFromModel],
    );
    expect(
      _updates(
        unknown.update({'sessionUpdate': 'usage_update', 'used': 1, 'size': 0}),
      ),
      [
        {'sessionUpdate': 'usage_update', 'used': 1, 'size': 0},
      ],
    );
  });
}
