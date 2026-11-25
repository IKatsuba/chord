import 'dart:async';
import 'dart:convert';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('tester: supplied input errors stay observable', () {
    test(
      'both listeners retain the error and continue until source EOF',
      () async {
        final source = StreamController<List<int>>();
        final terminal = StdioTerminal(input: source.stream);
        final text = [<String>[], <String>[]];
        final errors = [<Object>[], <Object>[]];
        final stacks = [<StackTrace>[], <StackTrace>[]];
        final ended = [Completer<void>(), Completer<void>()];
        final listeners = [
          for (var i = 0; i < 2; i++)
            terminal.input.listen(
              text[i].add,
              onError: (Object error, StackTrace stack) {
                errors[i].add(error);
                stacks[i].add(stack);
              },
              onDone: ended[i].complete,
            ),
        ];
        addTearDown(() async {
          for (final listener in listeners) {
            await listener.cancel();
          }
          await terminal.close();
          await source.close();
        });
        final failure = StateError('caller input failed');
        final stack = StackTrace.current;
        source.add(utf8.encode('before 界'));
        source.addError(failure, stack);
        source.add(utf8.encode('after 🙂e\u0301\x1b[31m'));
        await pumpEventQueue();
        for (var i = 0; i < 2; i++) {
          expect(text[i], ['before 界', 'after 🙂e\u0301\x1b[31m']);
          expect(errors[i], [same(failure)]);
          expect(stacks[i], [same(stack)]);
          expect(ended[i].isCompleted, isFalse);
        }
        await source.close();
        await Future.wait([for (final done in ended) done.future]);
      },
    );
  });
  group('tester: borrowed terminal input ownership', () {
    test(
      'last listener pauses source and resume keeps decoder across split UTF8',
      () async {
        var pauses = 0;
        var resumes = 0;
        var cancellations = 0;
        final source = StreamController<List<int>>(
          onPause: () => pauses++,
          onResume: () => resumes++,
          onCancel: () => cancellations++,
        );
        final terminal = StdioTerminal(input: source.stream);
        final first = <String>[];
        final second = <String>[];
        final a = terminal.input.listen(first.add);
        final b = terminal.input.listen(second.add);
        source.add(utf8.encode('a'));
        await Future<void>.delayed(Duration.zero);
        expect(first, ['a']);
        expect(second, ['a']);
        await a.cancel();
        expect(pauses, 0);
        // Partial scalar arrives while the final consumer is still attached.
        final bytes = utf8.encode('界');
        source.add(bytes.take(1).toList());
        await Future<void>.delayed(Duration.zero);
        await b.cancel();
        expect(pauses, 1);
        expect(cancellations, 0);
        source.add(bytes.skip(1).toList());
        final resumed = Completer<String>();
        final c = terminal.input.listen((text) => resumed.complete(text));
        expect(await resumed.future.timeout(const Duration(seconds: 1)), '界');
        expect(resumes, 1);
        expect(first, ['a']);
        expect(second, ['a']);
        await c.cancel();
        await terminal.close();
        expect(cancellations, 1);
        await source.close();
      },
    );

    test(
      'concurrent permanent closes wait for backing cancellation once',
      () async {
        final canceled = Completer<void>();
        var attempts = 0;
        final source = StreamController<List<int>>(
          onCancel: () {
            attempts++;
            return canceled.future;
          },
        );
        final terminal = StdioTerminal(input: source.stream);
        addTearDown(() async {
          if (!canceled.isCompleted) canceled.complete();
          await terminal.close();
          await source.close();
        });
        final cached = terminal.input;
        final listener = cached.listen((_) {});
        await listener.cancel();
        var completed = false;
        final first = terminal.close();
        final second = terminal.close();
        expect(second, same(first));
        unawaited(first.then((_) => completed = true));
        await Future<void>.delayed(Duration.zero);
        expect(attempts, 1);
        expect(completed, isFalse);
        expect(() => terminal.input, throwsStateError);
        expect(await cached.toList(), isEmpty);
        canceled.complete();
        await Future.wait([first, second]);
        expect(completed, isTrue);
        await source.close();
      },
    );
  });
}
