// From the original's tests/platform/heap_test.ts (CTUI-103): the files a
// snapshot leaves, the signal that takes one, and a failure left in the
// directory rather than on the terminal.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/platform/heap.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('chord-heap-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  final at = DateTime.utc(2026, 10, 12, 13, 40, 10, 9);
  final base = 'chord-$pid-2026-10-12T13-40-10-009Z';

  List<String> listed(String dir) =>
      [for (final e in Directory(dir).listSync()) p.basename(e.path)]..sort();

  group('writeHeapSnapshot', () {
    test(
      "the VM's snapshot and the memory, named by the pid and the time",
      () async {
        final dir = p.join(scratch.path, 'heaps');
        final files = await writeHeapSnapshot(dir, now: () => at);
        expect(files, (
          snapshot: p.join(dir, '$base.heapsnapshot'),
          stats: p.join(dir, '$base.json'),
        ));
        expect(listed(dir), ['$base.heapsnapshot', '$base.json']);
        // The Dart VM's own format, which its DevTools read.
        expect(
          String.fromCharCodes(File(files.snapshot!).readAsBytesSync().take(8)),
          'dartheap',
        );
        final stats =
            jsonDecode(File(files.stats).readAsStringSync())
                as Map<String, Object?>;
        expect(stats['pid'], pid);
        expect(stats['at'], '2026-10-12T13:40:10.009Z');
        expect(
          stats['currentRss'],
          isA<int>().having((n) => n, 'rss', greaterThan(0)),
        );
        expect(stats['maxRss'], isA<int>());
        expect(stats.keys, ['pid', 'at', 'currentRss', 'maxRss', 'buildId']);
      },
    );

    test(
      'a snapshot the VM cannot take leaves the memory and says why',
      () async {
        final dir = p.join(scratch.path, 'heaps');
        await expectLater(
          writeHeapSnapshot(
            dir,
            now: () => at,
            snapshot: (path) {
              File(path).writeAsStringSync('half');
              throw UnsupportedError(
                'Heap snapshots are only supported in non-product mode.',
              );
            },
          ),
          throwsA(isA<UnsupportedError>()),
        );
        expect(listed(dir), ['$base.json']);
      },
    );
  });

  group('snapshotOnSignal', () {
    test('the signal writes a snapshot and leaves chord running', () async {
      final written = Completer<HeapFiles>();
      final off = snapshotOnSignal(
        () => scratch.path,
        written: written.complete,
      );
      try {
        Process.killPid(pid, heapSignal);
        final files = await written.future.timeout(const Duration(seconds: 30));
        expect(files.snapshot, startsWith(scratch.path));
        expect(listed(scratch.path), hasLength(2));
      } finally {
        off();
      }
    });

    test('a signal while one is written is dropped; the dir is asked each '
        'time', () async {
      final signals = StreamController<ProcessSignal>();
      final release = Completer<void>();
      var asked = 0;
      var writes = 0;
      final off = snapshotOnSignal(
        () {
          asked++;
          return scratch.path;
        },
        signals: signals.stream,
        write: (dir) async {
          writes++;
          await release.future;
          return (snapshot: null, stats: p.join(dir, 'x.json'));
        },
      );
      signals
        ..add(heapSignal)
        ..add(heapSignal);
      await pumpEventQueue();
      expect((asked, writes), (1, 1));
      release.complete();
      await pumpEventQueue();
      signals.add(heapSignal);
      await pumpEventQueue();
      expect((asked, writes), (2, 2));
      off();
      await pumpEventQueue();
      signals.add(heapSignal);
      await pumpEventQueue();
      expect(writes, 2);
      await signals.close();
    });

    test('a failure is left in the directory, not on the terminal', () async {
      final signals = StreamController<ProcessSignal>();
      final off = snapshotOnSignal(
        () => scratch.path,
        signals: signals.stream,
        now: () => at,
        written: (_) => throw StateError('the disk is full'),
        write: (dir) async => (snapshot: null, stats: p.join(dir, 'x.json')),
      );
      final error = File(p.join(scratch.path, 'heap-error.txt'));
      const said = '2026-10-12T13:40:10.009Z Bad state: the disk is full\n';
      signals.add(heapSignal);
      // The file may be seen before its text is all written: wait for the
      // text, not the file.
      String read() {
        try {
          return error.readAsStringSync();
        } on FileSystemException {
          return '';
        }
      }

      for (var i = 0; i < 100 && !read().startsWith(said); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(read(), startsWith(said));
      // A directory that cannot be named leaves nothing anywhere.
      off();
      final again = StreamController<ProcessSignal>();
      var wrote = false;
      final off2 = snapshotOnSignal(
        () => throw StateError('no home'),
        signals: again.stream,
        write: (dir) async {
          wrote = true;
          return (snapshot: null, stats: '');
        },
      );
      again.add(heapSignal);
      await pumpEventQueue();
      expect(wrote, isFalse);
      off2();
      await signals.close();
      await again.close();
    });
  });
}
