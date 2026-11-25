import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_test.dart' show area, drag, pointer;

SelectionSource leaf(Object id, String text) =>
    SelectionSource.text(id: id, revision: 0, text: TextSpan(text));
SelectionChildDelegate delegate(List<SelectionSource> sources) =>
    SelectionChildDelegate(
      itemCount: sources.length,
      idAt: (i) => sources[i].id,
      indexOfId: (id) {
        final i = sources.indexWhere((s) => s.id == id);
        return i < 0 ? null : i;
      },
      sourceAt: (i) => sources[i],
    );

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'delegate exclusion retains wrapped rows and omits never-mounted content $size',
      (t) async {
        final c = SelectionController(), scroll = ScrollController();
        final sources = [
          for (var i = 0; i < 20; i++)
            SelectionSource.group(
              id: i,
              revision: 0,
              children: [
                SelectionSourceChild(source: leaf((i, 'before'), 'record $i')),
                SelectionSourceChild(
                  source: leaf((i, 'furniture'), 'wrapped furniture ' * 30),
                  selectable: false,
                ),
                SelectionSourceChild(source: leaf((i, 'after'), 'end $i')),
              ],
            ),
        ];
        var builds = 0;
        await t.pumpWidget(
          area(
            c,
            Column(
              children: [
                Text('header'),
                SizedBox(
                  height: 2,
                  child: ListView.builder(
                    controller: scroll,
                    selectionDelegate: delegate(sources),
                    itemCount: sources.length,
                    itemVersion: (i) => sources[i].revision,
                    itemBuilder: (_, i) {
                      builds++;
                      return Column(
                        children: [
                          for (final child in sources[i].children)
                            Text.fromSelectionSource(child),
                        ],
                      );
                    },
                  ),
                ),
                Text('draft'),
              ],
            ),
          ),
          size: size,
        );
        expect(t.screen.lines[1], 'record 0');
        expect(t.screen.lines[2], contains('wrapped furniture'));
        final before = builds;
        for (final reverse in [false, true]) {
          await drag(
            t,
            reverse ? const Offset(4, 3) : Offset.zero,
            reverse ? Offset.zero : const Offset(4, 3),
          );
          expect(
            c.snapshot()!.text,
            [
              'header',
              for (var i = 0; i < 20; i++) ...['record $i', 'end $i'],
              'draft',
            ].join('\n'),
          );
          expect(builds, before);
          expect(t.screen.styleAt(0, 2).isInverse, isFalse);
        }
        c.clear();
        await drag(t, const Offset(0, 2), const Offset(8, 2));
        expect(c.snapshot()!.text, isEmpty);
        c.dispose();
        scroll.dispose();
      },
    );

    testWidgets(
      'all disabled provider sources add no boundary between outside leaves $size',
      (t) async {
        final c = SelectionController();
        final source = SelectionSource.group(
          id: 'root',
          revision: 0,
          children: [
            SelectionSourceChild(
              source: leaf('furniture', 'excluded'),
              selectable: false,
              separatorBefore: 'wrong',
            ),
          ],
        );
        await t.pumpWidget(
          area(
            c,
            Column(
              children: [
                Text('before'),
                SizedBox(
                  height: 1,
                  child: ListView.builder(
                    itemCount: 1,
                    selectionDelegate: delegate([source]),
                    itemBuilder: (_, _) =>
                        Text.fromSelectionSource(source.children.single),
                  ),
                ),
                Text('after'),
              ],
            ),
          ),
          size: size,
        );
        await drag(t, Offset.zero, const Offset(4, 2));
        expect(c.snapshot()!.text, 'before\nafter');
        expect(t.screen.styleAt(0, 1).isInverse, isFalse);
        c.dispose();
      },
    );

    testWidgets(
      'eligibility update releases finalized and held ranges without resurrection $size',
      (t) async {
        final c = SelectionController();
        final enabled = ValueNotifier(true);
        final body = leaf('body', 'body text');
        SelectionSource? source;
        var revision = 0;
        await t.pumpWidget(
          ListenableBuilder(
            listenable: enabled,
            builder: (_) {
              source = SelectionSource.group(
                id: 'root',
                revision: revision++,
                previous: source,
                children: [
                  SelectionSourceChild(source: body, selectable: enabled.value),
                ],
              );
              return area(
                c,
                ListView.builder(
                  itemCount: 1,
                  selectionDelegate: delegate([source!]),
                  itemVersion: (_) => source!.revision,
                  itemBuilder: (_, _) => Text.fromSelectionSource(body),
                ),
              );
            },
          ),
          size: size,
        );
        for (final held in [false, true]) {
          enabled.value = true;
          await t.pump();
          if (held) {
            await t.mouse(pointer(MouseEventKind.press, 0, 0));
            await t.mouse(pointer(MouseEventKind.move, 3, 0));
          } else {
            await drag(t, Offset.zero, const Offset(3, 0));
          }
          expect(c.snapshot()!.text, 'body');
          enabled.value = false;
          expect(c.snapshot()!.phase, SelectionPhase.none);
          expect(c.snapshot()!.text, isEmpty);
          enabled.value = true;
          expect(c.snapshot()!.phase, SelectionPhase.none);
          expect(t.screen.text, contains('body text'));
          if (held) await t.mouse(pointer(MouseEventKind.release, 3, 0));
          expect(c.snapshot()!.phase, SelectionPhase.none);
        }
        c.dispose();
        enabled.dispose();
      },
    );

    testWidgets(
      'nested disabled code cannot register geometry or reveal $size',
      (t) async {
        final c = SelectionController(), scroll = ScrollController();
        final hidden = SelectionSource.markdown(
          id: 'hidden',
          revision: 0,
          text: '```\nhidden code\n```',
        );
        final visible = SelectionSource.markdown(
          id: 'visible',
          revision: 0,
          text: '```\nvisible code\n```',
        );
        final nested = SelectionSource.group(
          id: 'nested',
          revision: 0,
          children: [SelectionSourceChild(source: hidden)],
        );
        final root = SelectionSource.group(
          id: 'root',
          revision: 0,
          children: [
            SelectionSourceChild(source: nested, selectable: false),
            SelectionSourceChild(source: visible),
          ],
        );
        await t.pumpWidget(
          area(
            c,
            ListView.builder(
              itemCount: 1,
              controller: scroll,
              selectionDelegate: delegate([root]),
              itemBuilder: (_, _) => Column(
                children: [
                  Markdown.fromSelectionSource(hidden),
                  Markdown.fromSelectionSource(visible),
                ],
              ),
            ),
          ),
          size: size,
        );
        final hiddenId = hidden.codeBlocks.single.id;
        expect(root.codeBlocks.map((b) => b.id), [
          visible.codeBlocks.single.id,
        ]);
        expect(c.visibleCodeBlocks().map((g) => g.block.id), [
          visible.codeBlocks.single.id,
        ]);
        expect(c.codeBlockGeometry(hiddenId), isNull);
        expect(c.revealCodeBlock(hiddenId), isFalse);
        expect(t.screen, shows('hidden code'));
        final row = t.screen.lines.indexWhere(
          (line) => line.contains('hidden code'),
        );
        final column = t.screen.lines[row].indexOf('hidden code');
        await drag(t, Offset(column, row), Offset(column + 5, row));
        expect(c.snapshot()!.text, isEmpty);
        c.dispose();
        scroll.dispose();
      },
    );
  }
}
