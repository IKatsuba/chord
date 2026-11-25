// The original's tests/session/window_agents_test.ts, but for the cases of
// teams (CTUI-37) and of messages between agents, which come with the
// messages themselves.
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/waits.dart';
import 'package:chord/session/window_agents.dart';
import 'package:test/test.dart';

const up = Connected('s', AgentState.empty);
ConversationEvent prompt(String turnId) =>
    Transcribed(PromptAction(turnId, 'hi', 0));
ConversationEvent ended(String turnId) =>
    Transcribed(ResultAction(turnId, const TurnAnswered('end_turn')));
ConversationEvent failed(String turnId, [String message = 'boom']) =>
    Transcribed(ResultAction(turnId, TurnFailed(message)));
ConversationEvent asked(String turnId, String id) => Transcribed(
  PermissionRequestedAction(
    turnId,
    PermissionWait(id, title: 'Write notes.txt'),
  ),
);
ConversationEvent gone(String turnId) =>
    Transcribed(DisconnectedAction(turnId, at: 0));

ChildInfo info(String name, {String? id, String runtime = 'codex'}) =>
    ChildInfo(id: id ?? 'id-$name', name: name, runtime: runtime, openedAt: 0);

/// Main on the first of [agents], a child on each other, by that name, on
/// that runtime, the last opened picked.
WindowAgents<String> opened(List<String> agents) {
  var window = openMain(
    noAgents<String>(),
    agents.first,
    'conversation of ${agents.first}',
  );
  for (final name in agents.skip(1)) {
    window = openChild(
      window,
      info(name, runtime: name),
      'conversation of $name',
    )!.agents;
  }
  return pick(window, window.nextKey - 1);
}

/// [tabs] with children [names] opened in it, in order, on codex.
WindowAgents<String> withChildren(
  WindowAgents<String> tabs,
  List<String> names,
) {
  for (final name in names) {
    tabs = openChild(tabs, info(name), 'conversation of $name')!.agents;
  }
  return tabs;
}

/// Plays [events] into agent [key], each a second after the last from [at].
WindowAgents<String> heard(
  WindowAgents<String> agents,
  int key,
  List<ConversationEvent> events, [
  num at = 0,
]) {
  for (final (index, event) in events.indexed) {
    agents = hear(agents, key, event, at + index * 1000).agents;
  }
  return agents;
}

/// The window's agents as `main*`, the pick marked.
List<String> list(WindowAgents<String> tabs) => [
  for (final (key, name) in [
    (tabs.main!.key, 'main'),
    for (final child in tabs.children) (child.key, child.name),
  ])
    '$name${key == tabs.picked ? '*' : ''}',
];

List<String> names(List<MessageRecipient> recipients) => [
  for (final each in recipients) each.name,
];

void main() {
  messageTests();
  teamNames();
  testerNotificationNames();
  test('the attention order is the oldest waits first, then the oldest '
      'unseen', () {
    var tabs = opened(['a', 'b', 'c', 'd', 'e']);
    tabs = heard(tabs, 1, [up, prompt('t'), ended('t')]);
    tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')], 10000);
    tabs = heard(tabs, 3, [up, prompt('t'), failed('t')], 1000);
    tabs = heard(tabs, 4, [up, prompt('t'), asked('t', 'p')], 5000);
    expect(attentionOrder(tabs), [4, 2, 1, 3]);
  });

  test('an agent that waits and has an unseen reply counts once, as '
      'waiting', () {
    var tabs = opened(['a', 'b', 'c']);
    tabs = heard(tabs, 1, [up, prompt('t'), ended('t')]);
    tabs = heard(tabs, 1, [prompt('u'), asked('u', 'p')], 50000);
    tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')]);
    expect(attentionOrder(tabs), [2, 1]);
  });

  test('ties go to main, then to the child that opened first', () {
    var tabs = opened(['a', 'b', 'c']);
    for (final key in [3, 1, 2]) {
      tabs = heard(tabs, key, [up, prompt('t'), asked('t', 'p')]);
    }
    expect(attentionOrder(tabs), [1, 2, 3]);
  });

  test('attention goes to the longest wait, and again to the next, round '
      'the queue', () {
    var tabs = opened(['a', 'b', 'c']);
    tabs = heard(tabs, 1, [up, prompt('t'), asked('t', 'p')], 5000);
    tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')]);
    final first = attend(tabs)!;
    final second = attend(first)!;
    expect(first.picked, 2);
    expect(second.picked, 1);
    expect(attend(second)?.picked, 2);
  });

  test('attention reaches every one of three lasting waits, in order, and '
      'round again', () {
    var tabs = opened(['a', 'b', 'c', 'd']);
    tabs = heard(tabs, 1, [up, prompt('t'), asked('t', 'p')]);
    tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')], 10000);
    tabs = heard(tabs, 3, [up, prompt('t'), asked('t', 'p')], 20000);
    final fronts = <int>[];
    for (var n = 0; n < 6; n++) {
      tabs = attend(tabs)!;
      fronts.add(tabs.picked);
    }
    expect(fronts, [1, 2, 3, 1, 2, 3]);
  });

  test('attention walks the waits, then the unseen, then round to the '
      'waits', () {
    var tabs = opened(['a', 'b', 'c', 'd', 'e']);
    tabs = heard(tabs, 1, [up, prompt('t'), ended('t')]);
    tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')], 10000);
    tabs = heard(tabs, 3, [up, prompt('t'), failed('t')], 1000);
    tabs = heard(tabs, 4, [up, prompt('t'), asked('t', 'p')], 5000);
    final fronts = <int>[];
    for (var n = 0; n < 6; n++) {
      tabs = attend(tabs)!;
      fronts.add(tabs.picked);
    }
    // Seen once, the reply and the failure leave the order; the waits stay.
    expect(fronts, [4, 2, 1, 3, 4, 2]);
  });

  test('attention from a waiting agent picked by hand goes to the next '
      'wait', () {
    var tabs = opened(['a', 'b', 'c']);
    tabs = heard(tabs, 1, [up, prompt('t'), asked('t', 'p')]);
    tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')], 5000);
    tabs = pick(tabs, 2);
    expect(attend(tabs)?.picked, 1);
    expect(attend(pick(tabs, 1))?.picked, 2);
  });

  test('attention clears what it goes to, and says when nothing else '
      'waits', () {
    var tabs = opened(['a', 'b']);
    tabs = heard(tabs, 1, [up, prompt('t'), ended('t')]);
    final there = attend(tabs)!;
    expect(there.picked, 1);
    expect(waitOf(there, 1)!.unseen, isNull);
    expect(attend(there), isNull);
    expect(attend(opened(['a', 'b'])), isNull);
  });

  test('a child opens under the next key, takes the next colour, and leaves '
      'the pick alone', () {
    final tabs = withChildren(opened(['claude']), ['parser', 'docs']);
    expect(
      [for (final c in tabs.children) (c.key, c.colour)],
      [(2, 0), (3, 1)],
    );
    expect(tabs.picked, 1);
    expect(tabs.nextKey, 4);
    expect(agentOf(tabs, 3)?.child?.name, 'docs');
    expect(agentOf(tabs, 1)?.child, isNull);
    expect(agentOf(tabs, 1)?.main?.agent, 'claude');
  });

  test('a session holds eight children at most; the ninth is refused', () {
    final tabs = withChildren(opened(['claude']), [
      for (var i = 0; i < maxChildren; i++) 'c$i',
    ]);
    expect(maxChildren, 8);
    expect(openChild(tabs, info('x'), ''), isNull);
  });

  test('a child is named as asked, or by its runtime, numbered past the '
      'first, never main or chord', () {
    final tab = withChildren(opened(['claude']), ['codex']);
    expect(childName(tab, 'parser', 'codex'), 'parser');
    expect(childName(tab, null, 'codex'), 'codex 2');
    expect(childName(tab, ' ', 'gemini'), 'gemini');
    expect(childName(tab, 'main', 'codex'), 'main 2');
    expect(childName(tab, 'chord', 'codex'), 'chord 2');
  });

  test("U+0085 is kept in a name and in last words, as JavaScript's trim "
      'keeps it', () {
    final tab = opened(['claude']);
    expect(childName(tab, '\u0085', 'fake'), '\u0085');
    expect(childName(tab, ' a\u0085 ', 'fake'), 'a\u0085');
    expect(
      childEnded('parser', gone('t1'), 'killed\u0085'),
      "parser's agent exited: killed\u0085. open_agent opens it again.",
    );
  });

  test('the taken names are main, chord and every open child', () {
    final tab = withChildren(opened(['claude']), ['codex', 'the scout']);
    expect(takenNames(tab), ['main', 'chord', 'codex', 'the scout']);
  });

  test("a child's agent that exits tells its parent its last words, and how "
      'to open it again', () {
    expect(
      childEnded('parser', gone('t1'), 'out of memory reading tests/parse.'),
      "parser's agent exited: out of memory reading tests/parse. open_agent "
      'opens it again.',
    );
    expect(
      childEnded('parser', gone('t1'), ''),
      "parser's agent exited. open_agent opens it again.",
    );
  });

  test("a child's turn that fails tells its parent, unless the agent went, "
      'which its exit tells', () {
    final turn = failed('t1', 'The fake agent failed on purpose.');
    expect(
      childEnded('parser', turn, null),
      "parser's turn failed: The fake agent failed on purpose. It is still "
      'open; send_message reaches it.',
    );
    expect(childEnded('parser', turn, 'killed'), isNull);
    expect(childEnded('parser', ended('t1'), null), isNull);
  });

  test('picking moves down the list and stops at its end; above main the '
      'focus goes back', () {
    var tabs = withChildren(opened(['claude']), ['parser', 'docs']);
    expect(list(tabs), ['main*', 'parser', 'docs']);
    tabs = movePick(tabs, 1)!;
    expect(list(tabs), ['main', 'parser*', 'docs']);
    expect(shownKey(tabs), 2);
    tabs = movePick(movePick(tabs, 1)!, 1)!;
    expect(list(tabs), ['main', 'parser', 'docs*']);
    expect(movePick(pick(tabs, 1), -1), isNull);
  });

  test('closing a child keeps it among the closed, and a pick on it goes '
      'back to main; the colours stay', () {
    var tabs = withChildren(opened(['claude']), ['parser', 'docs']);
    tabs = closeChild(pick(tabs, 2), 2);
    tabs = withChildren(tabs, ['review']);
    expect(tabs.picked, 1);
    expect([for (final c in tabs.closed) c.name], ['parser']);
    expect(
      [for (final c in tabs.children) (c.name, c.colour)],
      [('docs', 1), ('review', 2)],
    );
  });

  test('main, shown, hears a turn of its own end unseen by no one, and a '
      'child not shown as unseen', () {
    var tabs = withChildren(opened(['claude']), ['parser']);
    tabs = heard(tabs, 2, [up, prompt('t'), ended('t')]);
    expect(agentOf(tabs, 2)?.child?.wait.unseen?.kind, UnseenKind.replied);
    expect(waitOf(tabs, 1)!.unseen, isNull);
  });

  test("a fork stands after main's whole tree, counts against none of its "
      "eight, and is no one's to message", () {
    const fork = ChildInfo(
      id: 'f',
      name: 'fork',
      runtime: 'claude',
      openedAt: 0,
      forkedFrom: 'main',
    );
    var tabs = withChildren(opened(['claude']), ['parser']);
    tabs = openChild(tabs, fork, '')!.agents;
    tabs = withChildren(tabs, [
      for (var i = 0; i < maxChildren - 1; i++) 'c$i',
    ]);
    final forkKey = tabs.children.firstWhere((c) => c.name == 'fork').key;
    expect(tabs.children.last.name, 'fork');
    expect(ownChildren(tabs), hasLength(maxChildren));
    expect(
      openChild(
        tabs,
        const ChildInfo(
          id: 'g',
          name: 'fork 2',
          runtime: 'claude',
          openedAt: 0,
          forkedFrom: 'fork',
        ),
        '',
      ),
      isNotNull,
    );
    expect(
      names(messageRecipients(tabs, tabs.main!.key)),
      isNot(contains('fork')),
    );
    expect(messageRecipients(tabs, forkKey), isEmpty);
  });

  test('a new or resumed session forgets the children closed', () {
    var tabs = withChildren(opened(['claude']), ['parser', 'docs']);
    tabs = closeChild(closeChild(tabs, 2), 3);
    expect([for (final c in tabs.closed) c.name], ['parser', 'docs']);
    final fresh = forgetClosed(tabs);
    expect(fresh.closed, isEmpty);
    expect(identical(forgetClosed(fresh), fresh), isTrue);
  });

  group('CHD-264 child failure lifecycle', () {
    test('showing the parent does not acknowledge a child; picking it '
        'clears only its failure and a later failure gets a fresh time', () {
      final base = withChildren(opened(['a', 'b']), ['parser', 'docs']);
      final both = heard(heard(base, 3, [up, prompt('p'), failed('p')]), 4, [
        up,
        prompt('d'),
        failed('d'),
      ], 5000);
      final parent = pick(both, 1);
      expect(attentionOrder(parent), [3, 4]);
      final seen = pick(parent, 3);
      expect(agentOf(seen, 3)?.child?.wait.unseen, isNull);
      expect(attentionOrder(seen), [4]);
      expect(agentOf(pick(pick(seen, 2), 1), 3)?.child?.wait.unseen, isNull);
      final later = heard(pick(seen, 1), 3, [
        prompt('next'),
        failed('next'),
      ], 20000);
      expect(agentOf(later, 3)!.child!.wait.unseen?.failedAt, 21000);
      expect(attentionOrder(later), [4, 3]);
    });

    test('acknowledging an exited child clears attention while keeping its '
        'exited state across switches', () {
      final base = withChildren(opened(['a', 'b']), ['parser']);
      final exited = heard(base, 3, [up, prompt('p'), failed('p'), gone('p')]);
      final returned = pick(pick(pick(exited, 3), 2), 1);
      final wait = agentOf(returned, 3)!.child!.wait;
      expect(wait.exited, isTrue);
      expect(wait.unseen, isNull);
      expect(attentionOrder(returned), isEmpty);
      expect(
        agentOf(returned, 3)?.child?.conversation,
        'conversation of parser',
      );
    });
  });

  test('from an agent put in front by hand, attention goes first to the '
      'longest wait behind it, then walks on', () {
    var tabs = opened(['a', 'b', 'c']);
    tabs = heard(tabs, 1, [up, prompt('t'), asked('t', 'p')]);
    tabs = heard(tabs, 2, [up, prompt('t'), asked('t', 'p')], 5000);
    tabs = pick(tabs, 2);
    tabs = heard(tabs, 3, [up, prompt('t'), ended('t')], 9000);
    final first = attend(tabs)!;
    expect(first.picked, 1);
    expect(attend(first)?.picked, 2);
    expect(attend(attend(first)!)?.picked, 3);
  });

  group('CHD-431 attention after a hand pick', () {
    ({WindowAgents<String> tabs, int child}) withChild() {
      final opened0 = openChild(
        opened(['main', 'other', 'quiet']),
        info('worker', runtime: 'fake'),
        'child conversation',
      )!;
      var tabs = heard(opened0.agents, 1, [up, prompt('a'), asked('a', 'a')]);
      tabs = heard(tabs, 2, [up, prompt('b'), asked('b', 'b')], 5000);
      tabs = heard(tabs, opened0.key, [up, prompt('c'), ended('c')], 9000);
      return (tabs: tabs, child: opened0.key);
    }

    test('a hand-picked child reaches the oldest wait and then walks', () {
      final (:tabs, :child) = withChild();
      final first = attend(pick(tabs, child))!;
      final second = attend(first)!;
      expect(shownKey(first), 1);
      expect(shownKey(second), 2);
      expect(shownKey(attend(second)!), 1);
    });

    test('picking a waiting child excludes itself and names the oldest '
        'other wait', () {
      final (:tabs, :child) = withChild();
      final waiting = heard(tabs, child, [prompt('d'), asked('d', 'd')], 15000);
      final first = attend(pick(waiting, child))!;
      final second = attend(first)!;
      final third = attend(second)!;
      expect(
        [shownKey(first), shownKey(second), shownKey(third)],
        [1, 2, child],
      );
      expect(shownKey(attend(third)!), 1);
    });

    test('another hand pick resets a previous walk to the oldest remaining '
        'wait', () {
      final (:tabs, :child) = withChild();
      final walked = attend(attend(pick(tabs, child))!)!;
      expect(shownKey(walked), 2);
      expect(shownKey(attend(pick(walked, 3))!), 1);
      expect(shownKey(attend(pick(walked, 1))!), 2);
    });

    test('without waits, unseen replies and failures are visited once in age '
        'order', () {
      var tabs = heard(opened(['a', 'b', 'quiet']), 1, [
        up,
        prompt('a'),
        ended('a'),
      ]);
      tabs = heard(tabs, 2, [up, prompt('b'), failed('b')], 5000);
      final first = attend(pick(tabs, 3))!;
      final second = attend(first)!;
      expect(shownKey(first), 1);
      expect(shownKey(second), 2);
      expect(attend(second), isNull);
    });
  });

  test('closed child keys never become a new child: late events leave a '
      'same-named replacement idle and main picked', () {
    final closed = closeChild(opened(['fake', 'other']), 2);
    final replacement = openChild(
      closed,
      const ChildInfo(
        id: 'replacement',
        name: 'other',
        runtime: 'fake',
        openedAt: 1,
      ),
      'replacement conversation',
    )!.agents;
    final late = heard(replacement, 2, [
      up,
      prompt('old-turn'),
      asked('old-turn', 'old-permission'),
      ended('old-turn'),
    ]);
    expect(late.main?.key, 1);
    expect(late.picked, 1);
    expect([for (final c in late.children) (c.key, c.name)], [(3, 'other')]);
    expect(agentOf(late, 2), isNull);
    expect(attentionOrder(late), isEmpty);
    expect(
      identical(late.children.first.wait, replacement.children.first.wait),
      isTrue,
    );
    expect([for (final c in late.closed) c.name], ['other']);
  });

  group('send_message recipients', () {
    test('main reaches its own long-lived children; a child only main', () {
      final tabs = opened(['codex', 'parser', 'docs']);
      expect(names(messageRecipients(tabs, 1)), ['parser', 'docs']);
      expect(messageRecipients(tabs, 2), [(key: 1, name: 'main', id: null)]);
    });

    test('a closed child is no longer offered, and a closed source reaches '
        'nobody', () {
      final tabs = closeChild(opened(['codex', 'parser', 'docs']), 2);
      expect(names(messageRecipients(tabs, 1)), ['docs']);
      expect(messageRecipients(tabs, 2), isEmpty);
    });

    test('recipients keep their exact key and opaque id', () {
      final tabs = opened(['fake', 'parser', 'bugfix 2']);
      final before = messageRecipients(tabs, 1);
      final replacement = openChild(
        closeChild(tabs, 3),
        const ChildInfo(
          id: 'replacement-run',
          name: 'bugfix 2',
          runtime: 'fake',
          openedAt: 1,
        ),
        'replacement conversation',
      )!;
      expect(before, [
        (key: 2, name: 'parser', id: 'id-parser'),
        (key: 3, name: 'bugfix 2', id: 'id-bugfix 2'),
      ]);
      expect(messageRecipients(replacement.agents, 1), [
        (key: 2, name: 'parser', id: 'id-parser'),
        (key: replacement.key, name: 'bugfix 2', id: 'replacement-run'),
      ]);
      expect(messageRecipients(replacement.agents, 3), isEmpty);
    });

    test('the explicit source controls scope independently of the pick, and '
        'a missing main offers nothing', () {
      final picked = pick(opened(['codex', 'parser', 'docs']), 3);
      expect(names(messageRecipients(picked, 1)), ['parser', 'docs']);
      expect(names(messageRecipients(picked, 2)), ['main']);
      expect(messageRecipients(noAgents<String>(), 2), isEmpty);
      expect(messageRecipients(picked, 999), isEmpty);
    });
  });

  test('numbering refuses quoted names and runtime fallbacks', () {
    final agents = opened(['main']);
    for (final (asked, runtime) in [('a"b', 'fake'), (null, 'a"b')]) {
      expect(
        () => childName(agents, asked, runtime),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'must not contain the character "',
          ),
        ),
      );
    }
  });

  test('numbering refuses control characters in every offered name', () {
    final agents = opened(['main']);
    for (final name in [
      'a\n@notes.md suffix',
      'a\rline',
      'a\ttab',
      'a\x00nul',
      'a\x7Fdel',
    ]) {
      for (final (asked, runtime) in [(name, 'fake'), (null, name)]) {
        expect(
          () => childName(agents, asked, runtime),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '${e.message}',
              'message',
              startsWith('must not contain the control character'),
            ),
          ),
        );
      }
    }
  });
}

ConversationEvent message(String turnId) => Transcribed(
  PromptAction(
    turnId,
    'hi',
    0,
    from: const MessageFrom('main', reachable: true),
  ),
);

void messageTests() {
  test("a child's message, reply and wait are its own", () {
    var tabs = withChildren(opened(['claude']), ['parser', 'docs']);
    tabs = heard(tabs, 2, [up, message('t')]);
    final unseen = agentOf(tabs, 2)!.child!.wait.unseen!;
    expect(unseen.kind, UnseenKind.message);
    // By the name its row gives.
    expect(unseen.from, '@main');
    // A message between agents wants no one.
    expect(attentionOrder(tabs), isEmpty);
    tabs = heard(tabs, 3, [up, prompt('d'), asked('d', 'p')], 5000);
    expect(attentionOrder(tabs), [3]);
    // Picking a child sees its marks; attending reaches the one that waits.
    expect(agentOf(pick(tabs, 2), 2)!.child!.wait.unseen, isNull);
    expect(shownKey(attend(tabs)!), 3);
  });

  test('a reply to a message counts its age from the reply, while the '
      'message keeps its place in the order', () {
    final asked = heard(opened(['a', 'b']), 1, [up, message('m')]);
    final replied = heard(asked, 1, [ended('m')], 24000);
    final wait = waitOf(replied, 1)!;
    expect(waitOf(asked, 1)!.unseen!.kind, UnseenKind.message);
    expect(wait.unseen!.kind, UnseenKind.replied);
    expect(wait.unseen!.since, 1000);
    expect(wait.unseen!.repliedAt, 24000);
  });

  test('a message after a reply or failure leaves that news as it is', () {
    final replied = heard(opened(['a', 'b']), 1, [up, prompt('t'), ended('t')]);
    final then = heard(replied, 1, [message('m')], 9000);
    expect(waitOf(then, 1)!.unseen!.kind, UnseenKind.replied);
  });
}

void teamNames() {
  test('a member is named with its run only while another run has one of '
      'its name', () {
    WindowAgents<String> lead(
      WindowAgents<String> tabs,
      String id,
      String name,
    ) => openChild(
      tabs,
      ChildInfo(
        id: id,
        name: name,
        runtime: 'claude',
        team: 'bugfix',
        openedAt: 0,
      ),
      '',
    )!.agents;
    WindowAgents<String> tester(
      WindowAgents<String> tabs,
      String id,
      String of,
    ) => openChild(
      tabs,
      ChildInfo(
        id: id,
        name: 'tester',
        runtime: 'claude',
        team: 'bugfix',
        lead: of,
        openedAt: 0,
      ),
      '',
    )!.agents;
    var tabs = tester(lead(opened(['claude']), 'one', 'bugfix'), 't1', 'one');
    Child<String> child(String id) =>
        tabs.children.firstWhere((c) => c.id == id);

    expect(namedChild(tabs, child('t1').info), 'tester');

    tabs = tester(lead(tabs, 'two', 'bugfix 2'), 't2', 'two');

    expect(namedChild(tabs, child('t1').info), 'tester · bugfix');
    expect(namedChild(tabs, child('t2').info), 'tester · bugfix 2');
    expect(namedChild(tabs, child('two').info), 'bugfix 2');

    // A notification names the run whoever shares the name.
    expect(notifiedName(tabs, child('t1').key), 'tester (bugfix)');
    expect(notifiedName(tabs, child('t2').key), 'tester (bugfix 2)');
    expect(notifiedName(tabs, child('two').key), 'bugfix 2');
    expect(notifiedName(tabs, 1), 'claude');
    expect(notifiedName(tabs, 99), isNull);
  });
}

void testerNotificationNames() {
  group('CTUI-93 tester: notification names', () {
    test('a single run is named without a colliding member', () {
      final lead = openChild(
        opened(['claude']),
        const ChildInfo(
          id: 'run',
          name: '修正 👩‍💻 é',
          runtime: 'claude',
          team: 'bugfix',
          openedAt: 0,
        ),
        '',
      )!;
      final member = openChild(
        lead.agents,
        const ChildInfo(
          id: 'member',
          name: 'tester',
          runtime: 'codex',
          lead: 'run',
          openedAt: 0,
        ),
        '',
      )!;
      expect(notifiedName(member.agents, member.key), 'tester (修正 👩‍💻 é)');
      expect(notifiedName(member.agents, lead.key), '修正 👩‍💻 é');
      expect(notifiedName(pick(member.agents, member.key), 1), 'claude');

      final withoutLead = closeChild(member.agents, lead.key);
      expect(notifiedName(withoutLead, member.key), 'tester');
      expect(notifiedName(withoutLead, lead.key), isNull);
      expect(
        notifiedName(closeChild(withoutLead, member.key), member.key),
        isNull,
      );
    });

    test(
      'empty windows and missing leads do not invent notification names',
      () {
        expect(notifiedName(noAgents<String>(), 1), isNull);
        final orphan = openChild(
          opened(['claude']),
          const ChildInfo(
            id: 'member',
            name: 'tester',
            runtime: 'codex',
            lead: 'absent',
            openedAt: 0,
          ),
          '',
        )!;
        expect(notifiedName(orphan.agents, orphan.key), 'tester');
        expect(notifiedName(orphan.agents, -1), isNull);
      },
    );
  });
}
