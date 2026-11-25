import 'package:chord/ui/app/start_layout.dart';
import 'package:chord/ui/header/mark_rows.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  test(
    'original layout table chooses art, list rows and top from window alone',
    () {
      for (final (columns, rows, lines, framed, hints, step, count, top) in [
        (120, 40, 28, false, 1, StartStep.full, 14, 4),
        (120, 40, 5, false, 1, StartStep.full, 5, 9),
        (120, 40, 14, true, 1, StartStep.full, 14, 3),
        (80, 24, 28, false, 1, StartStep.compact, 12, 0),
        (80, 24, 14, true, 1, StartStep.compact, 9, 0),
        (59, 40, 28, false, 2, StartStep.compact, 28, 0),
        (39, 24, 28, false, 2, StartStep.line, 15, 0),
        (30, 12, 14, true, 3, StartStep.none, 1, 0),
        (30, 8, 28, false, 3, StartStep.none, 1, 0),
      ]) {
        final view = startLayout(
          columns: columns,
          rows: rows,
          lines: lines,
          framed: framed,
          hintRows: hints,
        );
        expect((view.step, view.listRows, view.top), (step, count, top));
      }
    },
  );
  test('art thresholds and line minimums match the original', () {
    for (final (columns, rows, step) in [
      (120, 32, StartStep.full),
      (120, 31, StartStep.compact),
      (60, 40, StartStep.full),
      (59, 40, StartStep.compact),
      (80, 18, StartStep.compact),
      (80, 17, StartStep.line),
      (40, 24, StartStep.compact),
      (39, 24, StartStep.line),
    ]) {
      expect(
        startLayout(columns: columns, rows: rows, lines: 5, hintRows: 1).step,
        step,
      );
    }
    expect(
      startLayout(columns: 39, rows: 10, lines: 28, hintRows: 1).step,
      StartStep.line,
    );
    expect(
      startLayout(columns: 39, rows: 9, lines: 28, hintRows: 1).step,
      StartStep.none,
    );
    for (final lines in [1, 5, 14, 15, 28, 1000]) {
      expect(
        startLayout(columns: 120, rows: 32, lines: lines, hintRows: 1).step,
        StartStep.full,
      );
      expect(
        startLayout(columns: 120, rows: 31, lines: lines, hintRows: 1).step,
        StartStep.compact,
      );
    }
    expect(
      startLayout(columns: 120, rows: 31, lines: 28, hintRows: 1).listRows,
      19,
    );
    expect(
      startLayout(columns: 80, rows: 24, lines: 13, hintRows: 1).listRows,
      13,
    );
    expect(
      startLayout(columns: 80, rows: 24, lines: 14, hintRows: 1).listRows,
      12,
    );
    expect(startLayout(columns: 80, rows: 24, lines: 1, hintRows: 1).top, 6);
  });
  test('column, list and margin remain bounded at tiny windows', () {
    for (final (columns, framed, width) in [
      (120, false, 62),
      (64, false, 62),
      (63, false, 61),
      (120, true, 84),
      (86, true, 84),
      (80, true, 78),
      (2, false, 1),
      (1, true, 1),
    ]) {
      expect(startColumn(columns, framed: framed), width);
    }
    for (final columns in [1, 30, 39, 40, 59, 60, 120]) {
      for (var rows = 1; rows <= 45; rows++) {
        for (final lines in [0, 1, 2, 14, 15, 28]) {
          final view = startLayout(
            columns: columns,
            rows: rows,
            lines: lines,
            hintRows: 2,
          );
          expect(view.listRows, greaterThanOrEqualTo(1));
          expect(view.top, greaterThanOrEqualTo(0));
        }
      }
    }
  });
  test(
    'version line cuts directory first and keeps whole trailing components',
    () {
      expect(
        versionLine(version: '0.65.0', directory: '~/src/app', width: 118),
        'v0.65.0 · ~/src/app',
      );
      expect(
        versionLine(
          version: '0.65.0',
          agent: 'claude',
          directory: '~/work/acme/services/billing/acme-api',
          width: 48,
        ),
        'v0.65.0 · claude · …/services/billing/acme-api',
      );
      expect(
        versionLine(
          version: '0.65.0',
          agent: 'claude',
          directory: '~/src/app',
          width: 10,
        ),
        'v0.65.0 · claude · …',
      );
      final whole = 'v0.65.0 · ~/界/项目';
      expect(
        versionLine(
          version: '0.65.0',
          directory: '~/界/项目',
          width: cellWidth(whole),
        ),
        whole,
      );
      expect(
        versionLine(
          version: '0.65.0',
          directory: '~/界/项目',
          width: cellWidth(whole) - 1,
        ),
        'v0.65.0 · …/项目',
      );
      expect(
        versionLine(
          version: '0.65.0',
          agent: '界',
          directory: '~/work/services/app',
          width: 20,
        ),
        'v0.65.0 · 界 · …/app',
      );
    },
  );
  test('hint wraps and wordmark uses original colour roles', () {
    const hint = '↑↓ or j/k to move · Enter or 1–9 to select · Esc to cancel';
    for (final (width, rows) in [(60, 1), (58, 1), (57, 2), (37, 2), (28, 3)]) {
      expect(hintRows(hint, width), rows);
    }
    expect(hintRows('', 10), 1);
    expect(hintRows('Esc', 0), 3);
    expect(
      wordmarkColours(const MarkGradient(['#89f5b3', '#47e7a5', '#15c7a2'])),
      ('#47e7a5', '#15c7a2'),
    );
    expect(wordmarkColours(const MarkTone('green')), ('green', 'green'));
    expect(wordmarkColours(const MarkPlain()), isNull);
  });
}
