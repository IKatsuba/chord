import 'package:chord/session/servers.dart';
import 'package:test/test.dart';

const _stdio = {
  'name': 'files',
  'command': 'files-mcp',
  'args': <Object?>[],
  'env': <Object?>[],
};
const _http = {
  'type': 'http',
  'name': 'docs',
  'url': 'https://docs',
  'headers': <Object?>[],
};
const _sse = {
  'type': 'sse',
  'name': 'events',
  'url': 'https://events',
  'headers': <Object?>[],
};
const _acp = {'type': 'acp', 'name': 'peer', 'serverId': 'p'};

void main() {
  chordServerTests();
  testerChordServerTests();
  test('a stdio-only agent takes stdio servers and holds back the rest, '
      'saying what it takes', () {
    final (:servers, :heldBack, chord: _) = serversFor(
      'codex',
      {'http': false, 'sse': false},
      [_http, _stdio, _sse, _acp],
    );
    expect(servers, [_stdio]);
    expect(
      [for (final held in heldBack) held.toJson()],
      [
        {
          'server': 'docs',
          'agent': 'codex',
          'transport': 'http',
          'takes': ['stdio'],
        },
        {
          'server': 'events',
          'agent': 'codex',
          'transport': 'sse',
          'takes': ['stdio'],
        },
        {
          'server': 'peer',
          'agent': 'codex',
          'transport': 'acp',
          'takes': ['stdio'],
        },
      ],
    );
  });

  test('an HTTP and SSE agent takes those too, in the order given', () {
    final (:servers, :heldBack, chord: _) = serversFor(
      'claude',
      {'http': true, 'sse': true},
      [_http, _stdio, _sse, _acp],
    );
    expect(servers, [_http, _stdio, _sse]);
    expect(heldBack.single.transport, 'acp');
    expect(heldBack.single.takes, ['stdio', 'http', 'sse']);
  });

  test('only a transport advertised true counts, none without the '
      'capability', () {
    expect(serversFor('a', {'http': 'yes'}, [_http]).heldBack.single.takes, [
      'stdio',
    ]);
    expect(serversFor('a', null, [_http, _stdio]).servers, [_stdio]);
  });

  test('--no-mcp-servers holds back every one, saying so', () {
    final (:servers, :heldBack, chord: _) = serversFor(
      'claude',
      {'http': true},
      [_stdio, _http],
      none: true,
      from: noMcpServersFlag,
    );
    expect(servers, isEmpty);
    expect(heldBack.first.toJson(), {
      'server': 'files',
      'agent': 'claude',
      'transport': 'stdio',
      'takes': <String>[],
      'from': '--no-mcp-servers',
    });
  });

  group('the start line says what an agent was not given', () {
    final tracker = {..._sse, 'name': 'tracker'};
    final docs = {..._http, 'name': 'docs'};
    final all = [_stdio, docs, tracker, _acp];
    String? line(
      Map<String, Object?>? capabilities,
      List<Map<String, Object?>> servers,
    ) => heldBackLine(serversFor('fake', capabilities, servers).heldBack);
    // chord's own server waits for M4; its words are kept as the original's.
    HeldBack own(List<String> takes, {String? from}) => HeldBack(
      server: 'chord',
      agent: 'fake',
      transport: 'http',
      takes: takes,
      from: from,
      own: true,
    );

    test(
      'stdio alone names each with its transport, chord first, and what losing it costs',
      () {
        final held = serversFor('fake', null, [_stdio, docs, tracker]).heldBack;
        expect(
          heldBackLine([
            ...held,
            own(const ['stdio']),
          ]),
          '3 MCP servers were not passed to fake, which takes them over stdio '
          "only: chord (http, chord's own), docs (http), tracker (sse). "
          "Without chord's own, fake cannot start other agents or use chord's "
          'tools. /mcp lists them.',
        );
      },
    );

    test(
      'each transport the agent takes is named; lacking two or more, the names carry theirs',
      () {
        expect(
          line({'http': true}, [_stdio, tracker]),
          '1 MCP server was not passed to fake, which takes them over stdio and '
          'HTTP only: tracker (sse). /mcp lists it.',
        );
        expect(
          line({'sse': true}, [docs, tracker]),
          '1 MCP server was not passed to fake, which takes them over stdio and '
          'SSE only: docs (http). /mcp lists it.',
        );
        expect(
          line({'acp': true}, all),
          '2 MCP servers were not passed to fake, which takes them over stdio and '
          'ACP only: docs (http), tracker (sse). /mcp lists them.',
        );
      },
    );

    test('lacking one transport, the names go bare', () {
      expect(
        line({'http': true, 'sse': true}, all),
        '1 MCP server was not passed to fake, which takes them over stdio, '
        'HTTP and SSE only: peer. /mcp lists it.',
      );
      expect(
        line({'http': true, 'acp': true}, all),
        '1 MCP server was not passed to fake, which takes them over stdio, '
        'HTTP and ACP only: tracker. /mcp lists it.',
      );
    });

    test("chord's own alone is 'it'", () {
      expect(
        heldBackLine([
          own(const ['stdio']),
        ]),
        '1 MCP server was not passed to fake, which takes them over stdio '
        "only: chord (http, chord's own). Without it, fake cannot start "
        "other agents or use chord's tools. /mcp lists it.",
      );
    });

    test('nothing is said when every server went', () {
      expect(line({'http': true, 'sse': true, 'acp': true}, all), isNull);
      expect(heldBackLine(const []), isNull);
    });

    test('an agent set to take none says so, the names bare', () {
      expect(
        heldBackLine(
          serversFor(
            'openclaw',
            {'http': true},
            [docs, _stdio],
            none: true,
            from: '/p.json',
          ).heldBack,
        ),
        '2 MCP servers were not passed to openclaw, which takes none: docs, '
        'files. /mcp lists them.',
      );
    });

    test('--no-mcp-servers held them back, named as the flag', () {
      expect(
        heldBackLine(
          serversFor(
            'fake',
            {'http': true},
            [_stdio],
            none: true,
            from: noMcpServersFlag,
          ).heldBack,
        ),
        '--no-mcp-servers held back 1 MCP server from fake: files. /mcp lists it.',
      );
      final held = serversFor(
        'fake',
        {'http': true},
        [_stdio, docs],
        none: true,
        from: noMcpServersFlag,
      ).heldBack;
      expect(
        heldBackLine([own(const [], from: noMcpServersFlag), ...held]),
        '--no-mcp-servers held back 3 MCP servers from fake: chord '
        "(chord's own), files, docs. Without chord's own, fake cannot "
        "start other agents or use chord's tools. /mcp lists them.",
      );
    });

    test('the transports read as a list', () {
      expect(takenWords(['stdio']), 'stdio');
      expect(takenWords(['stdio', 'http']), 'stdio and HTTP');
      expect(takenWords(['stdio', 'sse', 'acp']), 'stdio, SSE and ACP');
    });
  });
}

const _chord = {
  'type': 'http',
  'name': 'chord',
  'url': 'http://127.0.0.1:9/mcp',
  'headers': [
    {'name': 'Authorization', 'value': 'Bearer token'},
  ],
};

Map<String, Object?> _user(String name) => {
  ..._chord,
  'name': name,
  'url': 'u',
};

void chordServerTests() {
  group("chord's own server", () {
    for (final (label, capabilities) in <(String, Map<String, Object?>?)>[
      ('nothing', null),
      ('none past stdio', {}),
      ('http alone', {'http': true}),
      ('http, sse said false', {'http': true, 'sse': false}),
    ]) {
      test('goes last to an agent advertising http, else is held back as '
          'its own: $label', () {
        final http = capabilities?['http'] == true;
        final given = serversFor('fake', capabilities, [
          _stdio,
          _http,
        ], chord: _chord);
        expect(given.servers, [_stdio, if (http) _http, if (http) _chord]);
        expect(given.chord, http ? _chord : isNull);
        expect(
          [for (final h in given.heldBack) h.toJson()],
          [
            if (!http) ...[
              {
                'server': 'docs',
                'agent': 'fake',
                'transport': 'http',
                'takes': ['stdio'],
              },
              {
                'server': 'chord',
                'agent': 'fake',
                'transport': 'http',
                'takes': ['stdio'],
                'own': true,
              },
            ],
          ],
        );
      });
    }

    test('takes the first free name among the servers that go', () {
      expect(
        serversFor(
          'fake',
          {'http': true},
          [_user('docs')],
          chord: _chord,
        ).servers,
        [_user('docs'), _chord],
      );
      final given = serversFor(
        'fake',
        {'http': true},
        [_user('chord'), _user('chord-2')],
        chord: _chord,
      );
      expect(given.servers, [
        _user('chord'),
        _user('chord-2'),
        {..._chord, 'name': 'chord-3'},
      ]);
      expect(given.chord, {..._chord, 'name': 'chord-3'});
      // A user's `chord` held back takes no name from chord's own.
      expect(
        serversFor(
          'fake',
          {'http': true},
          [
            {..._sse, 'name': 'chord'},
          ],
          chord: _chord,
        ).chord,
        _chord,
      );
    });

    test('an agent set to take none is given not even chord\'s own, saying '
        'what set it', () {
      final given = serversFor(
        'fake',
        {'http': true},
        [_http],
        chord: _chord,
        none: true,
        from: noMcpServersFlag,
      );
      expect(given.servers, isEmpty);
      expect(given.chord, isNull);
      expect(given.heldBack.last.toJson(), {
        'server': 'chord',
        'agent': 'fake',
        'transport': 'http',
        'takes': <String>[],
        'from': noMcpServersFlag,
        'own': true,
      });
      expect(
        heldBackLine(given.heldBack),
        '$noMcpServersFlag held back 2 MCP servers from fake: chord '
        "(chord's own), docs. Without chord's own, fake cannot start other "
        "agents or use chord's tools. /mcp lists them.",
      );
    });

    test("chord's own alone is 'it'", () {
      expect(
        heldBackLine(serversFor('fake', {}, [_stdio], chord: _chord).heldBack),
        '1 MCP server was not passed to fake, which takes them over stdio '
        "only: chord (http, chord's own). Without it, fake cannot start "
        "other agents or use chord's tools. /mcp lists it.",
      );
    });
  });
}

void testerChordServerTests() {
  group('tester: own server capability and naming boundaries', () {
    test(
      'only literal true admits chord and none overrides every capability',
      () {
        for (final value in <Object?>[null, false, 0, 1, 'true', [], {}]) {
          final result = serversFor('fake', {'http': value}, [], chord: _chord);
          expect(result.chord, isNull);
          expect(result.servers, isEmpty);
          expect(result.heldBack.single.toJson(), {
            'server': 'chord',
            'agent': 'fake',
            'transport': 'http',
            'takes': ['stdio'],
            'own': true,
          });
        }
        final result = serversFor(
          'fake',
          {'http': true, 'sse': true, 'acp': true},
          [],
          chord: _chord,
          none: true,
          from: 'project settings',
        );
        expect(result.chord, isNull);
        expect(result.heldBack.single.toJson(), {
          'server': 'chord',
          'agent': 'fake',
          'transport': 'http',
          'takes': <String>[],
          'own': true,
          'from': 'project settings',
        });
      },
    );

    test('first naming gap wins without mutating caller maps or headers', () {
      final own = Map<String, Object?>.unmodifiable(_chord);
      final users = List<Map<String, Object?>>.unmodifiable([
        Map<String, Object?>.unmodifiable(_user('chord-3')),
        Map<String, Object?>.unmodifiable(_user('chord')),
        Map<String, Object?>.unmodifiable({..._sse, 'name': 'chord-2'}),
      ]);
      final result = serversFor('fake', {'http': true}, users, chord: own);
      expect(result.servers.map((server) => server['name']), [
        'chord-3',
        'chord',
        'chord-2',
      ]);
      expect(result.chord, same(result.servers.last));
      expect(result.chord!['headers'], same(own['headers']));
      expect(own['name'], 'chord');
      expect(users.map((server) => server['name']), [
        'chord-3',
        'chord',
        'chord-2',
      ]);
      expect(result.heldBack.single.own, isFalse);
    });

    test('absent own entry stays absent beside a user server named chord', () {
      final result = serversFor('fake', {'http': true}, [_user('chord')]);
      expect(result.chord, isNull);
      expect(result.servers, [_user('chord')]);
      expect(result.heldBack, isEmpty);
    });
  });
}
