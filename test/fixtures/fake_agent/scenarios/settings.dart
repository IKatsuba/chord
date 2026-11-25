// chord's `settings` tool, called as an agent calls it, as the original's
// scenarios/settings.ts. The file it reads is whatever the run's
// `XDG_CONFIG_HOME` holds: a test's fixture, never a person's own.
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart' as mcp;
import 'package:path/path.dart' as p;

import '../rpc.dart';
import '../sessions.dart';
import '../turn.dart';
import 'agents.dart';
import 'chord_tools.dart';

/// What the linked file holds: a key the schema checks, which a read
/// shows, and one it does not, which no read may.
const linkTarget = <String, Object?>{
  'agent': 'linked-agent',
  'linkedUnknownKey': 'linked-unknown-value',
};

/// As long as the person takes to answer the box.
const _boxMs = 600000;

Future<String> _noServer(Turn turn) async {
  await turn.say(['No chord server.']);
  return 'end_turn';
}

/// Calls `settings` with each of [each] in turn.
Play _calls(List<Map<String, Object?>> each) => (turn) async {
  final client = await chordClient(turn);
  if (client == null) return _noServer(turn);
  try {
    for (final arguments in each) {
      await callChord(turn, client, 'settings', arguments, timeout: _boxMs);
    }
  } finally {
    await client.close();
  }
  return 'end_turn';
};

/// A second change while the first's box is up: the first asks, and once
/// the gate opens, at most 10 s on, the second is refused with that box
/// still open; the turn ends once the person answers.
Future<String> _overlap(Turn turn) async {
  final client = await chordClient(turn);
  if (client == null) return _noServer(turn);
  try {
    final first = callChord(turn, client, 'settings', {
      'action': 'set',
      'path': ['theme'],
      'value': 'light',
    }, timeout: _boxMs);
    await gateOpened(turn, gateRelease);
    await callChord(turn, client, 'settings', {
      'action': 'set',
      'path': ['agents', 'fake', 'model'],
      'value': 'fake-small',
    }, timeout: _boxMs);
    await first;
  } finally {
    await client.close();
  }
  return 'end_turn';
}

/// A change whose call the agent gives up on with the box up, once the
/// gate opens, as a cancelled request is withdrawn.
Future<String> _withdrawn(Turn turn) async {
  final client = await chordClient(turn);
  if (client == null) return _noServer(turn);
  final toolCallId = turn.callId('settings');
  final arguments = {
    'action': 'set',
    'path': ['theme'],
    'value': 'light',
  };
  try {
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': toolCallId,
      'status': 'pending',
      'title': 'mcp__chord__settings',
      'kind': 'other',
      'rawInput': arguments,
    });
    final cancelled = mcp.BasicAbortController();
    final call = client
        .callTool(
          mcp.CallToolRequest(name: 'settings', arguments: arguments),
          options: mcp.RequestOptions(signal: cancelled.signal),
        )
        .then<void>((_) {}, onError: (Object _) {});
    await gateOpened(turn, gateRelease);
    cancelled.abort();
    await call;
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': toolCallId,
      'status': 'failed',
    });
  } finally {
    await client.close();
  }
  return 'end_turn';
}

/// A read through a link planted at `.chord/settings.json`, to a file
/// outside the project, the link taken away after. A working directory
/// that already holds that file is left alone, and says so.
Future<String> _readLinked(Turn turn) async {
  final client = await chordClient(turn);
  final directory = p.join(cwds[turn.sessionId] ?? '.', '.chord');
  final link = p.join(directory, 'settings.json');
  if (client == null ||
      FileSystemEntity.typeSync(link) != FileSystemEntityType.notFound) {
    await turn.say(['No link planted.']);
    await client?.close();
    return 'end_turn';
  }
  final made = !Directory(directory).existsSync();
  final outside = await Directory.systemTemp.createTemp('chord-fake-linked-');
  final target = p.join(outside.path, 'settings.json');
  try {
    await File(target).writeAsString(stringify(linkTarget));
    await Directory(directory).create(recursive: true);
    await Link(link).create(target);
    await callChord(turn, client, 'settings', {'action': 'read'});
    await callChord(turn, client, 'settings', {
      'action': 'read',
      'path': ['agent'],
    });
  } finally {
    try {
      await Link(link).delete();
    } on FileSystemException {
      // Already gone, as `rm` with `force` allows.
    }
    if (made) await Directory(directory).delete();
    await outside.delete(recursive: true);
    await client.close();
  }
  return 'end_turn';
}

final Map<String, Play> settingsPlays = {
  // A read through a link, which is an ordinary read.
  'settingsreadlinked': _readLinked,
  'settingsoverlap': _overlap,
  // Every key, folded on its row until ctrl+o.
  'settingsread': _calls([
    {'action': 'read'},
  ]),
  // One key under a mask, its secret never drawn.
  'settingsreadkey': _calls([
    {
      'action': 'read',
      'path': ['mcpServers', 'linear', 'env', 'TOKEN'],
    },
  ]),
  // A name that can be no key, refused.
  'settingsreadbad': _calls([
    {
      'action': 'read',
      'path': ['__proto__'],
    },
  ]),
  // A user-only key: `set` on an unset file, `unchanged` once it holds it.
  'settingstheme': _calls([
    {
      'action': 'set',
      'path': ['theme'],
      'value': 'light',
    },
  ]),
  // An agent's model, next to whatever else that agent holds.
  'settingsmodel': _calls([
    {
      'action': 'set',
      'path': ['agents', 'fake', 'model'],
      'value': 'fake-small',
    },
  ]),
  // The theme again: `remove`, or `unchanged` where it is not set.
  'settingsremove': _calls([
    {
      'action': 'remove',
      'path': ['theme'],
    },
  ]),
  // A kind B key, which a project's file holding it shadows.
  'settingsagent': _calls([
    {
      'action': 'set',
      'path': ['agent'],
      'value': 'fake',
    },
  ]),
  // The prompt's editing, which the window takes up at once.
  'settingsvim': _calls([
    {
      'action': 'set',
      'path': ['editorMode'],
      'value': 'vim',
    },
  ]),
  // What `/new` lists, which the window takes up at once.
  'settingsoffered': _calls([
    {
      'action': 'set',
      'path': ['offeredAgents'],
      'value': ['claude'],
    },
  ]),
  // One of each refusal that reading no file can tell, none asking the box.
  'settingsrefused': _calls([
    {
      'action': 'set',
      'path': ['agents', 'claude', 'modle'],
      'value': 'm',
    },
    {
      'action': 'set',
      'path': ['agents', 'claude', 'command'],
      'value': 'c',
    },
    {
      'action': 'remove',
      'path': ['mcpServers', 'linear'],
    },
    {
      'action': 'set',
      'path': ['agents', 'codex'],
      'value': <String, Object?>{},
    },
    {
      'action': 'set',
      'path': ['teamSelection'],
      'value': <String, Object?>{},
    },
    {
      'action': 'set',
      'path': ['editorMode'],
      'value': 'emacs',
    },
    {
      'action': 'set',
      'path': ['agents', 'nope', 'model'],
      'value': 'm',
    },
  ]),
  'settingswithdrawn': _withdrawn,
  // A value far taller than the room left above the box at 80x24.
  'settingslong': _calls([
    {
      'action': 'set',
      'path': ['agents', 'fake', 'model'],
      'value': 'l' * 1200,
    },
  ]),
};
