import 'dart:async';

import 'package:chord/ui/app/selection.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  test('drag following restores only when no explicit scroll occurred', () {
    final drag = pressed(true);
    expect(released(drag, 'text').follow, isTrue);
    expect(released(scrolled(drag), 'text').follow, isFalse);
    expect(released(pressed(false), '').follow, isFalse);
    expect(released(drag, '').selection.kind, SelectionKind.none);
    const shown = Selection.shown();
    expect(scrolled(shown), same(shown));
    expect(copyable(shown), isTrue);
    expect(copyable(const Selection.copying()), isFalse);
  });

  for (final auto in [false, true]) {
    test(
      'sync ${auto ? 'auto' : 'explicit'} copy counts captured graphemes and note expires independently',
      () {
        fakeAsync((async) {
          final writes = <String>[];
          final copies = SelectionCopies(
            session: 1,
            copy: (text, token) {
              writes.add(text);
              return const CopyResult.sent();
            },
          );
          copies.press(true);
          expect(copies.release('e\u0301👍🏽'), isTrue);
          copies.copySelection('e\u0301👍🏽', auto: auto);
          expect(writes, ['e\u0301👍🏽']);
          expect(
            copies.selection.kind,
            auto ? SelectionKind.shown : SelectionKind.none,
          );
          expect(copies.note!.text, "sent 2 chars to the terminal's clipboard");
          async.elapse(const Duration(milliseconds: 2999));
          expect(copies.note, isNotNull);
          async.elapse(const Duration(milliseconds: 1));
          expect(copies.note, isNull);
          expect(
            copies.selection.kind,
            auto ? SelectionKind.shown : SelectionKind.none,
          );
          copies.dispose();
          expect(async.pendingTimers, isEmpty);
        });
      },
    );
  }

  test(
    'selection error is sanitized, persistent, retryable and clear removes retry',
    () {
      fakeAsync((async) {
        var calls = 0;
        final copies = SelectionCopies(
          session: 1,
          copy: (_, _) {
            if (calls++ == 0) throw 'bad\n\x1b[31mclipboard\x1b[0m\x07';
            return const CopyResult.copied();
          },
        );
        copies.release('text');
        copies.copySelection('text', auto: false);
        expect(copies.selection.kind, SelectionKind.shown);
        expect(
          copies.note!.text,
          'could not copy: bad clipboard · ctrl + c to try again',
        );
        async.elapse(const Duration(seconds: 10));
        expect(copies.note, isNotNull);
        copies.copySelection('text', auto: false);
        expect(copies.note!.text, 'copied 4 chars to clipboard');
        expect(copies.selection.kind, SelectionKind.none);
        copies.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    },
  );

  test('UTF8 limit rejects before adapter and is not a UTF16 limit', () {
    final writes = <String>[];
    final copies = SelectionCopies(
      session: 1,
      copy: (text, _) {
        writes.add(text);
        return const CopyResult.sent();
      },
    );
    copies.release('x');
    copies.copySelection('界' * (copyByteLimit ~/ 3 + 1), auto: false);
    expect(writes, isEmpty);
    expect(
      copies.note!.text,
      'could not copy: too large to copy · ctrl + c to try again',
    );
    copies.clear();
    expect(copies.note, isNull);
    copies.dispose();
  });

  test(
    'duplicate selection copy is ignored, code supersedes and cancels wrapper timeout',
    () {
      fakeAsync((async) {
        final first = Completer<CopyResult>();
        var calls = 0;
        late bool Function() cancelled;
        final copies = SelectionCopies(
          session: 1,
          copy: (text, token) {
            calls++;
            if (text == 'selection') {
              cancelled = () => token.isCancelled;
              return first.future;
            }
            return const CopyResult.failed('block failed');
          },
        );
        copies.release('selection');
        copies.copySelection('selection', auto: false);
        copies.copySelection('selection', auto: false);
        expect(calls, 1);
        copies.copyBlock('block');
        async.flushMicrotasks();
        expect(cancelled(), isTrue);
        expect(copies.selection.kind, SelectionKind.shown);
        expect(copies.note!.text, 'could not copy: block failed');
        first.complete(const CopyResult.copied());
        async.flushMicrotasks();
        expect(copies.note!.text, 'could not copy: block failed');
        async.elapse(copyNoteLifetime);
        expect(copies.note, isNull);
        expect(async.pendingTimers, isEmpty);
        copies.dispose();
      });
    },
  );

  test(
    'pending timeout cancels deferred effects and retains persistent retry',
    () {
      fakeAsync((async) {
        final result = Completer<CopyResult>();
        late bool Function() cancelled;
        var writes = 0;
        final copies = SelectionCopies(
          session: 1,
          copy: (_, token) {
            cancelled = () => token.isCancelled;
            result.future.then((_) {
              if (!token.isCancelled) writes++;
            });
            return result.future;
          },
        );
        copies.release('text');
        copies.copySelection('text', auto: true);
        async.elapse(const Duration(milliseconds: 1199));
        expect(copies.selection.kind, SelectionKind.copying);
        async.elapse(const Duration(milliseconds: 1));
        expect(cancelled(), isTrue);
        expect(
          copies.note!.text,
          'could not copy: the clipboard did not answer · ctrl + c to try again',
        );
        expect(copies.selection.kind, SelectionKind.shown);
        result.complete(const CopyResult.sent());
        async.flushMicrotasks();
        expect(writes, 0);
        expect(async.pendingTimers, isEmpty);
        copies.dispose();
      });
    },
  );

  for (final change in ['clear', 'new drag', 'session', 'dispose']) {
    test(
      '$change invalidates delayed result and promptly removes its timer',
      () {
        fakeAsync((async) {
          final result = Completer<CopyResult>();
          late bool Function() cancelled;
          final copies = SelectionCopies(
            session: 1,
            copy: (_, token) {
              cancelled = () => token.isCancelled;
              return result.future;
            },
          );
          copies.release('old');
          copies.copySelection('old', auto: false);
          switch (change) {
            case 'clear':
              copies.clear();
            case 'new drag':
              copies.press(false);
            case 'session':
              copies.replaceSession(2);
            case 'dispose':
              copies.dispose();
          }
          async.flushMicrotasks();
          expect(cancelled(), isTrue);
          expect(async.pendingTimers, isEmpty);
          result.complete(const CopyResult.sent());
          async.flushMicrotasks();
          expect(copies.note, isNull);
          copies.dispose();
        });
      },
    );
  }

  test('sync reentrant adapter cannot publish into a newer selection', () {
    late SelectionCopies copies;
    copies = SelectionCopies(
      session: 1,
      copy: (_, _) {
        copies.press(false);
        return const CopyResult.sent();
      },
    );
    copies.release('old');
    copies.copySelection('old', auto: true);
    expect(copies.selection.kind, SelectionKind.dragging);
    expect(copies.note, isNull);
    copies.dispose();
  });

  test(
    'copy-start observer supersession prevents old synchronous adapter effects',
    () {
      fakeAsync((async) {
        final writes = <String>[];
        final copies = SelectionCopies(
          session: 1,
          copy: (text, _) {
            writes.add(text);
            return const CopyResult.sent();
          },
        );
        var replace = true;
        copies.addListener(() {
          if (replace && copies.selection.kind == SelectionKind.copying) {
            replace = false;
            copies.copyBlock('new block');
          }
        });
        copies.release('old');
        copies.copySelection('old', auto: true);
        expect(writes, ['new block']);
        expect(copies.note!.chars, 9);
        copies.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    },
  );

  test('old note expiry cannot erase a newer code note or a new highlight', () {
    fakeAsync((async) {
      final copies = SelectionCopies(
        session: 1,
        copy: (_, _) => const CopyResult.sent(),
      );
      copies.copyBlock('first');
      final firstId = copies.note!.id;
      async.elapse(const Duration(seconds: 2));
      copies.copyBlock('second');
      expect(copies.note!.id, greaterThan(firstId));
      copies.release('new highlight');
      async.elapse(const Duration(seconds: 1));
      expect(copies.note!.chars, 6);
      expect(copies.selection.kind, SelectionKind.shown);
      copies.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });
}
