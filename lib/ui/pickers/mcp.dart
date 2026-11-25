/// `/mcp`, from the original's `ui/pickers/mcp.ts`: the MCP servers chord
/// passed to the agent, one row each, laid out in columns that fit the
/// width, and what the files defined that it did not pass. Nothing here
/// says whether the agent reached a server: ACP carries no word of it, and
/// the panel says so instead.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:chord_tui/chord_tui.dart';

import '../../mcp.dart';
import '../../server/tools.dart' show Role, toolNames;
import '../../session/servers.dart';

/// chord's own server, as `/mcp` lists it ahead of the person's.
final class ChordRow {
  const ChordRow({
    required this.server,
    required this.passed,
    required this.tools,
    this.child = false,
    this.none = false,
    this.from,
  });

  /// Its row, with `not passed` for the URL of one the agent did not get.
  final DefinedServer server;
  final bool passed;

  /// The tools it gives the session, by the names an agent calls them.
  final List<String> tools;

  /// The session is a long-lived child, whose one tool reaches `main`.
  final bool child;

  /// Not passed as the agent takes no MCP servers at all.
  final bool none;

  /// What set [none], as [HeldBack.from] says it.
  final String? from;
}

/// chord's row: the server the session got, or `not passed` for its URL;
/// a [child]'s gives it its child's tools.
ChordRow chordRow(
  Map<String, Object?>? passed, {
  bool child = false,
  bool none = false,
  String? from,
}) => ChordRow(
  server: DefinedServer(
    passed ??
        const {
          'type': 'http',
          'name': 'chord',
          'url': 'not passed',
          'headers': <Object?>[],
        },
    'chord itself',
  ),
  passed: passed != null,
  tools: [
    for (final tool in toolNames(child ? Role.child : Role.person)) tool.wire,
  ],
  child: child,
  none: none && passed == null,
  from: passed == null ? from : null,
);

/// The line under the table: what chord's server gives, or why it was not
/// passed.
String chordLine(ChordRow row, String agent) {
  // A child's send_message reaches main alone, its close_agent only the
  // tasks it started; its other tools are its own.
  final own = [
    for (final tool in row.tools)
      if (tool == 'close_agent')
        'close_agent for its own tasks'
      else if (tool != 'send_message')
        tool,
  ];
  if (row.passed) {
    return "chord's server gives $agent ${row.child ? '${own.isNotEmpty ? '${_listed(own)}, and ' : ''}send_message to main only' : _listed(row.tools)}.";
  }
  if (row.from == noMcpServersFlag) {
    return "chord's server was not passed: $noMcpServersFlag on the command line held it back, so $agent cannot start other agents.";
  }
  return "chord's server was not passed: $agent ${row.none ? 'takes no MCP servers' : 'does not take MCP servers over HTTP'}, so it cannot start other agents.";
}

/// What `/mcp` says while its agent's session is still being opened.
String startingLine(String agent) =>
    '$agent is starting: chord has not passed it MCP servers yet.';

/// One server's parts, before they are laid out.
typedef McpParts = ({
  String name,
  String transport,
  String target,
  String from,
});

/// The column titles, in the order the rows are laid out.
const McpParts mcpHeadings = (
  name: 'Name',
  transport: 'Transport',
  target: 'Command or URL',
  from: 'Defined in',
);

/// Between columns.
const mcpGap = 2;

/// The widest a name is drawn before the command is squeezed out.
const _most = 32;

/// The narrowest the command or URL is squeezed to by a long path. It
/// wraps, so a narrow column costs lines, not the part that tells servers
/// apart.
const _leastTarget = 16;

/// A server as `/mcp` lists it: one its agent was not given is [held].
final class ListedServer {
  const ListedServer(this.defined, {this.held = false});

  final DefinedServer defined;
  final bool held;
}

/// An argument with a space in it, quoted, so the line reads as typed.
String _shellWord(String word) =>
    RegExp(r'\s').hasMatch(word) || word.isEmpty ? jsonEncode(word) : word;

/// What the server runs, or where it is, or `not passed` for one held
/// back. Env and headers are never shown.
String targetOf(ListedServer listed) {
  if (listed.held) return 'not passed';
  final server = listed.defined.server;
  if (server.containsKey('url')) return '${server['url']}';
  // chord never reads an ACP-transport server from a file, but ACP has one.
  return server.containsKey('command')
      ? [
          '${server['command']}',
          for (final arg in server['args'] as List? ?? const []) '$arg',
        ].map(_shellWord).join(' ')
      : '${server['serverId']}';
}

String _pad(String text, int width) =>
    text + ' ' * math.max(0, width - cellWidth(text));

/// A path cut from the left, where it is least telling, and at a separator
/// where one is left, so the file's name and its directory survive whole.
String cutPath(String path, int width) {
  if (cellWidth(path) <= width) return path;
  final cut = truncateStart(path, width < 1 ? 1 : width);
  final separator = cut.indexOf('/', 1);
  return separator > 1 && separator < cut.length - 1
      ? '…${cut.substring(separator)}'
      : cut;
}

/// The first [width] cells of [line], whole graphemes, at least one.
String _head(String line, int width) {
  final out = StringBuffer();
  var used = 0;
  for (final grapheme in line.characters) {
    final cells = graphemeWidth(grapheme);
    if (used + cells > width && used > 0) break;
    out.write(grapheme);
    used += cells;
  }
  return out.toString();
}

/// A command or URL in lines of [width], broken at spaces and else after a
/// slash, where a package's scope, a path or a URL reads as whole; only a
/// piece longer than the line is cut through.
List<String> wrapTarget(String text, int width) {
  final lines = <String>[];
  var line = '';
  for (final (index, word) in text.split(' ').indexed) {
    for (final (at, piece) in word.split(RegExp('(?<=/)')).indexed) {
      final joined = line.isEmpty
          ? piece
          : '$line${index > 0 && at == 0 ? ' ' : ''}$piece';
      if (cellWidth(joined) <= width || line.isEmpty) {
        line = joined;
      } else {
        lines.add(line);
        line = piece;
      }
      while (cellWidth(line) > width) {
        final head = _head(line, width);
        lines.add(head);
        line = line.substring(head.length);
      }
    }
  }
  return [...lines, line];
}

/// Each server as its lines, laid out in columns to fit [width], and the
/// headings as one line laid out the same. The path takes its full width
/// first, as it is one of three files and a cut one says none of them; the
/// command or URL takes the rest and wraps inside its column, so the end
/// of `npx -y @scope/server-x`, which tells servers apart, is never cut off.
({String headings, List<List<String>> rows}) mcpRows(
  List<ListedServer> servers,
  int width,
) {
  final named = <McpParts>[
    for (final listed in servers)
      (
        name: '${listed.defined.server['name']}',
        transport: transportOf(listed.defined.server),
        target: targetOf(listed),
        from: listed.defined.from,
      ),
  ];
  final all = [mcpHeadings, ...named];
  int widest(String Function(McpParts) key, [int most = 1 << 30]) =>
      math.min(most, all.map((row) => cellWidth(key(row))).fold(0, math.max));
  final nameWidth = widest((row) => row.name, _most);
  final transportWidth = widest((row) => row.transport);
  final room = width - nameWidth - transportWidth - 3 * mcpGap;
  final int fromWidth = math.max(
    1,
    math.min(
      widest((row) => row.from),
      room - math.min(widest((row) => row.target), _leastTarget),
    ),
  );
  final wrapped = [
    for (final row in all)
      wrapTarget(row.target, math.max(1, room - fromWidth)),
  ];
  // As wide as its widest line, which wrapping may leave short of the room.
  final targetWidth = wrapped
      .expand((lines) => lines)
      .map(cellWidth)
      .fold(0, math.max);
  final gap = ' ' * mcpGap;
  List<String> laid(McpParts row, int at) => [
    for (final (index, target) in wrapped[at].indexed)
      (index == 0
              ? [
                  _pad(truncate(row.name, nameWidth), nameWidth),
                  _pad(row.transport, transportWidth),
                  _pad(target, targetWidth),
                  cutPath(row.from, fromWidth),
                ]
              : [' ' * nameWidth, ' ' * transportWidth, target])
          .join(gap)
          .trimRight(),
  ];
  return (
    headings: laid(mcpHeadings, 0).first,
    rows: [for (final (index, row) in named.indexed) laid(row, index + 1)],
  );
}

/// The servers that fit in [lines] lines, whole, with one line kept for
/// saying how many more there are when not all of them do. The first is
/// always shown, however many lines it wraps to.
({List<List<String>> shown, int more}) mcpFit(
  List<List<String>> rows,
  int lines,
) {
  if (rows.fold(0, (n, row) => n + row.length) <= lines) {
    return (shown: [...rows], more: 0);
  }
  final shown = <List<String>>[];
  var used = 0;
  for (final row in rows) {
    if (shown.isNotEmpty && used + row.length > lines - 1) break;
    shown.add(row);
    used += row.length;
  }
  return (shown: shown, more: rows.length - shown.length);
}

/// [items] as prose lists them: `a`, `a and b`, `a, b and c`.
String _listed(List<String> items) => items.length < 2
    ? items.join()
    : '${items.take(items.length - 1).join(', ')} and ${items.last}';

/// [items] as en's conjunction list writes them: `a, b, and c`.
String _listedEn(List<String> items) => items.length < 3
    ? _listed(items)
    : '${items.take(items.length - 1).join(', ')}, and ${items.last}';

/// What the files lost, for `/mcp`, or nothing when they lost nothing. The
/// warnings that said why are gone once the window is cleared, so the line
/// points to when chord said it rather than to where.
String? ignoredNote(List<Ignored> ignored) {
  if (ignored.isEmpty) return null;
  final each = [
    for (final Ignored(:from, :servers) in ignored)
      switch (servers) {
        null => '$from was ignored',
        1 => '1 server in $from was ignored',
        _ => '$servers servers in $from were ignored',
      },
  ];
  return '${_listedEn(each)}; chord said why when it started.';
}

/// How many lines of servers the panel draws before it says how many more
/// there are: the window's height less the panel's own lines and the
/// prompt's, and never fewer than three.
int mcpRowLimit(int windowRows) => math.max(3, windowRows - 16);

/// The person's servers as `/mcp` lists them, each [heldBack] names
/// (chord's own aside) with `not passed` for its command or URL.
List<ListedServer> withHeldBack(
  List<DefinedServer> servers,
  List<HeldBack> heldBack,
) {
  final held = {
    for (final each in heldBack)
      if (!each.own) each.server,
  };
  return [
    for (final defined in servers)
      ListedServer(defined, held: held.contains('${defined.server['name']}')),
  ];
}

/// The paragraph under `/mcp`'s table for the person's servers its agent
/// was not given, and why; none when all of them went.
String? heldNote(List<HeldBack> heldBack) {
  final held = [
    for (final each in heldBack)
      if (!each.own) each,
  ];
  if (held.isEmpty) return null;
  final names = _listed([for (final each in held) each.server]);
  final HeldBack(:agent, :takes, :from) = held.first;
  final were = held.length == 1 ? 'was' : 'were';
  // A setting would not help: the flag beats it.
  if (from == noMcpServersFlag) {
    return '$names $were not passed: $noMcpServersFlag on the command line '
        'held ${held.length == 1 ? 'it' : 'them'} back.';
  }
  return takes.isEmpty
      ? '$names $were not passed: $agent takes no MCP servers. '
            'agents.$agent.mcpServers in your settings changes that.'
      : '$names $were not passed: $agent takes MCP servers over '
            '${takenWords(takes)} only.';
}
