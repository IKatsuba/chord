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
  'cols': 48,
  'rows': 32,
  'frames': [
    {
      'at': 0,
      'rows': [marker, for (var i = 1; i < 32; i++) 'row $i'],
    },
    {
      'at': 3000,
      'rows': ['last', for (var i = 1; i < 32; i++) 'row $i'],
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
        expect(t.screen, shows('LOADING START…'));
        host.popped.add('/chord/permission');
        await t.pump();
        final [first, middle, latest] = host.pending;
        expect(
          [first.$1, middle.$1, latest.$1],
          [
            'permission.48x32.rec.json',
            'start.48x32.rec.json',
            'permission.48x32.rec.json',
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
        expect(t.screen, isNot(shows("COULDN'T LOAD")));
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
          'permission.48x32.rec.json': text,
        });
        addTearDown(host.popped.close);
        await t.pumpWidget(
          Site(host: host, recordings: const ['permission']),
          size: const Size(43, 37),
        );
        await t.pump();
        expect(t.screen, shows("COULDN'T LOAD PERMISSION"));
        expect(host.fetched, ['permission.48x32.rec.json']);
        await t.press('f1');
        expect(t.screen, shows(' Keys'));
        await t.press('ctrl+c');
        expect(host.pushed, ['/']);
        expect(t.exitRequested, isFalse);
      }
    });
  });

  group('CHD-638 tester: recording bar and clipped room boundaries', () {
    for (final (size, cols, rows) in const [
      (Size(205, 56), 120, 36),
      (Size(117, 73), 80, 20),
      (Size(55, 52), 48, 32),
      (Size(51, 40), 48, 32),
      (Size(80, 24), 48, 32),
      (Size(43, 37), 48, 32),
    ]) {
      testWidgets('wide labels keep both margins while panning reaches the '
          'last row at $size', (t) async {
        final file = 'permission.${cols}x$rows.rec.json';
        final host = FakeHost('/chord/permission', {
          file: jsonEncode({
            'version': 1,
            'cols': cols,
            'rows': rows,
            'frames': [
              {
                'at': 0,
                'rows': [for (var i = 0; i < rows; i++) 'recorded row $i'],
                'label': '界🙂e\u0301 ' * 100,
              },
              {
                'at': 10000,
                'rows': ['last frame'],
                'label': null,
              },
            ],
          }),
        });
        addTearDown(host.popped.close);
        await t.pumpWidget(
          Site(host: host, recordings: const ['permission']),
          size: size,
        );
        await t.pump();
        expect(host.fetched, [file]);
        await t.press('space');
        final y = t.screen.lines.indexWhere((line) => line.contains('0:00 /'));
        expect(y, greaterThanOrEqualTo(0));
        final margin = size.width < 60 ? 2 : 4;
        for (var x = 0; x < margin; x++) {
          expect(t.screen.charAt(x, y), ' ');
          expect(t.screen.charAt(size.width - x - 1, y), ' ');
        }
        expect(t.screen.lines[y].trimRight(), endsWith('…'));
        for (var i = 0; i < 1000; i++) {
          t.host.handleKey(KeyCombo.parse('shift+down').toEvent());
        }
        await t.pump();
        expect(t.screen, shows('recorded row ${rows - 1}'));
        expect(t.screen.lines[y], contains('0:00 /'));
        await t.press('r');
        await t.pumpWidget(Text('removed'));
        await t.pump(const Duration(milliseconds: 100));
        expect(t.screen.text, 'removed');
        expect(host.popped.hasListener, isFalse);
        expect(t.exitRequested, isFalse);
      });
    }
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
