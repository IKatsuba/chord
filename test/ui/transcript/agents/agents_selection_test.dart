// A subagent's title and task are the agent's words, and select, as the
// original's Agents.tsx makes them selectable; chord's counts after a group
// row's title do not. A message's words under its arrow select as the
// original's MessageBody does; the arrow and the name above them do not.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/transcript/selection.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../app/code_pick_window_test.dart' show clickAt, pressBounded;
import '../../app/selection_window_test.dart';

model.SubagentEntry _agent(
  String id,
  String title, {
  List<model.Entry> work = const [],
}) => model.SubagentEntry(
  't',
  model.Subagent(
    id,
    state: model.SubagentState.completed,
    title: title,
    prompt: 'Look for the $title.',
    entries: work,
    startedAt: 0,
    endedAt: 2000,
  ),
);

/// An update from [from], a subagent, folded as the session folds it.
model.UpdateAction _from(String from, Map<String, Object?> json) =>
    model.UpdateAction('t', acp.SessionUpdate.fromJson(json), subagentId: from);

model.UpdateAction _spawned(String id, String title) => model.UpdateAction(
  't',
  acp.SessionUpdate.fromJson({
    'sessionUpdate': 'subagent_update',
    'sessionId': id,
    'title': title,
    'prompt': 'Look for the $title.',
  }),
);

Future<List<String>> _window(
  WidgetTester t,
  Size size,
  List<model.Entry> entries,
) async {
  final connection = selectionConnection(appended([], entries));
  addTearDown(connection.close);
  final writes = <String>[];
  await t.pumpWidget(
    TranscriptWindow(
      launch: selectionLaunch,
      connection: connection,
      copyOnSelect: false,
      copy: (text, _) {
        writes.add(text);
        return const copy.CopyResult.sent();
      },
    ),
    size: size,
  );
  return writes;
}

Future<void> _drag(WidgetTester t, String from, String to) =>
    _dragAt(t, cellOf(t, from), cellOf(t, to, end: true));

Future<void> _dragAt(WidgetTester t, Offset start, Offset end) async {
  await t.mouse(primary(MouseEventKind.press, start));
  await t.mouse(primary(MouseEventKind.move, end));
  await t.mouse(primary(MouseEventKind.release, end));
  await t.press('ctrl+shift+c');
}

void main() {
  test('an open block binds nothing after work whose rows no source '
      'holds', () {
    final reply = model.AssistantEntry('t', TextRun.empty.plus('Found it.'));
    // No update puts a report in a subagent's work; were one there, its
    // rows are not held.
    const record = model.ReportEntry('t', 'status', [
      (label: 'Agent', text: 'not eligible'),
    ]);
    final entries = appended([], [
      _agent('a', 'layer', work: [reply, record]),
      _agent('b', 'drawing'),
    ]);
    final transcript = model.Transcript(entries: entries);
    final cache = TranscriptSources(Object())..retain(entries);
    final open = cache.entryAt(transcript, 0, width: 80, expanded: true);
    expect(selectionChildOrNull(open, ('agent-row', 'a', 0)), isNotNull);
    expect(selectionChildOrNull(open, ('agent-task', 'a')), isNotNull);
    expect(selectionChildOrNull(open, ('work', reply.identity)), isNotNull);
    // The report draws rows no source holds: what follows it is not bound.
    expect(selectionChildOrNull(open, ('work', record.identity)), isNull);
    expect(selectionChildOrNull(open, ('agent-row', 'b', 0)), isNull);
    expect(selectionChildOrNull(open, ('agent-task', 'b')), isNull);
    // Folded, every row is.
    final folded = cache.entryAt(transcript, 0, width: 80);
    expect(selectionChildOrNull(folded, ('agent-row', 'b', 0)), isNotNull);
  });

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('a group row copies its title and not its counts, and a '
        'message its words $size', (t) async {
      final writes = await _window(t, size, [
        const model.UserEntry('t', 'look'),
        const model.AgentMessageEntry(
          't',
          'm1',
          toSubagent: false,
          agentId: 'a',
          title: 'layer',
          text: 'The layer is in the renderer.',
        ),
        _agent('a', 'layer'),
        _agent('b', 'drawing'),
      ]);
      expect(t.screen.text, contains('├─ Agent(layer)'));
      // The tree row's title, not the message's name above it.
      final tree = cellOf(t, '├─ Agent(layer)');
      final title = Offset(tree.x + 3, tree.y);
      final closing = Offset(tree.x + 3 + 'Agent(layer)'.length - 1, tree.y);
      await _dragAt(t, title, closing);
      expect(writes, ['Agent(layer)']);
      // From the title across its counts copies the title alone.
      final row = t.screen.lines[tree.y].trimRight();
      await _dragAt(t, title, Offset(cellWidth(row) - 1, tree.y));
      expect(writes.last, 'Agent(layer)');
      await _drag(t, 'The layer is', 'renderer.');
      expect(writes.last, 'The layer is in the renderer.');
      await _drag(t, 'from', 'from');
      expect(writes, hasLength(3), reason: 'the arrow row selects nothing');
    });

    testWidgets('a lone block copies its title, and open its task and the '
        'reply in its work $size', (t) async {
      final writes = await _window(t, size, [
        const model.UserEntry('t', 'look'),
        _agent(
          'a',
          'layer',
          work: [model.AssistantEntry('t', TextRun.empty.plus('Found it.'))],
        ),
      ]);
      await _drag(t, 'Agent(layer)', 'Agent(layer)');
      expect(writes, ['Agent(layer)']);
      await t.press('ctrl+o');
      await _drag(t, 'Look for the layer.', 'Look for the layer.');
      expect(writes.last, 'Look for the layer.');
      await _drag(t, 'Agent(layer)', 'Found it.');
      expect(writes.last, 'Agent(layer)\nLook for the layer.\nFound it.');
    });

    testWidgets('a permission answered in a child\'s work holds its row: the '
        'reply after it and the next agent still select $size', (t) async {
      final writes = await _window(t, size, [
        const model.UserEntry('t', 'look'),
        _agent(
          'a',
          'layer',
          work: [
            const model.ToolEntry(
              't',
              model.ToolCall(
                'c1',
                title: 'Write notes.md',
                kind: 'edit',
                status: 'completed',
              ),
            ),
            const model.PermissionEntry('t', title: 'Write notes.md'),
            model.AssistantEntry('t', TextRun.empty.plus('Wrote the notes.')),
          ],
        ),
        _agent('b', 'drawing'),
      ]);
      await t.press('ctrl+o');
      expect(t.screen.text, contains('Wrote the notes.'));
      await _drag(t, 'Wrote the notes.', 'Wrote the notes.');
      expect(writes, ['Wrote the notes.']);
      final tree = cellOf(t, '└─ Agent(drawing)');
      final title = Offset(tree.x + 3, tree.y);
      await _dragAt(
        t,
        title,
        Offset(tree.x + 3 + 'Agent(drawing)'.length - 1, tree.y),
      );
      expect(writes.last, 'Agent(drawing)');
      await _drag(t, 'Look for the drawing.', 'Look for the drawing.');
      expect(writes.last, 'Look for the drawing.');
    });

    testWidgets('a reply in a child\'s work has its code block\'s copy, and '
        'is picked and copied $size', (t) async {
      final writes = await _window(t, size, [
        const model.UserEntry('t', 'look'),
        _agent(
          'a',
          'layer',
          work: [
            model.AssistantEntry(
              't',
              TextRun.empty.plus('Run this:\n\n```sh\nbun test\n```'),
            ),
          ],
        ),
      ]);
      await t.press('ctrl+o');
      expect(t.screen.text, contains('bun test'));
      expect(
        t.screen.lines.where((line) => line.contains('[copy]')),
        hasLength(1),
      );
      await pressBounded(t, 'ctrl+x b');
      await pressBounded(t, 'c');
      expect(writes, ['bun test']);
      await clickAt(t, cellOf(t, '[copy]'));
      expect(writes.last, 'bun test');
    });

    testWidgets('a notice and a compaction in a child\'s work hold their '
        'rows: the reply after them and the next agent still select $size', (
      t,
    ) async {
      final folded = [
        const model.PromptAction('t', 'look', 1),
        _spawned('a', 'layer'),
        _from('a', {
          'sessionUpdate': 'notice',
          'title': 'Rate limited',
          'description': 'Retrying in a moment.',
        }),
        _from('a', {
          'sessionUpdate': 'compaction_update',
          'compactionId': 'k1',
          'status': 'completed',
        }),
        _from('a', {
          'sessionUpdate': 'compaction_summary_chunk',
          'compactionId': 'k1',
          'content': {'type': 'text', 'text': 'Kept the layer notes.'},
        }),
        _from('a', {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'Wrote the notes.'},
        }),
        _spawned('b', 'drawing'),
      ].fold(model.Transcript.empty, reduceTranscript);
      final child = folded.entries
          .whereType<model.SubagentEntry>()
          .first
          .subagent
          .entries;
      expect(child.whereType<model.NoticeEntry>(), hasLength(1));
      expect(child.whereType<model.CompactionEntry>(), hasLength(1));
      final writes = await _window(t, size, folded.entries);
      await t.press('ctrl+o');
      expect(t.screen.text, contains('Kept the layer notes.'));
      await _drag(t, 'Kept the layer notes.', 'Kept the layer notes.');
      expect(writes, ['Kept the layer notes.']);
      await _drag(t, 'Wrote the notes.', 'Wrote the notes.');
      expect(writes.last, 'Wrote the notes.');
      final tree = cellOf(t, '└─ Agent(drawing)');
      await _dragAt(
        t,
        Offset(tree.x + 3, tree.y),
        Offset(tree.x + 3 + 'Agent(drawing)'.length - 1, tree.y),
      );
      expect(writes.last, 'Agent(drawing)');
    });
  }
}
