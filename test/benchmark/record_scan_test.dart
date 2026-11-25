import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../benchmark/record_scan.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('record-scan-bench-');
  });
  tearDown(() => temp.delete(recursive: true));

  const set = RecordScanSet(files: 4, bigCount: 1, bigMb: 1);

  List<String> listing(String dir) => [
    for (final entry in Directory(dir).listSync(recursive: true))
      p.relative(entry.path, from: dir),
  ]..sort();

  test('a missing directory is generated and marked complete', () {
    final state = p.join(temp.path, 'state');
    expect(prepareRecordScan(state, set), isA<RecordScanGenerated>());
    expect(File(p.join(state, recordScanMarker)).existsSync(), isTrue);
    expect(Directory(p.join(state, 'records')).listSync(), hasLength(5));
  });

  test('a completed set of the same shape is reused unchanged', () {
    final state = p.join(temp.path, 'state');
    prepareRecordScan(state, set);
    final before = listing(state);
    expect(prepareRecordScan(state, set), isA<RecordScanReused>());
    expect(listing(state), before);
  });

  test('a completed set of another shape is refused', () {
    final state = p.join(temp.path, 'state');
    prepareRecordScan(state, set);
    final before = listing(state);
    final other = prepareRecordScan(
      state,
      const RecordScanSet(files: 5, bigCount: 1, bigMb: 1),
    );
    expect(other, isA<RecordScanRefused>());
    expect(listing(state), before);
  });

  test('an unmarked state, such as a person\'s or an interrupted '
      'generation, is refused and left untouched', () {
    final state = Directory(p.join(temp.path, 'state', 'records'))
      ..createSync(recursive: true);
    final record = File(p.join(state.path, 'someone.jsonl'))
      ..writeAsStringSync('{"type":"session"}\n');
    final refused = prepareRecordScan(p.dirname(state.path), set);
    expect(refused, isA<RecordScanRefused>());
    expect((refused as RecordScanRefused).reason, contains(recordScanMarker));
    expect(listing(p.dirname(state.path)), [
      'records',
      'records/someone.jsonl',
    ]);
    expect(record.readAsStringSync(), '{"type":"session"}\n');
  });

  test('the same set generates the same bytes', () {
    final a = p.join(temp.path, 'a'), b = p.join(temp.path, 'b');
    prepareRecordScan(a, set);
    prepareRecordScan(b, set);
    for (final name in listing(p.join(a, 'records'))) {
      expect(
        File(p.join(b, 'records', name)).readAsBytesSync(),
        File(p.join(a, 'records', name)).readAsBytesSync(),
      );
    }
  });

  test(
    'runs below one and negative sizes are refused before anything',
    () async {
      for (final flag in ['--runs=0', '--files=-1', '--big-mb=x']) {
        final run = await Process.run(Platform.resolvedExecutable, [
          'run',
          'benchmark/record_scan.dart',
          flag,
          '--dir=${p.join(temp.path, 'unused')}',
        ]);
        expect(run.exitCode, 64, reason: flag);
        expect(Directory(p.join(temp.path, 'unused')).existsSync(), isFalse);
      }
    },
  );
}
