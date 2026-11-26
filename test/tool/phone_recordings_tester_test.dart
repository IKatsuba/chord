import 'dart:convert';

import 'package:chord_tui/chord_tui.dart' show TerminalRecording, cellWidth;
import 'package:test/test.dart';

import '../../tool/recordings.dart';
import '../../tool/screenshots.dart' show shots, UntilShown;

void main() {
  group('CHD-638 tester: phone recording contract', () {
    test('every shot gets a unique phone path beside both existing rooms', () {
      final names = [
        for (final shot in shots)
          for (final size in recordingSizes) recordingName(shot.name, size),
      ];
      expect(names.toSet(), hasLength(shots.length * 3));
      expect(
        names.where((name) => name.endsWith('.48x32.rec.json')),
        hasLength(shots.length),
      );
      for (final shot in shots) {
        expect(
          names,
          containsAll([
            '${shot.name}.120x36.rec.json',
            '${shot.name}.80x20.rec.json',
            '${shot.name}.48x32.rec.json',
          ]),
        );
      }
    });

    test('the phone bottom-right graphemes and ANSI survive serialization', () {
      const glyphs = '界👩‍💻e\u0301';
      final edge = '\x1b[1m${' ' * (48 - cellWidth(glyphs))}$glyphs\x1b[0m';
      final rows = [for (var i = 0; i < 31; i++) '', edge];
      final writer = RecordingWriter(48, 32)
        ..step('phone bottom edge')
        ..add(Duration.zero, '${rows.join('\n')}\noutside\n');
      final recording = TerminalRecording.fromJson(jsonDecode(writer.toJson()));
      expect((recording.cols, recording.rows), (48, 32));
      expect(recording.frames.single.rows, rows);
      expect(recording.frames.single.label, 'phone bottom edge');
    });

    test('phone waits use the narrow cue, with the normal cue as fallback', () {
      expect(const UntilShown('wide', narrow: 'phone').shownAt(48), 'phone');
      expect(const UntilShown('shared').shownAt(48), 'shared');
    });
  });
}
