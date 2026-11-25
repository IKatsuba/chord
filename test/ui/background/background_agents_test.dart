// The background's agent items: their states, parents, summary phrases,
// call places and details, as the original's
// tests/ui/background/background_test.ts has them for agents.
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/background/background.dart';
import 'package:test/test.dart';

Entry _task(String id, String name, num startedAt) => SubagentEntry(
  't1',
  Subagent(
    id,
    title: name,
    startedAt: startedAt,
    task: TaskInfo(name: name, runtime: 'fake', model: 'Fake Small'),
    callId: 'call-$id',
  ),
);

/// A subagent entry as Claude's adapter announces one, open to a cancel;
/// [without] leaves out the description or the cancel it offers.
Entry _claude(
  String id,
  num startedAt, {
  SubagentState state = SubagentState.running,
  num? endedAt,
  ({num? since})? waiting,
  List<Entry> entries = const [],
  Set<String> without = const {},
}) => SubagentEntry(
  't1',
  Subagent(
    id,
    title: '$id (Explore)',
    description: without.contains('description') ? null : 'Find $id',
    state: state,
    startedAt: startedAt,
    endedAt: endedAt,
    waiting: waiting,
    entries: entries,
    cancellable: !without.contains('cancellable'),
    offeredCancel: !without.contains('offeredCancel'),
  ),
);

BackgroundAgent _agent(
  int key, {
  ItemOwner? owner,
  num? since = 0,
  List<Entry> entries = const [],
  TurnState turn = const Idle(),
  List<ElicitationWait> asking = const [],
  Set<String> stopping = const {},
}) => BackgroundAgent(
  key: key,
  owner: owner,
  since: since,
  transcript: Transcript(entries: entries, turn: turn, asking: asking),
  stopping: stopping,
);

List<String> _brief(List<BackgroundItem> items) => [
  for (final item in items)
    '${item.kind.name} ${item.name} ${item.key} ${item.status.group.name}',
];

BackgroundItem _item(
  BackgroundKind kind,
  ItemStatus status, {
  String id = 'x',
  String? parent,
  int? parentAt,
}) => BackgroundItem(
  kind: kind,
  id: id,
  key: 1,
  name: 'x',
  startedAt: 0,
  status: status,
  parent: parent,
  parentAt: parentAt,
);

const _runningStatus = ItemRunning();
const _askingStatus = ItemAsking(AskingOn.permission, 0);
const _failedStatus = ItemEnded(BackgroundGroup.failed, 0);
const _doneStatus = ItemEnded(BackgroundGroup.done, 0);
const _stoppedStatus = ItemEnded(BackgroundGroup.stopped, 0);
const _stoppingStatus = ItemRunning(stopping: true);

List<String> _texts(List<SummaryGroup> groups) => [
  for (final group in groups) group.text,
];

void main() {
  testerStoppingProjection();
  group('agent items', () {
    test('every subagent its agent announced is an agent item, named by its '
        'short task; one that offered no cancel stops nothing (Q135)', () {
      final items = backgroundItems([
        _agent(
          1,
          entries: [
            _claude(
              'a',
              10,
              entries: [
                _claude('g', 12, without: {'description'}),
              ],
            ),
            // Codex's draft form, and a replayed one, offer none: an item
            // still, that offers no stop (CHD-487).
            _claude('b', 11, without: {'cancellable', 'offeredCancel'}),
            _task('t', 'Fix the tokenizer', 13),
            // Lost its cancel since: still an item, with no stop.
            _claude('l', 14, without: {'cancellable'}),
          ],
        ),
      ]);
      // A task's stop is none: the original's undefined is Dart's false.
      expect(
        [for (final i in items) (i.kind, i.name, i.stoppable)],
        [
          (BackgroundKind.agent, 'Find a', true),
          (BackgroundKind.agent, 'Find b', false),
          (BackgroundKind.agent, 'g (Explore)', true),
          (BackgroundKind.task, 'Fix the tokenizer', false),
          (BackgroundKind.agent, 'Find l', false),
        ],
      );
      // One from before its session came up is its past.
      expect(
        backgroundItems([
          _agent(1, since: 11, entries: [_claude('a', 10)]),
        ]),
        isEmpty,
      );
    });

    test("an agent item stands as its subagent does, by CHD-2's table", () {
      ItemStatus? status({
        SubagentState state = SubagentState.running,
        num? endedAt,
        ({num? since})? waiting,
        Set<String> stopping = const {},
      }) => backgroundItems([
        _agent(
          1,
          entries: [
            _claude('a', 10, state: state, endedAt: endedAt, waiting: waiting),
          ],
          stopping: stopping,
        ),
      ]).firstOrNull?.status;

      expect(status(), const ItemRunning());
      expect(status(stopping: {'a'}), _stoppingStatus);
      expect(
        status(waiting: (since: 20)),
        const ItemAsking(AskingOn.waiting, 20),
      );
      expect(
        backgroundItems([
          _agent(
            1,
            entries: [_claude('a', 10, waiting: (since: 20))],
            asking: [
              const FormWait(
                'e',
                'Pick',
                schema: {'type': 'object', 'properties': <String, Object?>{}},
                subagentId: 'a',
                at: 22,
              ),
            ],
          ),
        ]).firstOrNull?.status,
        const ItemAsking(AskingOn.input, 22),
      );

      // Ended, however, it has left the list (CHD-479).
      for (final state in [
        SubagentState.completed,
        SubagentState.failed,
        SubagentState.disconnected,
        SubagentState.cancelled,
        SubagentState.ended,
      ]) {
        expect(status(state: state, endedAt: 30), isNull, reason: state.name);
      }

      expect(
        status(state: SubagentState.untracked, endedAt: 30),
        const ItemEnded(BackgroundGroup.untracked, 30),
      );
    });

    test('the summary line counts agents after monitors and tasks, untracked '
        'after failed', () {
      expect(
        _texts(
          summaryGroups([
            _item(BackgroundKind.agent, const ItemAsking(AskingOn.waiting, 0)),
            _item(BackgroundKind.monitor, _failedStatus),
            _item(
              BackgroundKind.agent,
              const ItemEnded(BackgroundGroup.untracked, 0),
            ),
            _item(BackgroundKind.monitor, _runningStatus),
            _item(BackgroundKind.agent, _runningStatus),
            _item(BackgroundKind.agent, _stoppingStatus),
          ]),
        ),
        [
          "● main's agent asking",
          '✗ 1 monitor failed',
          "? main's agent untracked",
          "1 monitor and main's 2 agents running",
        ],
      );
    });

    test('an agent phrase names each parent in the possessive, in the agents '
        "list's order (CHD-479)", () {
      BackgroundItem of(String parent, int parentAt) => _item(
        BackgroundKind.agent,
        _runningStatus,
        parent: parent,
        parentAt: parentAt,
      );
      expect(
        _texts(
          summaryGroups([
            of('tester', 2),
            _item(BackgroundKind.task, _runningStatus),
            of('main', 0),
            of('tester', 2),
            of('parser', 1),
            of('main', 0),
          ]),
        ),
        [
          "1 task and main's 2 agents and parser's agent and tester's 2 "
              'agents running',
        ],
      );
    });

    test('an untracked agent stays listed, as it has not ended; an ended one '
        'has left (CHD-479, Q110)', () {
      List<String> at(SubagentState state, [num? endedAt]) => _brief(
        backgroundItems([
          _agent(
            1,
            entries: [_claude('a', 10, state: state, endedAt: endedAt)],
          ),
        ]),
      );
      expect(at(SubagentState.untracked, 30), ['agent Find a 1 untracked']);
      expect(at(SubagentState.completed, 50), isEmpty);
      expect(at(SubagentState.running), ['agent Find a 1 running']);
      expect(at(SubagentState.untracked, 50), ['agent Find a 1 untracked']);
    });
  });

  test('a stopped agent reads stopping while it still asks, until its agent '
      'says it ended', () {
    ItemStatus? asked({
      TurnState turn = const Idle(),
      List<ElicitationWait> asking = const [],
      SubagentState state = SubagentState.running,
      num? endedAt,
      ({num? since})? waiting,
    }) => backgroundItems([
      _agent(
        1,
        stopping: {'a'},
        entries: [
          _claude('a', 10, state: state, endedAt: endedAt, waiting: waiting),
        ],
        turn: turn,
        asking: asking,
      ),
    ]).firstOrNull?.status;
    const form = FormWait('e', '', subagentId: 'a', at: 22);
    const permission = AwaitingPermission('t1', 5, [
      PermissionWait('p', subagentId: 'a', toolCallId: 'c', at: 21),
    ]);

    expect(asked(waiting: (since: 20)), _stoppingStatus);
    expect(asked(turn: permission), _stoppingStatus);
    expect(asked(asking: [form]), _stoppingStatus);
    // Its agent's end wins over the key: it has left (CHD-479).
    expect(asked(state: SubagentState.completed, endedAt: 30), isNull);
  });

  group('an agent item names its parent, and which items leave as they end '
      '(CHD-479)', () {
    test("an agent item's parent is the listed agent that announced it, a "
        "subagent's own too", () {
      final items = backgroundItems([
        _agent(
          1,
          entries: [
            _claude('a', 10, entries: [_claude('g', 11)]),
          ],
        ),
        _agent(
          2,
          owner: (name: 'tester', colour: 3),
          entries: [_claude('b', 12), _task('t', 'Fix the tokenizer', 13)],
        ),
      ]);
      expect(
        [for (final i in items) (i.kind, i.id, i.parent)],
        [
          (BackgroundKind.agent, 'a', 'main'),
          (BackgroundKind.agent, 'g', 'main'),
          (BackgroundKind.agent, 'b', 'tester'),
          (BackgroundKind.task, 't', null),
        ],
      );
    });

    test('every kind leaves once done, failed or stopped; running, asking and '
        'untracked stay (CHD-479, CHD-482)', () {
      ItemStatus at(BackgroundGroup group) => switch (group) {
        BackgroundGroup.running => const ItemRunning(),
        BackgroundGroup.asking => const ItemAsking(AskingOn.waiting, 1),
        _ => ItemEnded(group, 2),
      };
      const groups = [
        BackgroundGroup.running,
        BackgroundGroup.asking,
        BackgroundGroup.untracked,
        BackgroundGroup.done,
        BackgroundGroup.failed,
        BackgroundGroup.stopped,
      ];
      for (final kind in [
        BackgroundKind.agent,
        BackgroundKind.monitor,
        BackgroundKind.task,
      ]) {
        expect(
          [
            for (final group in groups)
              if (leavesList(_item(kind, at(group)))) group,
          ],
          [
            BackgroundGroup.done,
            BackgroundGroup.failed,
            BackgroundGroup.stopped,
          ],
          reason: kind.name,
        );
      }
    });
  });

  group('the block an agent item goes to', () {
    BackgroundItem item(String id) => BackgroundItem(
      kind: BackgroundKind.agent,
      id: id,
      key: 1,
      name: 'x',
      startedAt: 0,
      status: const ItemRunning(),
    );
    const text = UserEntry('t1', 'hi');

    test("its own Agent block, its own row in a group, or, inside another's "
        'work, its own box there', () {
      final entries = [
        text,
        _claude('a', 0),
        _claude('b', 0),
        text,
        _claude('c', 0, entries: [_claude('g', 1)]),
      ];
      expect(callPlace(entries, item('a')), (entry: 1, target: 'agent:a'));
      expect(callPlace(entries, item('b')), (entry: 1, target: 'agent:b'));
      expect(callPlace(entries, item('g')), (entry: 4, target: 'agent:g'));
    });
  });

  group('CHD-2 tester: agent item ownership and terminal precedence', () {
    test('nested item order and owner remain stable when an untracked item '
        'persists and recovers', () {
      const ItemOwner owner = (name: 'parser', colour: 2);
      List<BackgroundItem> listed(SubagentState state) => backgroundItems([
        _agent(1, entries: [_claude('same', 20)]),
        _agent(
          2,
          owner: owner,
          entries: [
            _claude(
              'outer',
              10,
              entries: [_claude('same', 15, state: state, endedAt: 30)],
            ),
          ],
        ),
      ]);

      expect(
        [for (final i in listed(SubagentState.untracked)) (i.key, i.id)],
        [(2, 'outer'), (2, 'same'), (1, 'same')],
      );

      final recovered = listed(SubagentState.running);
      expect(
        [for (final i in recovered) (i.key, i.id)],
        [(2, 'outer'), (2, 'same'), (1, 'same')],
      );
      expect(recovered[1].owner, owner);
      expect(recovered[1].startedAt, 15);
    });

    test('all terminal wire states beat stopping and stale permission, input '
        'and waiting state', () {
      for (final (state, group) in [
        (SubagentState.completed, BackgroundGroup.done),
        (SubagentState.failed, BackgroundGroup.failed),
        (SubagentState.cancelled, BackgroundGroup.stopped),
        (SubagentState.ended, BackgroundGroup.stopped),
        (SubagentState.untracked, BackgroundGroup.untracked),
        (SubagentState.disconnected, BackgroundGroup.failed),
      ]) {
        final items = backgroundItems([
          _agent(
            1,
            entries: [
              _claude('a', 10, state: state, endedAt: 40, waiting: (since: 20)),
            ],
            turn: const AwaitingPermission('t1', 21, [
              PermissionWait('p', subagentId: 'a', at: 21),
            ]),
            asking: const [LinkWait('e', 'm', 'u', subagentId: 'a', at: 22)],
            stopping: {'a'},
          ),
        ]);
        final item = items.firstOrNull;

        if (group == BackgroundGroup.untracked) {
          expect(
            item?.status,
            isA<ItemEnded>()
                .having((s) => s.group, 'group', group)
                .having((s) => s.endedAt, 'endedAt', 40),
            reason: state.name,
          );
          expect(
            summaryGroups([?item]).firstOrNull?.group,
            group,
            reason: state.name,
          );
        } else {
          expect(item, isNull, reason: state.name);
        }
      }
    });

    test('every group and kind survives narrow and wide summary wrapping with '
        'agent counts', () {
      final groups = summaryGroups([
        _item(BackgroundKind.agent, _askingStatus),
        _item(BackgroundKind.agent, _failedStatus),
        _item(
          BackgroundKind.agent,
          const ItemEnded(BackgroundGroup.untracked, 0),
        ),
        _item(BackgroundKind.monitor, _runningStatus),
        _item(BackgroundKind.task, _runningStatus),
        _item(BackgroundKind.agent, _runningStatus),
        _item(BackgroundKind.agent, _doneStatus),
        _item(BackgroundKind.agent, _stoppedStatus),
      ]);
      final space = RegExp(r'\s+');
      final words = 'background ${_texts(groups).join(' · ')}'.split(space);

      for (final width in [74, 114]) {
        final lines = [
          for (final line in summaryLines(groups, width))
            line.map((piece) => piece.text).join(),
        ];
        expect(lines.join(' ').trim().split(space), words, reason: '$width');
        expect(
          lines.every((line) => line.runes.length <= width),
          isTrue,
          reason: '$width',
        );
      }
    });
  });

  group('CHD-479 tester: parent identity survives nested and reused adapter '
      'ids', () {
    test('the same adapter ids in different sessions retain distinct '
        'parents', () {
      final items = backgroundItems([
        _agent(
          17,
          owner: (name: 'tester', colour: 1),
          entries: [
            _claude(
              'shared',
              10,
              entries: [
                _claude('nested', 11, entries: [_claude('leaf', 12)]),
              ],
            ),
          ],
        ),
        _agent(
          23,
          owner: (name: 'coder', colour: 2),
          entries: [
            _claude('shared', 10, entries: [_claude('nested', 11)]),
          ],
        ),
      ]);

      expect(
        [
          for (final i in items)
            if (i.key == 17) (i.id, i.parent),
        ],
        [('shared', 'tester'), ('nested', 'tester'), ('leaf', 'tester')],
      );
      expect(
        [
          for (final i in items)
            if (i.key == 23) (i.id, i.parent),
        ],
        [('shared', 'coder'), ('nested', 'coder')],
      );
      expect({for (final i in items) '${i.key}:${i.id}'}, hasLength(5));
    });

    test('an ancestor without cancel is not substituted for the listed '
        'parent', () {
      final entries = [
        _claude(
          'container',
          10,
          entries: [
            _claude('inner', 11, entries: [_claude('leaf', 12)]),
          ],
          without: {'offeredCancel', 'cancellable'},
        ),
      ];

      for (final owner in <ItemOwner?>[null, (name: 'reviewer', colour: 3)]) {
        final items = backgroundItems([
          _agent(1, owner: owner, entries: entries),
        ]);
        final parent = owner?.name ?? 'main';
        expect(
          [for (final i in items) (i.id, i.parent)],
          [('container', parent), ('inner', parent), ('leaf', parent)],
        );
      }
    });

    test('a still-untracked agent and its recovered stopping state keep the '
        'parent', () {
      List<BackgroundItem> make(SubagentState state) => backgroundItems([
        _agent(
          31,
          owner: (name: 'parser', colour: 0),
          stopping: {'same'},
          entries: [_claude('same', 10, state: state)],
        ),
      ]);
      final lost = make(SubagentState.untracked);
      final recovered = make(SubagentState.running);

      expect(lost.firstOrNull?.status.group, BackgroundGroup.untracked);
      expect(recovered.firstOrNull?.status, _stoppingStatus);

      for (final item in [...lost, ...recovered]) {
        expect(item.parent, 'parser');
        expect(item.key, 31);
        expect(item.id, 'same');
        expect(leavesList(item), isFalse);
      }
    });
  });

  group('CHD-479 tester: parent order follows the list through live state '
      'changes', () {
    test('interleaved start times cannot reorder parents, and a removed '
        'parent returns in its list position', () {
      List<BackgroundItem> list(SubagentState state) => backgroundItems([
        _agent(1, entries: [_claude('main', 40)]),
        _agent(
          2,
          owner: (name: 'parser', colour: 1),
          entries: [_claude('parser', 30, state: state)],
        ),
        _agent(
          3,
          owner: (name: 'tester', colour: 2),
          entries: [_claude('tester-1', 10), _claude('tester-2', 20)],
        ),
      ]);

      expect(
        [for (final i in list(SubagentState.running)) i.parent],
        ['tester', 'tester', 'parser', 'main'],
      );
      expect(_texts(summaryGroups(list(SubagentState.completed))), [
        "main's agent and tester's 2 agents running",
      ]);
      expect(_texts(summaryGroups(list(SubagentState.untracked))), [
        "? parser's agent untracked",
        "main's agent and tester's 2 agents running",
      ]);

      final groups = summaryGroups(list(SubagentState.running));
      const expected =
          "main's agent and parser's agent and tester's 2 agents running";

      expect(_texts(groups), [expected]);

      for (final width in [74, 114]) {
        expect(
          summaryLines(groups, width)
              .expand((line) => line)
              .map((piece) => piece.text)
              .join()
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim(),
          'background $expected',
          reason: '$width',
        );
      }
    });
  });

  group("an agent's or a task's detail (CHD-487)", () {
    test('its item stays while its detail is open, ended or not, and leaves '
        'once the detail is left (Q136)', () {
      final ended = _agent(
        1,
        entries: [
          _claude('a', 10, state: SubagentState.completed, endedAt: 20),
          _claude('b', 11, without: {'cancellable', 'offeredCancel'}),
        ],
      );

      expect(
        [
          for (final i in backgroundItems([ended])) i.id,
        ],
        ['b'],
      );
      expect(
        [
          for (final i in backgroundItems([ended], keep: (key: 1, id: 'a')))
            i.id,
        ],
        ['a', 'b'],
      );
    });

    test("its subagent is found at any depth, an agent's and a task's alike, "
        'none for a monitor', () {
      final entries = [
        _claude('a', 10, entries: [_claude('g', 12)]),
        _task('t', 'Fix the tokenizer', 13),
      ];
      BackgroundItem of(BackgroundKind kind, String id) =>
          _item(kind, _runningStatus, id: id);

      expect(itemSubagent(entries, of(BackgroundKind.agent, 'g'))?.id, 'g');
      expect(itemSubagent(entries, of(BackgroundKind.task, 't'))?.id, 't');
      expect(itemSubagent(entries, of(BackgroundKind.agent, 'x')), isNull);
      expect(itemSubagent(entries, of(BackgroundKind.monitor, 'a')), isNull);
    });
  });

  group('CHD-487 U1 tester: retained non-cancellable rows are '
      'session-local', () {
    test('keeping one ended nested agent never keeps its reused id in another '
        'session or its ancestor', () {
      final entries = [
        _claude(
          'outer',
          10,
          state: SubagentState.completed,
          endedAt: 30,
          entries: [
            _claude(
              'inner',
              11,
              state: SubagentState.disconnected,
              endedAt: 29,
              without: {'offeredCancel', 'cancellable'},
            ),
          ],
        ),
      ];
      final agents = [
        _agent(1, entries: entries),
        _agent(2, entries: entries, owner: (name: 'other', colour: 2)),
      ];

      expect(backgroundItems(agents), isEmpty);
      final inner = backgroundItems(agents, keep: (key: 2, id: 'inner'));
      expect(
        [for (final i in inner) (i.id, i.key, i.parent, i.stoppable, i.status)],
        [
          (
            'inner',
            2,
            'other',
            false,
            const ItemEnded(
              BackgroundGroup.failed,
              29,
              word: EndWord.disconnected,
            ),
          ),
        ],
      );
      final outer = backgroundItems(agents, keep: (key: 1, id: 'outer'));
      expect(
        [for (final i in outer) (i.id, i.key, i.parent, i.status.group)],
        [('outer', 1, 'main', BackgroundGroup.done)],
      );
      expect(backgroundItems(agents), isEmpty);
    });
  });
}

void testerStoppingProjection() {
  group('CTUI-83 tester: stopping projection boundaries', () {
    test(
      'nested agent marks are collected through tasks but task marks are excluded',
      () {
        const markedAgent = SubagentEntry(
          't',
          Subagent('界👩‍💻é', startedAt: 10, stopping: true),
        );
        const markedTask = SubagentEntry(
          't',
          Subagent(
            'task',
            stopping: true,
            task: TaskInfo(name: 'Task', runtime: 'fake', model: 'Small'),
            entries: [markedAgent],
          ),
        );
        expect(stoppingIn([markedTask]), {'界👩‍💻é'});
        expect(stoppingIn(const []), isEmpty);
      },
    );

    test(
      'the exact live boundary is included and stopping stays session-local',
      () {
        final entries = [_claude('shared', 10)];
        expect(
          backgroundItems([_agent(1, since: null, entries: entries)]),
          isEmpty,
        );
        final items = backgroundItems([
          _agent(1, since: 10, entries: entries, stopping: {'shared'}),
          _agent(2, since: 10, entries: entries),
        ]);
        expect(items.map((i) => (i.key, i.status)), [
          (1, const ItemRunning(stopping: true)),
          (2, const ItemRunning()),
        ]);
      },
    );
  });
}
