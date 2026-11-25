import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/platform/heap.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<void> _until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('heap fixture did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('tester CTUI-103: signal ownership and whole files', () {
    test('a thousand signals drop during a pending write; removing the '
        'listener allows only that owned write to finish', () async {
      final signals = StreamController<ProcessSignal>();
      addTearDown(signals.close);
      final pending = Completer<HeapFiles>();
      var directories = 0, writes = 0, completions = 0;
      final off = snapshotOnSignal(
        () {
          directories++;
          return 'fixture';
        },
        signals: signals.stream,
        write: (_) {
          writes++;
          return pending.future;
        },
        written: (_) => completions++,
      );
      addTearDown(off);
      for (var i = 0; i < 1000; i++) {
        signals.add(heapSignal);
      }
      await pumpEventQueue();
      expect((directories, writes, completions), (1, 1, 0));
      off();
      await pumpEventQueue();
      pending.complete((snapshot: null, stats: 'fixture.json'));
      await pumpEventQueue();
      signals.add(heapSignal);
      await pumpEventQueue();
      expect((directories, writes, completions), (1, 1, 1));
    });

    test(
      'the snapshot part is private until the stats follow; a failing '
      'snapshot removes its partial bytes and still leaves whole stats',
      () async {
        final root = Directory.systemTemp.createTempSync('heap-files-tester-');
        addTearDown(() => root.deleteSync(recursive: true));
        final at = DateTime.utc(2026, 11, 24, 1, 2, 3);
        final order = <String>[];
        final files = await writeHeapSnapshot(
          root.path,
          now: () => at,
          snapshot: (path) {
            expect(path, endsWith('.heapsnapshot.part'));
            expect(root.listSync(), isEmpty);
            File(path).writeAsStringSync('fixture 界🙂e\u0301');
            order.add('snapshot');
          },
          stats: (_) {
            order.add('stats');
            expect(root.listSync().single.path, endsWith('.heapsnapshot'));
            return {'fixture': '界🙂e\u0301'};
          },
        );
        expect(order, ['snapshot', 'stats']);
        expect(File(files.snapshot!).readAsStringSync(), 'fixture 界🙂e\u0301');
        expect(jsonDecode(File(files.stats).readAsStringSync()), {
          'fixture': '界🙂e\u0301',
        });
        final failed = Directory(p.join(root.path, 'failed'));
        final reason = StateError('snapshot unsupported');
        await expectLater(
          writeHeapSnapshot(
            failed.path,
            now: () => at,
            snapshot: (path) {
              File(path).writeAsStringSync('partial');
              throw reason;
            },
            stats: (_) => {'pid': pid},
          ),
          throwsA(same(reason)),
        );
        expect(failed.listSync().single.path, endsWith('.json'));
        expect(
          jsonDecode((failed.listSync().single as File).readAsStringSync()),
          {'pid': pid},
        );
      },
    );

    test('each signal resolves its directory again and failures overwrite '
        'the previous error completely', () async {
      final root = Directory.systemTemp.createTempSync('heap-errors-tester-');
      addTearDown(() => root.deleteSync(recursive: true));
      final signals = StreamController<ProcessSignal>();
      addTearDown(signals.close);
      var current = root.path, attempt = 0;
      final errorWrites = <Future<File>>[];
      final outside = Zone.current;
      final off = IOOverrides.runZoned(
        () => snapshotOnSignal(
          () => current,
          signals: signals.stream,
          now: () => DateTime.utc(2026, 11, 24),
          write: (_) async {
            throw StateError('attempt ${++attempt}');
          },
        ),
        createFile: (path) =>
            _ObservedErrorFile(outside.run(() => File(path)), errorWrites.add),
      );
      addTearDown(off);
      final error = File(p.join(root.path, 'heap-error.txt'));
      error.writeAsStringSync('old bytes' * 1000);
      signals.add(heapSignal);
      await _until(() => error.readAsStringSync().contains('attempt 1'));
      // Content can become visible before writeAsString closes its file.
      // Await that real IO, then drain the handler's finally continuation.
      expect(errorWrites, hasLength(1));
      await errorWrites.single;
      await pumpEventQueue();
      expect(error.readAsStringSync(), isNot(contains('old bytes')));
      current = (Directory(p.join(root.path, 'second'))..createSync()).path;
      final nextError = File(p.join(current, 'heap-error.txt'));
      signals.add(heapSignal);
      await _until(
        () =>
            nextError.existsSync() &&
            nextError.readAsStringSync().contains('attempt 2'),
      );
      expect(error.readAsStringSync(), contains('attempt 1'));
      expect(nextError.readAsStringSync(), isNot(contains('attempt 1')));
    });
  });
}

/// Only the handler's error-file write is overridden; it still uses real IO.
final class _ObservedErrorFile implements File {
  _ObservedErrorFile(this.file, this.observe);

  final File file;
  final void Function(Future<File>) observe;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    final done = file.writeAsString(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    );
    observe(done);
    return done;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
