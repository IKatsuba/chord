/// The MCP servers chord hands the agent for its sessions, from the
/// original's `mcp.ts`: read from the `mcpServers` key of chord's settings
/// files and from the working directory's `.mcp.json`, checked, merged by
/// name, and turned into ACP's `McpServer` values, which go with
/// `session/new` and `session/load`. chord only reads these files; it never
/// writes `.mcp.json` or the agent's own configuration.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'js_trim.dart';
import 'settings.dart';

/// The transports ACP carries, which an entry's `type` may name.
const _transports = ['stdio', 'http', 'sse'];

/// A server chord passes, and the file that defined it.
final class DefinedServer {
  const DefinedServer(this.server, this.from);

  /// The server as ACP sends it.
  final Map<String, Object?> server;

  /// The file's path; the window shows it from the directory or `~`.
  final String from;

  @override
  bool operator ==(Object other) =>
      other is DefinedServer &&
      other.from == from &&
      jsonEncode(other.server) == jsonEncode(server);

  @override
  int get hashCode => Object.hash(from, jsonEncode(server));

  @override
  String toString() => 'DefinedServer($server, $from)';
}

/// What a file defined that chord did not pass: some of its servers, or all
/// of them ([servers] null) when the file itself could not be read as
/// servers.
final class Ignored {
  const Ignored(this.from, [this.servers]);

  final String from;

  /// How many servers; null for the whole file.
  final int? servers;

  @override
  bool operator ==(Object other) =>
      other is Ignored && other.from == from && other.servers == servers;

  @override
  int get hashCode => Object.hash(from, servers);

  @override
  String toString() => 'Ignored($from, ${servers ?? 'all'})';
}

/// One file's servers, what is wrong with it, and what that cost.
final class ReadServers {
  const ReadServers(this.servers, this.problems, this.ignored);

  final List<DefinedServer> servers;
  final List<SettingsProblem> problems;
  final List<Ignored> ignored;
}

const _none = ReadServers([], [], []);

/// A file that costs itself, with what is wrong with it.
ReadServers _fileIgnored(String file, String message) =>
    ReadServers(const [], [SettingsProblem(file, message)], [Ignored(file)]);

/// What zod calls a JSON value's type.
String _received(Object? value) => switch (value) {
  null => 'null',
  num() => 'number',
  String() => 'string',
  bool() => 'boolean',
  List() => 'array',
  _ => 'object',
};

/// What is wrong with one checked entry: where, and in zod's words.
typedef _Issue = ({List<String> path, String message});

_Issue _expected(List<String> path, String type, Object? value) => (
  path: path,
  message: 'invalid input: expected $type, received ${_received(value)}',
);

/// A key the entry needs is said to be missing, not of the wrong kind.
_Issue? _needed(Map<String, Object?> entry, String key, String type) {
  if (!entry.containsKey(key)) return (path: [key], message: 'missing');
  final value = entry[key];
  return value is String ? null : _expected([key], type, value);
}

/// A record of strings by name, as `env` and `headers` are.
_Issue? _strings(Map<String, Object?> entry, String key) {
  if (!entry.containsKey(key)) return null;
  final value = entry[key];
  if (value is! Map) return _expected([key], 'record', value);
  for (final MapEntry(key: name, :value) in value.entries) {
    if (value is! String) return _expected([key, '$name'], 'string', value);
  }
  return null;
}

/// [record]'s values as ACP's name and value pairs.
List<Map<String, Object?>> _pairs(Object? record) => [
  for (final MapEntry(:key, :value) in ((record as Map?) ?? const {}).entries)
    {'name': key, 'value': value},
];

/// [url] as zod's `url()` with an http or https protocol leaves it, trimmed
/// and without tabs or line breaks; null when it refuses it. Dart's [Uri]
/// takes more than a WHATWG parser and no maintained package parses as one,
/// so the hosts and ports it lets through that WHATWG refuses are refused
/// here; a punycode label IDNA would reject is not (docs/decisions.md).
String? _checkedUrl(String url) {
  final trimmed = jsTrim(url);
  if (!_httpPrefix.hasMatch(trimmed)) return null;
  final value = trimmed.replaceAll(_tabOrNewline, '');
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      !_portTaken(uri)) {
    return null;
  }
  // Uri has taken a bracketed IPv6 address as one already.
  if (uri.host.contains(':')) return value;
  final String host;
  try {
    host = Uri.decodeComponent(uri.host);
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
  if (host.contains(_forbiddenInDomain)) return null;
  if (_endsInNumber(host) && !_isIpv4(host)) return null;
  return value;
}

/// Whether [uri]'s port, if any, is one WHATWG takes; Uri reads the port
/// only when asked, and throws on one too long for an int.
bool _portTaken(Uri uri) {
  try {
    return !uri.hasPort || uri.port <= 65535;
  } on FormatException {
    return false;
  }
}

final _httpPrefix = RegExp(r'^https?://', caseSensitive: false);
final _tabOrNewline = RegExp(r'[\t\n\r]');

/// WHATWG's forbidden domain code points.
final _forbiddenInDomain = RegExp(r'[\x00-\x20#/:<>?@\[\\\]^|%\x7f]');

/// WHATWG's IPv4 number: decimal, `0x` hex or leading-zero octal.
BigInt? _ipv4Number(String part) {
  final (digits, radix) = switch (part) {
    '' => (null, 10),
    _ when part.toLowerCase().startsWith('0x') => (part.substring(2), 16),
    _ when part.length > 1 && part.startsWith('0') => (part.substring(1), 8),
    _ => (part, 10),
  };
  if (digits == null) return null;
  if (digits.isEmpty) return BigInt.zero;
  if (!_ipv4Digits[radix]!.hasMatch(digits)) return null;
  return BigInt.parse(digits, radix: radix);
}

final _ipv4Digits = {
  8: RegExp(r'^[0-7]+$'),
  10: RegExp(r'^[0-9]+$'),
  16: RegExp(r'^[0-9a-fA-F]+$'),
};

/// [host]'s labels without the empty one a trailing dot leaves.
List<String> _labels(String host) {
  final labels = host.split('.');
  if (labels.length > 1 && labels.last.isEmpty) labels.removeLast();
  return labels;
}

/// Whether WHATWG reads [host] as an IPv4 address: its last label a number.
bool _endsInNumber(String host) {
  final last = _labels(host).last;
  return last.isNotEmpty &&
      (_ipv4Digits[10]!.hasMatch(last) || _ipv4Number(last) != null);
}

/// Whether [host] is an IPv4 address WHATWG's parser takes.
bool _isIpv4(String host) {
  final numbers = [for (final part in _labels(host)) _ipv4Number(part)];
  if (numbers.length > 4 || numbers.contains(null)) return false;
  final byte = BigInt.from(255);
  if (numbers.take(numbers.length - 1).any((number) => number! > byte)) {
    return false;
  }
  return numbers.last! < BigInt.one << (8 * (5 - numbers.length));
}

/// [entry] checked as the transport its `type` names, a command's if none,
/// and the server ACP is sent; only the fields of that shape are kept, so
/// keys other tools add are let through and left out.
({Map<String, Object?>? server, _Issue? issue}) _parsedEntry(
  String name,
  Map<String, Object?> entry,
) {
  final type = entry['type'];
  if (type == 'http' || type == 'sse') {
    final issue =
        _needed(entry, 'url', 'string') ??
        (_checkedUrl(entry['url']! as String) != null
            ? null
            : (path: ['url'], message: 'invalid url')) ??
        _strings(entry, 'headers');
    if (issue != null) return (server: null, issue: issue);
    return (
      server: {
        'type': type,
        'name': name,
        'url': _checkedUrl(entry['url']! as String),
        'headers': _pairs(entry['headers']),
      },
      issue: null,
    );
  }

  final command = entry['command'];
  var issue = _needed(entry, 'command', 'string');
  if (issue == null && command == '') {
    issue = (
      path: ['command'],
      message: 'too small: expected string to have >=1 characters',
    );
  }
  if (issue == null && entry.containsKey('args')) {
    final args = entry['args'];
    if (args is! List) {
      issue = _expected(['args'], 'array', args);
    } else {
      for (final (index, arg) in args.indexed) {
        if (arg is! String) {
          issue = _expected(['args', '$index'], 'string', arg);
          break;
        }
      }
    }
  }
  issue ??= _strings(entry, 'env');
  if (issue != null) return (server: null, issue: issue);
  return (
    server: {
      'name': name,
      'command': command,
      'args': [...?(entry['args'] as List?)],
      'env': _pairs(entry['env']),
    },
    issue: null,
  );
}

/// [entry] as the transport its `type` names keeps it, a command's if
/// none: only that shape's fields, as the original's parsedEntry leaves a
/// success; null when it is not one.
Map<String, Object?>? checkedServerEntry(Object? entry) {
  if (entry is! Map<String, Object?>) return null;
  final type = entry['type'];
  final remote = type == 'http' || type == 'sse';
  if (!remote && entry.containsKey('type') && type != 'stdio') return null;
  if (_parsedEntry('', entry).issue != null) return null;
  return remote
      ? {
          'type': type,
          'url': _checkedUrl(entry['url']! as String),
          if (entry.containsKey('headers')) 'headers': entry['headers'],
        }
      : {
          if (entry.containsKey('type')) 'type': type,
          'command': entry['command'],
          if (entry.containsKey('args')) 'args': entry['args'],
          if (entry.containsKey('env')) 'env': entry['env'],
        };
}

/// The servers in one file's `mcpServers` object, by name. An entry that is
/// wrong costs only that server: it is named with what is wrong and left
/// out, and the file's other servers still count.
ReadServers parseServers(String file, Map<String, Object?> servers) {
  final found = <DefinedServer>[];
  final problems = <SettingsProblem>[];
  void ignored(List<String> path, String what) => problems.add(
    SettingsProblem(
      file,
      '"${['mcpServers', ...path].join('.')}": $what; the server is ignored',
    ),
  );

  for (final MapEntry(key: name, value: entry) in servers.entries) {
    if (name.trim().isEmpty) {
      ignored([name], 'a server needs a name');
      continue;
    }
    if (entry is! Map<String, Object?>) {
      ignored([name], 'expected an object with a command or a url');
      continue;
    }
    final type = entry['type'];
    // A null `type` is there, as the original's `undefined` check sees it.
    if (entry.containsKey('type') && !_transports.contains(type)) {
      ignored(
        [name, 'type'],
        '${jsonEncode(type)} is not a transport ACP carries (${_transports.join(', ')})',
      );
      continue;
    }
    // Claude Code's own `.mcp.json` names the transport of a URL; guessing
    // between HTTP and SSE would pick wrong half the time.
    if (!entry.containsKey('type') &&
        entry.containsKey('url') &&
        !entry.containsKey('command')) {
      ignored([
        name,
        'type',
      ], 'missing; a server with a url needs "http" or "sse"');
      continue;
    }
    final parsed = _parsedEntry(name, entry);
    if (parsed.issue case final issue?) {
      ignored([name, ...issue.path], issue.message);
      continue;
    }
    found.add(DefinedServer(parsed.server!, file));
  }

  return ReadServers(found, problems, [
    if (problems.isNotEmpty) Ignored(file, problems.length),
  ]);
}

/// A `.mcp.json`'s text. Keys other than `mcpServers` are other tools' and
/// left alone; a file without servers has none to pass. Text that is not a
/// JSON object, or servers that are not an object of them by name, cost the
/// file.
ReadServers parseMcpJson(String file, String text) {
  final Object? input;
  try {
    input = jsonDecode(text);
  } on FormatException catch (error) {
    return _fileIgnored(
      file,
      'not valid JSON (${error.message}); the file is ignored',
    );
  }
  if (input is! Map<String, Object?>) {
    return _fileIgnored(file, 'not a JSON object; the file is ignored');
  }
  if (!input.containsKey('mcpServers')) return _none;
  final servers = input['mcpServers'];
  if (servers is! Map<String, Object?>) {
    return _fileIgnored(
      file,
      '"mcpServers": expected an object of servers by name; the file is ignored',
    );
  }
  return parseServers(file, servers);
}

/// The working directory's `.mcp.json`; none there is no problem.
Future<ReadServers> readMcpJson(String cwd) async {
  final file = p.join(cwd, '.mcp.json');
  final String text;
  try {
    // As the original reads utf8: a malformed byte is replaced, not fatal.
    text = utf8.decode(await File(file).readAsBytes(), allowMalformed: true);
  } on PathNotFoundException {
    return _none;
  } on FileSystemException catch (error) {
    final os = error.osError?.message;
    final reason = os == null || os.isEmpty ? error.message : os;
    return _fileIgnored(file, 'cannot be read ($reason); the file is ignored');
  }
  return parseMcpJson(file, text);
}

/// Later lists win, server by server and whole: a server named again
/// replaces the earlier one, as merging a command's fields into a URL's
/// would make neither. It keeps the place it was first listed in.
List<DefinedServer> mergeServers(Iterable<List<DefinedServer>> lists) {
  final merged = <String, DefinedServer>{};
  for (final list in lists) {
    for (final defined in list) {
      merged['${defined.server['name']}'] = defined;
    }
  }
  return [...merged.values];
}

/// Every server for a session in [cwd], lowest precedence first: the user's
/// settings file, the project's `.mcp.json`, then the project's
/// `.chord/settings.json`, which is chord's own and the nearer word. The
/// problems are the servers' and `.mcp.json`'s; the settings files' other
/// problems are `loadSettings`'. What each file lost is kept for `/mcp`,
/// which is where someone looks for a server that is not there.
Future<ReadServers> loadMcpServers({
  required List<SettingsLayer> layers,
  required String cwd,
}) async {
  final project = p.join(cwd, '.chord', 'settings.json');
  ReadServers fromLayer(SettingsLayer layer) =>
      parseServers(layer.file, layer.settings.mcpServers ?? const {});
  final read = [
    for (final layer in layers)
      if (layer.file != project) fromLayer(layer),
    await readMcpJson(cwd),
    for (final layer in layers)
      if (layer.file == project) fromLayer(layer),
  ];
  return ReadServers(
    mergeServers(read.map((each) => each.servers)),
    [for (final each in read) ...each.problems],
    [for (final each in read) ...each.ignored],
  );
}
