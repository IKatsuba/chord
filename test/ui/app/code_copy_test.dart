import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/ui/app/selection.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  test('empty code leaves adapter, feedback and notifications untouched', () {
    fakeAsync((clock) {
      final writes = <String>[];
      final copies = SelectionCopies(
        copy: (text, _) {
          writes.add(text);
          return const CopyResult.sent();
        },
        session: Object(),
      );
      var changes = 0;
      copies.addListener(() => changes++);
      final epoch = copies.epoch;
      copies.copyBlock('');
      expect(writes, isEmpty);
      expect(copies.note, isNull);
      expect(copies.epoch, epoch);
      expect(changes, 0);
      expect(clock.pendingTimers, isEmpty);
      copies.noCodeBlock();
      final note = copies.note;
      expect(note!.text, 'No code block to pick');
      expect(changes, 1);
      copies.copyBlock('');
      expect(copies.note, same(note));
      expect(changes, 1);
      expect(writes, isEmpty);
      copies.dispose();
      expect(clock.pendingTimers, isEmpty);
    });
  });
  test('empty code preserves existing code note and its original expiry', () {
    fakeAsync((clock) {
      final writes = <String>[];
      final copies = SelectionCopies(
        copy: (text, _) {
          writes.add(text);
          return const CopyResult.sent();
        },
        session: Object(),
      );
      copies.copyBlock('prior');
      final note = copies.note;
      clock.elapse(const Duration(seconds: 2));
      copies.copyBlock('');
      expect(writes, ['prior']);
      expect(copies.note, same(note));
      clock.elapse(const Duration(seconds: 1));
      expect(copies.note, isNull);
      copies.dispose();
      expect(clock.pendingTimers, isEmpty);
    });
  });
  for (final selection in [false, true]) {
    test(
      'empty code preserves pending ${selection ? 'selection' : 'code'} copy',
      () {
        fakeAsync((clock) {
          final pending = Completer<CopyResult>();
          final writes = <String>[];
          CancellationToken? token;
          final copies = SelectionCopies(
            copy: (text, cancellation) {
              writes.add(text);
              token = cancellation;
              return pending.future;
            },
            session: Object(),
          );
          if (selection) {
            copies.press(false);
            copies.release('prior');
            copies.copySelection('prior', auto: false);
          } else {
            copies.copyBlock('prior');
          }
          final kind = copies.selection.kind;
          clock.elapse(const Duration(milliseconds: 100));
          copies.copyBlock('');
          expect(writes, ['prior']);
          expect(token!.isCancelled, isFalse);
          expect(copies.selection.kind, kind);
          expect(copies.note, isNull);
          pending.complete(const CopyResult.sent());
          clock.flushMicrotasks();
          expect(copies.note!.text, contains('sent 5 chars'));
          expect(copies.note!.block, !selection);
          copies.dispose();
          expect(clock.pendingTimers, isEmpty);
        });
      },
    );
  }
  test(
    'empty catalog note owns only its latest timer and never starts an adapter',
    () {
      fakeAsync((clock) {
        var writes = 0;
        final copies = SelectionCopies(
          copy: (_, _) {
            writes++;
            return const CopyResult.sent();
          },
          session: Object(),
        );
        copies.noCodeBlock();
        expect(copies.note!.text, 'No code block to pick');
        clock.elapse(const Duration(seconds: 2));
        copies.copyBlock('current');
        expect(writes, 1);
        clock.elapse(const Duration(seconds: 1));
        expect(copies.note!.text, contains('sent 7 chars'));
        clock.elapse(const Duration(seconds: 2));
        expect(copies.note, isNull);
        copies.noCodeBlock();
        copies.replaceSession(Object());
        expect(copies.note, isNull);
        copies.dispose();
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
}
