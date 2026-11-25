// The background view's agent rows, states, detail and stop offers, as the
// original's tests/ui/background/view_test.ts has them for agents.
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/background/background.dart';
import 'package:chord/ui/background/view.dart';
import 'package:chord_tui/chord_tui.dart' show cellWidth;
import 'package:test/test.dart';

const _now = 1000000;

const ItemOwner _parser = (name: 'parser', colour: 0);

BackgroundItem _agentItem(
  ItemStatus status, {
  String id = 'a',
  int key = 1,
  ItemOwner? owner,
  String name = 'A',
  num startedAt = 0,
  bool stoppable = false,
}) => BackgroundItem(
  kind: BackgroundKind.agent,
  id: id,
  key: key,
  owner: owner,
  name: name,
  startedAt: startedAt,
  status: status,
  stoppable: stoppable,
);

String _line(List<ViewCell> line) => line.map((c) => c.text).join();

List<String> _text(List<ViewRow> rows) => [
  for (final row in rows)
    for (final line in row.lines) _line(line).trimRight(),
];

void main() {
  test("an agent item's state reads as CHD-2's table words it, while it is "
      'listed (CHD-482)', () {
    String say(ItemStatus status) => stateText(
      _agentItem(status, name: 'Explore the parser', startedAt: _now - 41000),
      _now,
    ).text;

    expect(say(const ItemRunning()), 'running 41s');
    expect(say(const ItemRunning(stopping: true)), '■ stopping 41s');
    expect(
      say(const ItemAsking(AskingOn.permission, _now - 13000)),
      '● permission 13s',
    );
    expect(say(const ItemAsking(AskingOn.input, _now - 13000)), '● input 13s');
    expect(
      say(const ItemAsking(AskingOn.waiting, _now - 13000)),
      '● waiting 13s',
    );
    // Its time stands at the unknown.
    expect(
      say(const ItemEnded(BackgroundGroup.untracked, _now - 20000)),
      '? untracked 21s',
    );
  });

  group('CHD-2 tester: agent row clocks and wrapping', () {
    test('untracked time freezes while stopping time advances from the '
        'original start', () {
      final base = _agentItem(
        const ItemEnded(BackgroundGroup.untracked, _now - 5000),
        startedAt: _now - 10000,
      );

      expect(stateText(base, _now + 60000).text, '? untracked 5s');
      expect(
        stateText(
          _agentItem(
            const ItemRunning(stopping: true),
            startedAt: _now - 10000,
          ),
          _now + 60000,
        ).text,
        '■ stopping 1m 10s',
      );
    });

    test('long agent names preserve state and owner in narrow and wide '
        'rows', () {
      const name = 'Read the transport tests and describe cancellation';
      final entry = _agentItem(
        const ItemEnded(BackgroundGroup.untracked, _now - 10000),
        key: 2,
        owner: _parser,
        name: name,
        startedAt: _now - 20000,
      );

      for (final width in [76, 116]) {
        final rows = viewRows(
          [entry],
          width: width,
          focus: (key: 2, id: 'a'),
          now: _now,
        );
        final lines = _text(rows);
        final kept = [
          for (final line in rows.first.lines)
            for (final cell in line)
              if (cell.role == CellRole.name) cell.text.trim(),
        ].join(' ');

        expect(kept, name, reason: '$width');
        expect(lines.first, contains('? untracked 10s'), reason: '$width');
        expect(lines.first, contains('parser'), reason: '$width');
        expect(
          lines.every((line) => cellWidth(line) <= width),
          isTrue,
          reason: '$width',
        );
      }
    });
  });

  group("a monitor row's kind names its id (CHD-481)", () {
    test("a task's and an agent's kinds stay as they were", () {
      final rows = viewRows(
        [
          BackgroundItem(
            kind: BackgroundKind.task,
            id: 't1',
            key: 1,
            name: 'Fix the tokenizer',
            startedAt: _now - 32000,
            status: const ItemRunning(),
            runtime: 'fake',
            model: 'Fake Small',
          ),
          _agentItem(
            const ItemRunning(),
            id: 'a1',
            name: 'Find a',
            startedAt: _now - 1000,
          ),
        ],
        width: 116,
        focus: null,
        now: _now,
      );
      final kinds = [
        for (final row in rows)
          [
            for (final cell in row.lines.first)
              if (cell.role == CellRole.kind) cell.text.trim(),
          ].join(),
      ];

      expect(kinds[1], 'agent');
      expect(kinds[0], isNot(contains('t1')));
    });
  });

  group("an agent's or a task's detail (CHD-487)", () {
    const subagent = Subagent('a');
    List<String> plain(List<List<ViewCell>> lines) => [
      for (final line in lines) _line(line),
    ];

    test("its pinned lines: the description, then its state, tool uses and "
        "owner; a task's kind among them (Q139)", () {
      // The task's half is in view_test.dart; this is the agent's.
      final agent = _agentItem(
        const ItemRunning(),
        name: 'Run the test suite',
        startedAt: _now - 41000,
        stoppable: true,
      );

      expect(plain(workHead(agent, subagent, width: 116, now: _now)), [
        'Run the test suite',
        'running 41s · 0 tool uses · main',
      ]);
      // Narrow, its parts wrap after a ` · `, no line wider than its width.
      expect(
        workHead(
          agent,
          subagent,
          width: 20,
          now: _now,
        ).every((line) => cellWidth(_line(line)) <= 20),
        isTrue,
      );
    });
  });

  group("an agent's or a task's detail: reviewer's edges (CHD-487)", () {
    BackgroundItem ended(
      BackgroundKind kind,
      BackgroundGroup group, [
      EndWord? word,
    ]) => BackgroundItem(
      kind: kind,
      id: 'a',
      key: 1,
      name: 'x',
      startedAt: _now - 124000,
      status: ItemEnded(group, _now, word: word),
    );

    test("an agent's end reads as CHD-2's table, a task's as CHD-424's; a "
        "monitor's as it did", () {
      const agent = BackgroundKind.agent, task = BackgroundKind.task;
      expect(
        [
          ended(agent, BackgroundGroup.done),
          ended(agent, BackgroundGroup.failed),
          ended(agent, BackgroundGroup.failed, EndWord.disconnected),
          ended(agent, BackgroundGroup.stopped),
          ended(agent, BackgroundGroup.stopped, EndWord.ended),
          ended(task, BackgroundGroup.done),
          ended(task, BackgroundGroup.failed),
          ended(task, BackgroundGroup.stopped),
        ].map((item) => stateText(item, _now).text),
        [
          '✓ done in 2m 4s',
          '✗ failed after 2m 4s',
          '✗ disconnected after 2m 4s',
          '■ stopped after 2m 4s',
          '■ ended after 2m 4s',
          '✓ reported after 2m 4s',
          '✗ failed after 2m 4s',
          '■ stopped after 2m 4s',
        ],
      );
      expect(
        stateText(
          const BackgroundItem(
            kind: BackgroundKind.monitor,
            id: 'm1',
            key: 1,
            name: 'CI',
            startedAt: _now - 192000,
            status: ItemEnded(
              BackgroundGroup.failed,
              _now,
              end: MonitorExited(1),
            ),
            events: 3,
          ),
          _now,
        ).text,
        '✗ exit code 1 after 3m 12s · 3 events',
      );
    });
  });

  group('stopNowOffered', () {
    // The original's stoppable left out is Dart's false.
    BackgroundItem agent([bool stoppable = false]) =>
        _agentItem(const ItemRunning(), stoppable: stoppable);
    const ItemRef focus = (key: 1, id: 'a');

    test('names the focused agent once it offers the stop the hint '
        'denied', () {
      expect(stopNowOffered([agent(true)], focus, noStopHint), focus);
    });

    test('names none while it offers no stop, or the hint says something '
        'else', () {
      expect(stopNowOffered([agent(false)], focus, noStopHint), isNull);
      expect(stopNowOffered([agent()], focus, noStopHint), isNull);
      expect(stopNowOffered([agent(true)], focus, 'could not stop'), isNull);
      expect(stopNowOffered([agent(true)], focus, null), isNull);
    });
  });
}
