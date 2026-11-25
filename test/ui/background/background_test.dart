// The background's items and summary line, as the original's
// tests/ui/background/background_test.ts has them for monitors and tasks.
import 'package:chord/session/monitors.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/background/background.dart';
import 'package:test/test.dart';

RunningMonitor _running(String id, String description, int startedAt) =>
    RunningMonitor(
      MonitorInfo(
        id: id,
        description: description,
        command: 'cmd',
        startedAt: startedAt,
        timeoutMs: 600000,
      ),
      events: 1,
    );

EndedMonitor _ended(RunningMonitor monitor, MonitorEnd end, int endedAt) =>
    EndedMonitor(
      monitor.info,
      events: monitor.events,
      lastEvent: monitor.lastEvent,
      end: end,
      endedAt: endedAt,
    );

Entry _task(
  String id,
  String name,
  num startedAt, {
  SubagentState state = SubagentState.running,
  num? endedAt,
  List<Entry> entries = const [],
}) => SubagentEntry(
  't1',
  Subagent(
    id,
    title: name,
    state: state,
    startedAt: startedAt,
    endedAt: endedAt,
    entries: entries,
    task: TaskInfo(name: name, runtime: 'fake', model: 'Fake Small'),
    callId: 'call-$id',
  ),
);

BackgroundAgent _agent(
  int key, {
  ItemOwner? owner,
  num? since = 0,
  List<RunningMonitor> monitors = const [],
  List<EndedMonitor> endedMonitors = const [],
  List<Entry> entries = const [],
  TurnState turn = const Idle(),
  List<ElicitationWait> asking = const [],
}) => BackgroundAgent(
  key: key,
  owner: owner,
  since: since,
  monitors: monitors,
  endedMonitors: endedMonitors,
  transcript: Transcript(entries: entries, turn: turn, asking: asking),
);

List<String> _brief(List<BackgroundItem> items) => [
  for (final item in items)
    '${item.kind.name} ${item.name} ${item.key} ${item.status.group.name}',
];

BackgroundItem _item(
  BackgroundKind kind,
  ItemStatus status, [
  String id = 'x',
]) => BackgroundItem(
  kind: kind,
  id: id,
  key: 1,
  name: 'x',
  startedAt: 0,
  status: status,
);

const _runningStatus = ItemRunning();
const _askingStatus = ItemAsking(AskingOn.permission, 0);
const _failedStatus = ItemEnded(BackgroundGroup.failed, 0);
const _doneStatus = ItemEnded(BackgroundGroup.done, 0);
const _stoppedStatus = ItemEnded(BackgroundGroup.stopped, 0);

const _link = 'u';

void main() {
  group('the items', () {
    test("every monitor and task of the session's agents, oldest first, each "
        'in its state', () {
      final items = backgroundItems([
        _agent(
          1,
          monitors: [_running('m2', 'dev server', 300)],
          endedMonitors: [
            _ended(_running('m1', 'CI run', 100), const MonitorExited(1), 400),
          ],
          entries: [
            _task('task-1', 'Fix the tokenizer', 200),
            _task(
              'task-2',
              'Fix the printer',
              500,
              state: SubagentState.completed,
              endedAt: 900,
            ),
          ],
        ),
        _agent(
          2,
          owner: (name: 'parser', colour: 0),
          monitors: [_running('m1', 'parser tests', 250)],
        ),
      ]);
      // The ended monitor and the ended task have left.
      expect(_brief(items), [
        'task Fix the tokenizer 1 running',
        'monitor parser tests 2 running',
        'monitor dev server 1 running',
      ]);
      final first = items.first;
      expect(
        (
          first.id,
          first.startedAt,
          first.status,
          first.runtime,
          first.model,
          first.callId,
          first.owner,
        ),
        (
          'task-1',
          200,
          const ItemRunning(),
          'fake',
          'Fake Small',
          'call-task-1',
          null,
        ),
      );
      expect(items[1].owner, (name: 'parser', colour: 0));
    });

    test('a monitor leaves the list however it ended', () {
      final monitor = _running('m1', 'x', 0);
      expect(
        [
          for (final end in const [
            MonitorExited(0),
            MonitorExited(2),
            MonitorKilled('SIGKILL'),
            MonitorTimedOut(1000),
            MonitorFlooded(FloodBy.lines),
            MonitorStopped(),
          ])
            backgroundItems([
              _agent(1, endedMonitors: [_ended(monitor, end, 5)]),
            ]).length,
        ],
        [0, 0, 0, 0, 0, 0],
      );
    });

    test('an ended monitor whose detail is open stays until it is left, the '
        'others leaving as they would', () {
      final agents = [
        _agent(
          1,
          endedMonitors: [
            _ended(_running('m1', 'kept', 0), const MonitorTimedOut(1000), 5),
            _ended(_running('m2', 'gone', 0), const MonitorStopped(), 5),
          ],
        ),
      ];
      expect(_brief(backgroundItems(agents, keep: (key: 1, id: 'm1'))), [
        'monitor kept 1 stopped',
      ]);
      expect(backgroundItems(agents, keep: (key: 2, id: 'm1')), isEmpty);
    });

    test('a task leaves at once however it ends; its open detail keeps '
        'it', () {
      List<BackgroundItem> items(
        SubagentState state, [
        ({int key, String id})? keep,
      ]) => backgroundItems([
        _agent(1, entries: [_task('t', 'x', 10, state: state, endedAt: 20)]),
      ], keep: keep);
      const ends = [
        SubagentState.completed,
        SubagentState.failed,
        SubagentState.disconnected,
        SubagentState.cancelled,
      ];
      expect([for (final s in ends) items(s).length], [0, 0, 0, 0]);
      expect(
        [for (final s in ends) items(s, (key: 1, id: 't')).length],
        [1, 1, 1, 1],
      );
    });

    test('a task asking for a permission or an input counts from when it '
        'asked, its oldest request first', () {
      ItemStatus? asking({
        TurnState turn = const Idle(),
        List<ElicitationWait> asking = const [],
      }) => backgroundItems([
        _agent(
          1,
          entries: [_task('task-1', 'x', 10)],
          turn: turn,
          asking: asking,
        ),
      ]).firstOrNull?.status;
      expect(
        asking(
          turn: const AwaitingPermission('t1', 5, [
            PermissionWait('p0'),
            PermissionWait('p1', subagentId: 'task-1', at: 40),
          ]),
        ),
        const ItemAsking(AskingOn.permission, 40),
      );
      expect(
        asking(
          asking: const [
            LinkWait(
              'e1',
              'Sign in',
              'https://example.com',
              subagentId: 'task-1',
              at: 30,
            ),
          ],
        ),
        const ItemAsking(AskingOn.input, 30),
      );
      // Another's request leaves it working.
      expect(
        asking(
          asking: const [
            LinkWait('e1', 'm', _link, subagentId: 'other', at: 1),
          ],
        ),
        const ItemRunning(),
      );
    });

    test("a task in a subagent's work is one, and one from before its "
        'session came up is its past, not an item', () {
      // An adapter's subagent of its own, which is no task, with one inside.
      final nested = SubagentEntry(
        't1',
        Subagent(
          'outer',
          startedAt: 10,
          entries: [_task('inner', 'Inner task', 20)],
        ),
      );
      final items = backgroundItems([
        _agent(
          1,
          since: 15,
          entries: [
            _task(
              'past',
              'Past task',
              5,
              state: SubagentState.completed,
              endedAt: 8,
            ),
            nested,
          ],
        ),
        // Not up yet: nothing of it counts.
        _agent(2, since: null, entries: [_task('t', 'x', 30)]),
      ]);
      expect(_brief(items), ['task Inner task 1 running']);
    });

    test('items started in the same millisecond keep their places whichever '
        'ends first', () {
      final one = _running('m1', 'one', 100), two = _running('m2', 'two', 100);
      final tasks = [_task('task-a', 'a', 100), _task('task-b', 'b', 100)];
      expect(
        [
          for (final item in backgroundItems([
            _agent(1, entries: tasks, monitors: [one, two]),
            _agent(
              2,
              owner: (name: 'parser', colour: 0),
              monitors: [_running('m1', 'three', 100)],
            ),
          ]))
            item.name,
        ],
        ['one', 'two', 'a', 'b', 'three'],
      );
      expect(
        [
          for (final item in backgroundItems([
            _agent(
              1,
              endedMonitors: [
                _ended(two, const MonitorStopped(), 150),
                _ended(one, const MonitorExited(0), 160),
              ],
              entries: [
                tasks[0],
                _task(
                  'task-b',
                  'b',
                  100,
                  state: SubagentState.completed,
                  endedAt: 120,
                ),
              ],
            ),
            _agent(
              2,
              owner: (name: 'parser', colour: 0),
              endedMonitors: [
                _ended(
                  _running('m1', 'three', 100),
                  const MonitorStopped(),
                  110,
                ),
              ],
            ),
          ]))
            item.name,
        ],
        ['a'],
      );
    });

    test('same-millisecond monitor ids stay in numeric order', () {
      final items = backgroundItems([
        _agent(
          1,
          monitors: [
            _running('m10', 'ten', 10),
            _running('m11', 'eleven', 10),
            _running('m1', 'one', 10),
          ],
          endedMonitors: [
            _ended(_running('m9', 'nine', 10), const MonitorStopped(), 20),
            _ended(_running('m2', 'two', 10), const MonitorExited(1), 30),
          ],
        ),
      ]);
      expect([for (final i in items) i.id], ['m1', 'm10', 'm11']);
    });

    test('the oldest matching input or permission sets asking time, and an '
        'ended task ignores stale requests', () {
      ItemStatus? status({required List<Entry> entries, bool inputs = true}) =>
          backgroundItems([
            _agent(
              1,
              entries: entries,
              turn: const AwaitingPermission('t1', 5, [
                PermissionWait('p-other', subagentId: 'other', at: 1),
                PermissionWait('p-new', subagentId: 't', at: 40),
                PermissionWait('p-old', subagentId: 't', at: 30),
              ]),
              asking: inputs
                  ? const [LinkWait('e', 'm', _link, subagentId: 't', at: 20)]
                  : const [],
            ),
          ]).firstOrNull?.status;
      expect(
        status(entries: [_task('t', 'task', 10)]),
        const ItemAsking(AskingOn.input, 20),
      );
      expect(
        status(entries: [_task('t', 'task', 10)], inputs: false),
        const ItemAsking(AskingOn.permission, 30),
      );
      expect(
        status(
          entries: [
            _task('t', 'task', 10, state: SubagentState.cancelled, endedAt: 50),
          ],
        ),
        isNull,
      );
    });

    test('a monitor item keeps its command, start, timeout and last batch; '
        'no batch before the first', () {
      final quiet = _running('m1', 'dev server', 100);
      final said = RunningMonitor(
        const MonitorInfo(
          id: 'm2',
          description: 'CI run',
          command: 'bun test --watch',
          startedAt: 200,
          timeoutMs: 3600000,
        ),
        events: 1,
        lastEvent: (lines: ['ok 1', 'ok 2'], at: 900),
      );
      final items = backgroundItems([
        _agent(1, monitors: [quiet, said]),
      ]);
      expect(
        [
          for (final i in items)
            [i.id, i.command, i.startedAt, i.timeoutMs, i.lastEvent?.lines],
        ],
        [
          ['m1', 'cmd', 100, 600000, null],
          [
            'm2',
            'bun test --watch',
            200,
            3600000,
            ['ok 1', 'ok 2'],
          ],
        ],
      );
    });
  });

  group('the summary line', () {
    test('a group per state, most urgent first, its kinds joined by and, '
        'each word by its count', () {
      expect(
        summaryGroups([
          _item(BackgroundKind.task, _runningStatus),
          _item(BackgroundKind.monitor, _stoppedStatus),
          _item(BackgroundKind.monitor, _runningStatus),
          _item(BackgroundKind.task, _doneStatus),
          _item(BackgroundKind.monitor, _failedStatus),
          _item(BackgroundKind.task, _askingStatus),
          _item(BackgroundKind.monitor, _runningStatus),
        ]),
        [
          (group: BackgroundGroup.asking, text: '● 1 task asking'),
          (group: BackgroundGroup.failed, text: '✗ 1 monitor failed'),
          (
            group: BackgroundGroup.running,
            text: '2 monitors and 1 task running',
          ),
          (group: BackgroundGroup.done, text: '✓ 1 task done'),
          (group: BackgroundGroup.stopped, text: '■ 1 monitor stopped'),
        ],
      );
      expect(summaryGroups(const []), isEmpty);
      expect(
        summaryGroups([
          _item(BackgroundKind.task, _failedStatus),
          _item(BackgroundKind.task, _failedStatus),
        ]),
        [(group: BackgroundGroup.failed, text: '✗ 2 tasks failed')],
      );
    });

    List<String> text(List<List<SummaryPiece>> lines) => [
      for (final line in lines) line.map((p) => p.text).join(),
    ];
    final groups = summaryGroups([
      _item(BackgroundKind.task, _askingStatus),
      _item(BackgroundKind.monitor, _failedStatus),
      _item(BackgroundKind.monitor, _runningStatus),
      _item(BackgroundKind.monitor, _runningStatus),
      _item(BackgroundKind.task, _runningStatus),
    ]);

    test('on one line where it fits, the label first and the groups joined '
        'by a dot', () {
      final lines = summaryLines(groups, 120);
      expect(text(lines), [
        'background  ● 1 task asking · ✗ 1 monitor failed · 2 monitors and 1 '
            'task running',
      ]);
      const plain = PlainTone();
      expect(
        [for (final p in lines.first) p.tone],
        [
          const LabelTone(),
          plain,
          const GroupTone(BackgroundGroup.asking),
          plain,
          plain,
          const GroupTone(BackgroundGroup.failed),
          plain,
          plain,
          const GroupTone(BackgroundGroup.running),
        ],
      );
    });

    test('too long, it breaks between groups, the next line under the first '
        'group', () {
      expect(text(summaryLines(groups, 74)), [
        'background  ● 1 task asking · ✗ 1 monitor failed ·',
        '            2 monitors and 1 task running',
      ]);
      expect(text(summaryLines(groups, 34)), [
        'background  ● 1 task asking ·',
        '            ✗ 1 monitor failed ·',
        '            2 monitors and 1 task',
        '            running',
      ]);
    });

    test('a group longer than a line alone breaks between its words, its dot '
        'kept on its last', () {
      expect(
        text(
          summaryLines(
            summaryGroups([
              _item(BackgroundKind.monitor, _runningStatus),
              _item(BackgroundKind.task, _runningStatus),
              _item(BackgroundKind.task, _doneStatus),
            ]),
            26,
          ),
        ),
        [
          'background  1 monitor and',
          '            1 task',
          '            running ·',
          '            ✓ 1 task done',
        ],
      );
    });

    test('all summary words and separators survive wrapping at every width '
        'from 26 through 120', () {
      final all = summaryGroups([
        _item(BackgroundKind.task, _askingStatus),
        _item(BackgroundKind.monitor, _failedStatus),
        _item(BackgroundKind.monitor, _runningStatus),
        _item(BackgroundKind.task, _runningStatus),
        _item(BackgroundKind.task, _doneStatus),
        _item(BackgroundKind.monitor, _stoppedStatus),
      ]);
      final words = 'background ${all.map((g) => g.text).join(' · ')}'.split(
        RegExp(r'\s+'),
      );
      for (var width = 26; width <= 120; width++) {
        final lines = text(summaryLines(all, width));
        expect(lines.join(' ').trim().split(RegExp(r'\s+')), words);
        expect(lines.every((l) => l.runes.length <= width), isTrue);
        expect(lines.skip(1).every((l) => l.startsWith(' ' * 12)), isTrue);
      }
    });
  });

  group('the call that started an item', () {
    Entry monitorCall(String id, String callId) => ToolEntry(
      't1',
      ToolCall(
        callId,
        title: 'Monitor',
        chord: ChordCall(
          tool: ChordTool.monitor,
          input: const {},
          answer: {'id': id, 'description': 'x', 'timeout_ms': 1000},
        ),
      ),
    );
    BackgroundItem item(BackgroundKind kind, String id) =>
        _item(kind, _runningStatus, id);
    const text = UserEntry('t1', 'hi');

    test("a monitor's is its Monitor call, by the id its answer gave", () {
      final entries = [text, monitorCall('m1', 'c1'), monitorCall('m2', 'c2')];
      expect(callPlace(entries, item(BackgroundKind.monitor, 'm2')), (
        entry: 2,
        target: 'call:c2',
      ));
      expect(callPlace(entries, item(BackgroundKind.monitor, 'm9')), isNull);
    });

    test("a task's is its own Agent block, or its own row in the group of "
        'tasks that draws it', () {
      final entries = [
        text,
        _task('task-1', 'one', 0),
        _task('task-2', 'two', 0),
        text,
        _task('task-3', 'three', 0),
      ];
      expect(callPlace(entries, item(BackgroundKind.task, 'task-1')), (
        entry: 1,
        target: 'agent:task-1',
      ));
      expect(callPlace(entries, item(BackgroundKind.task, 'task-2')), (
        entry: 1,
        target: 'agent:task-2',
      ));
      expect(callPlace(entries, item(BackgroundKind.task, 'task-3')), (
        entry: 4,
        target: 'agent:task-3',
      ));
      expect(callPlace(entries, item(BackgroundKind.task, 'gone')), isNull);
    });

    test("a call inside a subagent's work is in the subagent's entry, by its "
        'own box', () {
      final outer = SubagentEntry(
        't1',
        Subagent(
          'claude-1',
          entries: [monitorCall('m1', 'c1'), _task('task-1', 'inner', 0)],
        ),
      );
      expect(callPlace([text, outer], item(BackgroundKind.monitor, 'm1')), (
        entry: 1,
        target: 'call:c1',
      ));
      expect(callPlace([text, outer], item(BackgroundKind.task, 'task-1')), (
        entry: 1,
        target: 'agent:task-1',
      ));
    });

    test("a task's subagent is found at any depth, none for a monitor", () {
      final entries = [
        SubagentEntry(
          't1',
          Subagent('a', startedAt: 10, entries: [_task('g', 'inner', 12)]),
        ),
        _task('t', 'Fix the tokenizer', 13),
      ];
      expect(itemSubagent(entries, item(BackgroundKind.task, 'g'))?.id, 'g');
      expect(itemSubagent(entries, item(BackgroundKind.task, 't'))?.id, 't');
      expect(itemSubagent(entries, item(BackgroundKind.task, 'x')), isNull);
      expect(itemSubagent(entries, item(BackgroundKind.monitor, 'a')), isNull);
    });
  });

  group('CTUI-36 tester: item identity and ordering', () {
    test('kept ended ids are scoped to the owning session', () {
      final agents = [
        for (final key in [1, 2])
          _agent(
            key,
            endedMonitors: [
              _ended(
                _running('m1', 'owner $key', 0),
                const MonitorStopped(),
                5,
              ),
            ],
          ),
      ];
      for (final key in [1, 2]) {
        final items = backgroundItems(agents, keep: (key: key, id: 'm1'));
        expect(items, hasLength(1));
        expect(items.single.key, key);
        expect(items.single.name, 'owner $key');
      }
      expect(backgroundItems(agents), isEmpty);
    });

    test('a thousand same-time monitors retain numeric id order', () {
      final monitors = [
        for (var i = 1000; i > 0; i--) _running('m$i', 'watch $i', 10),
      ];
      final items = backgroundItems([_agent(1, monitors: monitors)]);
      expect(
        [for (final item in items) item.id],
        [for (var i = 1; i <= 1000; i++) 'm$i'],
      );
      expect(monitors.first.info.id, 'm1000');
    });
  });
}
