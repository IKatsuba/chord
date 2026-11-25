import 'dart:async';

import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'selection_window_test.dart'
    show selectionConnection, selectionLaunch, select;

void main() {
  group('tester: copy ownership across overlapping operations', () {
    test(
      'three generations completed in reverse publish only latest result',
      () {
        fakeAsync((clock) {
          final results = [
            for (var i = 0; i < 3; i++) Completer<copy.CopyResult>(),
          ];
          final cancelled = <bool Function()>[];
          var calls = 0;
          final copies = copy.SelectionCopies(
            session: 'window',
            copy: (_, token) {
              cancelled.add(() => token.isCancelled);
              return results[calls++].future;
            },
          );
          copies.release('old selection');
          copies.copySelection('old selection', auto: true);
          copies.copyBlock('middle block');
          copies.press(false);
          copies.release('e\u0301👩‍💻');
          copies.copySelection('e\u0301👩‍💻', auto: false);
          expect(cancelled.map((cancelled) => cancelled()), [
            true,
            true,
            false,
          ]);
          results[2].complete(const copy.CopyResult.sent());
          clock.flushMicrotasks();
          expect(copies.note!.text, "sent 2 chars to the terminal's clipboard");
          expect(copies.selection.kind, copy.SelectionKind.none);
          results[1].complete(const copy.CopyResult.failed('obsolete block'));
          results[0].completeError(StateError('obsolete selection'));
          clock.flushMicrotasks();
          expect(copies.note!.chars, 2);
          clock.elapse(copy.copyNoteLifetime);
          expect(copies.note, isNull);
          copies.dispose();
          expect(clock.pendingTimers, isEmpty);
        });
      },
    );

    test('ordinary selection clear preserves a pending code-origin result', () {
      fakeAsync((clock) {
        final result = Completer<copy.CopyResult>();
        late bool Function() cancelled;
        final copies = copy.SelectionCopies(
          session: 1,
          copy: (_, token) {
            cancelled = () => token.isCancelled;
            return result.future;
          },
        );
        copies.copyBlock('code');
        copies.press(false);
        expect(cancelled(), isTrue);
        copies.copyBlock('current');
        copies.clear();
        expect(cancelled(), isFalse);
        result.complete(const copy.CopyResult.sent());
        clock.flushMicrotasks();
        expect(copies.note!.block, isTrue);
        expect(copies.note!.text, "sent 7 chars to the terminal's clipboard");
        expect(copies.selection.kind, copy.SelectionKind.none);
        copies.dispose();
        expect(clock.pendingTimers, isEmpty);
      });
    });

    test(
      'completion before bound cancels timeout and owns its full note lifetime',
      () {
        fakeAsync((clock) {
          final result = Completer<copy.CopyResult>();
          final copies = copy.SelectionCopies(
            session: 1,
            copy: (_, _) => result.future,
          );
          copies.release('text');
          copies.copySelection('text', auto: true);
          clock.elapse(const Duration(milliseconds: 1199));
          result.complete(const copy.CopyResult.sent());
          clock.flushMicrotasks();
          clock.elapse(const Duration(milliseconds: 1));
          expect(copies.note!.failed, isFalse);
          clock.elapse(const Duration(milliseconds: 2998));
          expect(copies.note, isNotNull);
          clock.elapse(const Duration(milliseconds: 1));
          expect(copies.note, isNull);
          expect(copies.selection.kind, copy.SelectionKind.shown);
          copies.dispose();
          expect(clock.pendingTimers, isEmpty);
        });
      },
    );

    test(
      'disposal in copy-start observer prevents adapter and timer creation',
      () {
        fakeAsync((clock) {
          var calls = 0;
          final copies = copy.SelectionCopies(
            session: 1,
            copy: (_, _) {
              calls++;
              return const copy.CopyResult.sent();
            },
          );
          copies.addListener(() {
            if (copies.selection.kind == copy.SelectionKind.copying) {
              copies.dispose();
            }
          });
          copies.release('text');
          copies.copySelection('text', auto: false);
          expect(calls, 0);
          expect(copies.note, isNull);
          expect(clock.pendingTimers, isEmpty);
        });
      },
    );

    test('separate window coordinators cannot expire or cancel each other', () {
      fakeAsync((clock) {
        final delayed = Completer<copy.CopyResult>();
        final a = copy.SelectionCopies(
          session: 'a',
          copy: (_, _) => delayed.future,
        );
        final b = copy.SelectionCopies(
          session: 'b',
          copy: (_, _) => const copy.CopyResult.sent(),
        );
        a.release('a');
        a.copySelection('a', auto: true);
        b.release('b');
        b.copySelection('b', auto: true);
        clock.elapse(copy.copyBound);
        expect(a.note!.failed, isTrue);
        expect(b.note!.failed, isFalse);
        a.replaceSession('new a');
        delayed.complete(const copy.CopyResult.sent());
        clock.flushMicrotasks();
        expect(a.note, isNull);
        expect(b.note!.chars, 1);
        clock.elapse(const Duration(milliseconds: 1800));
        expect(b.note, isNull);
        expect(b.selection.kind, copy.SelectionKind.shown);
        a.dispose();
        b.dispose();
        expect(clock.pendingTimers, isEmpty);
      });
    });

    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'explicit copy synchronizes one thousand occurrence revisions without frame $size',
        (t) async {
          final connection = selectionConnection();
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
          await select(t, 'reply');
          for (var i = 1; i <= 1000; i++) {
            final old = connection.app.value;
            connection.app.value = AppState(
              start: old.start,
              transcript: model.Transcript(
                entries: replacedAt(
                  old.transcript.entries,
                  1,
                  model.AssistantEntry(
                    'a',
                    TextRun.empty.plus(
                      'W${i.toString().padLeft(4, '0')} words',
                    ),
                  ),
                ),
              ),
            );
          }
          expect(t.host.handleKey(const KeyEvent('c', ctrl: true)), isTrue);
          expect(writes, ['W1000']);
          expect(t.exitRequested, isFalse);
          expect(connection.app.value.draft, isEmpty);
        },
      );
    }
  });
}
