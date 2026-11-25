import 'dart:async';
import 'dart:convert';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
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
