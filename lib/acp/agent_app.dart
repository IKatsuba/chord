/// chord's ACP agent side, from the original's `acp/agent_app.ts`: the
/// methods `chord acp` serves and the params each is parsed by, as the
/// SDK's zod schemas (`zod.gen.js`) and chord's own `STEER` parse them, so
/// every handler reads what the original's would.
library;

import 'params.dart';

const _string = Str();
const _strings = Arr(_string, nullIsEmpty: true);

/// `defaultOnError(z.record(z.string(), z.unknown()).nullish())`.
const _meta = Catch(Opt(Rec(), nullable: true));

/// An object with nothing but `_meta`.
const _onlyMeta = Obj({'_meta': _meta});

/// `defaultOnError(z.boolean().optional().default(false), () => false)`.
const _flag = Catch(Default(Bool(), false), false);

/// The SDK's `zClientCapabilities`, each part falling back on its own.
const _clientCapabilities = Obj({
  'fs': Catch(
    Default(
      Obj({'readTextFile': _flag, 'writeTextFile': _flag, '_meta': _meta}),
      {'readTextFile': false, 'writeTextFile': false},
    ),
    {'readTextFile': false, 'writeTextFile': false},
  ),
  'terminal': _flag,
  'session': Catch(
    Opt(
      Obj({
        'compaction': Catch(Opt(Rec(), nullable: true)),
        'configOptions': Catch(
          Opt(
            Obj({
              'boolean': Catch(Opt(_onlyMeta, nullable: true)),
              '_meta': _meta,
            }),
            nullable: true,
          ),
        ),
        'notices': Catch(Opt(Rec(), nullable: true)),
        '_meta': _meta,
      }),
      nullable: true,
    ),
  ),
  'subagents': Catch(Opt(_onlyMeta, nullable: true)),
  'plan': Catch(Opt(_onlyMeta, nullable: true)),
  'auth': Catch(
    Default(Obj({'terminal': _flag, '_meta': _meta}), {'terminal': false}),
    {'terminal': false},
  ),
  'elicitation': Catch(
    Opt(
      Obj({
        'form': Catch(Opt(_onlyMeta, nullable: true)),
        'url': Catch(Opt(_onlyMeta, nullable: true)),
        '_meta': _meta,
      }),
      nullable: true,
    ),
  ),
  '_meta': _meta,
});

/// What a client that declares nothing, or nothing readable, has.
const _noCapabilities = {
  'fs': {'readTextFile': false, 'writeTextFile': false},
  'terminal': false,
  'auth': {'terminal': false},
};

/// The SDK's `zImplementation`.
const _implementation = Obj({
  'name': _string,
  'title': Catch(Opt(_string, nullable: true)),
  'version': _string,
  '_meta': _meta,
});

/// The SDK's `zAnnotations`.
const _annotations = Catch(
  Opt(
    Obj({
      'audience': Catch(
        Opt(
          Arr(Union([Lit('assistant'), Lit('user')]), skipInvalid: true),
          nullable: true,
        ),
      ),
      'lastModified': Catch(Opt(_string, nullable: true)),
      'priority': Catch(Opt(Num(), nullable: true)),
      '_meta': _meta,
    }),
    nullable: true,
  ),
);

/// The SDK's `wideInt()`: a number that is an integer.
const _wideInt = Refine(Num(), _isInteger);

bool _isInteger(Object? value) =>
    value is num && value == value.truncateToDouble();

/// `zEnvVariable` and `zHttpHeader`.
const _nameValue = Obj({'name': _string, 'value': _string, '_meta': _meta});

/// The SDK's `zMcpServer`: HTTP, SSE and ACP by their `type`, else stdio.
const _mcpServer = Union([
  And(
    Obj({
      'name': _string,
      'url': _string,
      'headers': Arr(_nameValue, nullIsEmpty: true),
      '_meta': _meta,
    }),
    Obj({'type': Lit('http')}),
  ),
  And(
    Obj({
      'name': _string,
      'url': _string,
      'headers': Arr(_nameValue, nullIsEmpty: true),
      '_meta': _meta,
    }),
    Obj({'type': Lit('sse')}),
  ),
  And(
    Obj({'name': _string, 'serverId': _string, '_meta': _meta}),
    Obj({'type': Lit('acp')}),
  ),
  Obj({
    'name': _string,
    'command': _string,
    'args': _strings,
    'env': Arr(_nameValue, nullIsEmpty: true),
    '_meta': _meta,
  }),
]);

const _mcpServers = Arr(_mcpServer, nullIsEmpty: true);

/// The boolean-or-value union of an initial config option and
/// `session/set_config_option`.
const _configValue = Union([
  Obj({'type': Lit('boolean'), 'value': Bool()}),
  Obj({'value': _string}),
]);

/// The SDK's `zInitialSessionConfigOption`s.
const _initialOptions = Opt(
  Arr(
    And(_configValue, Obj({'configId': _string, '_meta': _meta})),
    nullIsEmpty: true,
  ),
);

const _additionalDirectories = Opt(_strings);

/// The SDK's `zContentBlock`.
const _contentBlock = Union([
  And(
    Obj({'annotations': _annotations, 'text': _string, '_meta': _meta}),
    Obj({'type': Lit('text')}),
  ),
  And(
    Obj({
      'annotations': _annotations,
      'data': _string,
      'mimeType': _string,
      'uri': Catch(Opt(_string, nullable: true)),
      '_meta': _meta,
    }),
    Obj({'type': Lit('image')}),
  ),
  And(
    Obj({
      'annotations': _annotations,
      'data': _string,
      'mimeType': _string,
      '_meta': _meta,
    }),
    Obj({'type': Lit('audio')}),
  ),
  And(
    Obj({
      'annotations': _annotations,
      'description': Catch(Opt(_string, nullable: true)),
      'mimeType': Catch(Opt(_string, nullable: true)),
      'name': _string,
      'size': Catch(Opt(_wideInt, nullable: true)),
      'title': Catch(Opt(_string, nullable: true)),
      'uri': _string,
      '_meta': _meta,
    }),
    Obj({'type': Lit('resource_link')}),
  ),
  And(
    Obj({
      'annotations': _annotations,
      'resource': Union([
        Obj({
          'mimeType': Catch(Opt(_string, nullable: true)),
          'text': _string,
          'uri': _string,
          '_meta': _meta,
        }),
        Obj({
          'blob': _string,
          'mimeType': Catch(Opt(_string, nullable: true)),
          'uri': _string,
          '_meta': _meta,
        }),
      ]),
      '_meta': _meta,
    }),
    Obj({'type': Lit('resource')}),
  ),
]);

/// The SDK's `zSystemPrompt`.
const _systemPrompt = Opt(
  Obj({
    'mode': Union([Lit('append'), Lit('override'), _string]),
    'content': Arr(_contentBlock),
    '_meta': _meta,
  }),
  nullable: true,
);

/// The kinds `promptOf` takes whole.
const _knownBlocks = {'text', 'image', 'resource', 'resource_link'};

bool _unknownKind(Object? type) => !_knownBlocks.contains(type);

const _nullableString = Opt(_string, nullable: true);

/// chord's own `BLOCKS`: the kinds `promptOf` takes whole, any other only
/// by its kind, which it refuses; each block kept whole.
const _steerBlocks = Arr(
  Union([
    Obj({'type': Lit('text'), 'text': _string}, loose: true),
    Obj({
      'type': Lit('image'),
      'data': _string,
      'mimeType': _string,
    }, loose: true),
    Obj({
      'type': Lit('resource'),
      'resource': Union([
        Obj({
          'uri': _string,
          'mimeType': _nullableString,
          'text': _string,
        }, loose: true),
        Obj({
          'uri': _string,
          'mimeType': _nullableString,
          'blob': _string,
        }, loose: true),
      ]),
    }, loose: true),
    Obj({
      'type': Lit('resource_link'),
      'uri': _string,
      'name': _string,
    }, loose: true),
    Obj({'type': Refine(_string, _unknownKind)}, loose: true),
  ]),
);

/// The params of each method `chord acp` serves, by method.
const Map<String, Schema> paramsOf = {
  'initialize': Obj({
    'protocolVersion': Int(0, 65535),
    'clientCapabilities': Catch(
      Default(_clientCapabilities, _noCapabilities),
      _noCapabilities,
    ),
    'clientInfo': Catch(Opt(_implementation, nullable: true)),
    '_meta': _meta,
  }),
  'session/new': Obj({
    'cwd': _string,
    'additionalDirectories': _additionalDirectories,
    'mcpServers': _mcpServers,
    'systemPrompt': _systemPrompt,
    'configOptions': _initialOptions,
    '_meta': _meta,
  }),
  'session/load': Obj({
    'mcpServers': _mcpServers,
    'cwd': _string,
    'additionalDirectories': _additionalDirectories,
    'sessionId': _string,
    'systemPrompt': _systemPrompt,
    'configOptions': _initialOptions,
    '_meta': _meta,
  }),
  'session/resume': Obj({
    'sessionId': _string,
    'cwd': _string,
    'additionalDirectories': _additionalDirectories,
    'mcpServers': Opt(_mcpServers),
    'systemPrompt': _systemPrompt,
    'configOptions': _initialOptions,
    '_meta': _meta,
  }),
  'session/list': Obj({
    'cwd': _nullableString,
    'cursor': _nullableString,
    'archived': Opt(
      Union([Lit('exclude'), Lit('include'), Lit('only'), _string]),
      nullable: true,
    ),
    '_meta': _meta,
  }),
  'session/close': Obj({'sessionId': _string, '_meta': _meta}),
  'session/prompt': Obj({
    'sessionId': _string,
    'prompt': Arr(_contentBlock),
    '_meta': _meta,
  }),
  'session/cancel': Obj({'sessionId': _string, '_meta': _meta}),
  'session/set_config_option': And(
    _configValue,
    Obj({'sessionId': _string, 'configId': _string, '_meta': _meta}),
  ),
  'session/set_mode': Obj({
    'sessionId': _string,
    'modeId': _string,
    '_meta': _meta,
  }),
  'session/set_title': Obj({
    'sessionId': _string,
    'title': _string,
    '_meta': _meta,
  }),
  'auth/status': _onlyMeta,
  '_chord/session/steer': Obj({'sessionId': _string, 'prompt': _steerBlocks}),
  '_chord/agents/send': Obj({'sessionId': _string, 'prompt': _steerBlocks}),
  '_chord/agents/close': Obj({'sessionId': _string}),
  '_chord/monitors/stop': Obj({'sessionId': _string, 'id': _string}),
};

/// The parse of [method]'s params, for `ClientRequests`.
Map<String, Object?> Function(Object? params) checkOf(String method) =>
    checkedBy(paramsOf[method]!);
