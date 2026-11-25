import 'dart:convert';

import 'package:chord/notify.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/waits.dart';
import 'package:chord/session/window_agents.dart';
import 'package:chord/status.dart';
import 'package:chord_tui/chord_tui.dart'
    show ProgramState, ProgramStatus, ProgramStatusKind;
import 'package:test/test.dart';

const up = Connected('s', AgentState.empty);
ConversationEvent prompt(String turnId) =>
    Transcribed(PromptAction(turnId, 'hi', 0));
ConversationEvent ended(String turnId) =>
    Transcribed(ResultAction(turnId, const TurnAnswered('end_turn')));
ConversationEvent failed(String turnId) =>
    Transcribed(ResultAction(turnId, const TurnFailed('boom')));
ConversationEvent permission(String turnId, String id) => Transcribed(
  PermissionRequestedAction(
    turnId,
    PermissionWait(id, title: 'Write notes.txt'),
  ),
);

/// The window's agent, shown, after [events], each a second after the last.
AgentWait heard(List<ConversationEvent> events, {AgentWait wait = idle}) {
  var now = 0;
  for (final event in events) {
    wait = heardWait(wait, event, now).wait;
    now += 1000;
  }
  return wait;
}

/// The record for a window whose only agent is main, `fake`, in [wait];
/// none open for null.
ProgramStatus status(AgentWait? wait, {String? title}) => programStatus(
  wait == null
      ? noAgents<String>()
      : WindowAgents(main: MainAgent(1, 'fake', 'fake', wait)),
  title: title,
);

/// The window for [agents]: main on the first, a child on each other, by
/// that name, the last opened picked.
WindowAgents<String> opened(List<String> agents) {
  var window = openMain(noAgents<String>(), agents.first, agents.first);
  for (final name in agents.skip(1)) {
    window = openChild(
      window,
      ChildInfo(id: name, name: name, runtime: name, openedAt: 0),
      name,
    )!.agents;
  }
  return pick(window, window.nextKey - 1);
}

/// Plays [events] into agent [key], each a second after the last from [at].
WindowAgents<String> heardBy(
  WindowAgents<String> tabs,
  int key,
  List<ConversationEvent> events, [
  num at = 0,
]) {
  for (final (index, event) in events.indexed) {
    tabs = hear(tabs, key, event, at + index * 1000).agents;
  }
  return tabs;
}

ConversationEvent link(String turnId, String id) => Transcribed(
  ElicitationRequestedAction(
    turnId,
    LinkWait(id, 'Sign in', 'https://example.com'),
  ),
);

void main() {
  rosterTests();
  testerRosterStatus();
  test('no agent doing anything is idle, and every report names chord', () {
    const idleChord = ProgramStatus(ProgramState.idle, app: 'chord');
    expect(status(null), idleChord);
    expect(status(heard([up])), idleChord);
  });

  test('a turn running is working, with no message', () {
    expect(
      status(heard([up, prompt('t1')])),
      const ProgramStatus(ProgramState.working, app: 'chord'),
    );
  });

  test('a permission blocks, by its kind and worded as its notification', () {
    expect(
      status(heard([up, prompt('t1'), permission('t1', 'p1')])),
      const ProgramStatus(
        ProgramState.blocked,
        app: 'chord',
        kind: ProgramStatusKind.permission,
        message: 'fake needs your permission: Write notes.txt',
      ),
    );
  });

  test("a turn that ended is done until the person's next key or the next "
      'turn', () {
    final done = heard([up, prompt('t1'), ended('t1')]);
    expect(
      status(done),
      const ProgramStatus(
        ProgramState.done,
        app: 'chord',
        message: 'fake is waiting for your input',
      ),
    );
    expect(status(keyed(done)).state, ProgramState.idle);
    expect(
      status(heard([prompt('t2')], wait: done)).state,
      ProgramState.working,
    );
  });

  test('an Esc-cancelled turn is idle when it ends, a late answer too', () {
    for (final result in [
      const TurnAnswered('cancelled'),
      const TurnAnswered('end_turn'),
    ]) {
      expect(
        status(
          heard([
            up,
            prompt('t1'),
            const Transcribed(CancelAction('t1', 1)),
            Transcribed(ResultAction('t1', result)),
          ]),
        ),
        const ProgramStatus(ProgramState.idle, app: 'chord'),
      );
    }
  });

  test('a failed turn, an agent that never came up and one that exited are '
      'errors that name the failure', () {
    final turn = heard([up, prompt('t1'), failed('t1')]);
    expect(
      status(turn),
      const ProgramStatus(
        ProgramState.error,
        app: 'chord',
        message: "fake's turn failed",
      ),
    );
    // A failed turn clears on a key, as a finished one does.
    expect(status(keyed(turn)).state, ProgramState.idle);
    expect(
      status(heard([const ConnectFailed('nope')])),
      const ProgramStatus(
        ProgramState.error,
        app: 'chord',
        message: 'fake failed to start',
      ),
    );
    final exited = heard([up, const Transcribed(DisconnectedAction(''))]);
    expect(
      status(exited),
      const ProgramStatus(
        ProgramState.error,
        app: 'chord',
        message: 'fake exited',
      ),
    );
    // An agent gone stays gone, keys or not.
    expect(status(keyed(exited)).state, ProgramState.error);
  });

  test('a message is one line with no control characters, cut to the bytes '
      'the protocol takes', () {
    expect(messageLine('a\nb\x1b[31mc\u0085d'), 'a b [31mc d');
    final long = messageLine('é' * messageBytes);
    expect(utf8.encode(long).length, messageBytes);
    expect(long, 'é' * (messageBytes ~/ 2));
    // A character that would cross the bound is left out whole.
    expect(messageLine('a${'é' * messageBytes}').length, messageBytes ~/ 2);
    final controls = [
      for (var code = 0; code < 160; code++)
        if (code < 32 || code >= 127) String.fromCharCode(code),
    ].join();
    expect(messageLine(controls), ' ' * 65);
    expect(messageLine('${'a' * 2044}😀x'), '${'a' * 2044}😀');
    expect(messageLine('${'a' * 2045}😀x'), 'a' * 2045);
  });

  group("the record's title names the session", () {
    final working = heard([up, prompt('t1')]);

    test('it goes with every state while the session has a name, and is left '
        'out while it has none', () {
      expect(
        status(null, title: 'Fix the tokenizer'),
        const ProgramStatus(
          ProgramState.idle,
          app: 'chord',
          title: 'Fix the tokenizer',
        ),
      );
      expect(
        status(working, title: 'Fix the tokenizer'),
        const ProgramStatus(
          ProgramState.working,
          app: 'chord',
          title: 'Fix the tokenizer',
        ),
      );
      final done = status(
        heard([ended('t1')], wait: working),
        title: 'Fix the tokenizer',
      );
      expect(
        (done.state, done.title),
        (ProgramState.done, 'Fix the tokenizer'),
      );
      for (final none in [null, '', '  ', '\n']) {
        expect(
          status(working, title: none),
          const ProgramStatus(ProgramState.working, app: 'chord'),
        );
      }
    });

    test('it is one line, cut to 192 UTF-8 bytes on a character’s edge', () {
      String title(String text) => status(null, title: text).title ?? '';
      expect(titleBytes, 192);
      expect(title('Fix\nthe\ttokenizer'), 'Fix the tokenizer');
      expect(title('a' * 193), 'a' * 192);
      expect(title('é' * 97), 'é' * 96);
      // A joined emoji, 11 bytes, stays whole or goes whole.
      const coder = '👩‍💻';
      expect(title('${'a' * 181}$coder'), '${'a' * 181}$coder');
      expect(title('${'a' * 182}$coder'), 'a' * 182);
      // An accent on its letter: the pair stays whole.
      expect(title('${'a' * 190}é'), 'a' * 190);
      for (final text in ['a' * 400, 'é' * 400, coder * 40]) {
        expect(utf8.encode(title(text)).length, lessThanOrEqualTo(192));
        expect(
          base64.encode(utf8.encode(title(text))).length,
          lessThanOrEqualTo(256),
        );
      }
    });
  });

  group('tester: status precedence and semantic boundaries', () {
    test('an open permission outranks exit until its own settlement', () {
      final blocked = heard([
        up,
        prompt('turn'),
        permission('turn', 'p'),
        const Transcribed(DisconnectedAction('turn')),
        failed('turn'),
      ]);
      expect(status(blocked).state, ProgramState.blocked);
      final seen = keyed(blocked);
      expect(identical(seen.watch, blocked.watch), isTrue);
      expect(identical(seen.asking, blocked.asking), isTrue);
      expect(seen.exited, isTrue);
      expect(seen.working, blocked.working);
      expect(seen.stopped, blocked.stopped);
      expect(status(seen).kind, ProgramStatusKind.permission);
      final settled = heard([
        const Transcribed(PermissionSettledAction('turn', 'p', Withdrawn())),
      ], wait: seen);
      expect(status(settled).state, ProgramState.error);
      expect(status(settled).message, 'fake exited');
    });

    test(
      'error outranks working and working outranks an earlier unseen reply',
      () {
        final replied = heardWait(
          heard([up, prompt('one')]),
          ended('one'),
          2000,
          front: false,
        ).wait;
        final working = heard([prompt('two')], wait: replied);
        expect(status(working).state, ProgramState.working);
        final failure = heardWait(
          working,
          failed('two'),
          3000,
          front: false,
        ).wait;
        final running = heard([prompt('three')], wait: failure);
        expect(running.working, isNotNull);
        expect(status(running).state, ProgramState.error);
        expect(status(running).message, "fake's turn failed");
      },
    );

    test('every text cut retains entire graphemes including zero room', () {
      for (final grapheme in ['界', '👩‍💻', 'é', '🇪🇸']) {
        final bytes = utf8.encode(grapheme).length;
        for (var room = 0; room <= bytes + 1; room++) {
          expect(statusLine(grapheme, room), room < bytes ? '' : grapheme);
        }
        final prefix = 'x' * (messageBytes - bytes);
        expect(messageLine('$prefix${grapheme}z'), '$prefix$grapheme');
        final over = 'x' * (messageBytes - bytes + 1);
        expect(messageLine('$over$grapheme'), over);
      }
      final wait = AgentWait(
        asking: (on: PermissionAsk(title: '👩‍💻' * 300), since: 0),
      );
      final report = status(wait, title: 'é' * 100);
      expect(
        utf8.encode(report.message!).length,
        lessThanOrEqualTo(messageBytes),
      );
      expect(utf8.encode(report.title!).length, 192);
      expect(report.title, 'é' * 64);
    });
  });
}

/// The original's cases of several agents at once.
void rosterTests() {
  test('keys on the parent leave a completed child done until it is '
      'picked', () {
    final child = openChild(
      heardBy(opened(['fake']), 1, [up]),
      const ChildInfo(
        id: 'child',
        name: 'tester',
        runtime: 'fake',
        openedAt: 0,
      ),
      'tester',
    )!;
    final done = heardBy(child.agents, child.key, [
      up,
      prompt('c'),
      ended('c'),
    ]);
    expect(
      programStatus(keyedAgents(done)),
      const ProgramStatus(
        ProgramState.done,
        app: 'chord',
        message: 'tester is waiting for your input',
      ),
    );
    expect(
      programStatus(pick(done, child.key)),
      const ProgramStatus(ProgramState.idle, app: 'chord'),
    );
  });

  test('a failed child turn clears on a key, leaving main working', () {
    final running = heardBy(opened(['first', 'second']), 1, [up, prompt('a')]);
    final failure = heardBy(running, 2, [up, prompt('b'), failed('b')]);
    expect(programStatus(failure).state, ProgramState.error);
    expect(
      programStatus(keyedAgents(failure)),
      const ProgramStatus(ProgramState.working, app: 'chord'),
    );
  });

  test('equal-age requests choose main first, then its child', () {
    final first = heardBy(opened(['first', 'second']), 1, [
      up,
      prompt('a'),
      permission('a', 'pa'),
    ]);
    final both = heardBy(first, 2, [up, prompt('b'), link('b', 'eb')]);
    expect(
      programStatus(both),
      const ProgramStatus(
        ProgramState.blocked,
        app: 'chord',
        kind: ProgramStatusKind.permission,
        message: 'first needs your permission: Write notes.txt',
      ),
    );
    final answered = heardBy(both, 1, [
      const Transcribed(PermissionSettledAction('a', 'pa', Withdrawn())),
    ]);
    expect(
      programStatus(answered),
      const ProgramStatus(
        ProgramState.blocked,
        app: 'chord',
        kind: ProgramStatusKind.auth,
        message: 'second asks for input: Sign in',
      ),
    );
  });

  test('an agent not shown stays done through keys until it is picked', () {
    // Main is behind the child.
    final behind = heardBy(opened(['fake', 'claude']), 1, [
      up,
      prompt('t1'),
      ended('t1'),
    ]);
    expect(
      programStatus(keyedAgents(behind)),
      const ProgramStatus(
        ProgramState.done,
        app: 'chord',
        message: 'fake is waiting for your input',
      ),
    );
    expect(programStatus(pick(behind, 1)).state, ProgramState.idle);
  });

  test('every agent folds as blocked, then error, then working, then done, '
      'then idle', () {
    // Main replied behind, the first child works, the second, in front, is
    // idle.
    final base = heardBy(
      heardBy(opened(['a', 'b', 'c']), 1, [up, prompt('t1'), ended('t1')]),
      2,
      [up, prompt('t2')],
    );
    expect(programStatus(base).state, ProgramState.working);
    final failing = heardBy(base, 3, [up, prompt('t3'), failed('t3')], 5000);
    expect(
      programStatus(failing),
      const ProgramStatus(
        ProgramState.error,
        app: 'chord',
        message: "c's turn failed",
      ),
    );
    expect(
      programStatus(heardBy(failing, 2, [permission('t2', 'p1')], 9000)),
      const ProgramStatus(
        ProgramState.blocked,
        app: 'chord',
        kind: ProgramStatusKind.permission,
        message: 'b needs your permission: Write notes.txt',
      ),
    );
    // With nothing working, the reply behind shows.
    expect(
      programStatus(heardBy(base, 2, [ended('t2')], 9000)),
      const ProgramStatus(
        ProgramState.done,
        app: 'chord',
        message: 'a is waiting for your input',
      ),
    );
  });

  test('of several agents in one state, the record names the one waiting '
      'longest, a child as its notification does', () {
    final tabs = openChild(
      heardBy(opened(['fake']), 1, [up, prompt('t1')]),
      const ChildInfo(id: 'c1', name: 'tester', runtime: 'codex', openedAt: 0),
      'tester',
    )!;
    final both = heardBy(
      heardBy(tabs.agents, tabs.key, [
        up,
        prompt('c'),
        permission('c', 'p2'),
      ], 1000),
      1,
      [permission('t1', 'p1')],
      9000,
    );
    expect(
      programStatus(both),
      const ProgramStatus(
        ProgramState.blocked,
        app: 'chord',
        kind: ProgramStatusKind.permission,
        message: 'tester needs your permission: Write notes.txt',
      ),
    );
  });
}

void testerRosterStatus() {
  group('CTUI-93 tester: aggregate lifecycle', () {
    test(
      'equal-age child failures choose key order regardless of list order',
      () {
        final failedBoth = heardBy(
          heardBy(opened(['main', 'first', 'second']), 2, [
            up,
            prompt('a'),
            failed('a'),
          ]),
          3,
          [up, prompt('b'), failed('b')],
        );
        final reordered = failedBoth.copyWith(
          children: failedBoth.children.reversed.toList(),
        );
        expect(programStatus(reordered).message, "first's turn failed");
        expect(
          programStatus(closeChild(reordered, 2)).message,
          "second's turn failed",
        );
        expect(
          programStatus(closeChild(closeChild(reordered, 2), 3)).state,
          ProgramState.idle,
        );
      },
    );

    test(
      'an older child error wins and acknowledgement preserves another error',
      () {
        final both = heardBy(
          heardBy(opened(['main', 'first', 'second']), 2, [
            up,
            prompt('a'),
            failed('a'),
          ], 9000),
          3,
          [up, prompt('b'), failed('b')],
          1000,
        );
        expect(programStatus(both).message, "second's turn failed");
        expect(programStatus(pick(both, 3)).message, "first's turn failed");
      },
    );
  });
}
