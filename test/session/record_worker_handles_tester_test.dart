import 'dart:io';

import 'package:test/test.dart';

import '../../tool/record_worker_handles.dart' show procDescriptors;

void main() {
  group('tester: Linux descriptor ownership boundaries', () {
    late Directory parent;
    late Directory owned;

    setUp(() {
      parent = Directory.systemTemp.createTempSync('record-fd-boundaries-');
      owned = Directory('${parent.resolveSymbolicLinksSync()}/owned')
        ..createSync();
    });
    tearDown(() => parent.deleteSync(recursive: true));

    test('an unlinked open file remains owned until its descriptor closes', () {
      if (!Platform.isLinux) {
        markTestSkipped('Exercises Linux /proc/self/fd deleted targets.');
        return;
      }
      final file = File('${owned.path}/saved 界😀.jsonl')
        ..writeAsStringSync('record');
      final handle = file.openSync();
      try {
        file.deleteSync();
        final found = procDescriptors(owned.path);
        expect(found, hasLength(1));
        expect(found.single['type'], 'REG');
        expect(found.single['path'], 'saved 界😀.jsonl');
        expect(found.single['descriptor'], matches(RegExp(r'^\d+$')));
      } finally {
        handle.closeSync();
      }
      expect(procDescriptors(owned.path), isEmpty);
    });

    test('a shared path prefix does not make a sibling descriptor owned', () {
      if (!Platform.isLinux) {
        markTestSkipped('Exercises Linux /proc/self/fd root boundaries.');
        return;
      }
      final sibling = Directory('${owned.path}-sibling')..createSync();
      final inside = File('${owned.path}/inside')..writeAsStringSync('owned');
      final outside = File('${sibling.path}/outside')
        ..writeAsStringSync('sibling');
      final handles = [inside.openSync(), outside.openSync()];
      try {
        final found = procDescriptors(owned.path);
        expect(found, hasLength(1));
        expect(found.single['path'], 'inside');
        expect(found.single['type'], 'REG');
        expect(procDescriptors(sibling.path).single['path'], 'outside');
      } finally {
        for (final handle in handles) {
          handle.closeSync();
        }
      }
      expect(procDescriptors(owned.path), isEmpty);
      expect(procDescriptors(sibling.path), isEmpty);
    });
  });
}
