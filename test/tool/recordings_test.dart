import 'dart:convert';

import 'package:chord_tui/chord_tui.dart' show TerminalRecording;
import 'package:test/test.dart';

import '../../tool/recordings.dart';
import '../../tool/screenshots.dart'
    show
        Aged,
        Exited,
        Pause,
        Respawn,
        SendKeys,
        TypeText,
        UntilShown,
        keyLabel,
        stepLabel;

const _ms = Duration(milliseconds: 1);

void main() {
  test('each shot is recorded at the two rooms the site gives', () {
    expect(recordingSizes, [(cols: 120, rows: 36), (cols: 80, rows: 20)]);
    expect(
      [for (final size in recordingSizes) recordingName('permission', size)],
      ['permission.120x36.rec.json', 'permission.80x20.rec.json'],
    );
  });

  test('a pane becomes exactly its rows, colours kept', () {
    expect(paneRows('\x1b[1ma\x1b[0m\nb\n', 3), ['\x1b[1ma\x1b[0m', 'b', '']);
    expect(paneRows('a\nb\nc\nd\n', 2), ['a', 'b']);
  });

  test('frames the same as the one before are dropped', () {
    final writer = RecordingWriter(10, 2)
      ..add(Duration.zero, 'a\n')
      ..add(_ms * 100, 'a\n')
      ..add(_ms * 200, 'b\n')
      ..add(_ms * 300, 'b\n')
      ..add(_ms * 400, 'a\n');
    final frames = (jsonDecode(writer.toJson()) as Map)['frames'] as List;
    expect([for (final f in frames) (f as Map)['at']], [0, 200, 400]);
  });

  test('a step labels the next frame that differs', () {
    final writer = RecordingWriter(10, 1)
      ..add(Duration.zero, 'a\n')
      ..step('typed hello')
      ..add(_ms * 100, 'a\n')
      ..add(_ms * 200, 'a hello\n')
      ..add(_ms * 300, 'a hello!\n')
      ..step('C-o')
      ..step('Enter')
      ..add(_ms * 400, 'done\n');
    final frames = (jsonDecode(writer.toJson()) as Map)['frames'] as List;
    expect(
      [for (final f in frames) (f as Map)['label']],
      [null, 'typed hello', null, 'C-o · Enter'],
    );
  });

  test('the framework reads what is written', () {
    final writer = RecordingWriter(120, 36)
      ..add(Duration.zero, '\x1b[1mchord\x1b[0m\n')
      ..step('Enter')
      ..add(_ms * 1300, 'next\n');
    final recording = TerminalRecording.fromJson(jsonDecode(writer.toJson()));
    expect((recording.cols, recording.rows), (120, 36));
    expect(recording.frames, hasLength(2));
    expect(recording.frames.first.rows, hasLength(36));
    expect(recording.frames.last.at, _ms * 1300);
    expect(recording.frames.last.label, 'Enter');
    expect(recording.steps, [1]);
  });

  test("keys are labelled in chord_tui's spelling, not tmux's", () {
    expect(keyLabel('Enter'), 'enter');
    expect(keyLabel('Escape'), 'escape');
    expect(keyLabel('BTab'), 'shift+tab');
    expect(keyLabel('C-o'), 'ctrl+o');
    expect(keyLabel('M-x'), 'alt+x');
    expect(keyLabel('C-S-Up'), 'ctrl+shift+up');
    expect(keyLabel('F2'), 'f2');
  });

  test('steps carry labels, waits none', () {
    expect(
      stepLabel(const TypeText('Write the notes')),
      'typed Write the notes',
    );
    expect(stepLabel(const SendKeys(['C-x', 'Enter'])), 'ctrl+x enter');
    expect(stepLabel(const Respawn(['--resume'])), 'started again');
    expect(stepLabel(const Exited()), 'left');
    expect(stepLabel(const UntilShown('x')), isNull);
    expect(stepLabel(const Pause(100)), isNull);
    expect(stepLabel(const Aged([1])), isNull);
    expect(stepLabel(TypeText('x' * 80))!.length, 40);
  });

  test('long labels are cut with an ellipsis', () {
    expect(cutLabel('short'), 'short');
    final cut = cutLabel('typed ${'x' * 60}');
    expect(cut, hasLength(40));
    expect(cut, endsWith('…'));
  });
}
