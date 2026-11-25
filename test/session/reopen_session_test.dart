import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/enrich.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Map<String, Object?> notification(
  String kind,
  Map<String, Object?> fields, [
  String id = 'literal/id',
]) => {
  'jsonrpc': '2.0',
  'method': 'session/update',
  'params': {
    'sessionId': id,
    'update': {'sessionUpdate': kind, ...fields},
  },
};
Map<String, Object?> say(String text, [String id = 'literal/id']) =>
    notification('agent_message_chunk', {
      'content': {'type': 'text', 'text': text},
    }, id);
Map<String, Object?> mode(String value) =>
    notification('current_mode_update', {'currentModeId': value});
Map<String, Object?> savedPrompt([String text = 'LOCAL']) => {
  'type': 'prompt',
  'turnId': 'saved',
  'prompt': text,
  'images': 0,
  'at': 1.25,
};

final class Memory {
  Memory({this.load = true, this.resume = true}) {
    process = MemoryAgentProcess(
      onSignal: (_) {
        process.exit();
        process.closeStdout();
        process.closeStderr();
      },
    );
  }
  final bool load, resume;
  late final MemoryAgentProcess process;
  String? openedCwd;
  final reopenAsked = Completer<void>();
  String? refusal;
  bool malformed = false, hang = false, promptUpdate = false;
  List<Map<String, Object?>>? pre;
  List<Map<String, Object?>> post = [];
  List<Map<String, Object?>> get requests => process.stdin.messages;
  final answer = <String, Object?>{
    'modes': {'currentModeId': 'B', 'availableModes': <Object?>[]},
  };

  SessionOpener get open =>
      ({
        required command,
        env,
        required cwd,
        required onTraffic,
        required onPermission,
        relay,
        cancellationToken,
      }) {
        openedCwd = cwd;
        return connectAgent(
          process,
          onTraffic: (traffic) {
            onTraffic(traffic);
            if (traffic case ChordTraffic(:final message)) _react(message);
          },
          onPermission: onPermission,
          relay: relay,
          cancellationToken: cancellationToken,
          stop: const StopBounds(
            exit: Duration.zero,
            term: Duration(milliseconds: 10),
            kill: Duration(milliseconds: 100),
          ),
        );
      };

  void _react(Map<String, Object?> request) {
    if (!request.containsKey('id') || process.exited) return;
    final method = request['method'], id = request['id'];
    if (method == 'initialize') {
      process.send({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'protocolVersion': 1,
          'agentCapabilities': {
            'loadSession': load,
            'sessionCapabilities': {if (resume) 'resume': <String, Object?>{}},
          },
        },
      });
    } else if (method == 'session/new') {
      process.send({
        'jsonrpc': '2.0',
        'id': id,
        'result': {'sessionId': 'literal/id', ...answer},
      });
    } else if (method == 'session/load' || method == 'session/resume') {
      if (!reopenAsked.isCompleted) reopenAsked.complete();
      if (hang) return;
      final frames = <Map<String, Object?>>[
        ...?pre,
        if (pre == null && method == 'session/load') ...[
          notification('user_message_chunk', {
            'content': {'type': 'text', 'text': 'load past'},
          }),
          say('HISTORY'),
        ],
        if (refusal != null)
          {
            'jsonrpc': '2.0',
            'id': id,
            'error': {'code': -32000, 'message': refusal},
          }
        else
          {'jsonrpc': '2.0', 'id': id, 'result': malformed ? 'wrong' : answer},
        ...post,
      ];
      process.writeStdout(
        utf8.encode(frames.map((m) => '${jsonEncode(m)}\n').join()),
      );
    } else {
      if (method == 'session/prompt' && promptUpdate) {
        process.send(say('live prompt reply'));
      }
      process.send({
        'jsonrpc': '2.0',
        'id': id,
        'result': method == 'session/prompt'
            ? {'stopReason': 'end_turn'}
            : <String, Object?>{},
      });
    }
  }

  Future<void> close(Session session) async {
    await session.close();
    expect(process.exited, isTrue);
    expect(process.stdin.addsAfterClose, 0);
  }
}

Future<Directory> directory() async {
  final dir = await Directory.systemTemp.createTemp('chord-reopen-test-');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  return dir;
}

void main() {
  test(
    'closed call cannot claim replacement admission with the same ACP id',
    () async {
      final dir = await directory();
      final oldMemory = Memory(), newMemory = Memory();
      final resolved = Completer<List<acp.ContentBlock>>();
      final old = await openSession(
        agent: 'memory',
        command: 'memory',
        cwd: dir.path,
        open: oldMemory.open,
        resolveMentions: (_, _, {cancellationToken}) => resolved.future,
      );
      final heard = <String>[];
      final pending = old.prompt(
        'old',
        mentions: ['fixture'],
        turnId: 'old',
        onSubmitted: (s) => heard.add(s.turnId),
      );
      await oldMemory.close(old);
      final replacement = await openSession(
        agent: 'memory',
        command: 'memory',
        cwd: dir.path,
        open: newMemory.open,
      );
      try {
        expect(replacement.id, old.id);
        await replacement
            .prompt(
              'replacement',
              turnId: 'replacement',
              onSubmitted: (s) => heard.add(s.turnId),
            )
            .result;
        resolved.complete([
          acp.ContentBlock.fromJson({
            'type': 'resource_link',
            'uri': 'file:fixture',
            'name': 'fixture',
          }),
        ]);
        await pending.result;
        expect(heard, ['replacement']);
        expect(
          oldMemory.requests.where((m) => m['method'] == 'session/prompt'),
          isEmpty,
        );
      } finally {
        await newMemory.close(replacement);
      }
    },
  );

  test(
    'cancellation at reply ingress publishes no successful Session',
    () async {
      final dir = await directory();
      final memory = Memory();
      final token = CancellationToken();
      await expectLater(
        openSession(
          agent: 'memory',
          command: 'memory',
          cwd: dir.path,
          open: memory.open,
          resume: Resume(sessionId: 'literal/id', cwd: dir.path),
          cancellationToken: token,
          onTraffic: (traffic) {
            if (traffic case AgentTraffic(
              message: {'id': final Object id, 'result': _},
            )) {
              if (memory.requests.any(
                (m) => m['id'] == id && m['method'] == 'session/load',
              )) {
                token.cancel();
              }
            }
          },
        ),
        throwsA(isA<CancelledException>()),
      );
      expect(memory.process.exited, isTrue);
    },
  );

  test(
    'unsupported version and pre-cancelled preparation start zero processes',
    () async {
      final dir = await directory();
      final file = File(p.join(dir.path, 'record.jsonl'));
      final bytes = utf8.encode(
        encodeRecord({'type': 'session', 'version': 2}),
      );
      await file.writeAsBytes(bytes);
      var opens = 0;
      Future<Agent> opener({
        required Object command,
        Map<String, String>? env,
        required String cwd,
        required void Function(Traffic) onTraffic,
        required PermissionHandler onPermission,
        Relay? relay,
        CancellationToken? cancellationToken,
      }) async {
        opens++;
        throw StateError('must not open');
      }

      final resume = Resume(
        sessionId: 'literal/id',
        cwd: dir.path,
        record: file.path,
      );
      await expectLater(
        openSession(
          agent: 'memory',
          command: 'memory',
          cwd: dir.path,
          resume: resume,
          open: opener,
        ),
        throwsA(isA<UnsupportedRecordVersion>()),
      );
      final token = CancellationToken()..cancel();
      await expectLater(
        openSession(
          agent: 'memory',
          command: 'memory',
          cwd: dir.path,
          resume: resume,
          open: opener,
          cancellationToken: token,
        ),
        throwsA(isA<CancelledException>()),
      );
      expect(opens, 0);
      expect(await file.readAsBytes(), bytes);
    },
  );

  for (final (local, canResume, canLoad, expected) in [
    (true, true, true, 'session/resume'),
    (true, true, false, 'session/resume'),
    (true, false, true, 'session/load'),
    (false, true, true, 'session/load'),
    (false, true, false, 'session/resume'),
    (false, false, true, 'session/load'),
  ]) {
    test(
      'method local=$local resume=$canResume load=$canLoad selects $expected',
      () async {
        final dir = await directory();
        final file = File(p.join(dir.path, 'record.jsonl'));
        if (local) await file.writeAsString(encodeRecord(savedPrompt()));
        final memory = Memory(load: canLoad, resume: canResume)
          ..post = [say('LIVE')];
        final session = await openSession(
          agent: 'memory',
          command: 'memory',
          cwd: 'invocation',
          resume: Resume(
            sessionId: 'literal/id',
            cwd: dir.path,
            record: local ? file.path : null,
          ),
          open: memory.open,
        );
        try {
          expect(memory.openedCwd, dir.path);
          expect(session.id, 'literal/id');
          final asked = memory.requests.singleWhere(
            (m) => m['method'] == expected,
          );
          expect(asked['params'], {
            'sessionId': 'literal/id',
            'cwd': dir.path,
            'mcpServers': [],
          });
          final past = session.takeHistory();
          final prompts = past.actions.whereType<PromptAction>().map(
            (a) => a.text,
          );
          expect(
            prompts,
            local
                ? ['LOCAL']
                : expected == 'session/load'
                ? ['load past']
                : isEmpty,
          );
          expect(session.takeHistory().actions, isEmpty);
          final live = <String>[];
          session.subscribe(
            (u) => live.add((u.toJson()['content'] as Map)['text'] as String),
          );
          expect(live, ['LIVE']);
        } finally {
          await memory.close(session);
        }
      },
    );
  }

  for (final kind in ['header', 'opaque', 'malformed', 'missing']) {
    test(
      '$kind record keeps raw presence separate and retains selected append path',
      () async {
        final dir = await directory();
        final file = File(p.join(dir.path, 'record.jsonl'));
        final text = switch (kind) {
          'header' => encodeRecord({
            'type': 'session',
            'version': 1,
            'sessionId': 'literal/id',
            'agent': 'memory',
            'cwd': dir.path,
            'at': 0,
          }),
          'opaque' => encodeRecord({'type': 'future', 'meaningful': true}),
          'malformed' => 'not JSON\n',
          _ => '',
        };
        if (kind != 'missing') await file.writeAsString(text);
        final memory = Memory();
        final session = await openSession(
          agent: 'memory',
          command: 'memory',
          cwd: dir.path,
          resume: Resume(
            sessionId: 'literal/id',
            cwd: dir.path,
            record: file.path,
          ),
          open: memory.open,
        );
        try {
          final method = kind == 'header' || kind == 'opaque'
              ? 'session/resume'
              : 'session/load';
          expect(
            memory.requests.where((m) => m['method'] == method),
            hasLength(1),
          );
          expect(session.record, file.path);
          final past = session.takeHistory();
          expect(past.rawHasPast, kind == 'header' || kind == 'opaque');
          expect(past.omitted, kind == 'opaque' || kind == 'malformed');
          if (kind != 'missing') {
            expect(await file.readAsString(), text);
          } else {
            expect(await file.exists(), isFalse);
          }
        } finally {
          await memory.close(session);
        }
      },
    );
  }

  test(
    'no offers selects load, refuses locally, starts no RPC and stops attempted process',
    () async {
      final dir = await directory();
      final memory = Memory(load: false, resume: false);
      await expectLater(
        openSession(
          agent: 'memory',
          command: 'memory',
          cwd: dir.path,
          resume: Resume(sessionId: 'literal/id', cwd: dir.path),
          open: memory.open,
        ),
        throwsA(
          isA<ResumeError>().having(
            (e) => e.message,
            'original line',
            'it cannot resume session literal/id: The agent does not offer session/load.',
          ),
        ),
      );
      expect(
        memory.requests.where(
          (m) => m['method'] == 'session/load' || m['method'] == 'session/new',
        ),
        isEmpty,
      );
      expect(memory.process.exited, isTrue);
    },
  );

  for (final failure in ['refusal', 'malformed', 'cancel']) {
    test(
      '$failure discards prepared past and stops the attempted connection',
      () async {
        final dir = await directory();
        final file = File(p.join(dir.path, 'record.jsonl'));
        final prefix = encodeRecord(savedPrompt());
        await file.writeAsString(prefix);
        final memory = Memory()
          ..refusal = failure == 'refusal' ? 'unknown saved session' : null
          ..malformed = failure == 'malformed'
          ..hang = failure == 'cancel';
        final token = CancellationToken();
        final future = openSession(
          agent: 'memory',
          command: 'memory',
          cwd: dir.path,
          resume: Resume(
            sessionId: 'literal/id',
            cwd: dir.path,
            record: file.path,
          ),
          open: memory.open,
          cancellationToken: token,
        );
        final check = expectLater(
          future,
          throwsA(
            failure == 'cancel'
                ? isA<CancelledException>()
                : isA<ResumeError>(),
          ),
        );
        if (failure == 'cancel') {
          await memory.reopenAsked.future;
          token.cancel();
        }
        await check;
        expect(memory.process.exited, isTrue);
        expect(await file.readAsString(), prefix);
      },
    );
  }

  for (final post in [false, true]) {
    test(
      'resume early A answer B${post ? ' post C' : ''} drains only after subscription',
      () async {
        final dir = await directory();
        final file = File(p.join(dir.path, 'record.jsonl'));
        await file.writeAsString(encodeRecord(savedPrompt()));
        final memory = Memory()
          ..pre = [mode('A')]
          ..post = post ? [mode('C')] : [];
        final session = await openSession(
          agent: 'memory',
          command: 'memory',
          cwd: dir.path,
          resume: Resume(
            sessionId: 'literal/id',
            cwd: dir.path,
            record: file.path,
          ),
          open: memory.open,
        );
        try {
          expect(session.state.modes!['currentModeId'], 'B');
          session.takeHistory();
          final heard = <String>[];
          session.subscribe(
            (_) => heard.add(session.state.modes!['currentModeId'] as String),
          );
          expect(heard, post ? ['A', 'C'] : ['A']);
          expect(session.state.modes!['currentModeId'], post ? 'C' : 'A');
        } finally {
          await memory.close(session);
        }
      },
    );
  }

  test(
    'recall carries saved tool facts without enriching content a second time',
    () async {
      final dir = await directory();
      final file = File(p.join(dir.path, 'record.jsonl'));
      await file.writeAsString(
        encodeRecord({
          'type': 'update',
          'turnId': 't',
          'update': {
            'sessionUpdate': 'tool_call',
            'toolCallId': 'tool',
            'title': 'Saved title',
            'kind': 'read',
            'content': [
              {
                'type': 'content',
                'content': {'type': 'text', 'text': 'saved own content'},
              },
            ],
            'rawOutput': 'saved raw',
          },
        }),
      );
      final memory = Memory()
        ..post = [
          notification('tool_call_update', {
            'toolCallId': 'tool',
            'rawOutput': 'new raw',
          }),
        ];
      final session = await openSession(
        agent: 'memory',
        command: 'memory',
        cwd: dir.path,
        resume: Resume(
          sessionId: 'literal/id',
          cwd: dir.path,
          record: file.path,
        ),
        open: memory.open,
      );
      try {
        final history = session.takeHistory();
        expect(
          history.actions
              .whereType<UpdateAction>()
              .single
              .update
              .toJson()['content'],
          hasLength(1),
        );
        final heard = <Map<String, Object?>>[];
        session.subscribe((u) => heard.add(u.toJson()));
        expect(heard.single['title'], 'Saved title');
        expect(heard.single['kind'], 'read');
        expect(heard.single.containsKey('content'), isFalse);
      } finally {
        await memory.close(session);
      }
    },
  );

  test(
    'actual admission snapshots finalized mentions before external traffic and inbound updates',
    () async {
      final dir = await directory();
      final memory = Memory()..promptUpdate = true;
      final resolved = Completer<List<acp.ContentBlock>>();
      final order = <String>[], snapshots = <SubmittedContent>[];
      final session = await openSession(
        agent: 'memory',
        command: 'memory',
        cwd: dir.path,
        open: memory.open,
        resolveMentions: (_, _, {cancellationToken}) => resolved.future,
        onTraffic: (traffic) {
          if (traffic case ChordTraffic(
            message: {'method': 'session/prompt', 'params': final Map params},
          )) {
            order.add('external wire');
            ((params['prompt'] as List)[0] as Map)['text'] =
                'mutated by listener';
          }
        },
      );
      try {
        session.subscribe((_) => order.add('update'));
        final turn = session.prompt(
          'final shell context @fixture',
          mentions: ['fixture'],
          turnId: 'conversation-turn',
          onSubmitted: (content) {
            order.add('admitted');
            snapshots.add(content);
          },
        );
        expect(snapshots, isEmpty);
        expect(
          memory.requests.where((m) => m['method'] == 'session/prompt'),
          isEmpty,
        );
        resolved.complete([
          acp.ContentBlock.fromJson({
            'type': 'resource_link',
            'uri': 'file:fixture',
            'name': 'fixture',
          }),
        ]);
        expect(await turn.result, isA<TurnAnswered>());
        expect(order, ['admitted', 'external wire', 'update']);
        expect(snapshots.single.turnId, 'conversation-turn');
        expect(snapshots.single.prompt, 'final shell context @fixture');
        expect(snapshots.single.links.single['name'], 'fixture');
      } finally {
        await memory.close(session);
      }
    },
  );

  test(
    'submitted resources retain metadata and image counts without payloads',
    () {
      final snapshot = SubmittedContent.fromWire('t', [
        {'type': 'text', 'text': 'hello'},
        {'type': 'image', 'data': 'image payload'},
        {'type': 'audio', 'data': 'audio payload'},
        {
          'type': 'resource',
          'resource': {
            'uri': 'resource:fixture',
            'mimeType': 'text/plain',
            'text': 'resource payload',
          },
        },
      ]);
      expect(snapshot.prompt, 'hello');
      expect(snapshot.images, 1);
      expect(snapshot.resources, [
        {'uri': 'resource:fixture', 'mimeType': 'text/plain'},
      ]);
      expect(jsonEncode(snapshot.resources), isNot(contains('payload')));
    },
  );

  for (final closing in [false, true]) {
    test(
      '${closing ? 'close' : 'cancel'} before mention admission cannot claim a later prompt',
      () async {
        final dir = await directory();
        final memory = Memory();
        final resolved = Completer<List<acp.ContentBlock>>();
        final session = await openSession(
          agent: 'memory',
          command: 'memory',
          cwd: dir.path,
          open: memory.open,
          resolveMentions: (_, _, {cancellationToken}) => resolved.future,
        );
        final heard = <String>[];
        final old = session.prompt(
          'old',
          mentions: ['fixture'],
          turnId: 'old',
          onSubmitted: (s) => heard.add(s.turnId),
        );
        if (closing) {
          await session.close();
        } else {
          await old.cancel();
        }
        expect((await old.result as TurnAnswered).cancelled, isTrue);
        resolved.complete([
          acp.ContentBlock.fromJson({
            'type': 'resource_link',
            'uri': 'file:fixture',
            'name': 'fixture',
          }),
        ]);
        if (!closing) {
          await session
              .prompt(
                'new',
                turnId: 'new',
                onSubmitted: (s) => heard.add(s.turnId),
              )
              .result;
        }
        await memory.close(session);
        expect(heard, closing ? isEmpty : ['new']);
        expect(
          memory.requests.where((m) => m['method'] == 'session/prompt'),
          hasLength(closing ? 0 : 1),
        );
      },
    );
  }

  test(
    'throwing admission observer leaves ACP intact; reentrant close stops later admission',
    () async {
      final dir = await directory();
      final memory = Memory();
      final session = await openSession(
        agent: 'memory',
        command: 'memory',
        cwd: dir.path,
        open: memory.open,
      );
      var calls = 0;
      expect(
        await session
            .prompt(
              'first',
              onSubmitted: (_) {
                calls++;
                throw StateError('observer');
              },
            )
            .result,
        isA<TurnAnswered>(),
      );
      Future<void>? closing;
      final second = session.prompt(
        'second',
        onSubmitted: (_) {
          calls++;
          closing = session.close();
        },
      );
      await closing;
      await second.result;
      await session.prompt('late', onSubmitted: (_) => calls++).result;
      await memory.close(session);
      expect(calls, 2);
      expect(
        memory.requests.where((m) => m['method'] == 'session/prompt'),
        hasLength(2),
      );
    },
  );

  test(
    'closing from first retained Session callback stops the rest synchronously',
    () async {
      final dir = await directory();
      final memory = Memory()..post = [say('one'), say('two')];
      final session = await openSession(
        agent: 'memory',
        command: 'memory',
        cwd: dir.path,
        resume: Resume(sessionId: 'literal/id', cwd: dir.path),
        open: memory.open,
      );
      final heard = <String>[];
      Future<void>? closing;
      session.subscribe((u) {
        heard.add((u.toJson()['content'] as Map)['text'] as String);
        closing = session.close();
      });
      await closing;
      expect(heard, ['one']);
      expect(session.takeHistory().actions, isEmpty);
      expect(memory.process.exited, isTrue);
    },
  );

  test(
    'Wire seeds reopen answers then reapplies early resume state in original order',
    () {
      for (final method in ['session/load', 'session/resume']) {
        var wire = heardFromChord(Wire.empty, {
          'id': 1,
          'method': method,
          'params': {'sessionId': 'literal/id'},
        });
        wire = heardFromAgent(wire, mode('A'));
        wire = heardFromAgent(wire, {
          'id': 1,
          'result': {
            'modes': {'currentModeId': 'B', 'availableModes': <Object?>[]},
          },
        });
        expect(
          wire.sessions['literal/id']!.modes!['currentModeId'],
          method == 'session/resume' ? 'A' : 'B',
        );
        wire = heardFromAgent(wire, mode('C'));
        expect(wire.sessions['literal/id']!.modes!['currentModeId'], 'C');
        expect(wire.asked, isEmpty);
      }
    },
  );
}
