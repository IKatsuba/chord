import 'dart:async';
import 'dart:convert';

import 'package:chord_site/pacing.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fake_host.dart';

class _ControlledHost extends FakeHost {
  _ControlledHost() : super('/chord/permission');

  final pending = <(String, Completer<String?>)>[];

  @override
  Future<String?> recording(String file) {
    final response = Completer<String?>();
    pending.add((file, response));
    return response.future;
  }
}

String _data(String marker) => jsonEncode({
  'version': 1,
  'cols': 80,
  'rows': 20,
  'frames': [
    {
      'at': 0,
      'rows': [marker, for (var i = 1; i < 20; i++) 'row $i'],
    },
    {
      'at': 3000,
      'rows': ['last', for (var i = 1; i < 20; i++) 'row $i'],
    },
  ],
});

void main() {
  group('tester: recording route request ownership', () {
    testWidgets(
      'route-name ABA ignores stale data and a stale malformed response',
      (t) async {
        final host = _ControlledHost();
        addTearDown(host.popped.close);
        await t.pumpWidget(
          Site(host: host, recordings: const ['permission', 'start']),
          size: const Size(80, 24),
        );
        host.popped.add('/chord/start');
        await t.pump();
        expect(t.screen, shows('loading start…'));
        host.popped.add('/chord/permission');
        await t.pump();
        final [first, middle, latest] = host.pending;
        expect(
          [first.$1, middle.$1, latest.$1],
          [
            'permission.80x20.rec.json',
            'start.80x20.rec.json',
            'permission.80x20.rec.json',
          ],
        );
        latest.$2.complete(_data('current 界🙂e\u0301'));
        await t.pump();
        expect(t.screen, shows('current 界🙂e\u0301'));
        first.$2.complete(_data('stale permission'));
        middle.$2.complete('not JSON');
        await t.pump();
        expect(t.screen, shows('current 界🙂e\u0301'));
        expect(t.screen, isNot(shows('stale permission')));
        expect(t.screen, isNot(shows("couldn't load")));
      },
    );

    testWidgets('malformed JSON is a recoverable page with working home keys', (
      t,
    ) async {
      for (final text in [
        'not JSON',
        'null',
        '{"version":2,"cols":80,"rows":20,"frames":[]}',
      ]) {
        final host = FakeHost('/chord/permission', {
          'permission.80x20.rec.json': text,
        });
        addTearDown(host.popped.close);
        await t.pumpWidget(
          Site(host: host, recordings: const ['permission']),
          size: const Size(43, 37),
        );
        await t.pump();
        expect(t.screen, shows("couldn't load permission"));
        await t.press('f1');
        expect(t.screen, shows(' Keys'));
        await t.press('ctrl+c');
        expect(host.pushed, ['/']);
        expect(t.exitRequested, isFalse);
      }
    });
  });

  group('tester: recording pacing preserves content', () {
    test(
      'custom holds accumulate without changing source frames or labels',
      () {
        final source = TerminalRecording(
          cols: 80,
          rows: 20,
          frames: [
            const TerminalRecordingFrame(
              at: Duration.zero,
              rows: ['\x1b[1m界🙂e\u0301\x1b[0m'],
              label: 'typed',
            ),
            const TerminalRecordingFrame(
              at: Duration(milliseconds: 100),
              rows: ['two'],
              label: 'enter',
            ),
            const TerminalRecordingFrame(
              at: Duration(milliseconds: 200),
              rows: ['three'],
            ),
            const TerminalRecordingFrame(
              at: Duration(milliseconds: 700),
              rows: ['last'],
              label: 'done',
            ),
          ],
        );
        final result = paced(source, hold: const Duration(milliseconds: 500));
        expect(result.frames.map((f) => f.at.inMilliseconds), [
          0,
          500,
          1000,
          1500,
        ]);
        expect(source.frames.map((f) => f.at.inMilliseconds), [
          0,
          100,
          200,
          700,
        ]);
        expect(
          result.frames.map((f) => f.rows),
          source.frames.map((f) => f.rows),
        );
        expect(result.frames.map((f) => f.label), [
          'typed',
          'enter',
          null,
          'done',
        ]);
        expect((result.cols, result.rows), (80, 20));
      },
    );

    test('empty input and a zero hold preserve the original timeline', () {
      const empty = TerminalRecording(cols: 80, rows: 20, frames: []);
      expect(paced(empty).frames, isEmpty);
      final source = TerminalRecording.fromJson(jsonDecode(_data('first')));
      expect(
        paced(source, hold: Duration.zero).frames.map((f) => f.at),
        source.frames.map((f) => f.at),
      );
    });
  });
}
