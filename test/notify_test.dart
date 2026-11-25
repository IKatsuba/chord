import 'package:chord/notify.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord_tui/chord_tui.dart' show StdioTerminal;
import 'package:test/test.dart';

const iterm = TerminalEnv(termProgram: 'iTerm.app');
const apple = TerminalEnv(termProgram: 'Apple_Terminal');
const tmux = TerminalEnv(
  termProgram: 'tmux',
  term: 'tmux-256color',
  tmux: true,
);

const connected = Connected('s', AgentState.empty);
ConversationEvent prompt(String turnId) =>
    Transcribed(PromptAction(turnId, 'hello', 0));
ConversationEvent ended(String turnId, {bool cancelled = false}) => Transcribed(
  ResultAction(turnId, TurnAnswered(cancelled ? 'cancelled' : 'end_turn')),
);
ConversationEvent asked(
  String turnId,
  String id, {
  String? title = 'Write notes.txt',
  num? at,
  bool between = false,
}) => Transcribed(
  PermissionRequestedAction(
    turnId,
    PermissionWait(id, title: title),
    at: at,
    between: between,
  ),
);
ConversationEvent settled(String turnId, String id) =>
    Transcribed(PermissionSettledAction(turnId, id, const Chosen('allow')));
ConversationEvent withdrawn(String turnId, String id) =>
    Transcribed(PermissionSettledAction(turnId, id, const Withdrawn()));

/// A terminal that keeps the bytes it is told.
class _Bytes extends StdioTerminal {
  _Bytes({required bool tmux})
    : super(input: const Stream.empty(), tmuxPassthrough: tmux);
  final written = <String>[];
  @override
  void write(String data) => written.add(data);
}

/// Every event in turn, and the bytes each wrote through the framework.
({Watch watch, List<String> written}) play(
  List<ConversationEvent> events, {
  NotifChannel channel = NotifChannel.osc9,
  TerminalEnv env = iterm,
}) {
  var watch = emptyWatch;
  final terminal = _Bytes(tmux: env.tmux);
  for (final event in events) {
    final seen = notify(
      watch,
      event,
      Notifications(channel: channel, env: env),
      'claude',
    );
    watch = seen.watch;
    if (seen.notification case final n?) {
      terminal.notify(n.message, channel: n.channel, title: n.title);
    }
  }
  return (watch: watch, written: terminal.written);
}

void main() {
  group('CTUI-36 tester: monitor notification lifetime', () {
    ConversationEvent monitor(String turn, MonitorEnd? end) => Transcribed(
      PromptAction(
        turn,
        'log',
        0,
        from: MessageFrom('watch', monitor: (id: 'm1', end: end)),
      ),
    );

    test('failed event turns stay silent and their watch entries retire', () {
      final result = play([
        connected,
        monitor('e1', null),
        const Transcribed(ResultAction('e1', TurnFailed('agent failed'))),
      ]);
      expect(result.written, isEmpty);
      expect(result.watch.events, isEmpty);
      expect(
        play([
          connected,
          monitor('e1', null),
          ended('e1'),
          const Cleared(),
          connected,
          prompt('e1'),
          ended('e1'),
        ]).written,
        hasLength(1),
      );
    });

    test(
      'every monitor end notifies once and cancellation still suppresses it',
      () {
        for (final end in const <MonitorEnd>[
          MonitorExited(0),
          MonitorExited(1),
          MonitorKilled('SIGKILL'),
          MonitorStopped(),
          MonitorTimedOut(1000),
          MonitorFlooded(FloodBy.bytes),
        ]) {
          expect(
            play([connected, monitor('end', end), ended('end')]).written,
            hasLength(1),
          );
          expect(
            play([
              connected,
              monitor('end', end),
              const Transcribed(CancelAction('end', 0)),
              ended('end', cancelled: true),
            ]).written,
            isEmpty,
          );
        }
      },
    );
  });

  test('a finished turn writes the channel chosen', () {
    final turn = [connected, prompt('t1'), ended('t1')];
    expect(play(turn, channel: NotifChannel.osc9).written, [
      '\x1b]9;claude is waiting for your input\x07',
    ]);
    expect(play(turn, channel: NotifChannel.osc777).written, [
      '\x1b]777;notify;chord;claude is waiting for your input\x07',
    ]);
    expect(play(turn, channel: NotifChannel.bell).written, ['\x07']);
    expect(play(turn, channel: NotifChannel.off).written, isEmpty);
  });

  test('a failed turn waits on the person too', () {
    expect(
      play([
        connected,
        prompt('t1'),
        const Transcribed(ResultAction('t1', TurnFailed('boom'))),
      ]).written,
      hasLength(1),
    );
  });

  test('auto is OSC 9 where the terminal shows it, OSC 777 on foot, BEL '
      'elsewhere', () {
    for (final env in const [
      iterm,
      TerminalEnv(termProgram: 'WezTerm'),
      TerminalEnv(termProgram: 'ghostty'),
      TerminalEnv(term: 'xterm-ghostty'),
      TerminalEnv(term: 'xterm-kitty'),
    ]) {
      expect(resolveChannel(NotifChannel.auto, env), NotifChannel.osc9);
    }
    expect(
      resolveChannel(NotifChannel.auto, const TerminalEnv(term: 'foot')),
      NotifChannel.osc777,
    );
    expect(resolveChannel(NotifChannel.auto, apple), NotifChannel.bell);
    expect(
      resolveChannel(NotifChannel.auto, const TerminalEnv()),
      NotifChannel.bell,
    );
    expect(resolveChannel(NotifChannel.bell, iterm), NotifChannel.bell);
  });

  test('inside tmux auto rings the bell, and a chosen OSC goes through '
      'passthrough', () {
    final turn = [connected, prompt('t1'), ended('t1')];
    expect(
      resolveChannel(
        NotifChannel.auto,
        const TerminalEnv(termProgram: 'iTerm.app', tmux: true),
      ),
      NotifChannel.bell,
    );
    expect(play(turn, channel: NotifChannel.auto, env: tmux).written, ['\x07']);
    expect(play(turn, channel: NotifChannel.osc9, env: tmux).written, [
      '\x1bPtmux;\x1b\x1b]9;claude is waiting for your input\x07\x1b\\',
    ]);
    expect(play(turn, channel: NotifChannel.osc777, env: tmux).written, [
      '\x1bPtmux;\x1b\x1b]777;notify;chord;claude is waiting for your '
          'input\x07\x1b\\',
    ]);
    expect(play(turn, channel: NotifChannel.bell, env: tmux).written, ['\x07']);
  });

  test('the environment says the terminal and whether tmux is between', () {
    TerminalEnv env(Map<String, String> vars) => terminalEnv((n) => vars[n]);
    expect(
      env({'TERM_PROGRAM': 'iTerm.app', 'TERM': 'xterm-256color'}),
      const TerminalEnv(termProgram: 'iTerm.app', term: 'xterm-256color'),
    );
    expect(env({'TMUX': '/tmp/tmux-1/default,1,0'}).tmux, isTrue);
    expect(env({'TMUX': ''}).tmux, isFalse);
  });

  test('settings name each channel, and nothing else', () {
    for (final channel in NotifChannel.values) {
      expect(NotifChannel.named(channel.name), channel);
    }
    expect(NotifChannel.named(null), isNull);
    expect(NotifChannel.named('osc'), isNull);
  });

  test('a turn cancelled with Esc writes nothing', () {
    const cancel = Transcribed(CancelAction('t1', 1));
    expect(
      play([connected, prompt('t1'), cancel, ended('t1')]).written,
      isEmpty,
    );
    // The agent's own word for it is enough.
    expect(
      play([connected, prompt('t1'), ended('t1', cancelled: true)]).written,
      isEmpty,
    );
    // And the turn after it notifies again.
    expect(
      play([
        connected,
        prompt('t1'),
        cancel,
        ended('t1'),
        prompt('t2'),
        ended('t2'),
      ]).written,
      hasLength(1),
    );
  });

  test('a permission request writes its own notification, once while any is '
      'open', () {
    expect(
      play([
        connected,
        prompt('t1'),
        asked('t1', 'p1'),
        asked('t1', 'p2'),
        settled('t1', 'p1'),
        settled('t1', 'p2'),
        asked('t1', 'p3', title: null),
      ]).written,
      [
        '\x1b]9;claude needs your permission: Write notes.txt\x07',
        '\x1b]9;claude needs your permission\x07',
      ],
    );
  });

  test('a turn with a queued prompt behind it is no wait', () {
    expect(
      play([
        connected,
        prompt('t1'),
        const Queued('t2', 'next'),
        ended('t1'),
        prompt('t2'),
        ended('t2'),
      ]).written,
      hasLength(1),
    );
    // Taken back, the queue is no longer behind it.
    expect(
      play([
        connected,
        prompt('t1'),
        const Queued('t2', 'next'),
        const QueueWithdrawn([]),
        ended('t1'),
      ]).written,
      hasLength(1),
    );
  });

  test("a turn a monitor's event started writes nothing; its end's turn and "
      'a permission inside one do', () {
    ConversationEvent event(String turnId, {bool end = false}) => Transcribed(
      PromptAction(
        turnId,
        'ERROR',
        0,
        from: MessageFrom(
          'dev server errors',
          monitor: (id: 'm1', end: end ? const MonitorStopped() : null),
        ),
      ),
    );
    expect(play([connected, event('e1'), ended('e1')]).written, isEmpty);
    expect(
      play([
        connected,
        event('e1'),
        ended('e1'),
        event('e2', end: true),
        ended('e2'),
      ]).written,
      hasLength(1),
    );
    expect(
      play([connected, event('e1'), asked('e1', 'p1'), ended('e1')]).written,
      ['\x1b]9;claude needs your permission: Write notes.txt\x07'],
    );
    // The person's next turn rings as ever.
    expect(
      play([
        connected,
        event('e1'),
        ended('e1'),
        prompt('t1'),
        ended('t1'),
      ]).written,
      hasLength(1),
    );
  });

  test("a resumed session's replayed turns write nothing", () {
    expect(play([prompt('old'), ended('old'), connected]).written, isEmpty);
    // `/clear` starts over: the next session's past is replayed too.
    expect(
      play([connected, const Cleared(), prompt('old'), ended('old')]).written,
      isEmpty,
    );
  });

  test('what the agent says cannot end the escape early or add a field', () {
    List<String> bytes(NotifChannel channel) => play([
      connected,
      asked('t1', 'p1', title: 'Run a; b\x07\x1b]9;x'),
    ], channel: channel).written;
    expect(bytes(NotifChannel.osc9), [
      '\x1b]9;claude needs your permission: Run a; b  ]9;x\x07',
    ]);
    expect(bytes(NotifChannel.osc777), [
      '\x1b]777;notify;chord;claude needs your permission: Run a, b  ]9,x\x07',
    ]);
  });

  test('a form or link says the agent asks for input', () {
    expect(
      waitMessage(const InputAsk('Set up the deploy target'), 'claude'),
      'claude asks for input: Set up the deploy target',
    );
  });

  group("a request across the turn that started it", () {
    test("stays open when the turn ends, as the agent's own does", () {
      final (:watch, written: _) = play([
        connected,
        prompt('t1'),
        asked('t1', 'p1', at: 1000),
        asked('t1', 'p2'),
        ended('t1'),
      ]);
      expect(watch.asking, ['p1', 'p2']);
      expect(watch.lasting, ['p1']);
    });

    test('goes once answered or withdrawn, and a later one asks again', () {
      final (:watch, :written) = play([
        connected,
        prompt('t1'),
        asked('t1', 'p1', at: 1000),
        ended('t1'),
        withdrawn('t1', 'p1'),
        asked('t1', 'p2', at: 1000),
      ]);
      expect(watch.asking, ['p2']);
      // The first request, the turn's end, and the second request.
      expect(written, hasLength(3));
    });

    test('withdrawal and clear remove lasting ids so a later request can '
        'notify again', () {
      final request = asked('t1', 'lasting', between: true);
      final events = [
        connected,
        request,
        ended('t1'),
        withdrawn('t1', 'lasting'),
      ];
      final gone = play(events).watch;
      expect(gone.asking, isEmpty);
      expect(gone.lasting, isEmpty);
      expect(
        play([...events, request]).written.last,
        contains('needs your permission'),
      );
      final cleared = play([connected, request, const Cleared()]).watch;
      expect(identical(cleared, emptyWatch), isTrue);
    });
  });

  test('the request on screen is the oldest permission still open', () {
    final (:watch, written: _) = play([
      connected,
      asked('t1', 'p1', title: 'first'),
      asked('t1', 'p2', title: 'second'),
      settled('t1', 'p1'),
    ]);
    expect(askingNow(watch), const PermissionAsk(title: 'second'));
    expect(askingNow(emptyWatch), isNull);
  });

  test("an agent's own cycle rings at its end, as a turn does, and not as it "
      'starts', () {
    const cycle = Transcribed(CycleStartedAction('c1', 0));
    expect(
      play([connected, prompt('t1'), ended('t1'), cycle]).written,
      hasLength(1),
    );
    expect(
      play([connected, prompt('t1'), ended('t1'), cycle, ended('c1')]).written,
      [
        '\x1b]9;claude is waiting for your input\x07',
        '\x1b]9;claude is waiting for your input\x07',
      ],
    );
  });
}
