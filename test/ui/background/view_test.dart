// The background view's rows, window, moves, details and log steps, as the
// original's tests/ui/background/view_test.ts has them for monitors and
// tasks.
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/background/background.dart';
import 'package:chord/ui/background/view.dart';
import 'package:chord_tui/chord_tui.dart' show ScrollStep, cellWidth;
import 'package:test/test.dart';

const _now = 1000000;

BackgroundItem _monitor(
  String id,
  String name,
  ItemStatus status, {
  int key = 1,
  ItemOwner? owner,
  num startedAt = _now - 242000,
  int events = 1,
  String? command,
  int? timeoutMs,
  ({List<String> lines, int at})? lastEvent,
}) => BackgroundItem(
  kind: BackgroundKind.monitor,
  id: id,
  key: key,
  owner: owner,
  name: name,
  startedAt: startedAt,
  status: status,
  events: events,
  command: command,
  timeoutMs: timeoutMs,
  lastEvent: lastEvent,
);

BackgroundItem _task(
  String id,
  String name,
  ItemStatus status, {
  int key = 1,
  ItemOwner? owner,
  String runtime = 'fake',
  String model = 'Fake Small',
}) => BackgroundItem(
  kind: BackgroundKind.task,
  id: id,
  key: key,
  owner: owner,
  name: name,
  startedAt: _now - 32000,
  status: status,
  runtime: runtime,
  model: model,
);

const ItemOwner _parser = (name: 'parser', colour: 0);
const ItemOwner _coder = (name: 'coder', colour: 1);
const _running = ItemRunning();

/// The design's five items, `Fix the tokenizer` asking.
final _items = [
  _monitor(
    'm1',
    'CI run 4812',
    const ItemEnded(
      BackgroundGroup.failed,
      _now - 30000,
      end: MonitorExited(1),
    ),
    startedAt: _now - 30000 - 192000,
    events: 3,
  ),
  _monitor('m2', 'dev server errors', _running),
  _monitor(
    'm1',
    'parser tests',
    _running,
    key: 2,
    owner: _parser,
    startedAt: _now - 123000,
    events: 4,
  ),
  _task(
    't1',
    'Fix the tokenizer',
    const ItemAsking(AskingOn.permission, _now - 13000),
  ),
  _task(
    't2',
    'Fix the printer',
    _running,
    key: 3,
    owner: _coder,
    model: 'Fake Large',
  ),
];

String _line(List<ViewCell> line) => line.map((c) => c.text).join();

List<String> _text(List<ViewRow> rows) => [
  for (final row in rows)
    for (final line in row.lines) _line(line).trimRight(),
];

void main() {
  test('each state says its time, an end its words, as the design table '
      'has them', () {
    String say(BackgroundItem item) => stateText(item, _now).text;
    expect(_items.map(say), [
      '✗ exit code 1 after 3m 12s · 3 events',
      'running 4m 2s · 1 event',
      'running 2m 3s · 4 events',
      '● permission 13s',
      'working 32s',
    ]);
    String ended(MonitorEnd end, BackgroundGroup group) => say(
      _monitor(
        'm',
        'x',
        ItemEnded(group, _now, end: end),
        startedAt: _now - 180000,
      ),
    );
    expect(
      ended(const MonitorExited(0), BackgroundGroup.done),
      '✓ exit code 0 after 3m · 1 event',
    );
    expect(
      ended(const MonitorKilled('SIGKILL'), BackgroundGroup.failed),
      '✗ killed by SIGKILL after 3m · 1 event',
    );
    expect(
      ended(const MonitorTimedOut(600000), BackgroundGroup.stopped),
      '■ timed out after 3m · 1 event',
    );
    expect(
      ended(const MonitorFlooded(FloodBy.lines), BackgroundGroup.failed),
      '✗ flooded after 3m · 1 event',
    );
    expect(
      ended(const MonitorStopped(), BackgroundGroup.stopped),
      '■ stopped after 3m · 1 event',
    );
    expect(
      say(_task('t', 'x', const ItemAsking(AskingOn.input, _now - 13000))),
      '● input 13s',
    );
    // A task's end in its own words.
    final at = _now;
    expect(
      [
        for (final group in const [
          BackgroundGroup.done,
          BackgroundGroup.failed,
          BackgroundGroup.stopped,
        ])
          say(_task('t', 'x', ItemEnded(group, at))),
      ],
      ['✓ reported after 32s', '✗ failed after 32s', '■ stopped after 32s'],
    );
  });

  test('a row is name, kind, state and owner in columns two cells apart, the '
      '❯ on the focused one', () {
    expect(_text(viewRows(_items, width: 116, focus: (key: 1, id: 't1'), now: _now)), [
      '  CI run 4812        monitor · m1              ✗ exit code 1 after 3m 12s · 3 events  main',
      '  dev server errors  monitor · m2              running 4m 2s · 1 event                main',
      '  parser tests       monitor · m1              running 2m 3s · 4 events               parser',
      '❯ Fix the tokenizer  task · fake · Fake Small  ● permission 13s                       main',
      '  Fix the printer    task · fake · Fake Large  working 32s                            coder',
    ]);
  });

  test("narrower, nothing gives way: a task's kind wraps in its column after "
      'a ` · `, then a state in its own, and the row grows a line', () {
    List<String> at(int width) =>
        _text(viewRows(_items, width: width, focus: null, now: _now));
    expect(at(85), [
      '❯ CI run 4812        monitor · m1       ✗ exit code 1 after 3m 12s · 3 events  main',
      '  dev server errors  monitor · m2       running 4m 2s · 1 event                main',
      '  parser tests       monitor · m1       running 2m 3s · 4 events               parser',
      '  Fix the tokenizer  task · fake ·      ● permission 13s                       main',
      '                     Fake Small',
      '  Fix the printer    task · fake ·      working 32s                            coder',
      '                     Fake Large',
    ]);
    expect(at(76), [
      '❯ CI run 4812        monitor · m1   ✗ exit code 1 after 3m 12s ·      main',
      '                                    3 events',
      '  dev server errors  monitor · m2   running 4m 2s · 1 event           main',
      '  parser tests       monitor · m1   running 2m 3s · 4 events          parser',
      '  Fix the tokenizer  task · fake ·  ● permission 13s                  main',
      '                     Fake Small',
      '  Fix the printer    task · fake ·  working 32s                       coder',
      '                     Fake Large',
    ]);
    expect(at(60).take(3), [
      '❯ CI run 4812        monitor · m1   ✗ exit code 1     main',
      '                                    after 3m 12s ·',
      '                                    3 events',
    ]);
    expect(at(46).take(3), [
      '❯ CI run 4812        monitor · m1',
      '    ✗ exit code 1 after 3m 12s · 3 events',
      '    main',
    ]);
  });

  test('narrower still, each item takes two lines or more: its name and '
      'kind, then its state and owner two cells further in', () {
    List<String> at(int width) => _text(
      viewRows(_items.sublist(2, 4), width: width, focus: null, now: _now),
    );
    expect(at(46), [
      '❯ parser tests       monitor · m1',
      '    running 2m 3s · 4 events  parser',
      '  Fix the tokenizer  task · fake · Fake Small',
      '    ● permission 13s  main',
    ]);
    expect(at(40), [
      '❯ parser tests',
      '    monitor · m1',
      '    running 2m 3s · 4 events  parser',
      '  Fix the tokenizer',
      '    task · fake · Fake Small',
      '    ● permission 13s  main',
    ]);
    final narrow = at(24);
    expect(narrow, [
      '❯ parser tests',
      '    monitor · m1',
      '    running 2m 3s · 4',
      '    events',
      '    parser',
      '  Fix the tokenizer',
      '    task · fake ·',
      '    Fake Small',
      '    ● permission 13s',
      '    main',
    ]);
    expect(narrow.every((line) => cellWidth(line) <= 24), isTrue);
  });

  test('a name past 24 cells wraps two cells short of its column, the rest '
      'two cells in, the other columns on its first line', () {
    final long = _monitor('m9', 'Run the parser suite in watch mode', _running);
    expect(_text(viewRows([long, _items[1]], width: 116, focus: null, now: _now)), [
      '❯ Run the parser suite      monitor · m9  running 4m 2s · 1 event  main',
      '    in watch mode',
      '  dev server errors         monitor · m2  running 4m 2s · 1 event  main',
    ]);
  });

  test('↑ ↓ move the ❯ by rows, stopping at the first and last, and it '
      'follows its item', () {
    ItemRef? move(List<BackgroundItem> items, ItemRef? focus, int by) =>
        moveView(
          items,
          focus == null ? null : (focus: focus, top: null, laid: null),
          by,
          width: 116,
          height: 40,
          now: _now,
        )?.focus;
    expect(move(_items, null, 1), (key: 1, id: 'm2'));
    expect(move(_items, null, -1), (key: 1, id: 'm1'));
    expect(move(_items, (key: 3, id: 't2'), 1), (key: 3, id: 't2'));
    // m1 of agent 2 is not m1 of agent 1.
    expect(move(_items, (key: 2, id: 'm1'), 1), (key: 1, id: 't1'));
    // An item gone leaves the ❯ on the first.
    expect(move(_items, (key: 9, id: 'x'), 1), (key: 1, id: 'm2'));
    expect(move(const [], null, 1), isNull);
  });

  test('more rows than fit scroll to keep the ❯ in sight', () {
    final many = [
      for (var i = 1; i <= 30; i++) _monitor('m$i', 'build $i', _running),
    ];
    ({List<String> names, int above, int below}) window(int focus, int height) {
      final shown = viewWindow(
        viewRows(many, width: 76, focus: (key: 1, id: 'm$focus'), now: _now),
        height,
      );
      return (
        names: [for (final row in shown.rows) row.item.name],
        above: shown.above,
        below: shown.below,
      );
    }

    final top = window(1, 20);
    expect(top.names, [for (var i = 1; i <= 20; i++) 'build $i']);
    expect([top.above, top.below], [0, 10]);
    final scrolled = window(25, 20);
    expect(scrolled.names.last, 'build 25');
    expect(scrolled.names, hasLength(20));
    expect(scrolled.above + scrolled.names.length + scrolled.below, 30);
    final end = window(30, 20);
    expect(end.names, [for (var i = 11; i <= 30; i++) 'build $i']);
    expect([end.above, end.below], [10, 0]);
    expect(window(1, 40).above + window(1, 40).below, 0);
  });

  test('a stop that could not be sent says its error whole', () {
    expect(
      stopRefused(StateError('Session not found\nat line 2')),
      'could not stop: Session not found\nat line 2',
    );
    expect(stopRefused('closed'), 'could not stop: closed');
  });

  test("the gutter says what is out of sight, as the pickers' edges do", () {
    final many = [
      for (var i = 1; i <= 10; i++) _monitor('m$i', 'build $i', _running),
    ];
    List<String> marked(int focus) => [
      for (final line in edgeMarked(
        viewWindow(
          viewRows(many, width: 116, focus: (key: 1, id: 'm$focus'), now: _now),
          4,
        ),
      ))
        _line(line.cells),
    ];
    expect(
      [for (final l in marked(1)) l.substring(0, 2)],
      ['❯ ', '  ', '  ', '↓ '],
    );
    expect(
      [for (final l in marked(6)) l.substring(0, 2)],
      ['↑ ', '  ', '  ', '❯ '],
    );
    expect(
      marked(6).first.substring(2),
      marked(1)[1].substring(2).replaceFirst('2', '3').replaceFirst('m2', 'm3'),
    );
  });

  group('a row taller than the frame scrolls by line inside it', () {
    final tall = _task('t1', ('word ' * 120).trim(), _running);
    final short = _task('t2', 'Watch the build', _running);
    final items = [short, tall, _task('t3', 'Lint', _running)];
    const width = 76, height = 6;
    final laid = laidAt(width, height);
    List<String> shown(ViewAt at) => [
      for (final line in edgeMarked(
        viewWindow(
          viewRows(items, width: width, focus: at.focus, now: _now),
          height,
          at,
          laid,
        ),
      ))
        _line(line.cells),
    ];
    final lines = viewRows(
      items,
      width: width,
      focus: null,
      now: _now,
    )[1].lines.length;
    const ItemRef t1 = (key: 1, id: 't1');
    ViewAt? move(ViewAt at, int by) =>
        moveView(items, at, by, width: width, height: height, now: _now);

    test('reached with ↓, it shows from its first line, the ❯ on it; each ↓ '
        'scrolls a line, then the next row comes whole into sight', () {
      var at = move((focus: (key: 1, id: 't2'), top: null, laid: null), 1)!;
      expect(at, (focus: t1, top: 1, laid: laid));
      expect(shown(at).first, startsWith('❯ word'));
      expect(shown(at).last, startsWith('↓ '));
      for (var step = 1; step <= lines - 6; step++) {
        at = move(at, 1)!;
        expect(at.top, 1 + step);
        expect(shown(at), hasLength(6));
      }
      expect(shown(at).first, startsWith('↑ '));
      expect(shown(at).any((line) => line.contains('❯')), isFalse);
      final off = move(at, 1)!;
      expect(off, (focus: (key: 1, id: 't3'), top: lines + 2 - 6, laid: laid));
      expect(shown(off), hasLength(6));
      expect(shown(off).first, startsWith('↑ '));
      expect(shown(off).last, startsWith('❯ Lint'));
    });

    test('reached with ↑, it shows from its last line, and each ↑ scrolls a '
        'line up, then the row above', () {
      var at = move((focus: (key: 1, id: 't3'), top: null, laid: null), -1)!;
      expect(at, (focus: t1, top: lines + 1 - 6, laid: laid));
      expect(shown(at).first, startsWith('↑ '));
      expect(shown(at).last, startsWith('↓ '));
      while (at.top! > 1) {
        at = move(at, -1)!;
        expect(at.focus, t1);
      }
      expect(shown(at).first, startsWith('❯ word'));
      final off = move(at, -1)!;
      expect(off, (focus: (key: 1, id: 't2'), top: 0, laid: laid));
      expect(shown(off).first, startsWith('❯ Watch the build'));
      expect(shown(off), hasLength(6));
    });

    test('at another size, or with no line kept, a tall row shows from its '
        'first line again', () {
      final ViewAt scrolled = (focus: t1, top: 5, laid: laid);
      expect(shown(scrolled).first, startsWith('↑ '));
      expect(
        shown((focus: t1, top: 5, laid: laidAt(70, 6))).first,
        startsWith('❯ word'),
      );
      expect(
        shown((focus: t1, top: null, laid: null)).first,
        startsWith('❯ word'),
      );
    });

    test('rows that all fit are moved over whole, nothing scrolled', () {
      expect(
        moveView(
          items,
          (focus: (key: 1, id: 't2'), top: null, laid: null),
          1,
          width: width,
          height: 40,
          now: _now,
        ),
        (focus: t1, top: 0, laid: laidAt(76, 40)),
      );
    });
  });

  test("the frame's hint, or an error in its place, wraps after a ` · ` and "
      'at its spaces, never cut', () {
    const keys = 'Enter to go to its call · x to stop · Esc to close';
    expect(hintLines(keys, 112), [keys]);
    expect(hintLines(keys, 42), [
      'Enter to go to its call · x to stop ·',
      'Esc to close',
    ]);
    final error = stopRefused(
      'the adapter refused the stop because the task had already\nhanded its '
      'result back',
    );
    final lines = hintLines(error, 30);
    expect(lines.every((line) => line.length <= 30), isTrue);
    expect(lines.join(' '), error.replaceAll('\n', ' '));
    expect(
      hintLines(
        'could not stop: Broken pipe\nwhile writing session/cancel to the '
        'agent process\r\nat\ttransport.write (stdio.ts:211)',
        42,
      ),
      [
        'could not stop: Broken pipe',
        'while writing session/cancel to the agent',
        'process',
        'at transport.write (stdio.ts:211)',
      ],
    );
  });

  group('the ❯ once its row leaves', () {
    final [a, b, c] = [
      for (final id in ['a', 'b', 'c']) _monitor(id, id, _running),
    ];
    ItemRef ref(BackgroundItem item) => (key: item.key, id: item.id);

    test('goes to the row that took its place, or the one above when it was '
        'the last', () {
      expect(focusAfter([a, b, c], [a, c], ref(b)), ref(c));
      expect(focusAfter([a, b, c], [a, b], ref(c)), ref(b));
      expect(focusAfter([a, b, c], [b, c], ref(a)), ref(b));
      expect(focusAfter([a, b, c], [c], ref(b)), ref(c));
    });

    test('stays where it is while its row is listed, and names none with no '
        'row left', () {
      expect(focusAfter([a, b, c], [b, c], ref(b)), isNull);
      expect(focusAfter([a, b], const [], ref(a)), isNull);
      expect(focusAfter([a, b], [b], null), isNull);
    });
  });

  group("a monitor row's kind names its id", () {
    const name = '30-min heartbeat while the owner is away';
    const ended = ItemEnded(
      BackgroundGroup.stopped,
      _now - 7200000,
      end: MonitorTimedOut(3600000),
    );
    final items = [
      for (final id in ['m22', 'm23', 'm24'])
        _monitor(id, name, ended, startedAt: _now - 10800000),
      _monitor('m25', name, _running, startedAt: _now - 2812000),
    ];
    List<List<String>> text(int width) => [
      for (final row in viewRows(
        items,
        width: width,
        focus: (key: 1, id: 'm25'),
        now: _now,
      ))
        [for (final line in row.lines) _line(line).trimRight()],
    ];

    test('at 120 columns it fits on the first line beside the name', () {
      expect(text(116).last, [
        '❯ 30-min heartbeat while    monitor · m25  running 46m 52s · 1 event       main',
        '    the owner is away',
      ]);
    });

    test('at 80 columns it wraps after the ·, onto the line the name takes '
        'already', () {
      expect(text(76), [
        for (final id in ['m22', 'm23', 'm24', 'm25'])
          [
            id == 'm25'
                ? '❯ 30-min heartbeat while    monitor ·   running 46m 52s · 1 event       main'
                : '  30-min heartbeat while    monitor ·   ■ timed out after 1h · 1 event  main',
            '    the owner is away       $id',
          ],
      ]);
    });
  });

  group("a monitor's detail lines", () {
    List<String> text(BackgroundItem item, [int width = 76]) => [
      for (final line in detailLines(item, width: width, now: _now))
        _line(line).trimRight(),
    ];
    final errors = _monitor(
      'm2',
      'dev server errors',
      _running,
      command: 'npm run dev 2>&1 | grep --line-buffered ERROR',
      timeoutMs: 3600000,
      events: 2,
      lastEvent: (
        lines: ['ERROR [router] POST /login 500', '    at validate'],
        at: _now - 12000,
      ),
    );

    test('a running one: its name, its facts, its command, its last batch '
        'with how long ago', () {
      expect(text(errors), [
        'dev server errors',
        'running 4m 2s · 2 events · started 4m ago · timeout 1h · main',
        r'$ npm run dev 2>&1 | grep --line-buffered ERROR',
        '← ERROR [router] POST /login 500',
        '      at validate · 12s ago',
      ]);
    });

    test('narrow, the facts wrap after a ·, the command and batch two cells '
        'in', () {
      expect(text(errors, 30), [
        'dev server errors',
        'running 4m 2s · 2 events ·',
        'started 4m ago · timeout 1h ·',
        'main',
        r'$ npm run dev 2>&1 | grep',
        '  --line-buffered ERROR',
        '← ERROR [router] POST /login',
        '  500',
        '      at validate · 12s ago',
      ]);
    });

    test("a word that ends at the width leaves the space it broke at off the "
        "next line, a batch line's own indent kept", () {
      expect(
        text(
          _monitor(
            'm2',
            'x',
            _running,
            command: 'abcdefghijklmn opq',
            lastEvent: (lines: ['  abcdefghijkl mn'], at: _now),
          ),
          16,
        ).reversed.take(4).toList().reversed,
        [r'$ abcdefghijklmn', '  opq', '←   abcdefghijkl', '  mn · 0s ago'],
      );
    });

    test(
      'with no batch yet it says so; ended, its end sentence comes last',
      () {
        expect(
          text(
            _monitor(
              'm1',
              'CI run 4812',
              const ItemEnded(
                BackgroundGroup.failed,
                _now - 30000,
                end: MonitorExited(1),
              ),
              command: 'sleep 600',
              events: 0,
            ),
          ),
          [
            'CI run 4812',
            '✗ exit code 1 after 3m 32s · no events · started 4m ago · main',
            r'$ sleep 600',
            '← no events yet',
            'Exited with code 1 after 3m 32s.',
          ],
        );
      },
    );

    test('no line is wider than its width, every part kept in its role', () {
      for (final name in [
        'a-child-with-a-very-long-name-indeed',
        '👩‍💻-coder-👨‍👩‍👧-family-of-agents',
      ]) {
        final item = _monitor(
          'm2',
          'dev server errors',
          _running,
          command: 'npm run dev 2>&1 | grep --line-buffered ERROR',
          timeoutMs: 3600000,
          events: 2,
          owner: (name: name, colour: 2),
          lastEvent: (lines: ['ERROR one', '    at two'], at: _now - 12000),
        );
        for (var width = 3; width <= 80; width++) {
          final lines = detailLines(item, width: width, now: _now);
          expect(
            [
              for (final line in lines)
                if (cellWidth(_line(line)) > width) _line(line),
            ],
            isEmpty,
            reason: '$width',
          );
          String of(CellRole role) => [
            for (final cell in lines.expand((l) => l))
              if (cell.role == role) cell.text,
          ].join().replaceAll(RegExp(r'\s'), '');
          expect(of(CellRole.state), 'running4m2s');
          expect(of(CellRole.owner), name);
          expect(of(CellRole.kind), '·2events·started4mago·timeout1h·');
        }
      }
    });
  });

  group('↑ ↓ in a detail', () {
    const stopped = ItemEnded(
      BackgroundGroup.stopped,
      _now,
      end: MonitorStopped(),
    );
    final items = [
      _monitor('m1', 'a long description ' * 8, _running),
      _monitor('m2', 'b', _running),
      _monitor('m3', 'c', _running),
    ];
    ItemRef ref(String id) => (key: 1, id: id);
    Object? step(List<BackgroundItem> items, String id, int by) =>
        switch (stepDetail(items, ref(id), by)) {
          DetailTo(:final to) => to,
          DetailClosed() => 'closed',
          null => null,
        };

    test('they step whole items, and stop at the ends while it runs', () {
      expect(step(items, 'm1', 1), ref('m2'));
      expect(step(items, 'm2', -1), ref('m1'));
      expect(step(items, 'm1', -1), isNull);
      expect(step(items, 'm3', 1), isNull);
    });

    test("an ended one's item leaves on either: past an end to the item that "
        'takes its place, the last closing the frame', () {
      final last = [...items.take(2), _monitor('m3', 'c', stopped)];
      final first = [_monitor('m1', 'a', stopped), ...items.skip(1)];
      expect(step(last, 'm3', -1), ref('m2'));
      expect(step(last, 'm3', 1), ref('m2'));
      expect(step(first, 'm1', -1), ref('m2'));
      expect(step([_monitor('m1', 'a', stopped)], 'm1', 1), 'closed');
      expect(step([_monitor('m1', 'a', stopped)], 'm1', -1), 'closed');
      expect(
        step(
          [_task('t1', 'x', const ItemEnded(BackgroundGroup.done, _now))],
          't1',
          1,
        ),
        'closed',
      );
    });
  });

  group("a task's detail", () {
    test('its log opens at its end, following; paging up leaves it, paging '
        'back to the end or end follows again', () {
      final up = logStep(ScrollStep.pageUp, 30, 10, 30);
      expect(up, lessThan(30));
      expect(logStep(ScrollStep.pageUp, 30, 10, up.toInt()), lessThan(up));
      expect(logStep(ScrollStep.pageDown, 30, 10, up.toInt()), following);
      expect(logStep(ScrollStep.bottom, 30, 10, 0), following);
      expect(logStep(ScrollStep.top, 30, 10, 30), 0);
      // A log that fits follows whatever the key.
      expect(logStep(ScrollStep.pageUp, 5, 10, 5), following);
      // In a room of one row, it still pages away from its end.
      expect(logStep(ScrollStep.pageUp, 30, 1, 29), lessThan(29));
    });

    const subagent = Subagent('t');
    List<String> plain(List<List<ViewCell>> lines) => [
      for (final line in lines) _line(line),
    ];

    test('its pinned lines: the name, then its state, tool uses, kind and '
        'owner', () {
      expect(
        plain(
          workHead(
            _task('t', 'Fix the tokenizer', _running, owner: _coder),
            subagent,
            width: 116,
            now: _now,
          ),
        ),
        [
          'Fix the tokenizer',
          'working 32s · 0 tool uses · task · fake · Fake Small · coder',
        ],
      );
      expect(
        workHead(
          _task('t', 'Fix the tokenizer', _running),
          subagent,
          width: 20,
          now: _now,
        ).every((line) => cellWidth(_line(line)) <= 20),
        isTrue,
      );
    });

    test("its pinned name takes one line, cut at its end with … when longer, "
        'saying whether it was', () {
      expect(pinnedName(_task('t', 'Run the test suite', _running), 40), (
        text: 'Run the test suite',
        cut: false,
      ));
      final long = pinnedName(
        _task(
          't',
          'Find where chord hands each session/update to its listeners',
          _running,
        ),
        30,
      );
      expect(long.cut, isTrue);
      expect(long.text, endsWith('…'));
      expect(cellWidth(long.text), 30);
    });

    test("in a short room the state line takes one line, cut with …, leaving "
        "the work's count its cells, and never passes them", () {
      final item = _task(
        't',
        'Fix the tokenizer',
        _running,
        owner: _coder,
        runtime: 'a-runtime-with-a-long-name',
        model: 'a model with a very long public name',
      );
      expect(
        workHead(item, subagent, width: 40, now: _now).length,
        greaterThan(2),
      );
      final short = workHead(
        item,
        subagent,
        width: 40,
        now: _now,
        short: true,
        reserve: 16,
      );
      expect(short, hasLength(2));
      expect(cellWidth(_line(short[1])), lessThanOrEqualTo(24));
      expect(_line(short[1]), matches(RegExp(r'^working 32s · .*…$')));

      final small = _task(
        't',
        'Fix the tokenizer',
        _running,
        owner: _coder,
        runtime: 'bun',
        model: 'fake',
      );
      final whole = _line(
        workHead(small, subagent, width: 200, now: _now, short: true)[1],
      );
      for (var width = 1; width <= cellWidth(whole) + 2; width++) {
        for (var reserve = 0; reserve < width; reserve++) {
          final line = _line(
            workHead(
              small,
              subagent,
              width: width,
              now: _now,
              short: true,
              reserve: reserve,
            )[1],
          );
          expect(cellWidth(line), lessThanOrEqualTo(width - reserve));
          expect(line == whole || line.endsWith('…'), isTrue);
        }
      }
      final state = whole.substring(0, whole.indexOf(' · '));
      expect(
        _line(
          workHead(
            small,
            subagent,
            width: cellWidth(state),
            now: _now,
            short: true,
          )[1],
        ),
        '${state.substring(0, state.length - 1)}…',
      );
    });
  });

  group('CTUI-36 tester: empty rooms and Unicode view cells', () {
    test('empty list and zero-line room have no visible rows or moves', () {
      final empty = viewWindow([], 0);
      expect(empty.rows, isEmpty);
      expect(empty.height, 0);
      expect(edgeMarked(empty), isEmpty);
      expect(moveView([], null, 1, width: 0, height: 0, now: _now), isNull);
      final rows = viewRows(_items, width: 76, focus: null, now: _now);
      expect(viewWindow(rows, 0).height, 0);
      expect(edgeMarked(viewWindow(rows, 0)), isEmpty);
      for (final step in ScrollStep.values) {
        expect(logStep(step, 0, 1, 0), following);
      }
    });

    test(
      'names and detail commands strip escapes and retain Unicode cells',
      () {
        const name = '界🙂e\u0301界🙂e\u0301';
        final item = _monitor(
          'm1',
          '\x1b[31m$name\x1b[0m',
          _running,
          command: '\x1b[1mecho $name\x1b[0m',
          lastEvent: (lines: ['  $name'], at: _now),
        );
        for (final width in [12, 26, 76, 116]) {
          final rows = viewRows([item], width: width, focus: null, now: _now);
          final names = [
            for (final line in rows.single.lines)
              for (final cell in line)
                if (cell.role == CellRole.name) cell.text,
          ].join().replaceAll(RegExp(r'\s'), '');
          expect(names, name);
          final detail = detailLines(item, width: width, now: _now);
          expect(detail.map(_line).join(), isNot(contains('\x1b')));
          expect(detail.map(_line).join(), isNot(contains('\uFFFD')));
          final text = [
            for (final line in detail)
              for (final cell in line)
                if (cell.role == CellRole.text) cell.text,
          ].join();
          expect(text.replaceAll(RegExp(r'\s'), ''), contains('echo$name'));
        }
      },
    );
  });
}
