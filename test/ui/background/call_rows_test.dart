// CTUI-85: how many rows into its entry a call's own box is drawn, read off
// the entry's selection source: the row the window draws it on, for a call
// in an open block's work; the entry's own first line where the box is
// folded away, as the original's jump falls back (layout.ts rowOf).
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/background/background.dart';
import 'package:chord/ui/transcript/selection.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../app/selection_window_test.dart'
    show selectionConnection, selectionLaunch;

Entry _monitorCall(String id, String callId) => ToolEntry(
  't1',
  ToolCall(
    callId,
    title: 'Monitor',
    status: 'completed',
    chord: ChordCall(
      tool: ChordTool.monitor,
      input: const {'description': 'dev server errors'},
      answer: {
        'id': id,
        'description': 'dev server errors',
        'timeout_ms': 1000,
      },
    ),
  ),
);

Entry _task(String id, String name) => SubagentEntry(
  't1',
  Subagent(
    id,
    title: name,
    state: SubagentState.running,
    startedAt: 0,
    task: TaskInfo(name: name, runtime: 'fake', model: 'Fake Small'),
    callId: 'call-$id',
  ),
);

/// How many rows below its gap row [entries]' only entry draws the second
/// line holding [text], in the window at [size], ctrl+o pressed.
Future<int> _drawnRow(
  WidgetTester t,
  List<Entry> entries,
  String title,
  String text,
  Size size,
) async {
  final connection = selectionConnection(entries);
  addTearDown(connection.close);
  await t.pumpWidget(
    TranscriptWindow(launch: selectionLaunch, connection: connection),
    size: size,
  );
  await t.press('ctrl+o');
  await t.pump();
  final lines = t.screen.lines;
  final top = lines.indexWhere((line) => line.contains(title)) - 1;
  final first = lines.indexWhere((line) => line.contains(text));
  final second = lines.indexWhere((line) => line.contains(text), first + 1);
  expect(second, greaterThan(first), reason: t.screen.text);
  return second - top;
}

int _rows(
  List<Entry> entries,
  CallPlace place,
  int width, {
  bool expanded = false,
}) {
  final source = TranscriptSources(Object()).entryAt(
    Transcript(entries: entries),
    place.entry,
    width: width,
    expanded: expanded,
  );
  return callRows(entries, place, source, width);
}

void main() {
  group('tester: nested call row geometry', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'a nested fold summary does not become a call box target at $size',
        (t) async {
          final entries = [
            SubagentEntry(
              't1',
              Subagent(
                'outer',
                title: 'Explore 界🙂e\u0301 parser',
                state: SubagentState.running,
                startedAt: 0,
                entries: [
                  SubagentEntry(
                    't1',
                    Subagent(
                      'inner',
                      title: 'Inspect work',
                      state: SubagentState.running,
                      startedAt: 0,
                      entries: [
                        _monitorCall('m0', 'c0'),
                        _monitorCall('m1', 'c1'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ];
          final drawn = await _drawnRow(
            t,
            entries,
            'Explore 界🙂e\u0301 parser',
            'Monitor(dev server errors)',
            size,
          );
          expect(drawn, greaterThan(1));
          expect(
            _rows(
              entries,
              (entry: 0, target: 'call:c1'),
              size.width - 2,
              expanded: true,
            ),
            1,
          );
          expect(
            _rows(entries, (entry: 0, target: 'call:c1'), size.width - 2),
            1,
          );
        },
      );
    }
  });

  final outer = [
    SubagentEntry(
      't1',
      Subagent(
        'claude-1',
        title: 'Explore the parser',
        state: SubagentState.running,
        startedAt: 0,
        entries: [_monitorCall('m0', 'c0'), _monitorCall('m1', 'c1')],
      ),
    ),
  ];
  const place = (entry: 0, target: 'call:c1');

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets("a call in an open block's work is found on its own row, at "
        '$size', (t) async {
      final drawn = await _drawnRow(
        t,
        outer,
        'Explore the parser',
        'Monitor(dev server errors)',
        size,
      );
      // At the width the window lays its entries out at.
      expect(_rows(outer, place, size.width - 2, expanded: true), drawn);
    });
  }

  test(
    "a call in a block's folded work goes to the entry's own first line",
    () {
      expect(_rows(outer, place, 118), 1);
    },
  );

  test('a lone block and a call of its own entry are past their gap', () {
    expect(
      _rows([_task('task-1', 'one')], (entry: 0, target: 'agent:task-1'), 80),
      1,
    );
    expect(
      _rows([_monitorCall('m1', 'c1')], (entry: 0, target: 'call:c1'), 80),
      1,
    );
  });
}
