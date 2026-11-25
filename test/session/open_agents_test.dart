// The original's tests/session/open_agents_test.ts on stand-ins; the cases
// on the fake agent come with the host, which opens real conversations.
import 'dart:async';

import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/open_agents.dart';
import 'package:chord/session/window_agents.dart';
import 'package:test/test.dart';

/// A stand-in whose close the test settles.
final class Stub implements Driven {
  Stub(this.name, this.started, this.closes);

  final String name;
  final List<String> started;
  final List<Completer<void>> closes;

  @override
  void start() => started.add(name);

  @override
  Future<void> close() {
    final done = Completer<void>();
    closes.add(done);
    return done.future;
  }
}

final class Rig {
  final started = <String>[];
  final closes = <Completer<void>>[];
  final heard = <int>[];
  final closingHeard = <(int, ConversationEvent)>[];
  final emits = <String, void Function(ConversationEvent)>{};
  late final open = OpenAgents<Stub>(
    conversation: (agent, emit, key) {
      emits[agent] = emit;
      return Stub(agent, started, closes);
    },
    heard: (key, event, wait) => heard.add(key),
    closingHeard: (key, event) => closingHeard.add((key, event)),
  );

  int child(String name) => open.openChild(
    ChildInfo(id: name, name: name, runtime: 'fake', openedAt: 0),
    (emit, key) {
      emits[name] = emit;
      return Stub(name, started, closes);
    },
  )!;
}

/// The failures [closing] ends with, none when it completes.
Future<List<String>> failures(Future<void> closing) async {
  try {
    await closing;
    return [];
  } on CloseFailures catch (error) {
    return [for (final each in error.errors) '$each'];
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  testerOpenLifecycleTests();
  test('a child opens beside main, its events heard under its own key, and '
      'closeAll closes both and waits for them', () async {
    final rig = Rig();
    final open = rig.open;
    expect(open.start('claude'), 1);
    expect(open.start('claude'), isNull);
    final child = rig.child('parser');
    expect(rig.started, ['claude', 'parser']);
    rig.emits['parser']!(const Connected('s', AgentState.empty));
    expect(rig.heard, [child]);
    expect(open.conversationOf(child), open.agents.children.first.conversation);
    open.pick(child);
    expect(open.front, open.conversationOf(child));
    var all = false;
    final closing = open.closeAll().then((_) => all = true);
    expect(rig.closes, hasLength(2));
    rig.closes[0].complete();
    await settle();
    expect(all, isFalse);
    rig.closes[1].complete();
    await closing;
    expect(all, isTrue);
  });

  test('before main starts no child opens, and nothing starts', () {
    final rig = Rig();
    expect(
      rig.open.openChild(
        const ChildInfo(id: 'x', name: 'x', runtime: 'fake', openedAt: 0),
        (emit, key) => fail('made'),
      ),
      isNull,
    );
    expect(rig.started, isEmpty);
  });

  test("a closed child's late events go to closingHeard, not heard", () async {
    final rig = Rig();
    rig.open.start('claude');
    final child = rig.child('parser');
    final closing = rig.open.closeChild(child);
    rig.emits['parser']!(const Connected('s', AgentState.empty));
    expect(rig.heard, isEmpty);
    expect(rig.closingHeard.single.$1, child);
    rig.closes.single.complete();
    await closing;
  });

  test('a child closed on its own still has its agent waited for by '
      'closeAll', () async {
    final rig = Rig();
    rig.open.start('a');
    rig.open.closeChild(rig.child('b')).ignore();
    var all = false;
    final closing = rig.open.closeAll().then((_) => all = true);
    expect(rig.closes, hasLength(2));
    rig.closes[1].complete();
    await settle();
    expect(all, isFalse);
    rig.closes[0].complete();
    await closing;
    expect(all, isTrue);
  });

  test('an earlier close that fails while closeAll waits is in its '
      'failure', () async {
    final rig = Rig();
    rig.open.start('a');
    final alone = rig.open
        .closeChild(rig.child('b'))
        .then<String?>((_) => null, onError: (Object e) => '$e');
    final all = failures(rig.open.closeAll());
    rig.closes[0].completeError('agent exit not observed');
    rig.closes[1].complete();
    expect(await alone, 'agent exit not observed');
    expect(await all, ['agent exit not observed']);
  });

  test('an earlier close that failed before closeAll is still in its '
      'failure, once', () async {
    final rig = Rig();
    rig.open.start('a');
    final alone = rig.open.closeChild(rig.child('b')).catchError((_) {});
    rig.closes[0].completeError('agent exit not observed');
    await alone;
    final first = failures(rig.open.closeAll());
    rig.closes[1].complete();
    expect(await first, ['agent exit not observed']);
    expect(await failures(rig.open.closeAll()), isEmpty);
  });

  // CTUI-114: a key in the window's zone, or a tool call in chord's, may
  // close a child; closeAll from another zone must still hear it failed.
  test('an earlier close that failed in another error zone is in '
      "closeAll's failure, not waited on for ever", () async {
    final rig = Rig();
    rig.open.start('a');
    final child = rig.child('b');
    runZonedGuarded(() {
      rig.open.closeChild(child).ignore();
      rig.closes[0].completeError('agent exit not observed');
    }, (_, _) {});
    await settle();
    final all = failures(rig.open.closeAll());
    rig.closes[1].complete();
    expect(await all.timeout(const Duration(seconds: 5)), [
      'agent exit not observed',
    ]);
  });

  test("closeAll reports an earlier failure beside an open agent's, after "
      'waiting for every agent', () async {
    final rig = Rig();
    rig.open.start('a');
    rig.child('c');
    rig.open.closeChild(rig.child('b')).catchError((_) {}).ignore();
    var settled = false;
    final all = failures(
      rig.open.closeAll(),
    ).whenComplete(() => settled = true);
    // b's close came first; a and c closed with closeAll.
    expect(rig.closes, hasLength(3));
    rig.closes[0].completeError('b did not exit');
    rig.closes[2].completeError('c did not exit');
    await settle();
    expect(settled, isFalse);
    rig.closes[1].complete();
    expect((await all)..sort(), ['b did not exit', 'c did not exit']);
  });

  group('CHD-493 forgotten children still finish closing', () {
    test('forgetting a hanging close removes its name at once but closeAll '
        'still waits for it', () async {
      final rig = Rig();
      rig.open.start('fake');
      final key = rig.child('parser');
      final alone = rig.open.closeChild(key);
      expect([for (final c in rig.open.agents.closed) c.name], ['parser']);
      rig.open.forgetClosed();
      expect(rig.open.agents.closed, isEmpty);
      expect(rig.open.conversationOf(key), isNull);
      var done = false;
      final all = rig.open.closeAll().then((_) => done = true);
      rig.closes[1].complete();
      await settle();
      expect(done, isFalse);
      rig.closes[0].complete();
      await alone;
      await all;
      expect(done, isTrue);
    });

    test('a failed child close survives forgetting and is reported once at '
        'shutdown', () async {
      final rig = Rig();
      rig.open.start('fake');
      final alone = rig.open.closeChild(rig.child('parser')).catchError((_) {});
      rig.open.forgetClosed();
      rig.closes[0].completeError('parser failed to stop');
      await alone;
      rig.open.forgetClosed();
      final all = failures(rig.open.closeAll());
      rig.closes[1].complete();
      expect(await all, ['parser failed to stop']);
      expect(await failures(rig.open.closeAll()), isEmpty);
    });
  });
}

void testerOpenLifecycleTests() {
  group('tester: one main and idempotent child close', () {
    test(
      'repeated starts and closes during child shutdown preserve main',
      () async {
        final rig = Rig();
        final mainKey = rig.open.start('fake')!;
        final main = rig.open.conversationOf(mainKey);
        final child = rig.child('parser');
        rig.open.pick(child);
        expect(rig.open.start('other-runtime'), isNull);
        final closing = rig.open.closeChild(child);
        await rig.open.closeChild(child);
        await rig.open.closeChild(mainKey);
        await rig.open.closeChild(999);
        expect(rig.closes, hasLength(1));
        expect(identical(rig.open.front, main), isTrue);
        expect(rig.open.start('other-runtime'), isNull);
        rig.emits['parser']!(const Connected('late', AgentState.empty));
        expect(rig.closingHeard.single.$1, child);
        rig.closes.single.complete();
        await closing;
        rig.open.forgetClosed();
        expect(rig.open.start('other-runtime'), isNull);
        expect(rig.started, ['fake', 'parser']);
        final all = rig.open.closeAll();
        rig.closes.last.complete();
        await all;
        expect(rig.open.front, isNull);
      },
    );
  });
}
