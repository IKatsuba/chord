import 'dart:async';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/ui/app/terminal.dart';
import 'package:chord/ui/prompt/state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  group('prompt-owned mention completion', () {
    test(
      'walk on opening, retain previous files, cancel close and reject late walk',
      () {
        fakeAsync((async) {
          final walks = <Completer<List<String>>>[],
              tokens = <CancellationToken>[];
          final choices = <MentionChoice>[];
          final c = MentionCompletions(
            cwd: '.',
            onChoice: choices.add,
            walk: (cwd, {cancellationToken}) {
              tokens.add(cancellationToken!);
              final done = Completer<List<String>>();
              walks.add(done);
              return done.future;
            },
          );
          c.update('@', 1);
          expect(walks, hasLength(1));
          expect(c.finder, isNull);
          walks.first.complete(['a', 'b']);
          async.flushMicrotasks();
          expect(c.finder!.files, ['a', 'b']);
          c.update('@ ', 2);
          expect(c.finder, isNull);
          c.update('@', 1);
          expect(walks, hasLength(2));
          expect(c.finder!.files, ['a', 'b']);
          c.dismiss();
          expect(tokens.last.isCancelled, isTrue);
          expect(c.finder, isNull);
          walks.last.complete(['late']);
          async.flushMicrotasks();
          expect(c.finder, isNull);
          c.update('@n', 2);
          expect(walks, hasLength(3));
          c.dispose();
          expect(tokens.last.isCancelled, isTrue);
          walks.last.complete(['late']);
          async.flushMicrotasks();
          expect(choices, isEmpty);
        });
      },
    );
    for (final enter in [false, true]) {
      test(
        'pending ${enter ? 'Enter' : 'Tab'} awaits current first result without blocking typing',
        () {
          fakeAsync((async) {
            final result = Completer<List<String>?>(),
                choices = <MentionChoice>[];
            final c = MentionCompletions(
              cwd: '.',
              onChoice: choices.add,
              walk: (cwd, {cancellationToken}) async => ['alpha', 'beta'],
              match: (names, query) =>
                  query.isEmpty ? Future.value(names) : result.future,
            );
            c.update('@', 1);
            async.flushMicrotasks();
            c.setRoom(6, visible: true);
            c.update('@b', 2);
            expect(c.finder!.pending, isTrue);
            expect(c.finder!.files, ['alpha', 'beta']);
            expect(c.accept(enter: enter), isTrue);
            expect(choices, isEmpty);
            result.complete(['beta']);
            async.flushMicrotasks();
            expect(choices.single.text, '@beta ');
            expect(choices.single.submit, isFalse);
            c.dispose();
          });
        },
      );
    }
    test(
      'moved pending highlight accepts retained row and navigation clamps',
      () {
        fakeAsync((async) {
          final pending = Completer<List<String>?>(),
              choices = <MentionChoice>[];
          final c = MentionCompletions(
            cwd: '.',
            onChoice: choices.add,
            walk: (cwd, {cancellationToken}) async => ['alpha', 'beta'],
            match: (names, query) =>
                query.isEmpty ? Future.value(names) : pending.future,
          );
          c.update('@', 1);
          async.flushMicrotasks();
          c.setRoom(6, visible: true);
          c.update('@z', 2);
          c.move(1);
          c.move(1);
          expect(c.finder!.highlighted, 1);
          expect(c.accept(enter: true), isTrue);
          expect(choices.single.text, '@beta ');
          pending.complete([]);
          async.flushMicrotasks();
          expect(choices, hasLength(1));
          c.dispose();
        });
      },
    );
    for (final enter in [false, true]) {
      test(
        'no result pending ${enter ? 'Enter submits' : 'Tab does nothing'}',
        () {
          fakeAsync((async) {
            final pending = Completer<List<String>?>(),
                choices = <MentionChoice>[];
            final c = MentionCompletions(
              cwd: '.',
              onChoice: choices.add,
              walk: (cwd, {cancellationToken}) async => ['alpha'],
              match: (names, query) =>
                  query.isEmpty ? Future.value(names) : pending.future,
            );
            c.update('@', 1);
            async.flushMicrotasks();
            c.setRoom(6, visible: true);
            c.update('@z', 2);
            c.accept(enter: enter);
            pending.complete([]);
            async.flushMicrotasks();
            expect(choices.length, enter ? 1 : 0);
            if (enter) {
              expect(choices.single.text, '@z');
              expect(choices.single.submit, isTrue);
            }
            expect(c.finder, isNull);
            c.dispose();
          });
        },
      );
    }
    for (final invalidation in [
      'typing',
      'cursor',
      'dismiss',
      'hidden',
      'zero',
      'candidates',
      'disabled',
      'dispose',
    ]) {
      test(
        '$invalidation invalidates awaited result and room return never replays',
        () {
          fakeAsync((async) {
            final pending = Completer<List<String>?>(),
                choices = <MentionChoice>[];
            final c = MentionCompletions(
              cwd: '.',
              onChoice: choices.add,
              recipients: ['alpha'],
              walk: (cwd, {cancellationToken}) async => ['alpha'],
              match: (names, query) =>
                  query.isEmpty ? Future.value(names) : pending.future,
            );
            c.update('@@', 2);
            async.flushMicrotasks();
            c.setRoom(6, visible: true);
            c.update('@@a', 3);
            c.accept(enter: true);
            switch (invalidation) {
              case 'typing':
                c.update('@@ab', 4);
              case 'cursor':
                c.update('@@a', 2);
              case 'dismiss':
                c.dismiss();
              case 'hidden':
                c.setRoom(6, visible: false);
              case 'zero':
                c.setRoom(0, visible: true);
              case 'candidates':
                c.replaceRecipients(['beta']);
              case 'disabled':
                c.update('@@a', 3, enabled: false);
              case 'dispose':
                c.dispose();
            }
            pending.complete(['alpha']);
            async.flushMicrotasks();
            c.setRoom(6, visible: true);
            async.flushMicrotasks();
            expect(choices, isEmpty);
            c.dispose();
          });
        },
      );
    }
    test(
      'slow file marker waits150ms, agent empty states are never selectable',
      () {
        fakeAsync((async) {
          final pending = Completer<List<String>?>();
          final c = MentionCompletions(
            cwd: '.',
            onChoice: (_) => fail('unexpected choice'),
            walk: (cwd, {cancellationToken}) async => ['alpha'],
            match: (names, query) =>
                query.isEmpty ? Future.value(names) : pending.future,
          );
          c.update('@', 1);
          async.flushMicrotasks();
          c.setRoom(6, visible: true);
          c.update('@a', 2);
          async.elapse(const Duration(milliseconds: 149));
          expect(c.finder!.searching, isFalse);
          async.elapse(const Duration(milliseconds: 1));
          expect(c.finder!.searching, isTrue);
          pending.complete(['alpha']);
          async.flushMicrotasks();
          expect(c.finder!.searching, isFalse);
          c.update('@@', 2);
          async.flushMicrotasks();
          expect(c.finder!.empty, 'No agents to mention');
          expect(c.accept(enter: true), isFalse);
          expect(c.navigable, isFalse);
          c.dispose();
        });
      },
    );
    test(
      'empty pending list is geometry intent; positive room permits wait only',
      () {
        fakeAsync((async) {
          final scores = <Completer<List<String>?>>[],
              choices = <MentionChoice>[];
          final c = MentionCompletions(
            cwd: '.',
            onChoice: choices.add,
            walk: (cwd, {cancellationToken}) async => ['alpha'],
            match: (names, query) {
              if (query.isEmpty) return Future.value(names);
              final result = Completer<List<String>?>();
              scores.add(result);
              return result.future;
            },
          );
          c.update('@none', 5);
          async.flushMicrotasks();
          scores.first.complete([]);
          async.flushMicrotasks();
          expect(c.finder, isNull);
          c.update('@a', 2);
          expect(c.finder!.files, isEmpty);
          expect(c.finder!.pending, isTrue);
          c.setRoom(6, visible: true);
          expect(c.navigable, isFalse);
          expect(c.accept(enter: true), isTrue);
          scores.last.complete(['alpha']);
          async.flushMicrotasks();
          expect(choices.single.text, '@alpha ');
          c.dispose();
        });
      },
    );

    for (final change in ['input', 'dispose', 'room']) {
      test(
        'prepublication validator $change reentrancy retires old pending choice',
        () {
          fakeAsync((async) {
            final pending = Completer<List<String>?>(),
                choices = <MentionChoice>[];
            late MentionCompletions c;
            c = MentionCompletions(
              cwd: '.',
              onChoice: choices.add,
              walk: (cwd, {cancellationToken}) async => ['alpha'],
              match: (names, q) =>
                  q.isEmpty ? Future.value(names) : pending.future,
              validatePending: () {
                expect(c.finder!.pending, isTrue);
                switch (change) {
                  case 'input':
                    c.update('@b', 2);
                  case 'dispose':
                    c.dispose();
                  case 'room':
                    c.setRoom(0, visible: false);
                }
                return true;
              },
            );
            c.update('@a', 2);
            async.flushMicrotasks();
            c.setRoom(6, visible: true);
            c.accept(enter: true);
            pending.complete(['alpha']);
            async.flushMicrotasks();
            expect(choices, isEmpty);
            c.dispose();
          });
        },
      );
    }
  });

  group('CTUI-159: SessionVar', () {
    (List<String>, SessionVar) told() {
      final written = <String>[];
      return (written, SessionVar(written.add));
    }

    test('none is told at once, and only once', () {
      fakeAsync((async) {
        final (written, tell) = told();
        tell(null, Completer<void>().future);
        tell(null, Completer<void>().future);
        async.flushMicrotasks();
        expect(written, ['']);
      });
    });

    test('an id waits for its record, then goes once', () {
      fakeAsync((async) {
        final (written, tell) = told();
        final recorded = Completer<void>();
        tell(null, recorded.future);
        tell('a', recorded.future);
        tell('a', recorded.future);
        async.flushMicrotasks();
        expect(written, ['']);
        recorded.complete();
        async.flushMicrotasks();
        expect(written, ['', 'a']);
        tell('a', recorded.future);
        async.flushMicrotasks();
        expect(written, ['', 'a']);
      });
    });

    test('a later id overtakes a write pending', () {
      fakeAsync((async) {
        final (written, tell) = told();
        final first = Completer<void>(), second = Completer<void>();
        tell('a', first.future);
        tell('b', second.future);
        second.complete();
        async.flushMicrotasks();
        first.complete();
        async.flushMicrotasks();
        expect(written, ['b']);
      });
    });

    test('none overtakes a write pending; the id wanted again goes when '
        'its record settles', () {
      fakeAsync((async) {
        final (written, tell) = told();
        final recorded = Completer<void>();
        tell('a', recorded.future);
        tell(null, recorded.future);
        expect(written, ['']);
        tell('a', recorded.future);
        recorded.complete();
        async.flushMicrotasks();
        expect(written, ['', 'a']);
        tell(null, Completer<void>().future);
        expect(written, ['', 'a', '']);
      });
    });

    test('while away a settled id is kept, not told; back, it goes', () {
      fakeAsync((async) {
        final (written, tell) = told();
        final recorded = Completer<void>();
        tell(null, recorded.future);
        tell('a', recorded.future);
        tell.away = true;
        recorded.complete();
        async.flushMicrotasks();
        expect(written, ['']);
        tell.away = false;
        expect(written, ['', 'a']);
        tell.away = true;
        tell.away = false;
        expect(written, ['', 'a']);
      });
    });

    test('while away, none is kept too; an id wanted since overtakes it', () {
      fakeAsync((async) {
        final (written, tell) = told();
        final first = Completer<void>(), second = Completer<void>();
        tell('a', first.future);
        first.complete();
        async.flushMicrotasks();
        tell.away = true;
        tell(null, first.future);
        expect(written, ['a']);
        tell('b', second.future);
        tell.away = false;
        expect(written, ['a']);
        second.complete();
        async.flushMicrotasks();
        expect(written, ['a', 'b']);
      });
    });

    test('back from away with nothing come due tells nothing', () {
      fakeAsync((async) {
        final (written, tell) = told();
        final recorded = Completer<void>();
        tell.away = true;
        tell('a', recorded.future);
        tell.away = false;
        expect(written, isEmpty);
        recorded.complete();
        async.flushMicrotasks();
        expect(written, ['a']);
      });
    });

    test('retired, a write pending and every later one is dropped', () {
      fakeAsync((async) {
        final (written, tell) = told();
        final recorded = Completer<void>();
        tell(null, recorded.future);
        tell('a', recorded.future);
        tell.retire();
        recorded.complete();
        async.flushMicrotasks();
        tell(null, recorded.future);
        tell.away = true;
        tell.away = false;
        expect(written, ['']);
      });
    });

    test('a write retired as it goes counts as untold', () {
      fakeAsync((async) {
        final written = <String>[];
        late final SessionVar tell;
        tell = SessionVar((value) {
          if (value == 'a') {
            tell.retire();
            return;
          }
          written.add(value);
        });
        final recorded = Completer<void>()..complete();
        tell('a', recorded.future);
        async.flushMicrotasks();
        expect(written, isEmpty);
      });
    });

    test('a record that fails tells nothing', () {
      fakeAsync((async) {
        final (written, tell) = told();
        tell('a', Future<void>.error(StateError('no record')));
        async.flushMicrotasks();
        expect(written, isEmpty);
      });
    });
  });
}
