import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:chord/acp/schema.dart';
import 'package:test/test.dart';

void main() {
  // What the original's fake agent wrote, captured from it playing `text`,
  // `thought`, `tools`, `edit`, `permission`, `unknown`, `error`, `plan`,
  // `calls` and `rewrite`; the last two lines are from its source
  // (scenarios/modes.ts and main.ts's HISTORY), which those do not play.
  final lines = File(
    Isolate.resolvePackageUriSync(
      Uri.parse('package:chord/acp/schema.dart'),
    )!.resolve('../../test/fixtures/acp/fake_agent.jsonl').toFilePath(),
  ).readAsLinesSync();
  final messages = [
    for (final line in lines) jsonDecode(line) as Map<String, Object?>,
  ];

  Map<String, Object?> result(int id) =>
      messages.firstWhere(
            (m) => m['id'] == id && m.containsKey('result'),
          )['result']
          as Map<String, Object?>;

  SessionUpdate update(String kind, [bool Function(SessionUpdate)? where]) {
    for (final message in messages) {
      if (message['method'] != 'session/update') continue;
      final notification = SessionNotification.fromJson(
        message['params'] as Map<String, Object?>,
      );
      final update = notification.update;
      if (update.kind == kind && (where == null || where(update))) {
        return update;
      }
    }
    throw StateError('no $kind');
  }

  test('initialize\'s answer', () {
    final init = InitializeResponse.fromJson(result(1));
    expect(init.protocolVersion, 1);
    expect(init.agentCapabilities!.loadSession, isTrue);
    expect(init.agentCapabilities!.promptCapabilities!.image, isTrue);
    expect(
      init.agentCapabilities!.promptCapabilities!.embeddedContext,
      isFalse,
    );
    expect(init.agentCapabilities!.sessionCapabilities, {'list': {}});
    expect(init.agentInfo!.name, 'chord-fake-agent');
    expect(init.agentInfo!.version, '0.0.0');
    expect(init.authMethods, isNull);
    expect(init.meta, isNull);
  });

  test('initialize\'s answer from an agent nobody signed in to, with its '
      'ways in', () {
    // The fake with `--auth-required methods`, as the original's
    // connection_test plays it.
    final [answer, _] = [
      for (final line in File(
        Isolate.resolvePackageUriSync(
              Uri.parse('package:chord/acp/schema.dart'),
            )!
            .resolve('../../test/fixtures/acp/fake_agent_auth_required.jsonl')
            .toFilePath(),
      ).readAsLinesSync())
        jsonDecode(line) as Map<String, Object?>,
    ];
    final init = InitializeResponse.fromJson(
      answer['result'] as Map<String, Object?>,
    );
    final [login, sso] = init.authMethods!;
    expect(login.id, 'fake-login');
    expect(login.name, 'Log in with the fake');
    expect(login.description, 'Run `fake login` in the terminal');
    expect(sso.id, 'fake-sso');
    expect(sso.name, 'Log in with SSO');
    expect(sso.description, isNull);
    expect(login.toJson(), {
      'id': 'fake-login',
      'name': 'Log in with the fake',
      'description': 'Run `fake login` in the terminal',
    });
  });

  test('session/new\'s answer', () {
    final opened = NewSessionResponse.fromJson(result(2));
    expect(opened.sessionId, isNotEmpty);
    expect(opened.modes!['currentModeId'], 'default');
    expect(opened.configOptions, hasLength(3));
  });

  test('session/prompt\'s answer', () {
    final answer = PromptResponse.fromJson(result(3));
    expect(answer.stopReason, StopReason.endTurn);
    expect(answer.usage!['totalTokens'], 2000);
  });

  test('the chunk kinds', () {
    final message = update(SessionUpdateKind.agentMessageChunk) as ContentChunk;
    expect(message.content.type, 'text');
    expect(message.content.text, 'Hello');
    expect(message.messageId, isNull);
    final thought = update(SessionUpdateKind.agentThoughtChunk) as ContentChunk;
    expect(thought.content.text, 'Considering');
    final mine = update(SessionUpdateKind.userMessageChunk) as ContentChunk;
    expect(mine.content.text, 'tools');
  });

  test('a tool call, with locations, and its updates', () {
    final call =
        update(
              SessionUpdateKind.toolCall,
              (u) => (u as ToolCall).toolCallId == 'rewrite-4',
            )
            as ToolCall;
    expect(call.title, 'Edit src/table.ts');
    expect(call.toolKind, ToolKind.edit);
    expect(call.status, ToolCallStatus.inProgress);
    expect(call.locations!.single.path, 'src/table.ts');
    expect(call.locations!.single.line, 1);

    final read =
        update(
              SessionUpdateKind.toolCallUpdate,
              (u) =>
                  (u as ToolCallUpdate).toolCallId == 'read-1' &&
                  u.status == ToolCallStatus.completed,
            )
            as ToolCallUpdate;
    expect(read.title, isNull);
    expect(read.content!.single.type, 'content');
    expect(read.content!.single.content!.text, '# chord');
    expect(read.content!.single.diff, isNull);
    expect(read.rawOutput, {'lines': 1});

    final edit =
        update(
              SessionUpdateKind.toolCallUpdate,
              (u) => (u as ToolCallUpdate).toolCallId == 'edit-2',
            )
            as ToolCallUpdate;
    final diff = edit.content!.single.diff!;
    expect(diff.path, 'src/greeting.ts');
    expect(diff.oldText, startsWith('export function greet'));
    expect(diff.newText, startsWith('/** Greets someone by name. */'));

    final failed =
        update(
              SessionUpdateKind.toolCallUpdate,
              (u) => (u as ToolCallUpdate).status == ToolCallStatus.failed,
            )
            as ToolCallUpdate;
    expect(failed.content!.single.content!.text, 'File does not exist.');
  });

  test('a plan', () {
    final plan = update(SessionUpdateKind.plan) as Plan;
    expect(
      [for (final e in plan.entries) e.content],
      ['Read the code', 'Write the change', 'Run the tests'],
    );
    expect(plan.entries.first.priority, 'high');
    expect(plan.entries.first.status, 'completed');
    expect(plan.entries[1].status, 'in_progress');
  });

  test('the commands offered', () {
    final commands =
        update(SessionUpdateKind.availableCommandsUpdate)
            as AvailableCommandsUpdate;
    expect(
      [for (final c in commands.availableCommands) c.name],
      ['greet', 'echo'],
    );
    expect(commands.availableCommands.first.hint, isNull);
    expect(commands.availableCommands.last.hint, 'text to repeat');
    expect(
      commands.availableCommands.first.description,
      'Say hello from the fake agent',
    );
  });

  test('the mode and the usage', () {
    final mode =
        update(SessionUpdateKind.currentModeUpdate) as CurrentModeUpdate;
    expect(mode.currentModeId, 'plan');
    final usage = update(SessionUpdateKind.usageUpdate) as UsageUpdate;
    expect(usage.used, 2000);
    expect(usage.size, 1000000);
    expect(usage.costAmount, 0.0125);
    expect(usage.costCurrency, 'USD');
  });

  test('an unknown kind is kept, raw', () {
    final unknown = update('future_update');
    expect(unknown.kind, 'future_update');
    expect(unknown.toJson()['detail'], 'from later');
  });

  test('a permission request', () {
    final request = RequestPermissionRequest.fromJson(
      messages.firstWhere(
            (m) => m['method'] == 'session/request_permission',
          )['params']
          as Map<String, Object?>,
    );
    expect(request.sessionId, isNotEmpty);
    expect(request.toolCall.toolCallId, 'write-3');
    expect(request.toolCall.toolKind, ToolKind.edit);
    expect(request.toolCall.status, ToolCallStatus.pending);
    expect(request.toolCall.content!.single.diff!.oldText, isNull);
    expect(request.toolCall.rawInput, {
      'file_path': 'notes.txt',
      'content': 'notes\n',
    });
    expect(
      [for (final o in request.options) o.optionId],
      ['allow', 'always', 'deny'],
    );
    expect(
      [for (final o in request.options) o.kind],
      [
        PermissionOptionKind.allowOnce,
        PermissionOptionKind.allowAlways,
        PermissionOptionKind.rejectOnce,
      ],
    );
    expect(request.options.first.name, 'Allow');
  });

  test('what chord writes', () {
    expect(
      InitializeRequest(
        protocolVersion: protocolVersion,
        clientCapabilities: ClientCapabilities(),
        clientInfo: Implementation(name: 'chord', version: '0.0.1'),
      ).toJson(),
      {
        'protocolVersion': 1,
        'clientCapabilities': <String, Object?>{},
        'clientInfo': {'name': 'chord', 'version': '0.0.1'},
      },
    );
    expect(NewSessionRequest(cwd: '/w', mcpServers: const []).toJson(), {
      'cwd': '/w',
      'mcpServers': <Object?>[],
    });
    final prompt = PromptRequest(
      sessionId: 's',
      prompt: [ContentBlock.text('hi')],
    );
    expect(prompt.toJson(), {
      'sessionId': 's',
      'prompt': [
        {'type': 'text', 'text': 'hi'},
      ],
    });
    expect(prompt.prompt.single.text, 'hi');
    expect(RequestPermissionResponse.cancelled().toJson(), {
      'outcome': {'outcome': 'cancelled'},
    });
    expect(RequestPermissionResponse.cancelled().optionId, isNull);
    final selected = RequestPermissionResponse.selected('allow');
    expect(selected.toJson(), {
      'outcome': {'outcome': 'selected', 'optionId': 'allow'},
    });
    expect(selected.outcome, 'selected');
    expect(selected.optionId, 'allow');
    expect(CancelNotification(sessionId: 's').toJson(), {'sessionId': 's'});
  });

  test('what chord writes reads back through the same views', () {
    final init = InitializeRequest.fromJson(
      jsonDecode(
            jsonEncode(
              InitializeRequest(
                protocolVersion: protocolVersion,
                clientCapabilities: ClientCapabilities(),
                clientInfo: Implementation(
                  name: 'chord',
                  version: '0.0.1',
                  title: 'chord',
                ),
              ),
            ),
          )
          as Map<String, Object?>,
    );
    expect(init.protocolVersion, 1);
    expect(init.clientCapabilities.toJson(), isEmpty);
    expect(init.clientCapabilities.meta, isNull);
    expect(init.clientInfo!.name, 'chord');
    expect(init.clientInfo!.version, '0.0.1');
    expect(init.clientInfo!.title, 'chord');
    expect(init.meta, isNull);

    final opened = NewSessionRequest.fromJson({
      'cwd': '/w',
      'mcpServers': [
        {'name': 'x'},
      ],
    });
    expect(opened.cwd, '/w');
    expect(opened.mcpServers, [
      {'name': 'x'},
    ]);
    expect(CancelNotification.fromJson({'sessionId': 's'}).sessionId, 's');

    final caps = InitializeResponse.fromJson(result(1)).agentCapabilities!;
    expect(caps.mcpCapabilities, {'http': true, 'sse': true});
    expect(caps.promptCapabilities!.audio, isFalse);
    expect(caps.meta, isNull);

    final image = ContentBlock.fromJson({
      'type': 'image',
      'data': 'AA==',
      'mimeType': 'image/png',
      '_meta': {'k': 1},
    });
    expect(image.type, 'image');
    expect(image.text, isNull);
    expect(image.meta, {'k': 1});
    final terminal = ToolCallContent.fromJson({
      'type': 'terminal',
      'terminalId': 't',
    });
    expect(terminal.content, isNull);
    expect(terminal.diff, isNull);
    expect(terminal.toJson()['terminalId'], 't');
  });

  test('a field of the wrong type throws where it is read', () {
    final call = SessionUpdate.fromJson({
      'sessionUpdate': 'tool_call',
      'toolCallId': 7,
      'title': 'x',
    });
    expect(call.kind, 'tool_call');
    expect(() => (call as ToolCall).toolCallId, throwsA(isA<TypeError>()));
    expect(
      () => PromptResponse.fromJson({}).stopReason,
      throwsA(isA<TypeError>()),
    );
  });

  test('every message survives decode and encode, unknown fields and _meta '
      'too', () {
    for (final line in lines) {
      final decoded = jsonDecode(line) as Map<String, Object?>;
      expect(jsonDecode(jsonEncode(decoded)), decoded);
    }
    final extended = {
      'sessionId': 's',
      'update': {
        'sessionUpdate': 'tool_call',
        'toolCallId': 'c',
        'title': 't',
        'kind': 'teleport',
        'status': 'warping',
        'unknownField': [1, 2.5, 'x', null, true],
        '_meta': {
          'terminal_output': {'data': 'out'},
          'nested': {'deep': {}},
        },
      },
      '_meta': {'traceId': 'abc'},
    };
    final notification = SessionNotification.fromJson(
      jsonDecode(jsonEncode(extended)) as Map<String, Object?>,
    );
    final call = notification.update as ToolCall;
    expect(call.toolKind, 'teleport');
    expect(call.status, 'warping');
    expect(call.meta, {
      'terminal_output': {'data': 'out'},
      'nested': {'deep': {}},
    });
    expect(notification.meta, {'traceId': 'abc'});
    expect(jsonDecode(jsonEncode(notification.toJson())), extended);
    // A view is the decoded map itself, so nothing is copied or dropped.
    expect(identical(notification.toJson()['update'], call.toJson()), isTrue);
  });

  group('tester: schema view boundaries', () {
    test('absent and explicit null optional capabilities share defaults', () {
      for (final json in <Map<String, Object?>>[
        {},
        {'loadSession': null, 'promptCapabilities': null, '_meta': null},
      ]) {
        final caps = AgentCapabilities.fromJson(json);
        expect(caps.loadSession, isFalse);
        expect(caps.promptCapabilities, isNull);
        expect(caps.mcpCapabilities, isNull);
        expect(caps.sessionCapabilities, isNull);
        expect(caps.meta, isNull);
        expect(caps.toJson(), same(json));
      }
      for (final json in <Map<String, Object?>>[
        {},
        {'image': null, 'audio': null, 'embeddedContext': null},
      ]) {
        final caps = PromptCapabilities.fromJson(json);
        expect(caps.image, isFalse);
        expect(caps.audio, isFalse);
        expect(caps.embeddedContext, isFalse);
      }
    });

    test('sparse tool updates leave every optional field absent', () {
      final json = <String, Object?>{'toolCallId': 'c'};
      final call = ToolCallUpdate.fromJson(json);
      expect(call.toolCallId, 'c');
      expect(call.title, isNull);
      expect(call.toolKind, isNull);
      expect(call.status, isNull);
      expect(call.content, isNull);
      expect(call.locations, isNull);
      expect(call.rawInput, isNull);
      expect(call.rawOutput, isNull);
      expect(call.toJson(), same(json));
      expect(json, {'toolCallId': 'c'});
    });

    test(
      'nested getters preserve unknown permission fields and option kinds',
      () {
        final json = <String, Object?>{
          'sessionId': 's',
          'toolCall': {
            'toolCallId': 'c',
            'title': '界👩‍💻e\u0301\u001b[31m',
            'content': [
              {
                'type': 'future_content',
                'nested': [null, 1.25, true],
              },
            ],
            'locations': [
              {'path': 'file.dart', 'future': 7},
            ],
            'rawInput': [1, 'raw'],
            'rawOutput': false,
            '_meta': {
              'future': {'x': 1},
            },
          },
          'options': [
            {
              'optionId': 'future',
              'name': 'Later',
              'kind': 'future_kind',
              '_meta': {'x': 1},
            },
          ],
          'future': {
            'list': [1, 2, 3],
          },
          '_meta': {'trace': 't'},
        };
        final decoded = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
        final request = RequestPermissionRequest.fromJson(decoded);
        expect(request.toolCall.content!.single.content, isNull);
        expect(request.toolCall.content!.single.diff, isNull);
        expect(request.toolCall.locations!.single.line, isNull);
        expect(request.toolCall.rawInput, [1, 'raw']);
        expect(request.toolCall.rawOutput, false);
        expect(request.options.single.kind, 'future_kind');
        expect(request.meta, {'trace': 't'});
        expect(request.toolCall.title, '界👩‍💻e\u0301\u001b[31m');
        expect(request.toJson(), same(decoded));
        expect(jsonDecode(jsonEncode(request.toJson())), json);
      },
    );

    test('unknown stop reasons and permission outcomes survive unchanged', () {
      final prompt = <String, Object?>{
        'stopReason': 'future_reason',
        '_meta': {'n': 3},
        'future': [null, false],
      };
      final response = PromptResponse.fromJson(prompt);
      expect(response.stopReason, 'future_reason');
      expect(response.toJson(), same(prompt));
      final permission = <String, Object?>{
        'outcome': {'outcome': 'future_outcome', 'optionId': 1},
      };
      final answer = RequestPermissionResponse.fromJson(permission);
      expect(answer.outcome, 'future_outcome');
      expect(answer.optionId, isNull);
      expect(jsonDecode(jsonEncode(answer.toJson())), permission);
    });

    test(
      'malformed nested fields fail only when the corresponding getter reads them',
      () {
        final init = InitializeResponse.fromJson({
          'protocolVersion': 2,
          'authMethods': [
            {'id': 1, 'name': 'name'},
          ],
          'agentCapabilities': {'loadSession': 'yes'},
        });
        expect(init.protocolVersion, 2);
        expect(init.authMethods!.single.name, 'name');
        expect(() => init.authMethods!.single.id, throwsA(isA<TypeError>()));
        expect(init.agentCapabilities!.loadSession, isTrue);
        final request = PromptRequest.fromJson({
          'sessionId': 's',
          'prompt': [1],
        });
        expect(request.sessionId, 's');
        expect(() => request.prompt, throwsA(isA<TypeError>()));
      },
    );

    test(
      'future prompt blocks survive read and semantic encode round trip',
      () {
        final json = <String, Object?>{
          'sessionId': 's',
          'prompt': [
            {
              'type': 'future_block',
              'payload': {
                'a': [1, null],
              },
              '_meta': {'x': true},
            },
            {'type': 'text', 'text': '界👩‍💻e\u0301\u001b[31m'},
          ],
          'future': [1.5, false],
        };
        final request = PromptRequest.fromJson(json);
        expect(request.prompt.first.type, 'future_block');
        expect(request.prompt.first.text, isNull);
        expect(request.prompt.first.meta, {'x': true});
        expect(request.prompt.last.text, '界👩‍💻e\u0301\u001b[31m');
        expect(jsonDecode(jsonEncode(request.toJson())), json);
        expect(request.toJson(), same(json));
      },
    );
  });

  group('an agent'
      's initialize answer, read raw as the original reads it', () {
    test('truthiness is JavaScript'
        's', () {
      for (final value in <Object?>[
        true,
        1,
        -1,
        'yes',
        'false',
        <Object?>[],
        <String, Object?>{},
      ]) {
        expect(jsTruthy(value), isTrue, reason: '$value');
      }
      for (final value in <Object?>[null, false, 0, 0.0, double.nan, '']) {
        expect(jsTruthy(value), isFalse, reason: '$value');
      }
    });

    test('a capability of the wrong type reads as absent, not an error', () {
      expect(
        InitializeResponse.fromJson({
          'protocolVersion': 1,
          'agentCapabilities': 3,
        }).agentCapabilities,
        isNull,
      );
      final caps = InitializeResponse.fromJson({
        'protocolVersion': 1,
        'agentCapabilities': {
          'sessionCapabilities': 'title',
          'promptCapabilities': [true],
          'mcpCapabilities': 'http',
          'loadSession': 'yes',
        },
        'agentInfo': 'fake',
      });
      expect(caps.agentCapabilities!.sessionCapabilities, isNull);
      expect(caps.agentCapabilities!.promptCapabilities, isNull);
      expect(caps.agentCapabilities!.mcpCapabilities, isNull);
      expect(caps.agentCapabilities!.loadSession, isTrue);
      expect(caps.agentInfo, isNull);
    });

    test('a prompt capability is taken only when it is true', () {
      final prompts = PromptCapabilities.fromJson({
        'image': 'yes',
        'audio': 1,
        'embeddedContext': true,
      });
      expect(prompts.image, isFalse);
      expect(prompts.audio, isFalse);
      expect(prompts.embeddedContext, isTrue);
    });
  });

  group('tester U6b raw initialize boundaries', () {
    test(
      'all prompt flags require literal true while loadSession stays truthy',
      () {
        for (final (value, truthy) in <(Object?, bool)>[
          (true, true),
          (false, false),
          (null, false),
          (0, false),
          (-1, true),
          ('', false),
          ('false', true),
          (<Object?>[], true),
          (<String, Object?>{}, true),
        ]) {
          final raw = <String, Object?>{
            'protocolVersion': 1,
            'future': [1, null],
            'agentCapabilities': {
              'loadSession': value,
              'promptCapabilities': {
                'image': value,
                'audio': value,
                'embeddedContext': value,
              },
            },
          };
          final init = InitializeResponse.fromJson(raw);
          expect(init.agentCapabilities!.loadSession, truthy, reason: '$value');
          final prompt = init.agentCapabilities!.promptCapabilities!;
          expect([
            prompt.image,
            prompt.audio,
            prompt.embeddedContext,
          ], List.filled(3, value == true));
          expect(init.toJson(), same(raw));
          expect(jsonDecode(jsonEncode(init.toJson())), raw);
        }
      },
    );

    test('wrong typed enclosing objects stay raw and read as absent', () {
      for (final value in <Object?>[false, 1, 'capabilities', <Object?>[]]) {
        final raw = <String, Object?>{
          'protocolVersion': 1,
          'agentCapabilities': value,
          'agentInfo': value,
        };
        final init = InitializeResponse.fromJson(raw);
        expect(init.agentCapabilities, isNull);
        expect(init.agentInfo, isNull);
        expect(init.toJson(), same(raw));
        final caps = AgentCapabilities.fromJson({
          'sessionCapabilities': value,
          'promptCapabilities': value,
          'mcpCapabilities': value,
          '_meta': value,
        });
        expect(caps.sessionCapabilities, isNull);
        expect(caps.promptCapabilities, isNull);
        expect(caps.mcpCapabilities, isNull);
        expect(caps.meta, isNull);
      }
    });
  });
}
