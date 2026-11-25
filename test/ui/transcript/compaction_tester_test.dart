import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/transcript/selection.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../app/code_pick_window_test.dart' show pressBounded, clickAt;
import '../app/keymap_window_test.dart' show launchWith;
import '../app/selection_window_test.dart';

const _summary = '界🙂e\u0301 summary\n\n```sh\n\$ echo safe\n```';
model.CompactionEntry _entry({String status = 'completed'}) =>
    model.CompactionEntry(
      'turn',
      model.Compaction('compact', status, summary: _summary),
    );

void main() {
  group('tester compaction summary lifecycle', () {
    test(
      'same source cache removes code on collapse and spinner transitions',
      () {
        final entries = appended([], [_entry()]);
        final cache = TranscriptSources(Object())..retain(entries);
        final done = model.Transcript(entries: entries);
        final open = cache.entryAt(done, 0, width: 80, expanded: true);
        expect(open.codeBlocks.single.text, r'$ echo safe');
        final running = replacedAt(entries, 0, _entry(status: 'in_progress'));
        cache.retain(running);
        final idle = model.Transcript(entries: running);
        final working = model.Transcript(
          entries: running,
          turn: const model.Working('turn', 0),
        );
        expect(
          cache.entryAt(idle, 0, width: 80, expanded: true).codeBlocks,
          isEmpty,
        );
        expect(
          cache.entryAt(working, 0, width: 80, expanded: true).children,
          isEmpty,
        );
        cache.retain(entries);
        final restored = cache.entryAt(done, 0, width: 80, expanded: true);
        expect(restored.codeBlocks.single.text, r'$ echo safe');
        expect(cache.entryAt(done, 0, width: 80).codeBlocks, isEmpty);
        cache.retain([]);
        expect(cache.cachedEntryCount, 0);
      },
    );

    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'copy, run and collapsed picking follow current summary $size',
        (t) async {
          final connection = selectionConnection([_entry()]);
          addTearDown(connection.close);
          final writes = <String>[];
          var executions = 0;
          await t.pumpWidget(
            TranscriptWindow(
              launch: selectionLaunch,
              connection: connection,
              copyOnSelect: false,
              copy: (text, _) {
                writes.add(text);
                return const copy.CopyResult.sent();
              },
              runShell: (_, _) {
                executions++;
                throw StateError('unexpected execution');
              },
            ),
            size: size,
          );
          await pressBounded(t, 'ctrl+x b');
          expect(t.screen, shows('No code block to pick'));
          await t.press('ctrl+o');
          final focus = t.focusManager.primaryFocus;
          await select(t, '界🙂e\u0301 summary');
          await t.press('ctrl+shift+c');
          expect(writes, ['界🙂e\u0301 summary']);
          await clickAt(t, cellOf(t, '[copy]'));
          expect(writes.last, r'$ echo safe');
          await pressBounded(t, 'ctrl+x b c');
          expect(writes.last, r'$ echo safe');
          expect(writes, hasLength(3));
          await pressBounded(t, 'ctrl+x b r');
          expect(connection.app.value.draft, 'echo safe');
          expect(connection.app.value.bash, isTrue);
          expect(executions, 0);
          expect(t.focusManager.primaryFocus, same(focus));
          await t.press('ctrl+c');
          await t.press('ctrl+o');
          expect(t.screen, isNot(shows('echo safe')));
          await pressBounded(t, 'ctrl+x b');
          expect(t.screen, shows('No code block to pick'));
          expect(writes, hasLength(3));
        },
      );

      testWidgets(
        'rebound history key and resized summary keep current geometry $size',
        (t) async {
          final connection = selectionConnection([_entry()]);
          addTearDown(connection.close);
          await t.pumpWidget(
            TranscriptWindow(
              launch: launchWith([
                {
                  'context': 'Global',
                  'bindings': {
                    'ctrl+t': 'app:toggleTranscript',
                    'ctrl+o': null,
                  },
                },
              ]),
              connection: connection,
            ),
            size: size,
          );
          expect(t.screen.text, contains('ctrl+t for history'));
          await t.press('ctrl+o');
          expect(connection.app.value.expanded, isFalse);
          await t.press('ctrl+t');
          expect(t.screen, shows('界🙂e\u0301 summary'));
          for (final resized in [
            Size.zero,
            const Size(1, 1),
            const Size(24, 12),
            size,
          ]) {
            await t.resize(resized);
          }
          expect(t.screen, shows('界🙂e\u0301 summary'));
          expect(t.screen.text, isNot(contains('for history')));
          await t.pumpWidget(const SizedBox(), size: size);
          await t.pump(const Duration(seconds: 3));
        },
      );
    }
  });
}
