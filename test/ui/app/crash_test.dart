import 'package:chord/ui/app/crash.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

const refused =
    'Error: codex not started: agents.codex.command in .chord/settings.json: expected a string, got a number';
final frames = List.generate(
  10,
  (i) => '#$i worker$i (fixture.dart:${i + 1}:1)',
);
final stack = StackTrace.fromString(frames.join('\n'));
List<String> text(int width, int height) =>
    crashRows(refused, stack, width, height).map((row) => row.text).toList();

void main() {
  test('80x24 wraps the message once and keeps every native frame and hint', () {
    final rows = crashRows(refused, stack, 80, 24);
    expect(rows.map((row) => row.text), [
      '',
      '  Error: codex not started: agents.codex.command in .chord/settings.json:',
      '  expected a string, got a number',
      for (final frame in frames) '  $frame',
      '',
      '  $crashHint',
    ]);
    expect(rows.map((row) => row.role), [
      CrashRole.blank,
      CrashRole.error,
      CrashRole.error,
      ...List.filled(10, CrashRole.dim),
      CrashRole.blank,
      CrashRole.dim,
    ]);
  });
  test('120x40 keeps the message in one row with no cuts', () {
    expect(text(120, 40).length, 14);
    expect(text(120, 40)[1], '  $refused');
  });
  test('60x9 removes bottom frames and counts them before a cut hint', () {
    expect(text(60, 9), [
      '',
      '  Error: codex not started: agents.codex.command in',
      '  .chord/settings.json: expected a string, got a number',
      for (final frame in frames.take(3)) '  $frame',
      '      … 7 more frames',
      '',
      '  any key to quit · chord prints the error to stderr as it …',
    ]);
  });
  test(
    '40x4 removes frames and blanks, ending the retained message in ellipsis',
    () {
      expect(text(40, 4), [
        '  Error: codex not started:',
        '  agents.codex.command in',
        '  .chord/settings.json: expected a…',
        '  any key to quit · chord prints the er…',
      ]);
    },
  );
  test('shrinking follows the original priority and keeps the hint last', () {
    expect(text(80, 14), contains('      … 2 more frames'));
    expect(text(80, 6).skip(3), ['      … 10 more frames', '', '  $crashHint']);
    expect(text(80, 5), [
      '',
      text(80, 24)[1],
      text(80, 24)[2],
      '',
      '  $crashHint',
    ]);
    expect(text(80, 4).first, startsWith('  Error:'));
    expect(text(80, 2), [
      '  Error: codex not started: agents.codex.command in .chord/settings.json:…',
      '  $crashHint',
    ]);
    expect(text(80, 1), ['  $crashHint']);
  });
  test('a value without a stack has no frame rows', () {
    expect(
      crashRows('the session went away', null, 80, 24).map((row) => row.text),
      ['', '  the session went away', '', '  $crashHint'],
    );
  });
  test('multiline native errors keep each message line once', () {
    expect(
      crashRows(
        StateError('first line\nsecond line'),
        StackTrace.fromString(
          '#0 worker (fixture.dart:4:2)\n<asynchronous suspension>',
        ),
        80,
        24,
      ).map((row) => row.text),
      [
        '',
        '  Bad state: first line',
        '  second line',
        '  #0 worker (fixture.dart:4:2)',
        '',
        '  $crashHint',
      ],
    );
  });
  test(
    'wide combining text hard-wraps while frames are cut and never wrap',
    () {
      final rows = crashRows(
        '界e\u0301' * 12,
        StackTrace.fromString('#0 worker (${'segment' * 12}.dart:4:2)'),
        12,
        24,
      );
      expect(
        rows.where((row) => row.text.startsWith('  #0')).single.text,
        endsWith('…'),
      );
      expect(
        rows.where((row) => row.role == CrashRole.error).length,
        greaterThan(1),
      );
      for (final row in rows) {
        expect(cellWidth(row.text), lessThanOrEqualTo(12));
      }
    },
  );
  test('an Error without a stack keeps the message and hint', () {
    expect(
      crashRows(
        StateError('no stack is available'),
        null,
        80,
        24,
      ).map((row) => row.text),
      ['', '  Bad state: no stack is available', '', '  $crashHint'],
    );
  });
  test('the hint survives every small height with no frames', () {
    for (var height = 1; height <= 6; height++) {
      final rows = crashRows('a long message ' * 20, null, 30, height);
      expect(rows.length, lessThanOrEqualTo(height));
      expect(rows.last.text, '  any key to quit · chord pri…');
      if (height > 1) expect(rows[rows.length - 2].text, endsWith('…'));
    }
  });
  test('zero width or height draws no rows', () {
    expect(crashRows(refused, stack, 0, 24), isEmpty);
    expect(crashRows(refused, stack, 80, 0), isEmpty);
  });

  group('tester: pure crash row boundaries', () {
    test('Unicode and escapes stay bounded at every tiny width and height', () {
      for (var width = 1; width <= 12; width++) {
        for (var height = 1; height <= 15; height++) {
          final rows = crashRows(
            '界🙂e\u0301\x1b[31mR\x1b[0m' * 8,
            StackTrace.fromString('#0 界🙂e\u0301 (fixture.dart:1:1)'),
            width,
            height,
          );
          expect(
            rows.length,
            lessThanOrEqualTo(height),
            reason: '$width x $height',
          );
          expect(rows.last.role, CrashRole.dim);
          expect(rows.last.text, truncate('  $crashHint', width));
          for (final row in rows) {
            expect(cellWidth(row.text), lessThanOrEqualTo(width));
            expect(row.text, isNot(contains('\x1b')));
          }
        }
      }
    });

    test(
      'explicit empty message lines survive before filtered native frames',
      () {
        final rows = crashRows(
          'first\n\nlast\n',
          StackTrace.fromString(
            'Error: first\n#0 first (fixture.dart:1:1)\n'
            '<asynchronous suspension>\nnot a frame\n#1 second (fixture.dart:2:1)',
          ),
          80,
          24,
        );
        expect(rows.map((row) => row.text), [
          '',
          '  first',
          '  ',
          '  last',
          '  ',
          '  #0 first (fixture.dart:1:1)',
          '  #1 second (fixture.dart:2:1)',
          '',
          '  $crashHint',
        ]);
        expect(rows.where((row) => row.role == CrashRole.error).length, 4);
      },
    );

    test(
      'a thousand independent calls do not retain previous frames or dimensions',
      () {
        for (var i = 0; i < 1000; i++) {
          final width = i.isEven ? 80 : 120;
          final rows = crashRows('message $i', null, width, i.isEven ? 24 : 40);
          expect(rows.map((row) => row.text), [
            '',
            '  message $i',
            '',
            '  $crashHint',
          ]);
        }
      },
    );

    test('negative dimensions and a single cell remain safe', () {
      expect(crashRows('failure', stack, -1, 24), isEmpty);
      expect(crashRows('failure', stack, 80, -1), isEmpty);
      final one = crashRows('failure', stack, 1, 1);
      expect(one.single.role, CrashRole.dim);
      expect(one.single.text, '…');
    });
  });
}
