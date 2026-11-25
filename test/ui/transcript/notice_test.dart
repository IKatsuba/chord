// From the original's tests/ui/transcript/notice_test.tsx.
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/transcript/notice.dart';
import 'package:chord/ui/transcript/selection.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../app/selection_window_test.dart';

/// The rows drawn, empty ones out.
List<String> rowsOf(WidgetTester t) => [
  for (final row in t.screen.lines)
    if (row.isNotEmpty) row,
];

void main() {
  test('a description folds each run of blank lines to one break', () {
    expect(noticeDescription('one\n\n\ntwo\n \t\nthree\n'), 'one\ntwo\nthree');
  });

  test("info's marker is dim; warning's and error's take their role", () {
    final theme = ThemeData.dark();
    expect(noticeMarker(NoticeSeverity.info, theme), theme.dim);
    expect(noticeMarker(NoticeSeverity.warning, theme), theme.warning);
    expect(noticeMarker(NoticeSeverity.error, theme), theme.error);
  });

  for (final size in const [Size(60, 12), Size(80, 24), Size(120, 40)]) {
    testWidgets('a notice is its title by ⏺, its description under it at the '
        'text column, wrapped and never cut, at $size', (t) async {
      const description =
          'The selected model does not support Auto mode; using Accept '
          'edits instead, until the model changes again.';
      await t.pumpWidget(
        const TranscriptEntry(
          NoticeEntry(
            't',
            NoticeSeverity.info,
            'Auto mode unavailable',
            description: description,
          ),
        ),
        size: size,
      );
      final rows = rowsOf(t);
      expect(rows.first, '⏺ Auto mode unavailable');
      expect(rows.skip(1).every((row) => row.startsWith('  ')), isTrue);
      expect(rows.skip(1).map((row) => row.trim()).join(' '), description);
      if (size.width == 60) expect(rows.length, greaterThan(2));
      // All of it dim, the marker too for info.
      final top = t.screen.lines.indexOf(rows.first);
      expect(t.screen.styleAt(0, top).isDim, isTrue);
      expect(t.screen.styleAt(2, top).isDim, isTrue);
    });
  }

  testWidgets("warning's and error's marker take the theme's role", (t) async {
    for (final severity in [NoticeSeverity.warning, NoticeSeverity.error]) {
      await t.pumpWidget(
        TranscriptEntry(NoticeEntry('t', severity, 'Said')),
        size: const Size(80, 24),
      );
      final top = t.screen.lines.indexWhere((row) => row.contains('Said'));
      final theme = ThemeData.dark();
      expect(
        t.screen.styleAt(0, top).fg,
        noticeMarker(severity, theme).fg,
        reason: '$severity',
      );
      expect(t.screen.styleAt(2, top).isDim, isTrue);
    }
  });

  testWidgets('a long title and description wrap without loss', (t) async {
    final title = 'A long notice title that must stay readable. ' * 5;
    final description =
        'The selected model does not support this setting; use another '
            'model or choose an available setting. ' *
        4;
    await t.pumpWidget(
      TranscriptEntry(
        NoticeEntry(
          't',
          NoticeSeverity.warning,
          title,
          description: description,
        ),
      ),
      size: const Size(80, 40),
    );
    final rows = rowsOf(t);
    expect(rows.length, greaterThan(6));
    expect(rows.skip(1).every((row) => row.startsWith('  ')), isTrue);
    expect(
      rows.join().replaceAll(RegExp(r'\s'), ''),
      '⏺$title$description'.replaceAll(RegExp(r'\s'), ''),
    );
  });

  group('tester: notice display boundaries', () {
    for (final (label, theme) in [
      ('dark', ThemeData.dark()),
      ('light', ThemeData.light()),
    ]) {
      testWidgets(
        'escape sequences style text and cannot emit terminal commands $label',
        (t) async {
          const escaped =
              '\x1b[31mred\x1b[0m\x1b[2K \x1b]8;;https://example.com\x07link\x1b]8;;\x07';
          for (final expanded in [false, true]) {
            await t.pumpWidget(
              Theme(
                data: theme,
                child: TranscriptEntry(
                  const NoticeEntry(
                    't',
                    NoticeSeverity.error,
                    escaped,
                    description: '$escaped\n\n\nFinal line',
                  ),
                  expanded: expanded,
                ),
              ),
              size: const Size(80, 24),
            );
            expect(rowsOf(t), ['⏺ red link', '  red link', '  Final line']);
          }
        },
      );
    }

    testWidgets('notice content never enters a copy', (t) async {
      final entry = NoticeEntry(
        't',
        NoticeSeverity.warning,
        '界👩‍💻é',
        description: 'Hidden from copy',
      );
      // Its rows are held, for a subagent's work drawn after it, but
      // nothing in them selects.
      final source = TranscriptSources(Object()).source(entry, width: 80);
      expect(source.codeBlocks, isEmpty);
      final connection = selectionConnection([
        const UserEntry('u', 'before'),
        entry,
      ]);
      addTearDown(connection.close);
      final writes = <String>[];
      await t.pumpWidget(
        TranscriptWindow(
          launch: selectionLaunch,
          connection: connection,
          copyOnSelect: false,
          copy: (text, _) {
            writes.add(text);
            return const copy.CopyResult.sent();
          },
        ),
        size: const Size(80, 24),
      );
      await select(t, 'Hidden from copy');
      await t.press('ctrl+shift+c');
      expect(writes, isEmpty);
    });

    testWidgets('zero and one cell resize recovers the full notice', (t) async {
      await t.pumpWidget(
        const TranscriptEntry(
          NoticeEntry(
            't',
            NoticeSeverity.info,
            '界👩‍💻é',
            description: 'Details',
          ),
        ),
      );
      for (final size in const [
        Size(0, 0),
        Size(1, 1),
        Size(120, 40),
        Size(80, 24),
      ]) {
        await t.resize(size);
        expect(t.screen.lines, hasLength(size.height));
        if (size.width > 1) expect(t.screen.text, contains('界👩‍💻é'));
      }
    });
  });
}
