import 'package:chord/mcp.dart';
import 'package:chord/session/servers.dart';
import 'package:chord/ui/pickers/mcp.dart';
import 'package:chord_tui/chord_tui.dart' show cellWidth;
import 'package:test/test.dart';

const _http = {
  'type': 'http',
  'url': 'https://mcp.example.com/mcp',
  'headers': {'Authorization': 'Bearer secret'},
};

List<ListedServer> _listed(List<DefinedServer> servers) => [
  for (final defined in servers) ListedServer(defined),
];

void main() {
  group('tester: own MCP admission precedence', () {
    test('an actually passed server wins over a stale held-back flag', () {
      final row = chordRow(
        const {
          'type': 'http',
          'name': 'chord',
          'url': 'http://127.0.0.1:4242/mcp',
          'headers': <Object?>[],
        },
        none: true,
        from: noMcpServersFlag,
      );
      expect(row.passed, isTrue);
      expect(row.none, isFalse);
      expect(row.from, isNull);
      expect(chordLine(row, 'fake'), startsWith("chord's server gives fake"));
      expect(chordLine(row, 'fake'), isNot(contains('held it back')));
    });

    test('a missing child server keeps the transport refusal reason', () {
      final row = chordRow(null, child: true);
      expect(row.child, isTrue);
      expect(row.server.server['url'], 'not passed');
      expect(
        chordLine(row, 'pi'),
        "chord's server was not passed: pi does not take MCP servers over HTTP, so it cannot start other agents.",
      );
      expect(row.tools, isNot(contains('open_agent')));
      expect(row.tools, isNot(contains('settings')));
    });
  });

  // CTUI-112: chord's own row and line, as the original's mcp_test and
  // tasks_test say them.
  group("chord's own server", () {
    const passedServer = {
      'type': 'http',
      'name': 'chord',
      'url': 'http://127.0.0.1:1/mcp',
      'headers': <Object?>[],
    };

    test('passed, missing and a child', () {
      final passed = chordRow(passedServer);
      final missing = chordRow(null);
      final child = chordRow(passedServer, child: true);
      expect(passed.server.from, 'chord itself');
      expect(
        chordLine(child, 'parser'),
        "chord's server gives parser list_agents, get_budgets, spawn_task, "
        'close_agent for its own tasks, monitor, stop_monitor and '
        'list_monitors, and send_message to main only.',
      );
      expect(
        chordLine(passed, 'claude'),
        "chord's server gives claude list_agents, get_budgets, "
        'list_sessions, list_teams, spawn_task, open_agent, run_team, '
        'propose_team, settings, send_message, close_agent, clear_agent, '
        'monitor, stop_monitor and list_monitors.',
      );
      expect(missing.server.server['url'], 'not passed');
      expect(
        chordLine(missing, 'pi'),
        "chord's server was not passed: pi does not take MCP servers over "
        'HTTP, so it cannot start other agents.',
      );
    });

    test('held back by an agent that takes none, and by the flag', () {
      expect(
        chordLine(chordRow(null, none: true), 'openclaw'),
        "chord's server was not passed: openclaw takes no MCP servers, so it "
        'cannot start other agents.',
      );
      expect(
        chordLine(chordRow(null, none: true, from: noMcpServersFlag), 'fake'),
        "chord's server was not passed: --no-mcp-servers on the command line "
        'held it back, so fake cannot start other agents.',
      );
    });
  });

  group('tester: CTUI-75 U3 list punctuation', () {
    test('four mixed losses retain order and use one final conjunction', () {
      expect(
        ignoredNote(const [
          Ignored('界🙂e\u0301.json', 0),
          Ignored('b.json', 1),
          Ignored('c.json', 2),
          Ignored('d.json'),
        ]),
        '0 servers in 界🙂e\u0301.json were ignored, '
        '1 server in b.json was ignored, 2 servers in c.json were ignored, '
        'and d.json was ignored; chord said why when it started.',
      );
    });
  });

  group('tester: CTUI-34 MCP Unicode targets', () {
    test(
      'cell wrapping never loses or splits a wide or combining grapheme',
      () {
        const target = '界🙂e\u0301界🙂e\u0301';
        for (var width = 1; width <= 12; width++) {
          final lines = wrapTarget(target, width);
          expect(lines.join(), target);
          for (final line in lines) {
            expect(line.startsWith('\u0301'), isFalse);
            expect(cellWidth(line), lessThanOrEqualTo(width < 2 ? 2 : width));
          }
        }
      },
    );
  });

  test('the rows fit the width and never show env or headers', () {
    final servers = mergeServers([
      parseServers('~/.config/chord/settings.json', {'docs': _http}).servers,
      parseServers('.mcp.json', {
        'filesystem': {
          'command': 'npx',
          'args': ['-y', 'a server', '.'],
          'env': {'TOKEN': 'secret'},
        },
      }).servers,
    ]);

    for (final width in [116, 76, 40]) {
      final (:headings, :rows) = mcpRows(_listed(servers), width);
      for (final line in [headings, ...rows.expand((row) => row)]) {
        expect(cellWidth(line), lessThanOrEqualTo(width), reason: line);
        expect(line, isNot(contains('secret')), reason: 'a header was shown');
      }
    }
    expect(targetOf(ListedServer(servers[1])), 'npx -y "a server" .');
  });

  test('a command wraps in its column rather than lose its end', () {
    final servers = parseServers('.mcp.json', {
      'memory': {
        'command': 'npx',
        'args': ['-y', '@modelcontextprotocol/server-memory'],
      },
    }).servers;
    final settings = parseServers('~/.config/chord/settings.json', {
      'docs': _http,
    }).servers;
    final wide = mcpRows(_listed([...settings, ...servers]), 116);
    final narrow = mcpRows(_listed([...settings, ...servers]), 76);

    expect([for (final row in wide.rows) row.length], [1, 1]);
    expect(narrow.rows[1], [
      'memory  stdio      npx -y                    .mcp.json',
      '                   @modelcontextprotocol/',
      '                   server-memory',
    ]);
    // The path is drawn whole, as it is short enough to be.
    expect(narrow.rows[0][0], endsWith('  ~/.config/chord/settings.json'));
  });

  test('a command breaks at spaces, then after slashes, then anywhere', () {
    expect(wrapTarget('https://mcp.example.com/mcp', 22), [
      'https://',
      'mcp.example.com/mcp',
    ]);
    expect(wrapTarget('uvx abcdefghij', 4), ['uvx', 'abcd', 'efgh', 'ij']);
    expect(wrapTarget('npx -y a', 40), ['npx -y a']);
  });

  test('a path too long for its column is cut from the left, at a '
      'separator', () {
    expect(
      cutPath('/tmp/chord-cfg.6XOm/chord/settings.json', 24),
      '…/chord/settings.json',
    );
    expect(cutPath('.mcp.json', 24), '.mcp.json');
    expect(cutPath('/a/settings.json', 8), '…gs.json');
  });

  test('the list keeps whole servers to its lines and counts the rest', () {
    final rows = [
      ['a'],
      ['b', 'b'],
      ['c'],
      ['d'],
    ];
    Object fit(List<List<String>> rows, int lines) {
      final (:shown, :more) = mcpFit(rows, lines);
      return [shown, more];
    }

    expect(fit(rows, 5), [rows, 0]);
    expect(fit(rows, 4), [
      [
        ['a'],
        ['b', 'b'],
      ],
      2,
    ]);
    expect(
      fit([
        ['a', 'a', 'a', 'a'],
        ['b'],
      ], 3),
      [
        [
          ['a', 'a', 'a', 'a'],
        ],
        1,
      ],
    );
    expect(mcpRowLimit(40), 24);
    expect(mcpRowLimit(10), 3);
  });

  test('what the files lost is said in one line, or not at all', () {
    expect(ignoredNote(const []), isNull);
    expect(
      ignoredNote(const [
        Ignored('~/.config/chord/settings.json', 1),
        Ignored('.mcp.json', 2),
      ]),
      '1 server in ~/.config/chord/settings.json was ignored and 2 servers '
      'in .mcp.json were ignored; chord said why when it started.',
    );
    expect(
      ignoredNote(const [Ignored('.mcp.json')]),
      '.mcp.json was ignored; chord said why when it started.',
    );
    expect(
      ignoredNote(const [
        Ignored('~/.config/chord/settings.json', 1),
        Ignored('.mcp.json', 2),
        Ignored('.chord/settings.json'),
      ]),
      '1 server in ~/.config/chord/settings.json was ignored, 2 servers '
      'in .mcp.json were ignored, and .chord/settings.json was ignored; '
      'chord said why when it started.',
    );
  });

  test('/mcp lists a server its agent was not given as not passed, and says '
      'why under the list', () {
    const docs = {
      'name': 'docs',
      'command': 'docs-server',
      'args': <Object?>[],
      'env': <Object?>[],
    };
    const search = {
      'type': 'http',
      'name': 'search',
      'url': 'https://search.example/mcp',
      'headers': <Object?>[],
    };
    const tracker = {
      'type': 'sse',
      'name': 'tracker',
      'url': 'https://tracker.example/sse',
      'headers': <Object?>[],
    };
    final defined = [
      for (final server in [docs, search, tracker])
        DefinedServer(server, '~/.config/chord/settings.json'),
    ];
    final stdio = serversFor('fake', null, [docs, search, tracker]);
    expect(
      [
        for (final each in withHeldBack(defined, stdio.heldBack))
          targetOf(each),
      ],
      ['docs-server', 'not passed', 'not passed'],
    );
    expect(
      heldNote(stdio.heldBack),
      'search and tracker were not passed: fake takes MCP servers over '
      'stdio only.',
    );
    expect(
      heldNote(
        serversFor('fake', {'http': true}, [docs, search, tracker]).heldBack,
      ),
      'tracker was not passed: fake takes MCP servers over stdio and HTTP '
      'only.',
    );
    // chord's own has a line of its own (M4), not this one.
    expect(
      heldNote(const [
        HeldBack(
          server: 'chord',
          agent: 'fake',
          transport: 'http',
          takes: ['stdio'],
          own: true,
        ),
      ]),
      isNull,
    );
  });

  test('/mcp says an agent set to take no MCP servers got none, and where '
      'the setting is', () {
    const docs = {
      'name': 'docs',
      'command': 'docs-server',
      'args': <Object?>[],
      'env': <Object?>[],
    };
    const tracker = {
      'type': 'sse',
      'name': 'tracker',
      'url': 'https://tracker.example/sse',
      'headers': <Object?>[],
    };
    final held = serversFor(
      'openclaw',
      {'http': true, 'sse': true},
      [docs, tracker],
      none: true,
    ).heldBack;
    final defined = [
      for (final server in [docs, tracker])
        DefinedServer(server, '~/.config/chord/settings.json'),
    ];
    expect(
      [for (final each in withHeldBack(defined, held)) targetOf(each)],
      ['not passed', 'not passed'],
    );
    expect(
      heldNote(held),
      'docs and tracker were not passed: openclaw takes no MCP servers. '
      'agents.openclaw.mcpServers in your settings changes that.',
    );
  });

  test('/mcp names --no-mcp-servers as what held them back, with no setting '
      'to change', () {
    const docs = {
      'name': 'docs',
      'command': 'docs',
      'args': <Object?>[],
      'env': <Object?>[],
    };
    final tracker = {...docs, 'name': 'tracker'};
    List<HeldBack> held(List<Map<String, Object?>> servers) => serversFor(
      'fake',
      const {},
      servers,
      none: true,
      from: noMcpServersFlag,
    ).heldBack;

    expect(
      heldNote(held([docs, tracker])),
      'docs and tracker were not passed: --no-mcp-servers on the command '
      'line held them back.',
    );
    expect(
      heldNote(held([docs])),
      'docs was not passed: --no-mcp-servers on the command line held it '
      'back.',
    );
  });

  test('while the agent starts, nothing is said to have been passed', () {
    expect(
      startingLine('codex'),
      'codex is starting: chord has not passed it MCP servers yet.',
    );
  });
}
