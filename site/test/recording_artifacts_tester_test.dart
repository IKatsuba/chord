import 'dart:convert';
import 'dart:io';

import 'package:chord_site/screens.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('tester: committed terminal recording artifacts', () {
    final expected = <String>{
      for (final name in screenCaptions.keys)
        for (final grid in ['120x36', '80x20']) '$name.$grid.rec.json',
    };
    test('every named screen has both recording grids', () {
      final actual = Directory('../docs/images')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.rec.json'))
          .map((file) => file.uri.pathSegments.last)
          .toSet();
      expect(expected, hasLength(20));
      expect(actual, expected);
    });
    for (final name in expected) {
      test('$name has ordered full frames and no personal directory paths', () {
        final recording = TerminalRecording.fromJson(
          jsonDecode(File('../docs/images/$name').readAsStringSync()),
        );
        final grid = name.split('.')[1].split('x').map(int.parse).toList();
        expect((recording.cols, recording.rows), (grid[0], grid[1]));
        expect(recording.frames, isNotEmpty);
        var previous = Duration.zero;
        final personalPath = RegExp(
          r'/(?:Users|home)/[^/\s]+/|[A-Z]:\\Users\\',
          caseSensitive: false,
        );
        var drawn = false;
        for (final frame in recording.frames) {
          expect(frame.at, greaterThanOrEqualTo(previous));
          expect(frame.rows, hasLength(recording.rows));
          for (final row in frame.rows) {
            expect(row, isNot(matches(personalPath)));
            drawn |= row.trim().isNotEmpty;
          }
          previous = frame.at;
        }
        expect(drawn, isTrue);
      });
    }
  });
}
