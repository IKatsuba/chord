import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'code_pick_window_test.dart' show reply, clickAt;
import 'selection_window_test.dart';

void main() {
  group('tester: run insertion refusal and held context lifetimes', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'repeated draft refusal resets exact timer and disposal cancels it $size',
        (t) async {
          final c = selectionConnection([reply('```sh\n\$ ready\n```')]);
          addTearDown(c.close);
          await t.pumpWidget(
            TranscriptWindow(launch: selectionLaunch, connection: c),
            size: size,
          );
          await t.type('draft');
          final at = cellOf(t, '[run]');
          fakeAsync((async) {
            void click() {
              t.host.handleMouse(primary(MouseEventKind.press, at));
              t.host.handleMouse(primary(MouseEventKind.release, at));
            }

            click();
            final first = c.app.value.draftHeld;
            expect(first, isNotNull);
            async.elapse(const Duration(milliseconds: 2999));
            expect(c.app.value.draftHeld, same(first));
            click();
            final second = c.app.value.draftHeld;
            expect(second, isNot(same(first)));
            async.elapse(const Duration(milliseconds: 1));
            expect(c.app.value.draftHeld, same(second));
            async.elapse(const Duration(milliseconds: 2998));
            expect(c.app.value.draftHeld, same(second));
            async.elapse(const Duration(milliseconds: 1));
            expect(c.app.value.draftHeld, isNull);
            click();
            expect(c.app.value.draftHeld, isNotNull);
            t.host.dispose();
            expect(c.app.value.draftHeld, isNull);
            expect(async.pendingTimers, isEmpty);
            async.elapse(const Duration(seconds: 4));
            expect(c.app.value.draft, 'draft');
          });
        },
      );

      testWidgets(
        'refused run clears selection without copying or executing $size',
        (t) async {
          final c = selectionConnection([
            reply('select me\n\n```bash\n\$ ready\n```'),
          ]);
          addTearDown(c.close);
          final copies = <String>[];
          var executions = 0;
          await t.pumpWidget(
            TranscriptWindow(
              launch: selectionLaunch,
              connection: c,
              copyOnSelect: false,
              copy: (text, _) {
                copies.add(text);
                return const copy.CopyResult.sent();
              },
              runShell: (_, _) {
                executions++;
                throw StateError('unexpected execution');
              },
            ),
            size: size,
          );
          await t.type('draft');
          await select(t, 'select me');
          final selected = cellOf(t, 'select me');
          expect(
            t.screen.styleAt(selected.x, selected.y).bg,
            const IndexedColor(66),
          );
          await clickAt(t, cellOf(t, '[run]'));
          expect(c.app.value.draft, 'draft');
          expect(c.app.value.draftHeld, isNotNull);
          expect(
            t.screen.styleAt(selected.x, selected.y).bg,
            isNot(const IndexedColor(66)),
          );
          expect(copies, isEmpty);
          expect(executions, 0);
        },
      );
    }

    test(
      'multiple queued contexts restore in queue order despite reversed withdrawal list',
      () {
        var state = const AppState(held: ['a', 'b']);
        state = reduceApp(state, const Queued('q1', 'first'));
        state = reduceWindow(state, ContextSentAction(['a', 'b']));
        for (final (id, queued) in [('c', true), ('d', false)]) {
          state = reduceApp(state, Transcribed(ShellStartedAction(id, id)));
          state = reduceApp(state, Transcribed(ShellEndedAction(id, code: 0)));
          if (queued) {
            state = reduceApp(state, const Queued('q2', 'second'));
            state = reduceWindow(state, ContextSentAction(['c']));
          }
        }
        state = reduceApp(
          state,
          const Queued('q1', 'first', afterAnswer: true),
        );
        expect(state.queue.first.held, ['a', 'b']);
        state = reduceApp(
          state,
          const QueueWithdrawn([
            QueuedPrompt('q2', 'second'),
            QueuedPrompt('q1', 'first'),
          ]),
        );
        expect(state.held, ['a', 'b', 'c', 'd']);
        expect(state.queue, isEmpty);
        final unchanged = reduceApp(
          state,
          const QueueWithdrawn([QueuedPrompt('q1', 'first')]),
        );
        expect(unchanged, same(state));
        expect(() => state.held.clear(), throwsUnsupportedError);
      },
    );
  });
}
