import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/permission_review.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_window_test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'crossing client reports notes and outcomes adds no text or separator $size',
      (t) async {
        final connection = selectionConnection([
          const model.UserEntry('before', 'before eligible'),
          const model.ReportEntry('report', 'status', [
            (label: 'Label:', text: 'report furniture'),
          ]),
          const model.NotedEntry('note', 'config', 'note furniture'),
          const model.CancelledEntry('cancel'),
          const model.StoppedEntry('stop', 'stopped furniture'),
          const model.ErrorEntry('error', 'error furniture'),
          const model.WarningEntry('warning', 'warning furniture'),
          const model.PermissionEntry(
            'permission',
            title: 'permission furniture',
          ),
          const model.UserEntry('after', 'after eligible'),
          // The existing below rule covers the last row during a held scroll.
          const model.ReportEntry('tail', 'status', []),
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
        await t.press('home');
        final start = cellOf(t, 'before eligible');
        await t.mouse(primary(MouseEventKind.press, start));
        await t.press('end');
        final end = cellOf(t, 'after eligible', end: true);
        await t.mouse(primary(MouseEventKind.move, end));
        await t.mouse(primary(MouseEventKind.release, end));
        await t.press('ctrl+shift+c');
        expect(writes, ['before eligible\nafter eligible']);
      },
    );

    for (final entry in <model.Entry>[
      const model.ReportEntry('report', 'status', [
        (label: 'Label:', text: 'report furniture'),
      ]),
      const model.NotedEntry('note', 'config', 'note furniture'),
      const model.NotedEntry('note', 'config', 'note furniture', failed: true),
    ]) {
      testWidgets(
        '${entry.runtimeType} client text cannot start selection $size ${entry is model.NotedEntry ? entry.failed : false}',
        (t) async {
          final connection = selectionConnection([entry]);
          addTearDown(connection.close);
          final writes = <String>[];
          await t.pumpWidget(
            TranscriptWindow(
              launch: selectionLaunch,
              connection: connection,
              copy: (text, _) {
                writes.add(text);
                return const copy.CopyResult.sent();
              },
            ),
            size: size,
          );
          await select(
            t,
            entry is model.ReportEntry ? 'report furniture' : 'note furniture',
          );
          await t.press('ctrl+shift+c');
          expect(writes, isEmpty);
          expect(connection.app.value.scroll.held, isFalse);
        },
      );
    }

    testWidgets(
      'tool headline/output/terminal/diff copy excludes review notes and signs $size',
      (t) async {
        final call = model.ToolCall(
          'tool',
          kind: 'execute',
          title: 'Bash echo',
          status: 'completed',
          review: const PermissionReview('caution', 'not copied'),
          content: [
            acp.ToolCallContent.fromJson({
              'type': 'content',
              'content': {'type': 'text', 'text': 'tool output'},
            }),
            acp.ToolCallContent.fromJson({
              'type': 'diff',
              'path': 'notes.txt',
              'oldText': 'old line\n',
              'newText': 'new line\n',
            }),
          ],
          terminals: [
            const model.Terminal(
              'term',
              output: 'terminal output',
              exited: true,
              exitCode: 1,
            ),
          ],
        );
        final connection = selectionConnection([model.ToolEntry('t', call)]);
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
        await select(t, 'Reviewed: caution');
        expect(writes, isEmpty);
        final start = cellOf(t, 'Bash(echo)');
        final end = cellOf(t, 'new line', end: true);
        await t.mouse(primary(MouseEventKind.press, start));
        await t.mouse(primary(MouseEventKind.move, end));
        await t.mouse(primary(MouseEventKind.release, end));
        await t.press('ctrl+shift+c');
        expect(writes, hasLength(1));
        expect(
          writes.single,
          startsWith(
            'Bash(echo)\ntool output\nterminal output\nUpdated notes.txt',
          ),
        );
        expect(writes.single, endsWith('old line\nnew line'));
        expect(writes.single, isNot(contains('Reviewed')));
        expect(writes.single, isNot(contains('Exit code')));
        expect(writes.single, isNot(contains('⎿')));
      },
    );

    testWidgets(
      'expanded thought and finished plan copy descriptions without titles or marks $size',
      (t) async {
        final entries = [
          acp.PlanEntry.fromJson({
            'content': 'first task',
            'priority': 'high',
            'status': 'completed',
          }),
          acp.PlanEntry.fromJson({
            'content': 'second task',
            'priority': 'medium',
            'status': 'pending',
          }),
        ];
        final connection = selectionConnection([
          model.ThoughtEntry('t', TextRun.empty.plus('thought body')),
          model.FinishedPlanEntry('p', entries),
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
        await select(t, 'Thinking…');
        await t.press('ctrl+shift+c');
        expect(writes, isEmpty);
        await t.press('ctrl+o');
        final start = cellOf(t, 'thought body'),
            end = cellOf(t, 'second task', end: true);
        await t.mouse(primary(MouseEventKind.press, start));
        await t.mouse(primary(MouseEventKind.move, end));
        await t.mouse(primary(MouseEventKind.release, end));
        await t.press('ctrl+shift+c');
        expect(writes, ['thought body\nfirst task\nsecond task']);
        expect(
          t.screen
              .styleAt(cellOf(t, 'first task').x, cellOf(t, 'first task').y)
              .isStrikethrough,
          isTrue,
        );
      },
    );
  }
}
