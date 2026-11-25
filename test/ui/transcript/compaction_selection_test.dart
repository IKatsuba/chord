// A compaction's summary, open under ctrl+o, is the agent's words as a
// reply's are: selectable, and its code blocks picked, copied and run; the
// line above it is furniture. The original draws it with Reply
// (Transcript.tsx CompactionRecord).
import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/transcript/selection.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../app/selection_window_test.dart';

const _summary = 'Kept the install section.\n\n```sh\nbun install\n```';

model.CompactionEntry _entry({
  String status = 'completed',
  bool unasked = false,
}) => model.CompactionEntry(
  'c',
  model.Compaction('k1', status, summary: _summary, unasked: unasked),
);

/// What a reply of the summary's words copies, selected the same way.
Future<String> _replyCopy(WidgetTester t, Size size) async {
  final connection = selectionConnection([
    model.AssistantEntry('a', TextRun.empty.plus(_summary)),
  ]);
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
  final start = cellOf(t, 'Kept the install');
  final end = cellOf(t, 'bun install', end: true);
  await t.mouse(primary(MouseEventKind.press, start));
  await t.mouse(primary(MouseEventKind.move, end));
  await t.mouse(primary(MouseEventKind.release, end));
  await t.press('ctrl+shift+c');
  return writes.single;
}

void main() {
  test('the summary is a source with its code block only while open, and '
      'the line selects nothing', () {
    final entries = appended([], [_entry()]);
    final transcript = model.Transcript(entries: entries);
    final cache = TranscriptSources(Object())..retain(entries);

    final closed = cache.entryAt(
      transcript,
      0,
      width: 80,
      copyCodeBlocks: true,
    );
    expect(closed.codeBlocks, isEmpty);
    expect(closed.children, hasLength(1));

    final open = cache.entryAt(
      transcript,
      0,
      width: 80,
      expanded: true,
      copyCodeBlocks: true,
      runCodeBlocks: true,
    );
    expect(open.codeBlocks.single.text, 'bun install');
    expect(open.children, hasLength(2));
  });

  test('one the spinner says has no source, and one outside a turn its '
      'running line alone', () {
    final running = appended([], [_entry(status: 'in_progress')]);
    final cache = TranscriptSources(Object())..retain(running);
    final spinning = cache.entryAt(
      model.Transcript(entries: running, turn: const model.Working('c', 0)),
      0,
      width: 80,
      expanded: true,
    );
    expect(spinning.children, isEmpty);
    final idle = cache.entryAt(
      model.Transcript(entries: running),
      0,
      width: 80,
      expanded: true,
    );
    // A gap, then the running line.
    expect(idle.children, hasLength(2));
    expect(idle.codeBlocks, isEmpty);
  });

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('the open summary copies as the agent wrote it, and the '
        'compacted line cannot start a selection $size', (t) async {
      final connection = selectionConnection([
        const model.UserEntry('before', 'before eligible'),
        _entry(unasked: true),
      ]);
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
      expect(
        t.screen.text,
        contains('⎿  Conversation compacted while idle (ctrl+o for history)'),
      );
      await select(t, 'Conversation compacted');
      await t.press('ctrl+shift+c');
      expect(writes, isEmpty);

      await t.press('ctrl+o');
      expect(t.screen.text, contains('     Kept the install section.'));
      final start = cellOf(t, 'Kept the install');
      final end = cellOf(t, 'bun install', end: true);
      await t.mouse(primary(MouseEventKind.press, start));
      await t.mouse(primary(MouseEventKind.move, end));
      await t.mouse(primary(MouseEventKind.release, end));
      await t.press('ctrl+shift+c');
      expect(writes, hasLength(1));
      expect(writes.single, startsWith('Kept the install section.\n'));
      expect(writes.single, endsWith('\nbun install'));
      // As a reply of the same words copies.
      expect(writes.single, await _replyCopy(t, size));
    });
  }
}
