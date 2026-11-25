// Original dialogs/permission_test.ts, excluding the M4 save box and Yoga layout.
import 'dart:math';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/dialogs/permission.dart';
import 'package:chord/ui/transcript/message.dart' show wrapLine;
import 'package:chord/ui/transcript/tools/paths.dart';
import 'package:chord/ui/transcript/tools/diff.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

final allow = acp.PermissionOption.fromJson({
  'optionId': 'allow',
  'name': 'Allow',
  'kind': 'allow_once',
});
final always = acp.PermissionOption.fromJson({
  'optionId': 'always',
  'name': 'Always allow',
  'kind': 'allow_always',
});
final deny = acp.PermissionOption.fromJson({
  'optionId': 'deny',
  'name': 'Deny',
  'kind': 'reject_once',
});
final write = PermissionWait(
  'p1',
  title: 'Write notes.txt',
  options: [allow, always, deny],
);

List<List<int>> pages(int total, int room, ScrollStep step, int from) {
  final seen = <List<int>>[];
  for (var top = from, last = -1; top != last;) {
    final view = requestView(total, room, top);
    seen.add(List.generate(view.shown, (i) => view.top + i));
    last = top;
    top = requestStep(step, total, room, top);
  }
  return seen;
}

void main() {
  test('oldest request and agent options retain their order', () {
    final second = PermissionWait('p2', options: [allow]);
    expect(
      askedPermission(AwaitingPermission('t', 0, [write, second])),
      same(write),
    );
    expect(askedPermission(const Working('t', 0)), isNull);
    expect(askedPermission(const Idle()), isNull);
    expect(askedPermission(const AwaitingPermission('t', 0, [])), isNull);
    expect(choicesFor(write), [
      (key: 'allow', label: '1. Allow', value: 'allow'),
      (key: 'always', label: '2. Always allow', value: 'always'),
      (key: 'deny', label: '3. Deny', value: 'deny'),
    ]);
    expect(choicesFor(PermissionWait('p', options: [deny])), [
      (key: 'deny', label: '1. Deny', value: 'deny'),
    ]);
  });
  test(
    'locations omit title suffix and execute locations use directory display',
    () {
      PermissionWait at(String? title, List<String> paths, [String? kind]) =>
          PermissionWait(
            'p',
            title: title,
            kind: kind,
            locations: [
              for (final path in paths)
                acp.ToolCallLocation.fromJson({'path': path}),
            ],
          );
      expect(locationsShown(at('Write notes.txt', ['notes.txt'])), isEmpty);
      expect(locationsShown(at('Edit file', ['src/a.ts'])), ['src/a.ts']);
      expect(locationsShown(at('Move a.ts', ['a.ts', 'b.ts'])), ['b.ts']);
      expect(locationsShown(at(null, ['a.ts'])), ['a.ts']);
      final paths = pathView(
        '/tmp/qa-home/src/app',
        '/tmp/qa-home',
        real: (path) => path.replaceFirst('/tmp/', '/private/tmp/'),
      );
      expect(
        locationsShown(
          at('Bash bun test', ['/private/tmp/qa-home/src/app'], 'execute'),
          paths,
        ),
        ['in ~/src/app'],
      );
      expect(locationsShown(at('Bash', ['/srv'], 'execute'), paths), [
        'in /srv',
      ]);
      expect(locationsShown(at('Edit', ['/srv/a.ts'], 'edit'), paths), [
        '/srv/a.ts',
      ]);
      expect(locationsShown(at('Bash', ['/srv'], 'execute')), ['in /srv']);
    },
  );
  test('raw input is unquoted strings and compact nested JSON', () {
    List<String> input(Object? raw) =>
        inputLines(PermissionWait('p', rawInput: raw));
    expect(
      input({
        'command': 'tail -f dev.log',
        'timeout_ms': 600000,
        'follow': true,
        'last': null,
      }),
      [
        'command: tail -f dev.log',
        'timeout_ms: 600000',
        'follow: true',
        'last: null',
      ],
    );
    expect(
      input({
        'paths': ['a.ts', 'b.ts'],
        'env': {'CI': '1'},
      }),
      ['paths: ["a.ts","b.ts"]', 'env: {"CI":"1"}'],
    );
    expect(input('ls -la'), ['ls -la']);
    expect(input([1, 2]), ['[1,2]']);
    expect(input(null), isEmpty);
    expect(input({}), isEmpty);
  });
  test(
    'request pins first title row and wraps locations and indented input',
    () {
      final request = requestRows(
        PermissionWait(
          'p',
          title: 'Write a file whose title runs on',
          locations: [
            acp.ToolCallLocation.fromJson({'path': 'docs/a.md'}),
          ],
          rawInput: {
            'content': 'one two three four\n\nfive',
            'mode': 'overwrite',
          },
        ),
        16,
      );
      expect(request.pinned, 'Write a file');
      expect(
        [
          for (final row in request.rows.cast<RequestText>())
            (row.text, row.kind),
        ],
        [
          ('whose title runs', 'title'),
          ('on', 'title'),
          ('docs/a.md', 'location'),
          ('content: one', 'input'),
          ('two three four', 'input'),
          ('', 'input'),
          ('five', 'input'),
          ('mode:', 'input'),
          ('overwrite', 'input'),
        ],
      );
      final title = requestRows(
        const PermissionWait('p', title: 'Write a long title'),
        20,
        titleWidth: 10,
      );
      expect(title.pinned, 'Write a');
      expect((title.rows.single as RequestText).text, 'long title');
      expect(requestRows(const PermissionWait('p'), 0).pinned, 'T');
    },
  );
  test('wrapping reserves clamped indentation for every row', () {
    final title = requestRows(
      const PermissionWait('p', title: '  abc def ghi'),
      8,
    );
    expect(title.pinned, '  abc');
    expect(
      [for (final row in title.rows.cast<RequestText>()) row.text],
      ['def', 'ghi'],
    );
    final over = requestRows(
      const PermissionWait('p', title: '          abc'),
      4,
    );
    expect(over.pinned, '   a');
    expect(
      [for (final row in over.rows.cast<RequestText>()) row.text],
      ['b', 'c'],
    );
    final input = requestRows(
      const PermissionWait('p', rawInput: '  abc def ghi'),
      10,
    );
    expect(
      [for (final row in input.rows.cast<RequestText>()) row.text],
      ['  abc', 'def', 'ghi'],
    );
  });

  test('a diff row drops the space at its break, as wrap-ansi', () {
    // Room 10: two rows, not keepSpaces' three that carry the space over.
    final view = diffTexts('', 'abcdefghij abcdefghij\n').view();
    expect(requestHeight([RequestDiff(ToolDiffView('file', view))], 16), 2);
  });

  for (final source in ['abcdefghij abcdefghij', 'a\tb\tcdefghijk', '界 界界界']) {
    for (final width in [0, 1, 5, 6, 16]) {
      testWidgets(
        'diff physical height matches the original and the renderer for '
        '$source in $width',
        (t) async {
          final view = diffTexts('', '$source\n').view();
          final request = RequestDiff(ToolDiffView('file', view));
          await t.pumpWidget(
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: inputIndent),
                  child: Diff.fromView(
                    view,
                    showTitle: false,
                    wrap: DiffWrap.wrapAnsi,
                  ),
                ),
                Text('END'),
              ],
            ),
            size: Size(width, 100),
          );
          // Inspect layout even at zero width, where the marker cannot paint.
          RenderBox? diff;
          void find(Element element) {
            if (element.widget is Diff) diff = element.findRenderObject();
            element.visitChildren(find);
          }

          find(t.host.rootElement);
          // The original: wrapLine per code line, in max(room, 1).
          final room = max(width - inputIndent - view.numberWidth - 3, 1);
          final original = view.rows.fold<int>(
            0,
            (n, line) =>
                n +
                (line is DiffLine
                    ? wrapLine(
                        TextSpan(line.text.replaceAll('\t', '  ')),
                        room,
                      ).length
                    : 1),
          );
          expect(requestHeight([request], width), original);
          expect(requestHeight([request], width), diff!.size.height);
        },
      );
    }
  }

  test('hidden rows and rules name counts, direction and fitting key', () {
    expect(hiddenRows(40, 0, 5), (above: 0, below: 35));
    expect(hiddenRows(40, 12, 4), (above: 12, below: 24));
    expect(hiddenRows(40, 35, 5), (above: 35, below: 0));
    expect(hiddenRows(40, 39, 0), (above: 39, below: 1));
    expect(
      requestRule('↓', 37, 'pagedown', 48),
      '── ↓ 37 lines below · pagedown to scroll ───────',
    );
    expect(
      requestRule('↑', 1, 'pageup', 40),
      '── ↑ 1 line above · pageup to scroll ───',
    );
    expect(requestRule('↓', 37, 'pagedown', 24), '── ↓ 37 lines below ────');
    expect(requestRule('↓', 2, null, 24), '── ↓ 2 lines below ─────');
  });
  test('request views share room with top and bottom rules', () {
    expect(requestView(42, 6, 0), (
      top: 0,
      shown: 5,
      above: false,
      below: true,
    ));
    expect(requestView(42, 6, 5), (top: 5, shown: 4, above: true, below: true));
    expect(requestView(42, 6, 37), (
      top: 37,
      shown: 5,
      above: true,
      below: false,
    ));
    expect(requestView(42, 6, 38).top, 37);
    expect(requestView(5, 6, 3), (
      top: 0,
      shown: 5,
      above: false,
      below: false,
    ));
    expect(requestView(42, double.nan, 3), (
      top: 0,
      shown: 42,
      above: false,
      below: false,
    ));
    expect(requestView(42, 0, 0), (
      top: 0,
      shown: 0,
      above: false,
      below: false,
    ));
  });
  test('paging down and up reaches every physical row', () {
    for (final (total, room) in [(42, 6), (42, 20), (30, 3), (7, 4)]) {
      for (final (step, from) in [
        (ScrollStep.pageDown, 0),
        (ScrollStep.pageUp, requestStep(ScrollStep.bottom, total, room, 0)),
      ]) {
        expect(
          pages(total, room, step, from).expand((rows) => rows).toSet(),
          hasLength(total),
        );
      }
    }
    final down = pages(42, 6, ScrollStep.pageDown, 0);
    expect(down.take(3), [
      [0, 1, 2, 3, 4],
      [5, 6, 7, 8],
      [9, 10, 11, 12],
    ]);
    expect(down.last, [37, 38, 39, 40, 41]);
    expect(requestStep(ScrollStep.pageUp, 42, 6, 5), 0);
    expect(requestStep(ScrollStep.pageUp, 42, 6, 37), 33);
    expect(requestStep(ScrollStep.lineDown, 42, 6, 5), 6);
    expect(requestStep(ScrollStep.lineUp, 42, 6, 5), 4);
  });
  test('one and two row rooms preserve a row and page without gaps', () {
    expect(requestView(42, 2, 0), (
      top: 0,
      shown: 1,
      above: false,
      below: true,
    ));
    expect(requestView(42, 2, 41), (
      top: 41,
      shown: 1,
      above: true,
      below: false,
    ));
    expect(requestStep(ScrollStep.pageDown, 42, 2, 0), 1);
    expect(requestView(42, 1, 3), (
      top: 3,
      shown: 1,
      above: false,
      below: false,
    ));
    expect(requestStep(ScrollStep.pageDown, 42, 1, 3), 4);
    expect(requestStep(ScrollStep.bottom, 42, 1, 3), 41);
    expect(requestStep(ScrollStep.top, 42, 1, 3), 0);
    expect(requestStep(ScrollStep.lineUp, 42, 1, 0), 0);
  });
  test('one-row counts keep stable title room and omit key names', () {
    expect(requestCount((above: 0, below: 41)), '↓ 41 lines below');
    expect(requestCount((above: 41, below: 0)), '↑ 41 lines above');
    expect(requestCount((above: 1, below: 0)), '↑ 1 line above');
    expect(requestCount((above: 3, below: 38)), '↑ 3 above · ↓ 38 below');
    final room = countRoom(42);
    expect(room, '↑ 99 above · ↓ 99 below'.length);
    for (final (above, below) in [(0, 41), (1, 40), (20, 21), (41, 0)]) {
      expect(
        cellWidth(requestCount((above: above, below: below))),
        lessThanOrEqualTo(room),
      );
    }
  });
  test('diff rows count wrapped source and label multiple files only', () {
    final first = acp.ToolCallContent.fromJson({
      'type': 'diff',
      'path': '/project/a.ts',
      'oldText': 'old\n',
      'newText': 'new\n',
    });
    final second = acp.ToolCallContent.fromJson({
      'type': 'diff',
      'path': '/project/b.ts',
      'newText': 'x' * 100 + '\n',
    });
    final rows = requestRows(
      PermissionWait('p', title: 'Update files', content: [first, second]),
      30,
    ).rows;
    expect(
      [
        for (final row in rows.whereType<RequestText>())
          if (row.kind == 'location') row.text,
      ],
      ['/project/a.ts', '/project/b.ts'],
    );
    expect(requestHeight(rows, 30), 10);
    final single = requestRows(PermissionWait('p', content: [first]), 30).rows;
    expect(
      single.whereType<RequestText>().any((row) => row.kind == 'location'),
      isFalse,
    );
    expect(requestHeight(single, 30), 3);
  });
}
