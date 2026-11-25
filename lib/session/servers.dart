/// Which MCP servers an agent is given, from the original's
/// `session/servers.ts`: only those whose transport its `initialize`
/// advertises in `mcpCapabilities`, stdio always, as ACP requires every
/// agent to take it; the rest held back, with why, for the client to be
/// told. The servers are the settings files' and `.mcp.json`'s, and a
/// `chord acp` client's, and chord's own last.
library;

/// The flag that holds every server back from the agent it starts.
const noMcpServersFlag = '--no-mcp-servers';

/// The transports past stdio an agent may advertise, in the order said.
const _advertised = ['http', 'sse', 'acp'];

/// A server an agent was not given, and why: its transport is not taken.
final class HeldBack {
  /// [server] held back from [agent], its [transport] not among [takes].
  const HeldBack({
    required this.server,
    required this.agent,
    required this.transport,
    required this.takes,
    this.from,
    this.own = false,
  });

  /// The server's name, as it would have gone.
  final String server;

  /// The agent it was held back from, by the name chord runs it as.
  final String agent;

  /// `http`, `sse`, or another transport ACP names.
  final String transport;

  /// The transports the agent takes, stdio first, then `http`, `sse` and
  /// `acp` as its `initialize` advertised them; none for an agent set to
  /// take no MCP servers at all.
  final List<String> takes;

  /// What set an agent to take none, as [noMcpServersFlag]; none for a
  /// transport not taken.
  final String? from;

  /// chord's own server, whose tools go with it.
  final bool own;

  /// As `_meta["chord/held_back"]` carries it.
  Map<String, Object?> toJson() => {
    'server': server,
    'agent': agent,
    'transport': transport,
    'takes': takes,
    'from': ?from,
    if (own) 'own': true,
  };
}

/// [server]'s transport: its `type`, or stdio for one without.
String transportOf(Map<String, Object?> server) =>
    server.containsKey('type') ? '${server['type']}' : 'stdio';

/// The servers of [userServers] that [agent] takes, by the transports
/// [capabilities] advertises, in their order, and those held back, and
/// [chord], chord's own server, last, under the name it went by: where a
/// server it is given takes chord's name, chord's goes as the first free
/// `chord-2`, `chord-3`, … and both stay reachable. An agent set to take
/// [none] is given no server, whatever it advertises, as [from] set it.
({
  List<Map<String, Object?>> servers,
  List<HeldBack> heldBack,
  Map<String, Object?>? chord,
})
serversFor(
  String agent,
  Map<String, Object?>? capabilities,
  List<Map<String, Object?>> userServers, {
  Map<String, Object?>? chord,
  bool none = false,
  String? from,
}) {
  final takes = none
      ? const <String>[]
      : [
          'stdio',
          for (final transport in _advertised)
            if (capabilities?[transport] == true) transport,
        ];
  final servers = <Map<String, Object?>>[];
  final heldBack = <HeldBack>[];
  bool sort(Map<String, Object?> server, {bool own = false}) {
    final transport = transportOf(server);
    if (takes.contains(transport)) {
      servers.add(server);
      return true;
    }
    heldBack.add(
      HeldBack(
        server: '${server['name']}',
        agent: agent,
        transport: transport,
        takes: takes,
        from: none ? from : null,
        own: own,
      ),
    );
    return false;
  }

  for (final server in userServers) {
    sort(server);
  }
  if (chord != null) {
    final taken = {for (final server in servers) server['name']};
    final base = chord['name'];
    var name = base;
    for (var n = 2; taken.contains(name); n++) {
      name = '$base-$n';
    }
    final named = {...chord, 'name': name};
    if (sort(named, own: true)) {
      return (servers: servers, heldBack: heldBack, chord: named);
    }
  }
  return (servers: servers, heldBack: heldBack, chord: null);
}

/// The transports an agent takes, as prose says them: `stdio and HTTP`,
/// `stdio, SSE and ACP`.
String takenWords(List<String> takes) {
  final words = [
    for (final transport in takes)
      transport == 'stdio' ? transport : transport.toUpperCase(),
  ];
  return words.length < 2
      ? words.join()
      : '${words.take(words.length - 1).join(', ')} and ${words.last}';
}

/// What the person is told at a session's start of the servers its agent
/// was not given: how many, to which agent, the transports it takes, every
/// one by name, chord's own first, and what losing chord's own costs; none
/// when every server went.
String? heldBackLine(List<HeldBack> heldBack) {
  if (heldBack.isEmpty) return null;
  final HeldBack(:agent, :takes, :from) = heldBack.first;
  final held = [
    ...heldBack.where((each) => each.own),
    ...heldBack.where((each) => !each.own),
  ];
  // An agent that lacks one transport holds back only servers of that one,
  // so the names go bare, as for one that takes none; lacking more, each
  // says its own.
  final bare = takes.isEmpty || _advertised.length - (takes.length - 1) == 1;
  final names = [
    for (final each in held)
      switch ([if (!bare) each.transport, if (each.own) "chord's own"]) {
        [] => each.server,
        final notes => '${each.server} (${notes.join(', ')})',
      },
  ].join(', ');
  final count = held.length;
  final own = held.any((each) => each.own)
      ? ' Without ${count == 1 ? 'it' : "chord's own"}, $agent cannot '
            "start other agents or use chord's tools."
      : '';
  final lists = '/mcp lists ${count == 1 ? 'it' : 'them'}.';
  // The person typed it, so it is named, not the agent's taking.
  if (from == noMcpServersFlag) {
    return '$noMcpServersFlag held back $count MCP '
        '${count == 1 ? 'server' : 'servers'} from $agent: $names.$own $lists';
  }
  final taking = takes.isEmpty
      ? 'takes none'
      : 'takes them over ${takenWords(takes)} only';
  return '$count MCP ${count == 1 ? 'server was' : 'servers were'} not '
      'passed to $agent, which $taking: $names.$own $lists';
}
