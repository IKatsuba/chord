import 'dart:convert';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/inbox.dart';
import 'package:fake_async/fake_async.dart';
import 'package:chord/session/subagents.dart' show Heard;
import 'package:test/test.dart';

import '../acp/connection_test.dart' show Harness;

Map<String, Object?> notification(String text, {String id = 'literal/id'}) => {
  'jsonrpc': '2.0',
  'method': 'session/update',
  'params': {
    'sessionId': id,
    'update': {
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': text},
    },
  },
};
Map<String, Object?> mode(String current) => {
  'jsonrpc': '2.0',
  'method': 'session/update',
  'params': {
    'sessionId': 'literal/id',
    'update': {
      'sessionUpdate': 'current_mode_update',
      'currentModeId': current,
    },
  },
};
String textOf(acp.SessionUpdate update) =>
    (update.toJson()['content'] as Map)['text'] as String;
Traffic request(String method, Object id, {String session = 'literal/id'}) =>
    Traffic.chord({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': {'sessionId': session},
    });
Traffic reply(Object id) =>
    Traffic.agent({'jsonrpc': '2.0', 'id': id, 'result': <String, Object?>{}});
acp.SessionResponse answer([String current = 'B']) =>
    acp.SessionResponse.fromJson({
      'modes': {'currentModeId': current, 'availableModes': <Object?>[]},
    });

Map<String, Object?> spawn(String child, {required String from}) => {
  'jsonrpc': '2.0',
  'method': 'session/update',
  'params': {
    'sessionId': from,
    'update': {
      'sessionUpdate': 'subagent_update',
      'sessionId': child,
      'title': 'Agent $child',
    },
  },
};

void main() {
  test('a load with no record routes its replay through the tree: a child '
      "and grandchild's work keep their ids, and the child's later updates "
      'are heard', () {
    final inbox = SessionInbox()..beginReopen('session/load', 'literal/id');
    inbox.hear(request('session/load', 3));
    for (final message in [
      notification('started'),
      spawn('c', from: 'literal/id'),
      notification('child work', id: 'c'),
      spawn('g', from: 'c'),
      notification('grandchild work', id: 'g'),
    ]) {
      inbox.hear(Traffic.agent(message));
    }
    inbox.hear(reply(3));
    inbox.hear(Traffic.agent(notification('child later', id: 'c')));
    final past = inbox.completeReopen(answer(), rawHasPast: false);
    expect(
      [for (final (:update, :subagentId) in past) (update.kind, subagentId)],
      [
        ('agent_message_chunk', null),
        ('subagent_update', null),
        ('agent_message_chunk', 'c'),
        ('subagent_update', 'c'),
        ('agent_message_chunk', 'g'),
      ],
    );
    final live = <(String, String?)>[];
    inbox.subscribeAll((update, subagentId) {
      live.add((textOf(update), subagentId));
    });
    expect(live, [('child later', 'c')]);
  });

  for (final method in ['session/load', 'session/resume']) {
    test('$method unadvertised is refused locally with no RPC', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(async);
        final request = acp.ReopenSessionRequest(
          sessionId: 'id',
          cwd: 'fixture',
          mcpServers: const [],
        );
        Object? error;
        final refused = method == 'session/load'
            ? agent.loadSession(request)
            : agent.resumeSession(request);
        refused.then<void>(
          (_) {},
          onError: (Object e) {
            error = e;
          },
        );
        async.flushMicrotasks();
        expect(
          error,
          isA<AgentCapabilityError>().having(
            (e) => e.message,
            'original error',
            'The agent does not offer $method.',
          ),
        );
        expect(h.written.where((m) => m['method'] == method), isEmpty);
        agent.close().ignore();
        async.elapse(const Duration(seconds: 3));
        expect(h.process.exited, isTrue);
      });
    });
  }

  for (final method in ['session/load', 'session/resume']) {
    for (final local in [false, true]) {
      test(
        '$method same-read HISTORY/reply/LIVE equals split reads, local=$local',
        () {
          List<List<String>> run(bool split) {
            late List<List<String>> result;
            fakeAsync((async) {
              final inbox = SessionInbox();
              final h = Harness(onTraffic: inbox.hear);
              final agent = h.open(
                async,
                init: {
                  'protocolVersion': 1,
                  'agentCapabilities': {
                    'loadSession': true,
                    'sessionCapabilities': {'resume': <String, Object?>{}},
                  },
                },
              );
              inbox.beginReopen(method, 'literal/id');
              final request = acp.ReopenSessionRequest(
                sessionId: 'literal/id',
                cwd: 'fixture-project',
                mcpServers: const [],
              );
              List<Heard>? past;
              final opened = method == 'session/load'
                  ? agent.loadSession(request)
                  : agent.resumeSession(request);
              opened.then(
                (response) =>
                    past = inbox.completeReopen(response, rawHasPast: local),
              );
              async.flushMicrotasks();
              expect(h.lastRequest(method)['params'], {
                'sessionId': 'literal/id',
                'cwd': 'fixture-project',
                'mcpServers': [],
              });
              final frames = [
                notification('HISTORY'),
                {
                  'jsonrpc': '2.0',
                  'id': h.lastRequest(method)['id'],
                  'result': <String, Object?>{},
                },
                notification('LIVE'),
              ];
              if (split) {
                for (final frame in frames) {
                  h.process.send(frame);
                  async.flushMicrotasks();
                }
              } else {
                h.process.writeStdout(
                  utf8.encode(
                    frames.map((frame) => '${jsonEncode(frame)}\n').join(),
                  ),
                );
                async.flushMicrotasks();
              }
              final live = <String>[];
              inbox.subscribe((update) => live.add(textOf(update)));
              result = [
                past!.map((heard) => textOf(heard.update)).toList(),
                live,
              ];
              agent.close().ignore();
              async.elapse(const Duration(seconds: 3));
              expect(h.process.exited, isTrue);
            });
            return result;
          }

          final expected = [
            if (method == 'session/load' && !local) ['HISTORY'] else <String>[],
            if (method == 'session/resume') ['HISTORY', 'LIVE'] else ['LIVE'],
          ];
          expect(run(false), expected);
          expect(run(true), expected);
        },
      );
    }
  }

  test(
    'only matching method, requested session and typed response id arm fence',
    () {
      final inbox = SessionInbox()..beginReopen('session/load', 'literal/id');
      inbox.hear(request('initialize', 1));
      inbox.hear(request('session/load', 2, session: 'other'));
      inbox.hear(reply(1));
      inbox.hear(reply(2));
      inbox.hear(Traffic.agent(notification('before real request')));
      inbox.hear(request('session/load', 3));
      inbox.hear(reply('3'));
      inbox.hear(Traffic.agent(notification('before typed reply')));
      inbox.hear(reply(3));
      inbox.hear(Traffic.agent(notification('after typed reply')));
      inbox.hear(Traffic.agent(notification('other session', id: 'other')));
      final past = inbox.completeReopen(answer(), rawHasPast: false);
      expect(past.map((heard) => textOf(heard.update)), [
        'before real request',
        'before typed reply',
      ]);
      final live = <String>[];
      inbox.subscribe((u) => live.add(textOf(u)));
      expect(live, ['after typed reply']);
      expect(
        () => past.add((
          update: acp.SessionUpdate.fromJson({}),
          subagentId: null,
        )),
        throwsUnsupportedError,
      );
    },
  );

  for (final post in [false, true]) {
    test(
      'resume early A, answer B${post ? ', post C' : ''} folds live after seeding',
      () {
        final inbox = SessionInbox()
          ..beginReopen('session/resume', 'literal/id');
        inbox.hear(request('session/resume', 1));
        inbox.hear(Traffic.agent(mode('A')));
        inbox.hear(reply(1));
        if (post) inbox.hear(Traffic.agent(mode('C')));
        expect(inbox.completeReopen(answer(), rawHasPast: true), isEmpty);
        expect(inbox.state.modes!['currentModeId'], 'B');
        final heard = <String>[];
        inbox.subscribe(
          (_) => heard.add(inbox.state.modes!['currentModeId'] as String),
        );
        expect(heard, post ? ['A', 'C'] : ['A']);
        expect(inbox.state.modes!['currentModeId'], post ? 'C' : 'A');
      },
    );
  }

  test(
    'load history never replaces opening facts; retained live arrives after publication',
    () {
      final inbox = SessionInbox()..beginReopen('session/load', 'literal/id');
      inbox.hear(request('session/load', 1));
      inbox.hear(Traffic.agent(mode('historical')));
      inbox.hear(reply(1));
      final past = inbox.completeReopen(answer(), rawHasPast: false);
      expect(past, hasLength(1));
      expect(inbox.state.modes!['currentModeId'], 'B');
      inbox.hear(Traffic.agent(mode('current')));
      expect(inbox.state.modes!['currentModeId'], 'B');
      inbox.subscribe((_) {});
      expect(inbox.state.modes!['currentModeId'], 'current');
    },
  );

  test(
    'close before or during synchronous retained drain stops all remaining work',
    () {
      for (final before in [true, false]) {
        final inbox = SessionInbox()
          ..beginReopen('session/resume', 'literal/id');
        inbox.hear(request('session/resume', 1));
        inbox.hear(Traffic.agent(notification('one')));
        inbox.hear(reply(1));
        inbox.hear(Traffic.agent(notification('two')));
        inbox.completeReopen(answer(), rawHasPast: true);
        if (before) inbox.close();
        final heard = <String>[];
        inbox.subscribe((u) {
          heard.add(textOf(u));
          inbox.close();
        });
        inbox.hear(Traffic.agent(notification('late')));
        expect(heard, before ? isEmpty : ['one']);
      }
    },
  );

  test(
    'reentrant subscribe and notification preserve once-only ordered drain',
    () {
      final inbox = SessionInbox()..beginReopen('session/resume', 'literal/id');
      inbox.hear(request('session/resume', 1));
      inbox.hear(Traffic.agent(notification('one')));
      inbox.hear(reply(1));
      inbox.hear(Traffic.agent(notification('two')));
      inbox.completeReopen(answer(), rawHasPast: true);
      final first = <String>[], second = <String>[];
      inbox.subscribe((u) {
        final text = textOf(u);
        first.add(text);
        if (text == 'one') {
          inbox.subscribe((u) => second.add(textOf(u)));
          inbox.hear(Traffic.agent(notification('three')));
        }
      });
      expect(first, ['one', 'two', 'three']);
      expect(second, ['two', 'three']);
    },
  );

  for (final method in ['session/load', 'session/resume']) {
    test(
      '$method uses existing malformed-answer and cancellation machinery',
      () {
        fakeAsync((async) {
          final h = Harness();
          final agent = h.open(
            async,
            init: {
              'protocolVersion': 1,
              'agentCapabilities': {
                'loadSession': true,
                'sessionCapabilities': {'resume': <String, Object?>{}},
              },
            },
          );
          final request = acp.ReopenSessionRequest(
            sessionId: 'id',
            cwd: 'fixture',
            mcpServers: const [],
          );
          Object? error;
          final malformed = method == 'session/load'
              ? agent.loadSession(request)
              : agent.resumeSession(request);
          malformed.then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
          async.flushMicrotasks();
          h.process.send({
            'jsonrpc': '2.0',
            'id': h.lastRequest(method)['id'],
            'result': 'bad',
          });
          async.flushMicrotasks();
          expect(error, isA<FormatException>());
          error = null;
          final token = CancellationToken();
          final cancelled = method == 'session/load'
              ? agent.loadSession(request, cancellationToken: token)
              : agent.resumeSession(request, cancellationToken: token);
          cancelled.then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
          async.flushMicrotasks();
          token.cancel();
          async.flushMicrotasks();
          expect(error, isA<CancelledException>());
          agent.close().ignore();
          async.elapse(const Duration(seconds: 3));
          expect(h.process.exited, isTrue);
        });
      },
    );
  }
}
