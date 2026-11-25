// The params of each method the fake serves, read as the original's SDK
// reads them with zod before a handler runs: unknown keys dropped, known
// ones in the schema's order, and params that do not fit answered -32602
// `Invalid params` with zod's `format()` tree as data. A small reader of
// the same shape as the SDK's generated schemas: objects, intersections,
// unions whose every branch's issues go into the tree when none fits, and
// the lenient fields (`defaultOnError`, `defaultOnNull`) as they read.
import 'rpc.dart';

/// One issue: where, by path, and zod's words.
typedef _Issue = ({List<Object> path, String message});

/// What reading a value gave: its value, or none to leave its key out,
/// and the issues it raised.
typedef _Read = ({Object? value, bool omit, List<_Issue> issues});

_Read _ok(Object? value) => (value: value, omit: false, issues: const []);

const _Read _omitted = (value: null, omit: true, issues: []);

_Read _failed(String message) => (
  value: null,
  omit: true,
  issues: [(path: const <Object>[], message: message)],
);

List<_Issue> _under(Object key, List<_Issue> issues) => [
  for (final issue in issues)
    (path: [key, ...issue.path], message: issue.message),
];

/// zod's name for the type of [value], `undefined` when it was not there.
String _received(Object? value, bool present) => !present
    ? 'undefined'
    : switch (value) {
        null => 'null',
        String() => 'string',
        bool() => 'boolean',
        num() => 'number',
        List() => 'array',
        Map() => 'object',
        _ => 'unknown',
      };

String _expected(String type, Object? value, bool present) =>
    'Invalid input: expected $type, received ${_received(value, present)}';

/// A schema: reads a value that was [present], or not.
typedef _Schema = _Read Function(Object? value, bool present);

_Read _string(Object? value, bool present) =>
    value is String ? _ok(value) : _failed(_expected('string', value, present));

_Read _boolean(Object? value, bool present) =>
    value is bool ? _ok(value) : _failed(_expected('boolean', value, present));

_Read _number(Object? value, bool present) =>
    value is num ? _ok(value) : _failed(_expected('number', value, present));

_Read _integer(Object? value, bool present) =>
    value is num && value == value.truncate()
    ? _ok(value)
    : _failed(
        value is num
            ? 'Invalid input: expected int, received number'
            : _expected('number', value, present),
      );

_Read _record(Object? value, bool present) =>
    value is Map ? _ok(value) : _failed(_expected('record', value, present));

_Read _unknown(Object? value, bool present) => present ? _ok(value) : _omitted;

/// `z.literal(text)`.
_Schema _literal(String text) =>
    (value, present) =>
        value == text ? _ok(value) : _failed('Invalid input: expected "$text"');

/// `defaultOnError(schema.nullish(), () => undefined)`: never an issue;
/// null kept, what does not fit left out.
_Schema _lenient(_Schema schema) => (value, present) {
  if (!present) return _omitted;
  if (value == null) return _ok(null);
  final read = schema(value, true);
  return read.issues.isEmpty ? read : _omitted;
};

/// `schema.nullish()`.
_Schema _nullish(_Schema schema) =>
    (value, present) =>
        !present ? _omitted : (value == null ? _ok(null) : schema(value, true));

/// `schema.optional()`.
_Schema _optional(_Schema schema) =>
    (value, present) => present ? schema(value, true) : _omitted;

/// `defaultOnNull(schema, () => [])`: null is empty.
_Schema _orEmpty(_Schema schema) =>
    (value, present) =>
        present && value == null ? _ok(<Object?>[]) : schema(value, present);

/// `z.array(item)`.
_Schema _array(_Schema item) => (value, present) {
  if (value is! List) return _failed(_expected('array', value, present));
  final out = <Object?>[];
  final issues = <_Issue>[];
  for (final (index, each) in value.indexed) {
    final read = item(each, true);
    issues.addAll(_under(index, read.issues));
    out.add(read.value);
  }
  return (value: out, omit: false, issues: issues);
};

/// `vecSkipError(item)`: an array whose items that do not fit are dropped.
_Schema _skipping(_Schema item) => (value, present) {
  if (value is! List) return _failed(_expected('array', value, present));
  final kept = <Object?>[];
  for (final each in value) {
    final read = item(each, true);
    if (read.issues.isEmpty) kept.add(read.value);
  }
  return _ok(kept);
};

/// `z.object(fields)`: its fields in their order, unknown keys dropped.
_Schema _object(List<(String, _Schema)> fields) => (value, present) {
  if (value is! Map) return _failed(_expected('object', value, present));
  final out = <String, Object?>{};
  final issues = <_Issue>[];
  for (final (key, schema) in fields) {
    final read = schema(value[key], value.containsKey(key));
    issues.addAll(_under(key, read.issues));
    if (!read.omit && read.issues.isEmpty) out[key] = read.value;
  }
  return (value: out, omit: false, issues: issues);
};

/// `left.and(right)`: both read, the left's keys first.
_Schema _and(_Schema left, _Schema right) => (value, present) {
  final a = left(value, present);
  final b = right(value, present);
  final issues = [...a.issues, ...b.issues];
  if (issues.isNotEmpty) return (value: null, omit: true, issues: issues);
  return _ok(<String, Object?>{
    ...(a.value as Map<String, Object?>),
    ...(b.value as Map<String, Object?>),
  });
};

/// `z.union(options)`: the first that fits; when none does, every
/// option's issues, as `format()` lays an `invalid_union` out.
_Schema _union(List<_Schema> options) => (value, present) {
  final issues = <_Issue>[];
  for (final option in options) {
    final read = option(value, present);
    if (read.issues.isEmpty) return read;
    issues.addAll(read.issues);
  }
  return (value: null, omit: true, issues: issues);
};

final _meta = _lenient(_record);

final _nameValue = _object([
  ('name', _string),
  ('value', _string),
  ('_meta', _meta),
]);

_Schema _remote(String type) => _and(
  _object([
    ('name', _string),
    ('url', _string),
    ('headers', _orEmpty(_array(_nameValue))),
    ('_meta', _meta),
  ]),
  _object([('type', _literal(type))]),
);

/// `zMcpServer`.
final _mcpServer = _union([
  _remote('http'),
  _remote('sse'),
  _and(
    _object([('name', _string), ('serverId', _string), ('_meta', _meta)]),
    _object([('type', _literal('acp'))]),
  ),
  _object([
    ('name', _string),
    ('command', _string),
    ('args', _orEmpty(_array(_string))),
    ('env', _orEmpty(_array(_nameValue))),
    ('_meta', _meta),
  ]),
]);

final _annotations = _lenient(
  _object([
    (
      'audience',
      _lenient(_skipping(_union([_literal('assistant'), _literal('user')]))),
    ),
    ('lastModified', _lenient(_string)),
    ('priority', _lenient(_number)),
    ('_meta', _meta),
  ]),
);

_Schema _block(String type, List<(String, _Schema)> fields) =>
    _and(_object(fields), _object([('type', _literal(type))]));

/// `zContentBlock`.
final _Schema _contentBlock = _union([
  _block('text', [
    ('annotations', _annotations),
    ('text', _string),
    ('_meta', _meta),
  ]),
  _block('image', [
    ('annotations', _annotations),
    ('data', _string),
    ('mimeType', _string),
    ('uri', _lenient(_string)),
    ('_meta', _meta),
  ]),
  _block('audio', [
    ('annotations', _annotations),
    ('data', _string),
    ('mimeType', _string),
    ('_meta', _meta),
  ]),
  _block('resource_link', [
    ('annotations', _annotations),
    ('description', _lenient(_string)),
    ('mimeType', _lenient(_string)),
    ('name', _string),
    ('size', _lenient(_integer)),
    ('title', _lenient(_string)),
    ('uri', _string),
    ('_meta', _meta),
  ]),
  _block('resource', [
    ('annotations', _annotations),
    (
      'resource',
      _union([
        _object([
          ('mimeType', _lenient(_string)),
          ('text', _string),
          ('uri', _string),
          ('_meta', _meta),
        ]),
        _object([
          ('blob', _string),
          ('mimeType', _lenient(_string)),
          ('uri', _string),
          ('_meta', _meta),
        ]),
      ]),
    ),
    ('_meta', _meta),
  ]),
]);

/// A config option's value, as both `zInitialSessionConfigOption` and
/// `zSetSessionConfigOptionRequest` take it.
final _configValue = _union([
  _object([('type', _literal('boolean')), ('value', _boolean)]),
  _object([('value', _string)]),
]);

final _systemPrompt = _nullish(
  _object([
    ('mode', _string),
    ('content', _array(_contentBlock)),
    ('_meta', _meta),
  ]),
);

final _directories = _optional(_orEmpty(_array(_string)));

final _initialOptions = _optional(
  _orEmpty(
    _array(
      _and(_configValue, _object([('configId', _string), ('_meta', _meta)])),
    ),
  ),
);

/// Reads [params] with [schema], or fails as the SDK does.
Map<String, Object?> _parse(_Schema schema, Object? params) {
  final read = schema(params, true);
  if (read.issues.isNotEmpty) {
    throw RequestError.invalidParams(_tree(read.issues));
  }
  return (read.value as Map).cast<String, Object?>();
}

/// zod's `format()` tree of [issues].
Map<String, Object?> _tree(List<_Issue> issues) {
  final root = <String, Object?>{'_errors': <String>[]};
  for (final issue in issues) {
    var node = root;
    for (final part in issue.path) {
      node =
          node.putIfAbsent(
                '$part',
                () => <String, Object?>{'_errors': <String>[]},
              )
              as Map<String, Object?>;
    }
    (node['_errors'] as List<String>).add(issue.message);
  }
  return root;
}

final _newSession = _object([
  ('cwd', _string),
  ('additionalDirectories', _directories),
  ('mcpServers', _orEmpty(_array(_mcpServer))),
  ('systemPrompt', _systemPrompt),
  ('configOptions', _initialOptions),
  ('_meta', _meta),
]);

final _loadSession = _object([
  ('mcpServers', _orEmpty(_array(_mcpServer))),
  ('cwd', _string),
  ('additionalDirectories', _directories),
  ('sessionId', _string),
  ('systemPrompt', _systemPrompt),
  ('configOptions', _initialOptions),
  ('_meta', _meta),
]);

final _resumeSession = _object([
  ('sessionId', _string),
  ('cwd', _string),
  ('additionalDirectories', _directories),
  ('mcpServers', _optional(_orEmpty(_array(_mcpServer)))),
  ('systemPrompt', _systemPrompt),
  ('configOptions', _initialOptions),
  ('_meta', _meta),
]);

final _forkSession = _object([
  ('sessionId', _string),
  ('cwd', _string),
  ('additionalDirectories', _directories),
  ('mcpServers', _optional(_orEmpty(_array(_mcpServer)))),
  ('systemPrompt', _systemPrompt),
  ('_meta', _meta),
]);

Map<String, Object?> parseNewSession(Object? params) =>
    _parse(_newSession, params);

Map<String, Object?> parseLoadSession(Object? params) =>
    _parse(_loadSession, params);

Map<String, Object?> parseResumeSession(Object? params) =>
    _parse(_resumeSession, params);

Map<String, Object?> parseForkSession(Object? params) =>
    _parse(_forkSession, params);

Map<String, Object?> parsePrompt(Object? params) => _parse(
  _object([
    ('sessionId', _string),
    ('prompt', _array(_contentBlock)),
    ('_meta', _meta),
  ]),
  params,
);

Map<String, Object?> parseSetConfigOption(Object? params) => _parse(
  _and(
    _configValue,
    _object([('sessionId', _string), ('configId', _string), ('_meta', _meta)]),
  ),
  params,
);

Map<String, Object?> parseSetMode(Object? params) => _parse(
  _object([('sessionId', _string), ('modeId', _string), ('_meta', _meta)]),
  params,
);

Map<String, Object?> parseSetTitle(Object? params) => _parse(
  _object([('sessionId', _string), ('title', _string), ('_meta', _meta)]),
  params,
);

Map<String, Object?> parseListSessions(Object? params) => _parse(
  _object([
    ('cwd', _nullish(_string)),
    ('cursor', _nullish(_string)),
    ('archived', _nullish(_unknown)),
    ('_meta', _meta),
  ]),
  params,
);

Map<String, Object?> parseSessionId(Object? params) =>
    _parse(_object([('sessionId', _string), ('_meta', _meta)]), params);

Map<String, Object?> parseSessionOptions(Object? params) => _parse(
  _object([
    ('cwd', _string),
    ('additionalDirectories', _directories),
    ('sessionId', _nullish(_string)),
    ('_meta', _meta),
  ]),
  params,
);

Map<String, Object?> parseAuthenticate(Object? params) =>
    _parse(_object([('methodId', _string), ('_meta', _meta)]), params);

Map<String, Object?> parseMetaOnly(Object? params) =>
    _parse(_object([('_meta', _meta)]), params);

/// `initialize`: its protocol version checked, the rest as it came, which
/// the fake reads its client's capabilities from.
Map<String, Object?> parseInitialize(Object? params) {
  _parse(
    _object([
      (
        'protocolVersion',
        (value, present) {
          final read = _integer(value, present);
          if (read.issues.isNotEmpty) return read;
          final version = value as num;
          return version < 0
              ? _failed('Too small: expected number to be >=0')
              : version > 65535
              ? _failed('Too big: expected number to be <=65535')
              : read;
        },
      ),
    ]),
    params,
  );
  return (params as Map).cast<String, Object?>();
}

/// What a method takes that the fake reads whole: any object.
Map<String, Object?> parseObject(Object? params) => _parse(
  (value, present) =>
      value is Map ? _ok(value) : _failed(_expected('object', value, present)),
  params,
);
