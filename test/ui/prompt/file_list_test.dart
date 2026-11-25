import 'package:chord/ui/prompt/file_list.dart';
import 'package:chord/ui/prompt/mentions.dart';
import 'package:chord/ui/prompt/state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final (i, theme) in [
      ThemeData.dark(),
      ThemeData.light(),
      ThemeData.plain(),
    ].indexed) {
      testWidgets(
        'passive file/agent rows use supplied roles and bounded room theme$i $size',
        (t) async {
          final names = List.generate(
            20,
            (i) => 'path_${i.toString().padLeft(2, '0')}.dart',
          );
          var room = -1;
          await t.pumpWidget(
            Theme(
              data: theme,
              child: FileList(
                finder: FileFinder(
                  mention: const Mention(query: '', start: 0),
                  files: names,
                ),
                windowRows: size.height,
                onRoom: (n) => room = n,
              ),
            ),
            size: size,
          );
          final count = size.height ~/ 4;
          expect(room, count);
          expect(
            t.screen.lines.where((x) => x.contains('path_')),
            hasLength(count),
          );
          expect(t.screen.styleAt(2, 1), theme.focus);
          expect(t.screen.styleAt(2, 2), theme.dim);
          await t.pumpWidget(
            Theme(
              data: theme,
              child: FileList(
                finder: const FileFinder(
                  mention: AgentMention(query: '', start: 0, quoted: false),
                  files: ['parser', 'docs', 'main'],
                ),
                colors: i == 2
                    ? const {}
                    : const {'docs': Colors.cyan, 'main': Colors.red},
                windowRows: size.height,
                onRoom: (_) {},
              ),
            ),
            size: size,
          );
          expect(t.screen.styleAt(2, 1), theme.focus);
          expect(
            t.screen.styleAt(2, 2),
            i == 2 ? Style.plain : const Style(fg: Colors.cyan),
          );
          expect(t.screen.styleAt(2, 3), theme.dim);
        },
      );
    }
    testWidgets(
      'one-row slow marker preserves choice, empty marker draws, zero room reports $size',
      (t) async {
        var room = -1;
        Widget list(List<String> files) => FileList(
          finder: FileFinder(
            mention: const Mention(query: 'a', start: 0),
            files: files,
            pending: true,
            searching: true,
          ),
          windowRows: size.height,
          onRoom: (n) => room = n,
        );
        await t.pumpWidget(list(['alpha', 'beta']), size: Size(size.width, 2));
        expect(room, 1);
        expect(t.screen, shows('alpha'));
        expect(t.screen, isNot(shows('searching…')));
        await t.pumpWidget(
          list(['alpha', 'beta', 'gamma', 'delta', 'epsilon']),
          size: Size(size.width, 7),
        );
        expect(t.screen.lines.where((line) => line.isNotEmpty), hasLength(6));
        expect(t.screen, shows('searching…'));
        await t.pumpWidget(list([]), size: Size(size.width, 2));
        expect(t.screen, shows('searching…'));
        await t.resize(Size(size.width, 1));
        expect(room, 0);
        expect(t.screen.text, isEmpty);
      },
    );
  }
}
