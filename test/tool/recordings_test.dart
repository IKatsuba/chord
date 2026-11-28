import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:chord_tui/chord_tui.dart' show TerminalRecording, cellWidth;
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
        ShotPane,
        keyLabel,
        playSteps,
        stepLabel;

const _ms = Duration(milliseconds: 1);

void main() {
  test('each shot is recorded at the three rooms the site gives', () {
    expect(recordingSizes, [
      (cols: 120, rows: 36),
      (cols: 80, rows: 20),
      (cols: 48, rows: 32),
    ]);
    expect(
      [for (final size in recordingSizes) recordingName('permission', size)],
      [
        'permission.120x36.rec.json',
        'permission.80x20.rec.json',
        'permission.48x32.rec.json',
      ],
    );
  });

  test('a pane becomes exactly its rows, colours kept', () {
    expect(paneRows('\x1b[1ma\x1b[0m\nb\n', 3), ['\x1b[1ma\x1b[0m', 'b', '']);
    expect(paneRows('a\nb\nc\nd\n', 2), ['a', 'b']);
  });

  test('frames the same as the one before are dropped', () {
    final writer = RecordingWriter(10, 2)
      ..add(Duration.zero, 'a\n')
      ..add(_ms * 300, 'a\n')
      ..add(_ms * 600, 'b\n')
      ..add(_ms * 900, 'b\n')
      ..add(_ms * 1200, 'a\n');
    final frames = (jsonDecode(writer.toJson()) as Map)['frames'] as List;
    expect([for (final f in frames) (f as Map)['at']], [0, 600, 1200]);
  });

  test('unlabelled frames come at most every 250 ms, the last one kept', () {
    final writer = RecordingWriter(10, 1);
    for (var i = 0; i <= 10; i++) {
      writer.add(_ms * (i * 100), 'frame $i\n');
    }
    final frames = (jsonDecode(writer.toJson()) as Map)['frames'] as List;
    final kept = [for (final f in frames) (f as Map)['at']];
    expect(kept, [0, 300, 600, 900, 1000]);
    for (var i = 1; i < kept.length - 1; i++) {
      expect(
        (kept[i] as int) - (kept[i - 1] as int),
        greaterThanOrEqualTo(250),
      );
    }
    expect(((frames.last as Map)['rows'] as List).first, 'frame 10');
  });

  test('a labelled frame is kept however soon it comes', () {
    final writer = RecordingWriter(10, 1)
      ..add(Duration.zero, 'a\n')
      ..step('enter')
      ..add(_ms * 50, 'b\n')
      ..add(_ms * 100, 'c\n');
    final frames = (jsonDecode(writer.toJson()) as Map)['frames'] as List;
    expect(
      [for (final f in frames) ((f as Map)['at'], f['label'])],
      [(0, null), (50, 'enter'), (100, null)],
    );
  });

  test('a held frame the screen returns from is dropped', () {
    final writer = RecordingWriter(10, 1)
      ..add(Duration.zero, 'a\n')
      ..add(_ms * 100, 'flash\n')
      ..add(_ms * 200, 'a\n');
    final frames = (jsonDecode(writer.toJson()) as Map)['frames'] as List;
    expect(frames, hasLength(1));
  });

  test('a step labels the next frame that differs', () {
    final writer = RecordingWriter(10, 1)
      ..add(Duration.zero, 'a\n')
      ..step('typed hello')
      ..add(_ms * 100, 'a\n')
      ..add(_ms * 200, 'a hello\n')
      ..add(_ms * 500, 'a hello!\n')
      ..step('C-o')
      ..step('Enter')
      ..add(_ms * 600, 'done\n');
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

  test('labels are cut by cells, wide characters and emoji whole', () {
    final wide = cutLabel('typed ${'日本語' * 10}');
    expect(cellWidth(wide), lessThanOrEqualTo(40));
    expect(wide, endsWith('…'));
    final family = '👨‍👩‍👧';
    final emoji = cutLabel('typed ${family * 30}');
    expect(cellWidth(emoji), lessThanOrEqualTo(40));
    // Every grapheme before the ellipsis is a whole family.
    final graphemes = emoji.characters.toList();
    expect(graphemes.last, '…');
    for (final g in graphemes.skip(6).take(graphemes.length - 7)) {
      expect(g, family);
    }
  });

  test(
    'a narrow pane waits on its own wording, the pictures on theirs',
    () async {
      const step = UntilShown('● permission', narrow: 'needs your permission');
      expect(step.shownAt(120), '● permission');
      expect(step.shownAt(80), 'needs your permission');
      expect(const UntilShown('same').shownAt(80), 'same');
      final waited = <String>[];
      final pane = ShotPane(
        type: (_) {},
        send: (_) {},
        until: (text) async => waited.add(text),
        exited: () async {},
        age: (_) {},
        respawn: (_) {},
        idle: (_) async {},
        sample: () {},
        label: (_) {},
      );
      await playSteps(const [step], pane, cols: 80);
      await playSteps(const [step], pane);
      expect(waited, ['needs your permission', '● permission']);
    },
  );

  test('a frame is taken after every step, before the next acts', () async {
    final calls = <String>[];
    final pane = ShotPane(
      type: (text) => calls.add('type'),
      send: (keys) => calls.add('send'),
      // Met at once: no sample while waiting.
      until: (text) async => calls.add('until'),
      exited: () async => calls.add('exited'),
      age: (hours) => calls.add('age'),
      respawn: (args) => calls.add('respawn'),
      idle: (time) async => calls.add('idle'),
      sample: () => calls.add('sample'),
      label: (label) => calls.add('label $label'),
    );
    await playSteps(const [
      TypeText('hi'),
      UntilShown('hi'),
      Aged([1]),
      Respawn(['--resume']),
      SendKeys(['Enter']),
    ], pane);
    expect(calls, [
      'sample',
      'label typed hi',
      'type',
      'idle',
      'sample',
      'until',
      'sample',
      'age',
      'sample',
      'label started again',
      'respawn',
      'sample',
      'label enter',
      'send',
      'idle',
      'sample',
      'idle',
    ]);
  });
}
