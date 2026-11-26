import 'dart:async';
import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:chord_tui/chord_tui.dart' show TerminalRecording, cellWidth;
import 'package:test/test.dart';

import '../../tool/recordings.dart';
import '../../tool/screenshots.dart'
    show ShotPane, Step, TypeText, UntilShown, playSteps;

void main() {
  group('tester: recording writer boundary data', () {
    test(
      'the 250 ms boundary keeps the current sample, not a held transient',
      () {
        final writer = RecordingWriter(80, 1)
          ..add(Duration.zero, 'start\n')
          ..add(const Duration(microseconds: 249999), 'transient\n')
          ..add(const Duration(milliseconds: 250), 'edge\n');
        final decoded = TerminalRecording.fromJson(jsonDecode(writer.toJson()));
        expect(decoded.frames.map((frame) => frame.at), [
          Duration.zero,
          const Duration(milliseconds: 250),
        ]);
        expect(decoded.frames.last.rows, ['edge']);
      },
    );

    test('serializing a final held frame is stable and preserves its time', () {
      final writer = RecordingWriter(80, 1)
        ..add(Duration.zero, 'start\n')
        ..add(const Duration(milliseconds: 100), '\x1b[1m界🙂e\u0301\x1b[0m\n');
      final first = writer.toJson();
      expect(writer.toJson(), first);
      final decoded = TerminalRecording.fromJson(jsonDecode(first));
      expect(decoded.frames, hasLength(2));
      expect(decoded.frames.last.at, const Duration(milliseconds: 100));
      expect(decoded.frames.last.rows, ['\x1b[1m界🙂e\u0301\x1b[0m']);
    });

    test(
      'discarding a held transient leaves queued labels for the next change',
      () {
        final writer = RecordingWriter(80, 1)
          ..add(Duration.zero, 'start\n')
          ..add(const Duration(milliseconds: 100), 'transient\n')
          ..step('enter')
          ..add(const Duration(milliseconds: 150), 'start\n')
          ..add(const Duration(milliseconds: 200), 'next\n');
        final decoded = TerminalRecording.fromJson(jsonDecode(writer.toJson()));
        expect(decoded.frames, hasLength(2));
        expect(decoded.frames.last.at, const Duration(milliseconds: 200));
        expect(decoded.frames.last.label, 'enter');
        expect(decoded.frames.last.rows, ['next']);
      },
    );

    for (final size in recordingSizes) {
      test('version 1 preserves ANSI and graphemes at $size', () {
        const first = '\x1b[1m界🙂e\u0301\x1b[0m';
        final writer = RecordingWriter(size.cols, size.rows);
        final rows = [first, for (var i = 1; i < size.rows; i++) 'row $i'];
        writer.add(Duration.zero, '${rows.join('\n')}\noverflow\n');
        writer.add(
          const Duration(milliseconds: 100),
          '${rows.join('\n')}\nchanged overflow\n',
        );
        final decoded = TerminalRecording.fromJson(jsonDecode(writer.toJson()));
        expect((decoded.cols, decoded.rows), (size.cols, size.rows));
        expect(decoded.frames, hasLength(1));
        expect(decoded.frames.single.rows, rows);
        expect(decoded.frames.single.at, Duration.zero);
      });
    }

    test('a thousand duplicate samples retain labels for the next change', () {
      final writer = RecordingWriter(80, 1)..add(Duration.zero, 'start\n');
      for (var i = 0; i < 1000; i++) {
        if (i == 0) writer.step('typed 界🙂e\u0301');
        writer.add(Duration(milliseconds: i + 1), 'start\n');
      }
      writer.step('enter');
      writer.add(const Duration(milliseconds: 1001), 'done\n');
      final decoded = TerminalRecording.fromJson(jsonDecode(writer.toJson()));
      expect(decoded.frames, hasLength(2));
      expect(decoded.frames.last.at, const Duration(milliseconds: 1001));
      expect(decoded.frames.last.label, 'typed 界🙂e\u0301 · enter');
      final retained = writer.toJson();
      writer.add(const Duration(milliseconds: 1002), 'later\n');
      expect(
        TerminalRecording.fromJson(jsonDecode(retained)).frames,
        hasLength(2),
      );
    });

    test(
      'zero and one cell labels keep complete combining and ZWJ graphemes',
      () {
        final original = '界👨‍👩‍👧e\u0301' * 30;
        for (final width in [0, 1, 2, 3, 39, 40, 41]) {
          final cut = cutLabel(original, width: width);
          expect(cellWidth(cut), lessThanOrEqualTo(width));
          if (width == 0) {
            expect(cut, isEmpty);
          } else {
            expect(cut, endsWith('…'));
            final prefix = cut.characters.toList()..removeLast();
            expect(original.characters.take(prefix.length).toList(), prefix);
          }
        }
      },
    );
  });

  group('tester: step sequencing and asynchronous failures', () {
    test(
      'an outstanding wait completes and samples before the next action',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final events = <String>[];
        final running = playSteps(
          const [UntilShown('ready'), TypeText('next')],
          _pane(
            sample: () => events.add('sample'),
            until: (_) async {
              events.add('wait');
              entered.complete();
              await release.future;
              events.add('ready');
            },
            type: (_) => events.add('type'),
            idle: (_) async => events.add('idle'),
            label: (label) => events.add(label),
          ),
        );
        await entered.future;
        expect(events, ['sample', 'wait']);
        release.complete();
        await running;
        expect(events, [
          'sample',
          'wait',
          'ready',
          'sample',
          'typed next',
          'type',
          'idle',
          'sample',
          'idle',
        ]);
      },
    );

    test(
      'a failed wait propagates and does not run later steps or final idle',
      () async {
        final failure = StateError('canned pane exited');
        final events = <String>[];
        await expectLater(
          playSteps(
            const [UntilShown('ready'), TypeText('unreached')],
            _pane(
              sample: () => events.add('sample'),
              until: (_) async {
                events.add('wait');
                throw failure;
              },
              type: (_) => events.add('type'),
              idle: (_) async => events.add('idle'),
            ),
          ),
          throwsA(same(failure)),
        );
        expect(events, ['sample', 'wait']);
      },
    );

    test(
      'an empty step list still samples startup and gives final drawing time',
      () async {
        final events = <Object>[];
        await playSteps(
          const <Step>[],
          _pane(
            sample: () => events.add('sample'),
            idle: (duration) async => events.add(duration),
          ),
        );
        expect(events, ['sample', const Duration(milliseconds: 400)]);
      },
    );
  });
}

ShotPane _pane({
  required void Function() sample,
  Future<void> Function(String)? until,
  Future<void> Function(Duration)? idle,
  void Function(String)? type,
  void Function(String)? label,
}) => ShotPane(
  sample: sample,
  type: type ?? (_) {},
  send: (_) {},
  until: until ?? (_) async {},
  exited: () async {},
  age: (_) {},
  respawn: (_) {},
  idle: idle ?? (_) async {},
  label: label ?? (_) {},
);
