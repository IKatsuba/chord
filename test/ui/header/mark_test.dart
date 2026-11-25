import 'package:chord/ui/header/header.dart';
import 'package:chord/ui/header/mark.dart';
import 'package:chord/ui/header/mark_rows.dart';
import 'package:chord/ui/header/wordmark.dart';
import 'package:chord/ui/status/status.dart' show MarkTones;
import 'package:test/test.dart';

List<String> text(List<List<MarkSegment>> rows) => [
  for (final row in rows) row.map((s) => s.text).join(),
];

void main() {
  const stops = ['#89f5b3', '#47e7a5', '#15c7a2'];
  test('original mark and splash shapes use full and half cells', () {
    expect(text(markRows(mark, const MarkPlain())), [
      '█▄  ',
      '▀██▄',
      '▄██▀',
      '█▀  ',
    ]);
    expect(text(markRows(splashMark, const MarkPlain())), [
      '██▄      ',
      '████▄    ',
      '██████▄  ',
      ' ▀██████▄',
      ' ▄██████▀',
      '██████▀  ',
      '████▀    ',
      '██▀      ',
    ]);
    for (final segment in markRows(mark, const MarkPlain()).expand((r) => r)) {
      expect(segment.color, isNull);
      expect(segment.backgroundColor, isNull);
    }
  });
  test('package sRGB interpolation keeps the original stops and middle', () {
    final paint = markPaint(stops);
    expect([paint(0), paint(0.55), paint(1)], stops);
    expect(paint(0.275), '#68eeac');
    expect(paint(0.775), '#2ed7a4');
  });
  test('halves of different colours use foreground and background', () {
    expect(
      markRows([
        [0],
        [1],
      ], const MarkGradient(stops)),
      [
        [(text: '▀', color: '#89f5b3', backgroundColor: '#15c7a2')],
      ],
    );
    expect(
      markRows([
        [0, 0, null, 0],
        [0, 0, 0, 1],
      ], const MarkTone('green')),
      [
        [(text: '██▄█', color: 'green', backgroundColor: null)],
      ],
    );
    expect(
      markRows([
        [null, 0],
      ], const MarkTone('green')),
      [
        [
          (text: ' ', color: null, backgroundColor: null),
          (text: '▀', color: 'green', backgroundColor: null),
        ],
      ],
    );
  });
  test('theme colour chooses stops before tone, and plain without either', () {
    expect(
      markColour(const MarkTones(stops: stops, tone: 'green')),
      isA<MarkGradient>(),
    );
    expect(markColour(const MarkTones(tone: 'green')), isA<MarkTone>());
    expect(markColour(const MarkTones()), isA<MarkPlain>());
    expect(markColour(null), isA<MarkPlain>());
  });
  test('constant wordmark rows match OpenTUI fonts and retain both roles', () {
    final full = [
      for (final row in fullWordmark) row.map((s) => s.text).join(),
    ];
    final compact = [
      for (final row in compactWordmark) row.map((s) => s.text).join(),
    ];
    expect(full, hasLength(6));
    expect(full.map((s) => s.length).toSet(), {45});
    expect(full.first, ' ██████╗ ██╗  ██╗  ██████╗  ██████╗  ██████╗ ');
    expect(full.last, ' ╚═════╝ ╚═╝  ╚═╝  ╚═════╝  ╚═╝  ╚═╝ ╚═════╝ ');
    expect(compact, ['█▀▀ █ █ █▀█ █▀█ █▀▄', '█▄▄ █▀█ █▄█ █▀▄ █▄▀']);
    expect(fullWordmark.expand((row) => row).map((s) => s.role).toSet(), {
      0,
      1,
    });
  });
}
