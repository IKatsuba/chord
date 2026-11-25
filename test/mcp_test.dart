import 'dart:convert';
import 'dart:io';

import 'package:chord/mcp.dart';
import 'package:chord/settings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _stdio = {
  'command': 'npx',
  'args': ['-y', '@modelcontextprotocol/server-filesystem', '.'],
  'env': {'DEBUG': '1'},
};

const _http = {
  'type': 'http',
  'url': 'https://mcp.example.com/mcp',
  'headers': {'Authorization': 'Bearer secret'},
};

List<String> _messages(ReadServers found) => [
  for (final problem in found.problems) problem.message,
];

List<String> _names(List<DefinedServer> servers) => [
  for (final defined in servers)
    '${defined.server['name']} from ${defined.from}',
];

void main() {
  test('a command server goes to ACP with its env as name and value pairs', () {
    final found = parseServers('.mcp.json', {
      'filesystem': _stdio,
      'bare': {'type': 'stdio', 'command': 'serve'},
    });

    expect(found.problems, isEmpty);
    expect(found.servers, [
      const DefinedServer({
        'name': 'filesystem',
        'command': 'npx',
        'args': ['-y', '@modelcontextprotocol/server-filesystem', '.'],
        'env': [
          {'name': 'DEBUG', 'value': '1'},
        ],
      }, '.mcp.json'),
      const DefinedServer({
        'name': 'bare',
        'command': 'serve',
        'args': <String>[],
        'env': <Object>[],
      }, '.mcp.json'),
    ]);
  });

  test('an HTTP or SSE server goes to ACP with its headers as pairs', () {
    final found = parseServers('settings.json', {
      'docs': _http,
      'events': {'type': 'sse', 'url': 'http://localhost:9000/sse'},
    });

    expect(found.problems, isEmpty);
    expect(
      jsonEncode([for (final each in found.servers) each.server]),
      jsonEncode([
        {
          'type': 'http',
          'name': 'docs',
          'url': 'https://mcp.example.com/mcp',
          'headers': [
            {'name': 'Authorization', 'value': 'Bearer secret'},
          ],
        },
        {
          'type': 'sse',
          'name': 'events',
          'url': 'http://localhost:9000/sse',
          'headers': <Object>[],
        },
      ]),
    );
  });

  test('a wrong server costs only itself, named with what is wrong', () {
    final found = parseServers('.mcp.json', {
      'search': {'type': 'ws', 'url': 'wss://example.com'},
      'github': {'type': 'http'},
      'plain': {'url': 'https://example.com/mcp'},
      'nothing': <String, Object?>{},
      'odd': {'command': 3},
      'secret': {
        'command': 'serve',
        'env': {'TOKEN': 1},
      },
      'ftp': {'type': 'sse', 'url': 'ftp://example.com'},
      'word': 'npx serve',
      'memory': {
        'command': 'npx',
        'args': ['-y', '@modelcontextprotocol/server-memory'],
      },
    });

    expect(_names(found.servers), ['memory from .mcp.json']);
    expect(_messages(found), [
      '"mcpServers.search.type": "ws" is not a transport ACP carries (stdio, http, sse); the server is ignored',
      '"mcpServers.github.url": missing; the server is ignored',
      '"mcpServers.plain.type": missing; a server with a url needs "http" or "sse"; the server is ignored',
      '"mcpServers.nothing.command": missing; the server is ignored',
      '"mcpServers.odd.command": invalid input: expected string, received number; the server is ignored',
      '"mcpServers.secret.env.TOKEN": invalid input: expected string, received number; the server is ignored',
      '"mcpServers.ftp.url": invalid url; the server is ignored',
      '"mcpServers.word": expected an object with a command or a url; the server is ignored',
    ]);
    expect(found.ignored, [const Ignored('.mcp.json', 8)]);
  });

  test('a null type is a transport ACP does not carry, not a missing one', () {
    final found = parseServers('.mcp.json', {
      'command': {'type': null, 'command': 'serve'},
      'url': {'type': null, 'url': 'https://a.example'},
    });

    expect(found.servers, isEmpty);
    expect(_messages(found), [
      '"mcpServers.command.type": null is not a transport ACP carries (stdio, http, sse); the server is ignored',
      '"mcpServers.url.type": null is not a transport ACP carries (stdio, http, sse); the server is ignored',
    ]);
  });

  test('a url is refused where the WHATWG parser refuses it', () {
    const refused = [
      'https://example.com:65536',
      'https://example.com:99999',
      'http://999.1.1.1',
      'http://1.2.3.256',
      'http://1.2.3.4.5',
      'http://a.b.c.256',
      'http://08.1.1.1',
      'http://1..2',
      'http://4294967296',
      'http://a b.com',
      'http://a<b.com',
      'http://a^b.com',
      'http://a|b.com',
      'http://a%20b.com',
      'http://a%2Fb.com',
      'http://a%zzb.com',
      'http:example.com',
      'https:/path',
      'ftp://example.com',
    ];
    final found = parseServers('.mcp.json', {
      for (final (index, url) in refused.indexed)
        'r$index': {'type': 'http', 'url': url},
    });

    expect(found.servers, isEmpty);
    expect(_messages(found), [
      for (final index in refused.indexed.map((e) => e.$1))
        '"mcpServers.r$index.url": invalid url; the server is ignored',
    ]);
  });

  test('a url WHATWG takes is sent trimmed, without tabs or line breaks', () {
    const taken = {
      'https://example.com:65535': 'https://example.com:65535',
      'http://0x7f.1': 'http://0x7f.1',
      'http://4294967295': 'http://4294967295',
      'http://1.16777215': 'http://1.16777215',
      'http://1.2.3.4.': 'http://1.2.3.4.',
      'http://[::1]': 'http://[::1]',
      'http://ex%41mple.com': 'http://ex%41mple.com',
      'HTTPS://EXAMPLE.COM/X': 'HTTPS://EXAMPLE.COM/X',
      'http://example.com/a b': 'http://example.com/a b',
      ' https://a.com ': 'https://a.com',
      'https://exa\tmple.com': 'https://example.com',
      '\thttps://ex\nample.com\n': 'https://example.com',
    };
    final found = parseServers('.mcp.json', {
      for (final (index, url) in taken.keys.indexed)
        't$index': {'type': 'sse', 'url': url},
    });

    expect(found.problems, isEmpty);
    expect([
      for (final defined in found.servers) defined.server['url'],
    ], taken.values);
  });

  test('an empty name, command, a wrong args or headers each cost the server', () {
    final found = parseServers('.mcp.json', {
      ' ': _stdio,
      'empty': {'command': ''},
      'list': {'command': 'serve', 'args': 'x'},
      'item': {
        'command': 'serve',
        'args': ['a', true],
      },
      'headers': {'type': 'http', 'url': 'https://a.example', 'headers': []},
      'hostless': {'type': 'http', 'url': 'https://'},
    });

    expect(found.servers, isEmpty);
    expect(_messages(found), [
      '"mcpServers. ": a server needs a name; the server is ignored',
      '"mcpServers.empty.command": too small: expected string to have >=1 characters; the server is ignored',
      '"mcpServers.list.args": invalid input: expected array, received string; the server is ignored',
      '"mcpServers.item.args.1": invalid input: expected string, received boolean; the server is ignored',
      '"mcpServers.headers.headers": invalid input: expected record, received array; the server is ignored',
      '"mcpServers.hostless.url": invalid url; the server is ignored',
    ]);
  });

  test("keys other tools add to a server are let through, not the agent's", () {
    final found = parseServers('.mcp.json', {
      'filesystem': {..._stdio, 'description': 'Files', 'disabled': false},
    });

    expect(found.problems, isEmpty);
    expect(found.servers.single.server.keys, [
      'name',
      'command',
      'args',
      'env',
    ]);
  });

  test('a broken .mcp.json costs the file and says why', () {
    const broken = '{ "mcpServers": ';
    String parseError() {
      try {
        jsonDecode(broken);
      } on FormatException catch (error) {
        return error.message;
      }
      fail('$broken parsed');
    }

    expect(_messages(parseMcpJson('.mcp.json', broken)), [
      'not valid JSON (${parseError()}); the file is ignored',
    ]);
    expect(_messages(parseMcpJson('.mcp.json', '[]')), [
      'not a JSON object; the file is ignored',
    ]);
    expect(_messages(parseMcpJson('.mcp.json', '{ "mcpServers": ["a"] }')), [
      '"mcpServers": expected an object of servers by name; the file is ignored',
    ]);
    expect(parseMcpJson('.mcp.json', '[]').ignored, [
      const Ignored('.mcp.json'),
    ]);
  });

  test(".mcp.json's other keys are other tools' and pass without a word", () {
    final found = parseMcpJson(
      '.mcp.json',
      jsonEncode({
        r'$schema': 'x',
        'inputs': <Object>[],
        'mcpServers': {'a': _stdio},
      }),
    );

    expect(found.problems, isEmpty);
    expect(_names(found.servers), ['a from .mcp.json']);
    final empty = parseMcpJson('.mcp.json', '{}');
    expect(
      [empty.servers, empty.problems, empty.ignored],
      [isEmpty, isEmpty, isEmpty],
    );
  });

  test('a server named again replaces the earlier one whole, in its place', () {
    final first = parseServers('user', {'a': _stdio, 'b': _http}).servers;
    final second = parseServers('project', {'a': _http, 'c': _stdio}).servers;
    final merged = mergeServers([first, second]);

    expect(_names(merged), ['a from project', 'b from user', 'c from project']);
    expect(merged.first, second.first);
  });

  test(
    'the settings files take mcpServers, and one that is not an object is a problem',
    () {
      final parsed = parseSettings(
        's.json',
        jsonEncode({
          'mcpServers': {'a': _stdio},
        }),
      );
      expect(parsed.problems, isEmpty);
      expect(jsonEncode(parsed.settings.mcpServers), jsonEncode({'a': _stdio}));
      expect(
        [
          for (final problem in parseSettings(
            's.json',
            '{ "mcpServers": [] }',
          ).problems)
            problem.message,
        ],
        [
          '"mcpServers": invalid input: expected record, received array, ignored',
        ],
      );
    },
  );

  group('tester: CTUI-34 U1 recovery and isolation', () {
    test('transport shapes discard fields belonging to another transport', () {
      final found = parseServers('.mcp.json', {
        'local': {..._stdio, 'url': 'https://unused.example', 'headers': 3},
        'remote': {..._http, 'command': 3, 'args': false, 'env': null},
        '界🙂e\u0301': {
          'command': 'serve\u001b[31m',
          'args': ['界', '🙂', 'e\u0301'],
          'env': {'TOKEN': ''},
        },
      });

      expect(found.problems, isEmpty);
      expect(found.servers[0].server.containsKey('url'), isFalse);
      expect(found.servers[1].server.containsKey('command'), isFalse);
      expect(found.servers[2].server, {
        'name': '界🙂e\u0301',
        'command': 'serve\u001b[31m',
        'args': ['界', '🙂', 'e\u0301'],
        'env': [
          {'name': 'TOKEN', 'value': ''},
        ],
      });
    });

    test('explicit null optional fields cost their server, not siblings', () {
      final found = parseServers('.mcp.json', {
        'args': {'command': 'serve', 'args': null},
        'env': {'command': 'serve', 'env': null},
        'headers': {..._http, 'headers': null},
        'url': {'type': 'sse', 'url': null},
        'ok': _stdio,
      });

      expect(_names(found.servers), ['ok from .mcp.json']);
      expect(_messages(found), [
        '"mcpServers.args.args": invalid input: expected array, received null; the server is ignored',
        '"mcpServers.env.env": invalid input: expected record, received null; the server is ignored',
        '"mcpServers.headers.headers": invalid input: expected record, received null; the server is ignored',
        '"mcpServers.url.url": invalid input: expected string, received null; the server is ignored',
      ]);
      expect(found.ignored, [const Ignored('.mcp.json', 4)]);
    });

    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('chord-mcp-qa-'));
    tearDown(() => root.deleteSync(recursive: true));

    test('malformed UTF-8 is replaced inside a valid server', () async {
      final file = File(p.join(root.path, '.mcp.json'));
      await file.writeAsBytes([
        ...utf8.encode('{"mcpServers":{"local":{"command":"a'),
        0xff,
        ...utf8.encode('b"}}}'),
      ]);

      final found = await readMcpJson(root.path);
      expect(found.problems, isEmpty);
      expect(found.servers.single.server['command'], 'a\ufffdb');
    });

    test(
      'broken files can be repaired and deleted without retained state',
      () async {
        final file = File(p.join(root.path, '.mcp.json'));
        await file.writeAsString('{');
        final broken = await readMcpJson(root.path);
        expect(broken.ignored, [Ignored(file.path)]);

        await file.writeAsString(
          jsonEncode({
            'mcpServers': {'ok': _stdio},
          }),
        );
        final repaired = await readMcpJson(root.path);
        expect(_names(repaired.servers), ['ok from ${file.path}']);
        expect(repaired.problems, isEmpty);
        expect(repaired.ignored, isEmpty);

        await file.delete();
        final deleted = await readMcpJson(root.path);
        expect(deleted.servers, isEmpty);
        expect(deleted.problems, isEmpty);
        expect(deleted.ignored, isEmpty);
        expect(broken.ignored, [Ignored(file.path)]);
        expect(repaired.servers, hasLength(1));
      },
    );

    test(
      'invalid later overrides preserve valid servers and ordered losses',
      () async {
        final shared = p.join(root.path, '.mcp.json');
        final project = p.join(root.path, '.chord', 'settings.json');
        await File(shared).writeAsString(
          jsonEncode({
            'mcpServers': {
              'a': {'command': ''},
              'shared': _stdio,
            },
          }),
        );
        final found = await loadMcpServers(
          cwd: root.path,
          layers: [
            SettingsLayer(
              project,
              const Settings(
                mcpServers: {
                  'shared': {'type': 'sse'},
                  'project': _http,
                },
              ),
            ),
            const SettingsLayer(
              'user.json',
              Settings(mcpServers: {'a': _stdio, 'bad': false}),
            ),
          ],
        );

        expect(_names(found.servers), [
          'a from user.json',
          'shared from $shared',
          'project from $project',
        ]);
        expect(found.problems.map((each) => each.file), [
          'user.json',
          shared,
          project,
        ]);
        expect(found.ignored, [
          const Ignored('user.json', 1),
          Ignored(shared, 1),
          Ignored(project, 1),
        ]);
      },
    );
  });

  group('tester: CTUI-75 U1 URL boundaries', () {
    final hugePort = List.filled(200, '9').join();
    final paddedPort = '${List.filled(200, '0').join()}65535';
    final accepted = [
      'http://example.com:$paddedPort',
      'http://%31%32%37.1',
      'http://0x',
      'http://0X.1',
      'http://%30%78.1',
      'http://[::1]:0',
      'http://[::1]:65535',
    ];
    final refused = [
      'http://example.com:$hugePort',
      'http://[::1]:$hugePort',
      'http://[::1]:65536',
      'http://%32%35%36.1',
      'http://%34%32%39%34%39%36%37%32%39%36',
      'http://a.0x',
      'http://a%00b.com',
      'http://a%7Fb.com',
      'http://a%25b.com',
      'http://a%5Cb.com',
    ];

    for (final (index, url) in accepted.indexed) {
      test('accepted numeric and port boundary $index retains its URL', () {
        final entry = {'type': 'sse', 'url': url};
        final found = parseServers('.mcp.json', {'edge': entry});
        expect(found.problems, isEmpty, reason: url);
        expect(found.ignored, isEmpty);
        expect(found.servers.single.server['url'], url);
        expect(checkedServerEntry(entry), entry);
      });
    }

    for (final (index, url) in refused.indexed) {
      test('refused numeric and domain boundary $index isolates its loss', () {
        final entry = {'type': 'http', 'url': url};
        final found = parseServers('.mcp.json', {
          'before': _stdio,
          'edge': entry,
          'after': _http,
        });
        expect(_names(found.servers), [
          'before from .mcp.json',
          'after from .mcp.json',
        ], reason: url);
        expect(_messages(found), [
          '"mcpServers.edge.url": invalid url; the server is ignored',
        ]);
        expect(found.ignored, [const Ignored('.mcp.json', 1)]);
        expect(checkedServerEntry(entry), isNull);
      });
    }

    test('explicit null transport is refused by both entry paths', () {
      for (final entry in [
        {'type': null, 'command': 'serve'},
        {'type': null, 'url': 'https://example.com'},
      ]) {
        expect(checkedServerEntry(entry), isNull);
        final found = parseServers('.mcp.json', {'edge': entry});
        expect(found.servers, isEmpty);
        expect(_messages(found), [
          '"mcpServers.edge.type": null is not a transport ACP carries (stdio, http, sse); the server is ignored',
        ]);
      }
    });

    test('URL cleaning is shared by configuration and ACP entry paths', () {
      const input = '\uFEFF HTTPS://exa\tmple.com/a\rb\nc \u00A0';
      const output = 'HTTPS://example.com/abc';
      final entry = {'type': 'http', 'url': input};
      final found = parseServers('.mcp.json', {'edge': entry});
      expect(found.problems, isEmpty);
      expect(found.servers.single.server['url'], output);
      expect(checkedServerEntry(entry), {'type': 'http', 'url': output});
    });
  });

  group('files', () {
    late Directory root;
    late String cwd;
    late String configHome;

    setUp(() {
      root = Directory.systemTemp.createTempSync('chord-mcp-');
      cwd = p.join(root.path, 'work');
      configHome = p.join(root.path, 'config');
      Directory(p.join(cwd, '.chord')).createSync(recursive: true);
      Directory(p.join(configHome, 'chord')).createSync(recursive: true);
    });

    tearDown(() => root.deleteSync(recursive: true));

    void write(String file, Object? value) =>
        File(file).writeAsStringSync(jsonEncode(value));

    test(
      "the user's file, then .mcp.json, then the project's file, each over the last",
      () async {
        final user = p.join(configHome, 'chord', 'settings.json');
        final shared = p.join(cwd, '.mcp.json');
        final project = p.join(cwd, '.chord', 'settings.json');

        write(user, {
          'mcpServers': {'docs': _http, 'files': _stdio, 'mine': _stdio},
        });
        write(shared, {
          'mcpServers': {
            'files': {'command': 'shared'},
            'team': _stdio,
          },
        });
        write(project, {
          'mcpServers': {
            'team': {'command': 'ours'},
            'broken': {'type': 'http'},
          },
        });

        final layers = (await loadSettings(
          configHome: configHome,
          cwd: cwd,
        )).layers;
        final found = await loadMcpServers(layers: layers, cwd: cwd);

        expect(_names(found.servers), [
          'docs from $user',
          'files from $shared',
          'mine from $user',
          'team from $project',
        ]);
        expect(found.problems, [
          SettingsProblem(
            project,
            '"mcpServers.broken.url": missing; the server is ignored',
          ),
        ]);
        expect(found.ignored, [Ignored(project, 1)]);
      },
    );

    test(
      'no .mcp.json and no settings pass no servers and say nothing',
      () async {
        final layers = (await loadSettings(
          configHome: configHome,
          cwd: cwd,
        )).layers;
        final found = await loadMcpServers(layers: layers, cwd: cwd);

        expect(
          [found.servers, found.problems, found.ignored],
          [isEmpty, isEmpty, isEmpty],
        );
      },
    );

    test('a .mcp.json that cannot be read is named and ignored', () async {
      Directory(p.join(cwd, '.mcp.json')).createSync();
      final found = await readMcpJson(cwd);

      expect(found.servers, isEmpty);
      expect(found.problems.single.file, p.join(cwd, '.mcp.json'));
      expect(
        found.problems.single.message,
        allOf(
          startsWith('cannot be read ('),
          endsWith('); the file is ignored'),
        ),
      );
      expect(found.ignored, [Ignored(p.join(cwd, '.mcp.json'))]);
    });
  });
}
