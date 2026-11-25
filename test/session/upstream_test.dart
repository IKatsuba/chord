import 'dart:convert';

import 'package:chord/session/agent_state.dart';
import 'package:chord/session/upstream.dart';
import 'package:test/test.dart';

const none = <String, Object?>{};
const all = <String, Object?>{
  'subagents': <String, Object?>{},
  'plan': <String, Object?>{},
  'session': {
    'compaction': <String, Object?>{},
    'notices': <String, Object?>{},
  },
};

Map<String, Object?> announce(String id, [String state = 'running']) => {
  'sessionUpdate': 'subagent_update',
  'sessionId': id,
  'state': {'state': state},
};

const chunk = <String, Object?>{
  'sessionUpdate': 'agent_message_chunk',
  'content': {'type': 'text', 'text': 'hi'},
};

/// A deep copy, to show an input was left as it was.
Object? copied(Object? value) => jsonDecode(jsonEncode(value));

void main() {
  group('what is not sent', () {
    const needs = <(String, Map<String, Object?>)>[
      ('subagent_update', {'subagents': <String, Object?>{}}),
      ('session_message', {'subagents': <String, Object?>{}}),
      ('session_message_chunk', {'subagents': <String, Object?>{}}),
      ('plan_update', {'plan': <String, Object?>{}}),
      ('plan_removed', {'plan': <String, Object?>{}}),
      (
        'compaction_update',
        {
          'session': {'compaction': <String, Object?>{}},
        },
      ),
      (
        'compaction_summary_chunk',
        {
          'session': {'compaction': <String, Object?>{}},
        },
      ),
      (
        'notice',
        {
          'session': {'notices': <String, Object?>{}},
        },
      ),
    ];

    for (final (kind, declared) in needs) {
      test('$kind goes only to a client that declares it', () {
        expect(reaches(none, kind), isFalse);
        expect(reaches(declared, kind), isTrue);
      });

      test('$kind is not let through by another capability', () {
        for (final (_, other) in needs) {
          if (jsonEncode(other) == jsonEncode(declared)) continue;
          expect(reaches(other, kind), isFalse);
        }
      });
    }

    for (final kind in [
      'user_message_chunk',
      'agent_message_chunk',
      'agent_thought_chunk',
      'tool_call',
      'tool_call_update',
      'plan',
      'available_commands_update',
      'config_option_update',
      'session_info_update',
      'usage_update',
    ]) {
      test('$kind needs nothing declared, and a child\'s needs subagents', () {
        expect(reaches(none, kind), isTrue);
        expect(reaches(none, kind, child: true), isFalse);
        expect(
          reaches({'subagents': <String, Object?>{}}, kind, child: true),
          isTrue,
        );
      });
    }

    test('a kind the v1 schema lacks never goes', () {
      for (final kind in [
        'never_heard_of',
        'toString',
        'constructor',
        '__proto__',
        'current_mode_update',
      ]) {
        expect(reaches(all, kind), isFalse);
      }
    });

    test('a capability declared false or null is not declared', () {
      expect(reaches({'plan': false}, 'plan_update'), isFalse);
      expect(reaches({'plan': null}, 'plan_update'), isFalse);
      expect(reaches({'session': null}, 'notice'), isFalse);
    });
  });

  group('aliases', () {
    test('a free id stays; a taken one counts up', () {
      expect(aliasFor({}, 's1'), 's1');
      expect(aliasFor({'s1'}, 's1'), 's1~2');
      expect(aliasFor({'s1', 's1~2'}, 's1'), 's1~3');
    });
  });

  group('ids going up', () {
    test('main goes under its upstream id, whole, _meta too', () {
      final update = {
        ...chunk,
        '_meta': {
          'chord/filled': ['x'],
        },
      };
      expect(
        mapUpdate(
          const UpstreamSession('s1', 's1~2'),
          none,
          update,
        ).notification,
        {'sessionId': 's1~2', 'update': update},
      );
    });

    test('a child goes under <main>/<child>, its own under '
        '<main>/<child>/<id>', () {
      var session = mapUpdate(
        const UpstreamSession.of('s1'),
        all,
        announce('c'),
      ).session;
      final nested = mapUpdate(session, all, announce('d'), subagentId: 'c');
      session = nested.session;
      expect(nested.notification, {
        'sessionId': 's1/c',
        'update': {...announce('d'), 'sessionId': 's1/c/d'},
      });
      expect(
        mapUpdate(
          session,
          all,
          chunk,
          subagentId: 'd',
        ).notification?['sessionId'],
        's1/c/d',
      );
    });

    test('under an alias the composite takes the alias', () {
      final session = mapUpdate(
        const UpstreamSession('s1', 's1~2'),
        all,
        announce('c'),
      ).session;
      expect(
        mapUpdate(
          session,
          all,
          chunk,
          subagentId: 'c',
        ).notification?['sessionId'],
        's1~2/c',
      );
    });

    test('a composite is looked up exactly, a slash in an id no matter', () {
      final session = mapUpdate(
        const UpstreamSession.of('s1'),
        all,
        announce('tool/1'),
      ).session;
      expect(childOf(session, 's1/tool/1'), 'tool/1');
      expect(childOf(session, 's1/tool'), isNull);
      expect(childOf(session, 's1'), isNull);
    });

    test('a child is known even to a client that never hears of it', () {
      final (:session, :notification) = mapUpdate(
        const UpstreamSession.of('s1'),
        none,
        announce('c'),
      );
      expect(notification, isNull);
      expect(childOf(session, 's1/c'), 'c');
      expect(
        mapUpdate(session, none, chunk, subagentId: 'c').notification,
        isNull,
      );
    });

    test('a message between sessions names them as the client knows '
        'them', () {
      final session = mapUpdate(
        const UpstreamSession.of('s1'),
        all,
        announce('c'),
      ).session;
      final update =
          mapUpdate(session, all, {
                'sessionUpdate': 'session_message',
                'messageId': 'm',
                'senderSessionId': 's1',
                'recipientSessionId': 'c',
              }).notification?['update']
              as Map;
      expect(update['senderSessionId'], 's1');
      expect(update['recipientSessionId'], 's1/c');
    });

    test('main\'s command list goes with chord\'s team and new first, a '
        'name both have being chord\'s, and marks the list sent', () {
      final update = {
        'sessionUpdate': 'available_commands_update',
        'availableCommands': [
          {'name': 'review', 'description': 'the agent\'s own'},
          {'name': 'new', 'description': 'the agent\'s new'},
          {'name': 'team', 'description': 'the agent\'s team'},
        ],
      };
      final mapped = mapUpdate(const UpstreamSession.of('s1'), none, update);
      expect(mapped.notification, {
        'sessionId': 's1',
        'update': {
          'sessionUpdate': 'available_commands_update',
          'availableCommands': [
            {
              'name': 'team',
              'description': 'Show and run teams of agents',
              'input': {
                'hint':
                    'list | run <name> <job> | show <name> | stop <run> | new <words>',
              },
            },
            {
              'name': 'new',
              'description': 'Open a new agent beside main',
              'input': {'hint': '[agent] [--name <name>]'},
            },
            {'name': 'review', 'description': 'the agent\'s own'},
          ],
        },
      });
      expect(mapped.session.commandsSent, isTrue);
      expect(commandsIfNone(mapped.session).notification, isNull);
    });

    test('a child\'s and a subagent\'s command lists are their own', () {
      final update = {
        'sessionUpdate': 'available_commands_update',
        'availableCommands': [
          {'name': 'review', 'description': 'its own'},
        ],
      };
      final child = mapUpdate(childSession('c', 's1/c'), all, update);
      expect(child.notification, {'sessionId': 's1/c', 'update': update});
      expect(child.session.commandsSent, isFalse);
      final grown = mapUpdate(
        const UpstreamSession.of('s1'),
        all,
        announce('sub'),
      ).session;
      expect(mapUpdate(grown, all, update, subagentId: 'sub').notification, {
        'sessionId': 's1/sub',
        'update': update,
      });
    });

    test('an agent that sends none gets chord\'s once', () {
      final first = commandsIfNone(const UpstreamSession('s1', 'up'));
      expect(first.notification, {
        'sessionId': 'up',
        'update': {
          'sessionUpdate': 'available_commands_update',
          'availableCommands': [
            {
              'name': 'team',
              'description': 'Show and run teams of agents',
              'input': {
                'hint':
                    'list | run <name> <job> | show <name> | stop <run> | new <words>',
              },
            },
            {
              'name': 'new',
              'description': 'Open a new agent beside main',
              'input': {'hint': '[agent] [--name <name>]'},
            },
          ],
        },
      });
      expect(commandsIfNone(first.session).notification, isNull);
    });

    test('chord\'s own task says chord can cancel it; an adapter\'s does '
        'not', () {
      final task = {
        ...announce('t1'),
        '_meta': {
          'chord/task': {'name': 'scan', 'runtime': 'codex'},
        },
      };
      final ours = mapUpdate(const UpstreamSession.of('s1'), all, task);
      expect((ours.notification!['update'] as Map)['capabilities'], {
        'cancel': <String, Object?>{},
      });
      final theirs = mapUpdate(
        const UpstreamSession.of('s1'),
        all,
        announce('t2'),
      );
      expect(
        (theirs.notification!['update'] as Map).containsKey('capabilities'),
        isFalse,
      );
    });

    test('an update with no kind goes nowhere', () {
      expect(
        mapUpdate(const UpstreamSession.of('s1'), all, {'x': 1}).notification,
        isNull,
      );
    });
  });

  group('what an ask may name', () {
    test('the session and a child it announced, nothing else', () {
      final session = mapUpdate(const UpstreamSession('s1', 's1~2'), none, {
        'sessionUpdate': 'subagent_update',
        'sessionId': 'c',
      }).session;
      expect(asksIn(session, 's1'), isTrue);
      expect(asksIn(session, 'c'), isTrue);
      expect(asksIn(session, 'other'), isFalse);
      expect(asksIn(session, 's1~2'), isFalse);
      expect(asksIn(session, 'toString'), isFalse);
    });
  });

  group('subagent state words', () {
    const table = <(String, Map<String, Object?>)>[
      ('completed', {'state': 'idle', 'stopReason': 'end_turn'}),
      ('failed', {'state': 'idle', 'stopReason': 'error'}),
      ('cancelled', {'state': 'idle', 'stopReason': 'cancelled'}),
      ('disconnected', {'state': 'unknown'}),
    ];
    for (final (word, state) in table) {
      test('a draft\'s $word goes as ACP\'s, the word in _meta', () {
        final update =
            mapUpdate(const UpstreamSession.of('s1'), all, {
                  ...announce('c', word),
                  '_meta': {'kept': 1},
                }).notification?['update']
                as Map;
        expect(update['state'], state);
        expect(update['_meta'], {
          'kept': 1,
          'chord/agent': {'state': word},
        });
      });
    }

    for (final word in [
      'running',
      'idle',
      'requires_action',
      'unknown',
      'toString',
      'constructor',
    ]) {
      test('the word $word goes as it is', () {
        expect(
          mapUpdate(
            const UpstreamSession.of('s1'),
            all,
            announce('c', word),
          ).notification?['update'],
          {...announce('c', word), 'sessionId': 's1/c'},
        );
      });
    }
  });

  group('one shape for configuration', () {
    Map<String, Object?> select(
      String id,
      String? category,
      String currentValue,
      List<String> values,
    ) => {
      'type': 'select',
      'id': id,
      'name': id.toUpperCase(),
      'category': ?category,
      'currentValue': currentValue,
      'options': [
        for (final value in values) {'value': value, 'name': value},
      ],
    };
    const legacyModes = {
      'currentModeId': 'ask',
      'availableModes': [
        {'id': 'ask', 'name': 'Ask'},
      ],
    };
    const legacyModels = {
      'currentModelId': 'big',
      'availableModels': [
        {'modelId': 'big', 'name': 'Big'},
      ],
    };

    test('modes the older way become a mode option', () {
      expect(configOptionsOf(const AgentState(modes: legacyModes)), [
        {
          'type': 'select',
          'id': 'mode',
          'name': 'Mode',
          'category': 'mode',
          'currentValue': 'ask',
          'options': [
            {'value': 'ask', 'name': 'Ask'},
          ],
        },
      ]);
    });

    test('an agent with only session/set_model shows the same model '
        'option', () {
      expect(configOptionsOf(const AgentState(models: legacyModels)), [
        {
          'type': 'select',
          'id': 'model',
          'name': 'Model',
          'category': 'model',
          'currentValue': 'big',
          'options': [
            {'value': 'big', 'name': 'Big'},
          ],
        },
      ]);
    });

    test('the agent\'s own options keep their ids and names', () {
      final own = AgentState(
        configOptions: [
          select('approvals', 'mode', 'a', ['a', 'b']),
          select('engine', 'model', 'x', ['x']),
          select('effort', null, 'low', ['low', 'high']),
        ],
      );
      expect(
        [
          for (final option in configOptionsOf(own))
            [option['id'], option['name']],
        ],
        [
          ['approvals', 'APPROVALS'],
          ['engine', 'ENGINE'],
          ['effort', 'EFFORT'],
        ],
      );
      expect(configSetter(own, 'approvals'), ConfigSetter.mode);
      expect(configSetter(own, 'engine'), ConfigSetter.model);
      expect(configSetter(own, 'effort'), ConfigSetter.option);
      expect(configSetter(own, 'nothing'), isNull);
    });

    test('both kinds of agent read alike', () {
      const made = AgentState(modes: legacyModes, models: legacyModels);
      const own = AgentState(
        configOptions: [
          {
            'type': 'select',
            'id': 'mode',
            'category': 'mode',
            'currentValue': 'ask',
            'options': [
              {'value': 'ask', 'name': 'Ask'},
            ],
            'name': 'Mode',
          },
          {
            'type': 'select',
            'id': 'model',
            'category': 'model',
            'currentValue': 'big',
            'options': [
              {'value': 'big', 'name': 'Big'},
            ],
            'name': 'Model',
          },
        ],
      );
      expect(
        jsonEncode(configOptionsOf(own)),
        jsonEncode(configOptionsOf(made)),
      );
      expect(configSetter(made, 'model'), ConfigSetter.model);
    });

    test('what an agent lacks is absent; booleans never appear', () {
      expect(configOptionsOf(AgentState.empty), isEmpty);
      expect(
        configOptionsOf(
          const AgentState(
            configOptions: [
              {
                'type': 'boolean',
                'id': 'fast',
                'name': 'Fast',
                'currentValue': true,
              },
            ],
          ),
        ),
        isEmpty,
      );
    });

    test('grouped values are flattened in the agent\'s order', () {
      const grouped = {
        'type': 'select',
        'id': 'effort',
        'name': 'Effort',
        'currentValue': 'b',
        'options': [
          {
            'group': 'one',
            'name': 'One',
            'options': [
              {'value': 'a', 'name': 'A'},
            ],
          },
          {
            'group': 'two',
            'name': 'Two',
            'options': [
              {'value': 'b', 'name': 'B'},
            ],
          },
        ],
      };
      expect(
        configOptionsOf(
          const AgentState(configOptions: [grouped]),
        ).single['options'],
        [
          {'value': 'a', 'name': 'A'},
          {'value': 'b', 'name': 'B'},
        ],
      );
    });

    test('an update goes only when the list differs, marked and whole', () {
      const before = AgentState(modes: legacyModes);
      final (:session, configOptions: _) = answeredConfig(
        const UpstreamSession('s1', 'up'),
        before,
      );
      expect(configChange(session, before).notification, isNull);
      const after = AgentState(
        modes: {'currentModeId': 'ask', 'availableModes': <Object?>[]},
      );
      final changed = configChange(session, after);
      expect(changed.notification, {
        'sessionId': 'up',
        'update': {
          'sessionUpdate': 'config_option_update',
          'configOptions': <Object?>[],
          '_meta': {
            'chord/filled': ['configOptions'],
          },
        },
      });
      expect(configChange(changed.session, after).notification, isNull);
    });

    test('the agent\'s own config updates never go as it sent them', () {
      for (final update in [
        {'sessionUpdate': 'current_mode_update', 'currentModeId': 'x'},
        {'sessionUpdate': 'config_option_update', 'configOptions': <Object?>[]},
      ]) {
        expect(
          mapUpdate(const UpstreamSession.of('s1'), all, update).notification,
          isNull,
        );
      }
    });
  });

  group('a permission\'s answer', () {
    const options = [
      {'optionId': 'yes', 'name': 'Yes', 'kind': 'allow_once'},
      {'optionId': 'no', 'name': 'No', 'kind': 'reject_once'},
    ];

    test('an offered option is chosen', () {
      expect(
        permissionAnswerOf(options, {
          'outcome': {'outcome': 'selected', 'optionId': 'yes'},
        }),
        'yes',
      );
    });

    test('anything else is a refusal', () {
      expect(
        permissionAnswerOf(options, {
          'outcome': {'outcome': 'selected', 'optionId': 'maybe'},
        }),
        isNull,
      );
      expect(
        permissionAnswerOf(options, {
          'outcome': {'outcome': 'cancelled'},
        }),
        isNull,
      );
      expect(permissionAnswerOf(options, null), isNull);
    });

    test('a prototype-like option id is accepted only when offered', () {
      const selected = {
        'outcome': {'outcome': 'selected', 'optionId': 'toString'},
      };
      expect(permissionAnswerOf(const [], selected), isNull);
      expect(
        permissionAnswerOf(const [
          {'optionId': 'toString', 'name': 'Allow', 'kind': 'allow_once'},
        ], selected),
        'toString',
      );
    });
  });

  group('a form\'s answer', () {
    test('each of ACP\'s words passes as it came', () {
      const accept = {
        'action': 'accept',
        'content': {'name': 'x'},
      };
      expect(elicitationReplyOf(accept), accept);
      expect(elicitationReplyOf({'action': 'decline'}), {'action': 'decline'});
      expect(elicitationReplyOf({'action': 'cancel'}), {'action': 'cancel'});
    });

    test('an error, or any other word, is cancel', () {
      expect(elicitationReplyOf(null), {'action': 'cancel'});
      expect(elicitationReplyOf({'action': 'maybe'}), {'action': 'cancel'});
    });
  });

  group('a prompt\'s blocks', () {
    Map<String, Object?> text(String value) => {'type': 'text', 'text': value};
    const image = {'type': 'image', 'data': 'AAAA', 'mimeType': 'image/png'};
    const link = {
      'type': 'resource_link',
      'name': 'a.ts',
      'uri': 'file:///a.ts',
    };

    test('text joined in order, images and links apart', () {
      final (:prompt, :refused) = promptOf(
        [text('a'), link, image, text('b')],
        'fake',
        takesImages: true,
      );
      expect(refused, isNull);
      expect(prompt!.text, 'a\nb');
      expect(prompt.parts.images, [(mimeType: 'image/png', data: 'AAAA')]);
      expect(prompt.parts.links, [link]);
      expect(prompt.parts.resources, isEmpty);
    });

    test('an image to an agent without them is refused in the window\'s '
        'words', () {
      expect(
        promptOf([image], 'fake', takesImages: false).refused,
        'fake does not take images',
      );
    });

    test('resource and audio are refused', () {
      expect(
        promptOf(
          [
            {
              'type': 'resource',
              'resource': {'uri': 'file:///a', 'text': 'x'},
            },
          ],
          'fake',
          takesImages: true,
        ).refused,
        'fake does not take embedded resources',
      );
      expect(
        promptOf(
          [
            {'type': 'audio', 'data': 'AAAA', 'mimeType': 'audio/wav'},
          ],
          'fake',
          takesImages: true,
        ).refused,
        'A prompt cannot carry a audio block.',
      );
    });

    const resources = [
      {
        'type': 'resource',
        'resource': {'uri': 'custom:text', 'text': '', 'mimeType': null},
        '_meta': {'source': 'client'},
      },
      {
        'type': 'resource',
        'resource': {'uri': 'custom:blob', 'blob': 'opaque, not checked'},
      },
    ];

    test('keeps whole text and blob blocks when embedded context is '
        'advertised', () {
      final prompt = promptOf(
        resources,
        'fake',
        takesImages: true,
        takesEmbeddedContext: true,
      ).prompt!;
      expect(prompt.text, '');
      expect(prompt.parts.images, isEmpty);
      expect(prompt.parts.links, isEmpty);
      expect(prompt.parts.resources, resources);
    });

    test('refuses a whole prompt when any resource is unsupported', () {
      for (final resource in resources) {
        expect(
          promptOf([text('held'), resource], 'fake', takesImages: true).refused,
          'fake does not take embedded resources',
        );
      }
    });

    test('embedded context does not allow audio or an unknown block kind', () {
      for (final block in [
        {'type': 'audio', 'data': '', 'mimeType': 'audio/wav'},
        {'type': 'unknown'},
      ]) {
        expect(
          promptOf(
            [block],
            'fake',
            takesImages: true,
            takesEmbeddedContext: true,
          ).refused,
          isNotNull,
        );
      }
    });
  });

  group('a message no prompt began', () {
    test('is a user chunk, marked who from', () {
      expect(messageChunk('up', 'hi', from: {'name': 'lead'}), {
        'sessionId': 'up',
        'update': {
          'sessionUpdate': 'user_message_chunk',
          'content': {'type': 'text', 'text': 'hi'},
          '_meta': {
            'chord/from': {'name': 'lead'},
          },
        },
      });
    });

    test('without a sender it has no _meta', () {
      expect(
        (messageChunk('up', 'hi')['update'] as Map).containsKey('_meta'),
        isFalse,
      );
    });
  });

  group('chord\'s commands', () {
    Map<String, Object?> text(String words) => {'type': 'text', 'text': words};

    test('/team and /new are chord\'s, with the words after them and whether '
        'each is alone', () {
      for (final (words, command) in [
        ('/team', (name: 'team', args: '', alone: true)),
        ('/team list', (name: 'team', args: 'list', alone: true)),
        (
          '/team run bugfix fix\nit',
          (name: 'team', args: 'run bugfix fix\nit', alone: true),
        ),
      ]) {
        expect(commandOf([text(words)]), command, reason: words);
      }
      expect(commandOf([text('/team'), text('more')])?.alone, isFalse);
      expect(commandOf([text('hello'), text('/team')]), isNull);
      expect(commandOf([text('  /new codex --name a b  ')]), (
        name: 'new',
        args: 'codex --name a b',
        alone: true,
      ));
      expect(commandOf([text('/new')]), (name: 'new', args: '', alone: true));
      expect(
        commandOf([
          {'type': 'image', 'data': '', 'mimeType': 'image/png'},
          text('/new\nfake'),
        ]),
        (name: 'new', args: 'fake', alone: false),
      );
      // Anything else goes as typed.
      for (final words in [
        '/teams',
        'team',
        'say /team',
        '/',
        '/newer',
        'new',
        '/model x',
        '',
      ]) {
        expect(commandOf([text(words)]), isNull, reason: words);
      }
      expect(commandOf(const []), isNull);
    });
  });

  group('mapper session boundaries', () {
    test('equal child ids stay under separate aliases without changing the '
        'input', () {
      const original = UpstreamSession('main', 'first');
      final update = {
        ...announce('child/opaque', 'completed'),
        '_meta': {'kept': 'value'},
      };
      final before = copied(update);
      final first = mapUpdate(original, all, update);
      final second = mapUpdate(
        const UpstreamSession('main', 'second'),
        all,
        update,
      );
      final firstUpdate = first.notification?['update'] as Map;
      expect(firstUpdate['sessionId'], 'first/child/opaque');
      expect(firstUpdate['state'], {'state': 'idle', 'stopReason': 'end_turn'});
      expect(
        (second.notification?['update'] as Map)['sessionId'],
        'second/child/opaque',
      );
      expect(original.children, isEmpty);
      expect(update, before);
    });

    test('one session announcing config does not suppress another', () {
      const state = AgentState.empty;
      final first = configChange(const UpstreamSession('same', 'first'), state);
      final second = configChange(
        const UpstreamSession('same', 'second'),
        state,
      );
      expect(first.notification?['sessionId'], 'first');
      expect(second.notification?['sessionId'], 'second');
      expect(configChange(first.session, state).notification, isNull);
    });
  });

  group('a call\'s references to subagents going up', () {
    const text = {
      'type': 'content',
      'content': {'type': 'text', 'text': 'Stopped.'},
    };
    List<Object?>? sent(
      Map<String, Object?> capabilities,
      List<Object?> content,
    ) {
      final session = mapUpdate(
        const UpstreamSession('s1', 's1~2'),
        capabilities,
        announce('c'),
      ).session;
      return (mapUpdate(session, capabilities, {
                'sessionUpdate': 'tool_call_update',
                'toolCallId': 'stop',
                'content': content,
              }).notification?['update']
              as Map)['content']
          as List<Object?>?;
    }

    test('an announced child\'s reference goes by its alias; any other id is '
        'dropped, never raw', () {
      expect(
        sent(all, [
          text,
          {'type': 'session', 'sessionId': 'c'},
          {'type': 'session', 'sessionId': 's1'},
          {'type': 'session', 'sessionId': 'stranger'},
        ]),
        [
          text,
          {'type': 'session', 'sessionId': 's1~2/c'},
        ],
      );
    });

    test('a client that takes no subagents gets none of them; content of '
        'references alone goes empty', () {
      expect(
        sent(none, [
          text,
          {'type': 'session', 'sessionId': 'c'},
        ]),
        [text],
      );
      expect(
        sent(all, [
          {'type': 'session', 'sessionId': 'stranger'},
        ]),
        isEmpty,
      );
    });

    UpstreamSession announced(String upstream) {
      var session = UpstreamSession('main', upstream);
      for (final (id, parent) in [('child', null), ('grand', 'child')]) {
        session = mapUpdate(session, all, {
          'sessionUpdate': 'subagent_update',
          'sessionId': id,
          'title': id,
          'state': {'state': 'running'},
        }, subagentId: parent).session;
      }
      return session;
    }

    const opaque = {
      'example.com/opaque': {
        'array': [false, null, 2],
      },
    };
    const kept = {
      'type': 'content',
      'content': {'type': 'text', 'text': 'Kept.', '_meta': opaque},
      '_meta': opaque,
    };

    for (final kind in ['tool_call', 'tool_call_update']) {
      test('$kind keeps metadata and other content, resolves ended '
          'grandchildren, and leaves the input unchanged', () {
        final session = mapUpdate(
          announced('public'),
          all,
          announce('grand', 'completed'),
          subagentId: 'child',
        ).session;
        final update = {
          'sessionUpdate': kind,
          'toolCallId': 'call',
          'title': 'Stop',
          'status': 'completed',
          '_meta': opaque,
          'content': [
            kept,
            {'type': 'session', 'sessionId': 'grand', '_meta': opaque},
            {'type': 'session', 'sessionId': 'main'},
            {'type': 'session', 'sessionId': 'unknown'},
          ],
        };
        final before = copied(update);
        final notification = mapUpdate(
          session,
          all,
          update,
          subagentId: 'child',
        ).notification;
        expect(notification?['sessionId'], 'public/child');
        expect(notification?['update'], {
          ...update,
          'content': [
            kept,
            {
              'type': 'session',
              'sessionId': 'public/child/grand',
              '_meta': opaque,
            },
          ],
        });
        expect(update, before);
        expect(mapUpdate(session, none, update).notification?['update'], {
          ...update,
          'content': [kept],
        });
      });

      test('$kind cannot resolve another main\'s child alias or raw ids it '
          'never announced', () {
        final first = announced('main');
        final second = announced('main~2');
        final update = {
          'sessionUpdate': kind,
          'toolCallId': 'call',
          'title': 'Stop',
          'content': [
            {'type': 'session', 'sessionId': 'child'},
            {'type': 'session', 'sessionId': 'grand'},
            {'type': 'session', 'sessionId': 'main/child'},
            {'type': 'session', 'sessionId': 'main~2/child'},
          ],
        };
        expect(mapUpdate(first, all, update).notification?['update'], {
          ...update,
          'content': [
            {'type': 'session', 'sessionId': 'main/child'},
            {'type': 'session', 'sessionId': 'main/child/grand'},
          ],
        });
        expect(mapUpdate(second, all, update).notification?['update'], {
          ...update,
          'content': [
            {'type': 'session', 'sessionId': 'main~2/child'},
            {'type': 'session', 'sessionId': 'main~2/child/grand'},
          ],
        });
        expect(
          mapUpdate(
            const UpstreamSession.of('other'),
            all,
            update,
          ).notification?['update'],
          {...update, 'content': <Object?>[]},
        );
        expect(mapUpdate(first, none, update).notification?['update'], {
          ...update,
          'content': <Object?>[],
        });
      });
    }
  });
}
