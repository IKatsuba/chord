import 'package:chord/mcp.dart';
import 'package:chord/session/servers.dart';
import 'package:chord/ui/pickers/mcp.dart' show ChordRow, chordRow;
import 'package:chord/ui/pickers/pickers.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const _files = {
  'name': 'files',
  'command': 'npx',
  'args': ['-y', '@modelcontextprotocol/server-filesystem', '.'],
  'env': [
    {'name': 'TOKEN', 'value': 'secret'},
  ],
};
const _docs = {
  'type': 'http',
  'name': 'docs',
  'url': 'https://docs.example/mcp',
  'headers': [
    {'name': 'Authorization', 'value': 'Bearer secret'},
  ],
};

Future<void> _panel(
  WidgetTester t,
  Size size, {
  List<DefinedServer> servers = const [],
  List<Ignored> ignored = const [],
  List<HeldBack> heldBack = const [],
  bool starting = false,
  ChordRow? chord,
  void Function()? onClose,
}) => t.pumpWidget(
  Align(
    alignment: Alignment.bottomLeft,
    child: McpPanel(
      servers: servers,
      ignored: ignored,
      heldBack: heldBack,
      agent: 'fake',
      windowRows: size.height.toInt(),
      room: size.height.toInt() - 5,
      starting: starting,
      chord: chord,
      onClose: onClose ?? () {},
    ),
  ),
  size: size,
);

/// The panel's words without its frame, its wrapped lines joined.
String _prose(WidgetTester t) => [
  for (final line in t.screen.lines)
    line.replaceAll(RegExp('[│╭╮╰╯─]'), '').trim(),
].where((line) => line.isNotEmpty).join(' ');

void main() {
  group('tester: own MCP row transitions', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'starting, passed child and held-back redraw without stale URL at $size',
        (t) async {
          final own = chordRow(const {
            'type': 'http',
            'name': 'chord',
            'url': 'http://127.0.0.1:4242/mcp',
            'headers': [
              {'name': 'Authorization', 'value': 'tester-private-header'},
            ],
          }, child: true);
          await _panel(t, size, starting: true, chord: own);
          expect(_prose(t), contains('fake is starting'));
          expect(t.screen.text, isNot(contains('127.0.0.1:4242')));
          await _panel(t, size, chord: own);
          expect(t.screen.text, contains('http://127.0.0.1:4242/mcp'));
          expect(_prose(t), contains('send_message to main only'));
          expect(_prose(t), contains('close_agent for its own tasks'));
          expect(t.screen.text, isNot(contains('tester-private-header')));
          expect(t.screen.text, isNot(contains('No MCP servers were passed')));
          await _panel(
            t,
            size,
            chord: chordRow(null, none: true, from: noMcpServersFlag),
          );
          expect(t.screen.text, isNot(contains('127.0.0.1:4242')));
          expect(_prose(t), contains('--no-mcp-servers on the command line'));
          await t.resize(
            size == const Size(120, 40)
                ? const Size(80, 24)
                : const Size(120, 40),
          );
          expect(_prose(t), contains('cannot start other agents'));
        },
      );
    }
  });

  // CTUI-112: chord's own row first, as the original lists it on the fake,
  // and its line under the table; "not passed" with --no-mcp-servers.
  group("chord's own server", () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('passed, listed first with its line, at $size', (t) async {
        await _panel(
          t,
          size,
          servers: const [DefinedServer(_files, '.mcp.json')],
          chord: chordRow(const {
            'type': 'http',
            'name': 'chord',
            'url': 'http://127.0.0.1:4242/mcp',
            'headers': <Object?>[],
          }),
        );
        final lines = t.screen.lines;
        final chord = lines.indexWhere(
          (line) => line.contains('http://127.0.0.1:4242/mcp'),
        );
        final files = lines.indexWhere((line) => line.contains('files'));
        expect(chord, greaterThan(0));
        expect(chord, lessThan(files));
        expect(
          lines[chord],
          matches(
            RegExp(
              r'chord\s+http\s+http://127\.0\.0\.1:4242/mcp\s+chord itself',
            ),
          ),
        );
        expect(_prose(t), contains("chord's server gives fake list_agents,"));
        expect(_prose(t), isNot(contains('No MCP servers were passed')));
      });

      testWidgets('held back by --no-mcp-servers, at $size', (t) async {
        await _panel(
          t,
          size,
          chord: chordRow(null, none: true, from: noMcpServersFlag),
        );
        expect(
          t.screen.lines.any(
            (line) => RegExp(
              r'chord\s+http\s+not passed\s+chord itself',
            ).hasMatch(line),
          ),
          isTrue,
          reason: t.screen.text,
        );
        expect(
          _prose(t),
          contains(
            "chord's server was not passed: --no-mcp-servers on the command "
            'line held it back, so fake cannot start other agents.',
          ),
        );
      });
    }
  });

  group('tester: CTUI-75 U3 lost-note rebuilds', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'lost-note spacing follows servers across rebuilds at $size',
        (t) async {
          const lost = [
            Ignored('a.json'),
            Ignored('b.json'),
            Ignored('c.json'),
          ];
          await _panel(
            t,
            size,
            servers: const [DefinedServer(_files, '.mcp.json')],
            ignored: lost,
          );
          var rows = t.screen.lines;
          var note = rows.indexWhere(
            (row) => row.contains('a.json was ignored'),
          );
          expect(note, greaterThan(0));
          expect(rows[note - 1].replaceAll('│', '').trim(), isEmpty);
          await _panel(t, size, ignored: lost);
          rows = t.screen.lines;
          final none = rows.indexWhere(
            (row) => row.contains('No MCP servers were passed to fake.'),
          );
          note = rows.indexWhere((row) => row.contains('a.json was ignored'));
          expect(note, none + 1);
          expect(
            _prose(t),
            contains(
              'a.json was ignored, b.json was ignored, and c.json was ignored;',
            ),
          );
          await t.resize(
            size == const Size(80, 24)
                ? const Size(120, 40)
                : const Size(80, 24),
          );
          expect(_prose(t), contains('and c.json was ignored;'));
          await t.press('esc');
        },
      );
    }
  });

  group('tester: CTUI-34 MCP clipped panel ownership', () {
    for (final size in const [
      Size.zero,
      Size(1, 1),
      Size(24, 8),
      Size(120, 40),
    ]) {
      testWidgets(
        'resize from $size keeps close active and credentials absent',
        (t) async {
          var closed = 0;
          await _panel(
            t,
            size,
            servers: const [
              DefinedServer(_files, '.mcp.json'),
              DefinedServer(_docs, 'settings.json'),
            ],
            onClose: () => closed++,
          );
          expect(t.screen.text, isNot(contains('secret')));
          await t.resize(const Size(80, 24));
          expect(t.screen, shows('MCP servers'));
          expect(t.screen.text, isNot(contains('secret')));
          await t.press('esc');
          expect(closed, 1);
        },
      );
    }
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('lists each server with its transport, command or URL and '
        'file, never its env or headers, at $size', (t) async {
      await _panel(
        t,
        size,
        servers: const [
          DefinedServer(_docs, '~/.config/chord/settings.json'),
          DefinedServer(_files, '.mcp.json'),
        ],
      );
      final text = t.screen.text;
      expect(text, contains('MCP servers'));
      expect(text, contains("chord's MCP servers for fake."));
      expect(text, contains('Name'));
      expect(text, contains('Command or URL'));
      expect(text, contains('https://docs.example/mcp'));
      expect(text, contains('.mcp.json'));
      expect(text, contains('Esc to close'));
      expect(text, isNot(contains('secret')));
      for (final line in t.screen.lines) {
        expect(cellWidth(line), lessThanOrEqualTo(size.width));
      }
    });

    testWidgets('a held-back server is not passed, with why and what the '
        'files lost under the list, at $size', (t) async {
      await _panel(
        t,
        size,
        servers: const [
          DefinedServer(_docs, '~/.config/chord/settings.json'),
          DefinedServer(_files, '.mcp.json'),
        ],
        heldBack: serversFor('fake', null, const [_files, _docs]).heldBack,
        ignored: const [Ignored('.mcp.json', 2)],
      );
      final text = t.screen.text;
      expect(text, contains('not passed'));
      expect(text, isNot(contains('https://docs.example/mcp')));
      expect(
        _prose(t),
        allOf(
          contains(
            'docs was not passed: fake takes MCP servers over stdio only.',
          ),
          contains(
            '2 servers in .mcp.json were ignored; chord said why when it '
            'started.',
          ),
        ),
      );
    });

    testWidgets('none defined, none passed, and while starting nothing is '
        'said to have gone, at $size', (t) async {
      await _panel(t, size);
      expect(
        _prose(t),
        contains(
          'No MCP servers were passed to fake: none are defined in .mcp.json '
          "or in chord's settings files.",
        ),
      );
      await _panel(t, size, ignored: const [Ignored('.mcp.json')]);
      final lost = _prose(t);
      expect(lost, contains('No MCP servers were passed to fake.'));
      expect(lost, contains('.mcp.json was ignored;'));
      final rows = t.screen.lines;
      final none = rows.indexWhere(
        (row) => row.contains('No MCP servers were passed to fake.'),
      );
      // The note follows the none line with no gap, as the original's.
      expect(rows[none + 1], contains('.mcp.json was ignored;'));
      await _panel(
        t,
        size,
        starting: true,
        servers: const [DefinedServer(_files, '.mcp.json')],
      );
      final starting = _prose(t);
      expect(
        starting,
        contains('fake is starting: chord has not passed it MCP servers yet.'),
      );
      expect(starting, isNot(contains('Command or URL')));
    });

    testWidgets('more servers than the window holds are counted, at $size', (
      t,
    ) async {
      await _panel(
        t,
        size,
        servers: [
          for (var i = 0; i < 40; i++)
            DefinedServer({..._files, 'name': 'server-$i'}, '.mcp.json'),
        ],
      );
      expect(t.screen.text, contains('more'));
      expect(t.screen.text, contains('Esc to close'));
      expect(t.screen.lines.first, isNot(contains('server-')));
    });
  }

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the frame takes the window\'s width whatever it holds, at '
        '$size', (t) async {
      for (final starting in [true, false]) {
        await _panel(
          t,
          size,
          starting: starting,
          servers: const [DefinedServer(_files, '.mcp.json')],
          heldBack: serversFor(
            'fake',
            null,
            const [_files],
            none: true,
            from: noMcpServersFlag,
          ).heldBack,
        );
        final top = t.screen.lines.firstWhere((l) => l.contains('╭'));
        expect(top, startsWith('╭'));
        expect(cellWidth(top.trimRight()), size.width, reason: '$starting');
      }
    });
  }

  testWidgets('Esc closes it', (t) async {
    var closed = 0;
    await _panel(t, const Size(80, 24), onClose: () => closed++);
    await t.press('esc');
    expect(closed, 1);
  });
}
