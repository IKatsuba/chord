// The original's tests/session/subagents_test.ts for the session's tree:
// which sessions are the session's subagents, their updates tagged with
// their ids on the session, and a cancel that withdraws their requests.
@Tags(['fake_agent'])
library;

import 'dart:async';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/permissions.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/subagents.dart';
import 'package:chord/session/transcript/types.dart'
    show TurnAnswered, TurnResult;
import 'package:test/test.dart';

import 'session_fake.dart';

/// What the session sends a client that takes subagents.
final _subagents = acp.ClientCapabilities.fromJson({
  'subagents': <String, Object?>{},
});

/// One prompt's updates, the session's own and its subagents', in order.
Future<
  ({
    List<acp.SessionUpdate> own,
    List<(acp.SessionUpdate, String)> sub,
    TurnResult result,
  })
>
_play(Session session, String text, {void Function(Turn turn)? onAsked}) async {
  final own = <acp.SessionUpdate>[];
  final sub = <(acp.SessionUpdate, String)>[];
  final stop = session.subscribeAll((update, subagentId) {
    if (subagentId == null) {
      own.add(update);
    } else {
      sub.add((update, subagentId));
    }
  });
  try {
    final turn = session.prompt(text);
    if (onAsked != null) {
      session.permissions.subscribe((_) => onAsked(turn));
    }
    return (own: own, sub: sub, result: await turn.result);
  } finally {
    stop();
  }
}

void main() {
  test("the session's tree takes a subagent its own updates or a subagent's "
      'announce, and no session it never opened', () {
    acp.SessionNotification notice(String sessionId, Map<String, Object?> u) =>
        acp.SessionNotification.fromJson({'sessionId': sessionId, 'update': u});
    Map<String, Object?> announce(String id) => {
      'sessionUpdate': 'subagent_update',
      'sessionId': id,
    };
    const chunk = {
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'hi'},
    };
    var tree = const SessionTree('root');
    String hear(acp.SessionNotification notification) {
      final where = routed(tree, notification);
      tree = where.tree;
      return where.heard ? (where.subagentId ?? 'root') : 'dropped';
    }

    expect(hear(notice('a', chunk)), 'dropped');
    expect(hear(notice('root', announce('a'))), 'root');
    expect(hear(notice('a', chunk)), 'a');
    expect(hear(notice('a', announce('g'))), 'a');
    expect(hear(notice('g', chunk)), 'g');
    // A session nobody announced announces nothing.
    expect(hear(notice('other', announce('x'))), 'dropped');
    expect(hear(notice('x', chunk)), 'dropped');
    // The session never announces itself.
    expect(hear(notice('root', announce('root'))), 'root');
    expect(tree.subagents, {'a', 'g'});
  });

  final skip = fakeAgentSkip;

  test("a subagent's updates reach its parent's session tagged with it, and "
      "none reads as the parent's", () async {
    await withSession(capabilities: _subagents, (session, _) async {
      final heard = <acp.SessionUpdate>[];
      session.subscribe(heard.add);
      final ran = await _play(session, 'subagentupdate');
      final child = ran.own
          .map((u) => u.toJson())
          .firstWhere(
            (u) => u['sessionUpdate'] == 'subagent_update',
          )['sessionId'];
      expect(said(ran.own), [
        'It says chord is a terminal client for ACP agents.',
      ]);
      // The plain listener hears the session's own alone.
      expect(heard.length, ran.own.length);
      expect({for (final (_, id) in ran.sub) id}, {child});
      expect([
        for (final (u, _) in ran.sub) u.kind,
      ], containsAll(['tool_call', 'agent_message_chunk']));
      expect(said([for (final (u, _) in ran.sub) u]), [
        'chord is a terminal client for ACP agents.',
      ]);
      expect(ran.result, isA<TurnAnswered>());
    });
  }, skip: skip);

  test("the adapters' draft shape reaches the session as ACP's, a child's "
      'request named by its own session', () async {
    await withSession(capabilities: _subagents, (session, _) async {
      final asked = <PendingPermission>[];
      session.permissions.subscribe((request) {
        asked.add(request);
        Timer(const Duration(milliseconds: 10), () => request.resolve('allow'));
      });
      final ran = await _play(session, 'subagent');
      final every = [...ran.own, for (final (u, _) in ran.sub) u];
      final announced = <String, String>{
        for (final update in every)
          if (update.toJson() case {
            'sessionUpdate': 'subagent_update',
            'title': final String title,
            'sessionId': final String id,
          })
            title: id,
      };
      final find = announced['Find the session layer']!;
      final read = announced['Read the transport tests']!;
      expect(
        every.where(
          (u) => u.kind.startsWith('subagent_') && u.kind != 'subagent_update',
        ),
        isEmpty,
      );
      expect(said(ran.own), [
        'I will send two agents, one for each side.',
        'Now the tests, in the background.',
        'It is running; I will say when it ends.',
      ]);
      expect(ran.own.where((u) => u.kind == 'tool_call'), isEmpty);
      // The grandchild is announced on its parent's session, not the root's.
      expect(
        ran.sub.any(
          (each) =>
              each.$2 == find &&
              each.$1.toJson()['sessionUpdate'] == 'subagent_update' &&
              each.$1.toJson()['sessionId'] == read,
        ),
        isTrue,
      );
      expect(
        [for (final r in asked) (r.sessionId, r.toolCall.title)],
        [(find, 'Write notes/routing.md')],
      );
    });
  }, skip: skip);

  test('a client that takes no subagents hears none', () async {
    await withSession((session, _) async {
      final ran = await _play(session, 'subagentupdate');
      expect(ran.sub, isEmpty);
      expect(said(ran.own), ['Subagents go only to a client that takes them.']);
    });
  }, skip: skip);

  test("Esc while a subagent asks withdraws its request", () async {
    await withSession(capabilities: _subagents, (session, _) async {
      final asked = Completer<PendingPermission>();
      session.permissions.subscribe(asked.complete);
      final turn = session.prompt('claudesubagents');
      final request = await asked.future;
      expect(request.sessionId, isNot(session.id));
      await turn.cancel();
      expect(request.withdrawn.isCancelled, isTrue);
      expect(
        await turn.result,
        isA<TurnAnswered>().having((r) => r.cancelled, 'cancelled', isTrue),
      );
    });
  }, skip: skip);
}
