import 'dart:async';

import 'package:chord/ui/app/terminal.dart';
import 'package:chord/ui/prompt/state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  group('tester: mention result publication callback ownership', () {
    test(
      'a listener editing the query during publication retires the old awaited choice',
      () {
        fakeAsync((async) {
          final first = Completer<List<String>?>(),
              second = Completer<List<String>?>();
          final choices = <MentionChoice>[];
          final c = MentionCompletions(
            cwd: '.',
            onChoice: choices.add,
            walk: (_, {cancellationToken}) async => ['alpha', 'beta'],
            match: (names, query) => query.isEmpty
                ? Future.value(names)
                : query == 'a'
                ? first.future
                : second.future,
          );
          c.update('@a', 2);
          async.flushMicrotasks();
          c.setRoom(6, visible: true);
          expect(c.accept(enter: true), isTrue);
          var edited = false;
          c.addListener(() {
            if (!edited && c.finder?.pending == false) {
              edited = true;
              c.update('@b', 2);
            }
          });
          first.complete(['alpha']);
          async.flushMicrotasks();
          expect(edited, isTrue);
          expect(choices, isEmpty);
          second.complete(['beta']);
          async.flushMicrotasks();
          expect(choices, isEmpty);
          expect(c.accept(enter: false), isTrue);
          expect(choices.single.text, '@beta ');
          c.dispose();
          expect(async.pendingTimers, isEmpty);
        });
      },
    );
  });
}
