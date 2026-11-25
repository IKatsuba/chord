import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

SelectionSource source({
  Object revision = 0,
  SelectionSource? previous,
  String text = '```ts\ncopy payload\n```',
}) => SelectionSource.markdown(
  id: 'markdown',
  revision: revision,
  text: text,
  copyCodeBlocks: true,
  previous: previous,
);
Offset cell(WidgetTester t, String text, {int within = 0}) {
  final y = t.screen.lines.indexWhere((line) => line.contains(text));
  expect(y, greaterThanOrEqualTo(0), reason: t.screen.text);
  return Offset(cellWidth(t.screen.lines[y].split(text).first) + within, y);
}

MouseEvent primary(MouseEventKind kind, Offset at) =>
    MouseEvent(kind, position: at, button: MouseButton.primary);
Future<void> click(WidgetTester t, Offset at) async {
  await t.mouse(primary(MouseEventKind.press, at));
  await t.mouse(primary(MouseEventKind.release, at));
}

class _Clip extends SingleChildRenderObjectWidget {
  const _Clip(this.columns, {required super.child});
  final int columns;
  @override
  _ClipBox createRenderObject(BuildContext context) => _ClipBox(columns);
  @override
  void updateRenderObject(BuildContext context, _ClipBox box) =>
      box.columns = columns;
}

class _ClipBox extends RenderProxyBox {
  _ClipBox(this.columns);
  int columns;
  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(_ClipBox);
  @override
  void visitPaintChildren(Offset origin, Rect clip, PaintChildVisitor visitor) {
    final value = child;
    if (value != null) {
      visitor(
        value,
        origin,
        clip.intersect(Rect(origin.x, origin.y, columns, size.height)),
      );
    }
  }
}

class _Unknown extends SingleChildRenderObjectWidget {
  const _Unknown({required super.child});
  @override
  RenderProxyBox createRenderObject(BuildContext context) => _UnknownBox();
}

class _UnknownBox extends RenderProxyBox {}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'nested area defines button boundary independently of outer disabled ancestors $size',
      (t) async {
        final outer = SelectionController(), inner = SelectionController();
        addTearDown(outer.dispose);
        addTearDown(inner.dispose);
        final allowed = source();
        final blocked = SelectionSource.markdown(
          id: 'inner-disabled',
          revision: 0,
          text: '```\nhidden payload\n```',
          copyCodeBlocks: true,
        );
        final copies = <String>[];
        await t.pumpWidget(
          SelectionArea(
            controller: outer,
            selectionStyle: const Style(inverse: true),
            child: Column(
              children: [
                Text('outer words'),
                SelectionContainer.disabled(
                  child: SelectionArea(
                    controller: inner,
                    selectionStyle: const Style(inverse: true),
                    child: Column(
                      children: [
                        Markdown.fromSelectionSource(
                          allowed,
                          onCopyCodeBlock: (b) => copies.add(b.text),
                        ),
                        SelectionContainer.disabled(
                          child: Markdown.fromSelectionSource(
                            blocked,
                            onCopyCodeBlock: (b) => copies.add(b.text),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          size: size,
        );
        expect(outer.visibleCodeBlocks(), isEmpty);
        expect(inner.visibleCodeBlocks().map((g) => g.block.id), [
          allowed.codeBlocks.single.id,
        ]);
        final outside = cell(t, 'outer words');
        await t.mouse(primary(MouseEventKind.press, outside));
        await t.mouse(
          primary(MouseEventKind.move, Offset(outside.x + 2, outside.y)),
        );
        await t.mouse(
          primary(MouseEventKind.release, Offset(outside.x + 2, outside.y)),
        );
        final text = cell(t, 'copy payload');
        await t.mouse(primary(MouseEventKind.press, text));
        await t.mouse(primary(MouseEventKind.move, Offset(text.x + 2, text.y)));
        await t.mouse(
          primary(MouseEventKind.release, Offset(text.x + 2, text.y)),
        );
        expect(inner.snapshot()!.text, 'cop');
        expect(outer.snapshot()!.text, 'out');
        await click(t, cell(t, '[copy]'));
        expect(copies, ['copy payload']);
        expect(inner.value.phase, SelectionPhase.none);
        expect(outer.snapshot()!.text, 'out');
        await t.mouse(primary(MouseEventKind.press, text));
        await t.mouse(primary(MouseEventKind.move, Offset(text.x + 2, text.y)));
        await t.mouse(
          primary(MouseEventKind.release, Offset(text.x + 2, text.y)),
        );
        final hidden = cell(t, 'hidden payload');
        final y = hidden.y - 1,
            x = cellWidth(t.screen.lines[hidden.y - 1].split('[copy]').first);
        await click(t, Offset(x, y));
        expect(copies, ['copy payload']);
        expect(inner.snapshot()!.text, 'cop');
        expect(outer.snapshot()!.text, 'out');
      },
    );
    testWidgets(
      'authoritative provider gates mounted false child without wrapper and fresh capture $size',
      (t) async {
        final excluded = SelectionSource.markdown(
          id: 'excluded',
          revision: 0,
          text: '```\nblocked payload\n```',
          copyCodeBlocks: true,
        );
        final allowed = SelectionSource.markdown(
          id: 'allowed',
          revision: 0,
          text: '```\nallowed payload\n```',
          copyCodeBlocks: true,
        );
        final tick = ValueNotifier(0),
            scroll = ScrollController(),
            selection = SelectionController();
        addTearDown(tick.dispose);
        addTearDown(scroll.dispose);
        addTearDown(selection.dispose);
        SelectionSource group(int revision, {SelectionSource? previous}) =>
            SelectionSource.group(
              id: 'provider',
              revision: revision,
              previous: previous,
              children: [
                SelectionSourceChild(
                  source: excluded,
                  selectable: revision.isOdd,
                ),
                SelectionSourceChild(source: allowed),
              ],
            );
        var root = group(0);
        final copies = <String>[];
        await t.pumpWidget(
          SelectionArea(
            controller: selection,
            selectionStyle: const Style(inverse: true),
            child: ListenableBuilder(
              listenable: tick,
              builder: (_) {
                if (root.revision != tick.value) {
                  root = group(tick.value, previous: root);
                }
                return SizedBox(
                  height: 8,
                  child: ListView.builder(
                    controller: scroll,
                    itemCount: 1,
                    selectionDelegate: SelectionChildDelegate(
                      itemCount: 1,
                      idAt: (_) => root.id,
                      indexOfId: (id) => id == root.id ? 0 : null,
                      sourceAt: (_) => root,
                    ),
                    itemVersion: (_) => root.revision,
                    itemBuilder: (_, _) => Column(
                      children: [
                        Markdown.fromSelectionSource(
                          excluded,
                          onCopyCodeBlock: (b) => copies.add(b.text),
                        ),
                        Markdown.fromSelectionSource(
                          allowed,
                          onCopyCodeBlock: (b) => copies.add(b.text),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          size: size,
        );
        expect(selection.visibleCodeBlocks().map((g) => g.block.id), [
          allowed.codeBlocks.single.id,
        ]);
        final text = cell(t, 'allowed payload');
        await t.mouse(primary(MouseEventKind.press, text));
        await t.mouse(primary(MouseEventKind.move, Offset(text.x + 2, text.y)));
        await t.mouse(
          primary(MouseEventKind.release, Offset(text.x + 2, text.y)),
        );
        expect(selection.snapshot()!.text, 'all');
        final at = cell(t, '[copy]');
        await click(t, at);
        expect(copies, isEmpty);
        expect(selection.snapshot()!.text, 'all');
        tick.value = 1;
        await t.pump();
        expect(selection.visibleCodeBlocks().map((g) => g.block.id), [
          excluded.codeBlocks.single.id,
          allowed.codeBlocks.single.id,
        ]);
        await click(t, at);
        expect(copies, ['blocked payload']);
        await t.mouse(primary(MouseEventKind.press, at));
        tick.value = 2;
        await t.pump();
        tick.value = 3;
        await t.pump();
        await t.mouse(primary(MouseEventKind.release, at));
        expect(copies, ['blocked payload']);
        await click(t, at);
        expect(copies, hasLength(2));
        await t.pumpWidget(
          Markdown.fromSelectionSource(
            excluded,
            onCopyCodeBlock: (b) => copies.add(b.text),
          ),
          size: size,
        );
        await click(t, cell(t, '[copy]'));
        expect(copies, hasLength(3));
      },
    );
    testWidgets(
      'provider eligibility also gates fallback without a SelectionArea $size',
      (t) async {
        final excluded = SelectionSource.markdown(
          id: 'excluded',
          revision: 0,
          text: '```\nblocked payload\n```',
          copyCodeBlocks: true,
        );
        final allowed = SelectionSource.markdown(
          id: 'allowed',
          revision: 0,
          text: '```\nallowed payload\n```',
          copyCodeBlocks: true,
        );
        final root = SelectionSource.group(
          id: 'root',
          revision: 0,
          children: [
            SelectionSourceChild(source: excluded, selectable: false),
            SelectionSourceChild(source: allowed),
          ],
        );
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final copies = <String>[];
        await t.pumpWidget(
          SizedBox(
            height: 8,
            child: ListView.builder(
              controller: scroll,
              itemCount: 1,
              selectionDelegate: SelectionChildDelegate(
                itemCount: 1,
                idAt: (_) => root.id,
                indexOfId: (id) => id == root.id ? 0 : null,
                sourceAt: (_) => root,
              ),
              itemBuilder: (_, _) => Column(
                children: [
                  Markdown.fromSelectionSource(
                    excluded,
                    onCopyCodeBlock: (b) => copies.add(b.text),
                  ),
                  Markdown.fromSelectionSource(
                    allowed,
                    onCopyCodeBlock: (b) => copies.add(b.text),
                  ),
                ],
              ),
            ),
          ),
          size: size,
        );
        await click(t, cell(t, '[copy]'));
        expect(copies, isEmpty);
        final text = cell(t, 'allowed payload');
        final y = text.y - 1;
        final x = cellWidth(t.screen.lines[y].split('[copy]').first);
        await click(t, Offset(x, y));
        expect(copies, ['allowed payload']);
      },
    );
    testWidgets(
      'detached enclosing range owner cannot regain button eligibility $size',
      (t) async {
        final selection = SelectionController();
        addTearDown(() {
          if (!selection.isDisposed) selection.dispose();
        });
        var copies = 0;
        await t.pumpWidget(
          SelectionArea(
            controller: selection,
            selectionStyle: const Style(inverse: true),
            child: Markdown.fromSelectionSource(
              source(),
              onCopyCodeBlock: (_) => copies++,
            ),
          ),
          size: size,
        );
        final at = cell(t, '[copy]');
        await t.mouse(primary(MouseEventKind.press, at));
        selection.dispose();
        await t.mouse(primary(MouseEventKind.release, at));
        expect(copies, 0);
        await click(t, at);
        expect(copies, 0);
      },
    );
    testWidgets(
      'explicit disabled ancestry rejects mounted button in area and standalone $size',
      (t) async {
        final selection = SelectionController();
        addTearDown(selection.dispose);
        final s = source();
        var copies = 0;
        Widget content() => SelectionContainer.disabled(
          child: Markdown.fromSelectionSource(
            s,
            onCopyCodeBlock: (_) => copies++,
          ),
        );
        await t.pumpWidget(
          SelectionArea(
            controller: selection,
            selectionStyle: const Style(inverse: true),
            child: Column(children: [content(), Text('eligible text')]),
          ),
          size: size,
        );
        expect(selection.visibleCodeBlocks(), isEmpty);
        final text = cell(t, 'eligible text');
        await t.mouse(primary(MouseEventKind.press, text));
        await t.mouse(primary(MouseEventKind.move, Offset(text.x + 2, text.y)));
        await t.mouse(
          primary(MouseEventKind.release, Offset(text.x + 2, text.y)),
        );
        await click(t, cell(t, '[copy]'));
        expect(copies, 0);
        expect(selection.snapshot()!.text, 'eli');
        await t.pumpWidget(content(), size: size);
        await click(t, cell(t, '[copy]'));
        expect(copies, 0);
        await t.pumpWidget(
          Markdown.fromSelectionSource(s, onCopyCodeBlock: (_) => copies++),
          size: size,
        );
        await click(t, cell(t, '[copy]'));
        expect(copies, 1);
      },
    );
    testWidgets(
      'only full word button cells click and text drag never activates $size',
      (t) async {
        final s = source();
        final copies = <MarkdownCodeBlock>[];
        final selection = SelectionController();
        addTearDown(selection.dispose);
        await t.pumpWidget(
          SelectionArea(
            controller: selection,
            selectionStyle: const Style(inverse: true),
            child: Markdown.fromSelectionSource(s, onCopyCodeBlock: copies.add),
          ),
          size: size,
        );
        final at = cell(t, '[copy]');
        for (var x = 0; x < 6; x++) {
          await click(t, Offset(at.x + x, at.y));
        }
        expect(copies, hasLength(6));
        expect(copies.map((b) => b.text), everyElement('copy payload'));
        for (final x in [-1, 6]) {
          await click(t, Offset(at.x + x, at.y));
        }
        await t.mouse(
          MouseEvent(
            MouseEventKind.wheel,
            position: at,
            scrollDelta: const Offset(0, 1),
          ),
        );
        expect(copies, hasLength(6));
        final text = cell(t, 'copy payload');
        await t.mouse(primary(MouseEventKind.press, text));
        await t.mouse(primary(MouseEventKind.move, at));
        await t.mouse(primary(MouseEventKind.release, at));
        expect(copies, hasLength(6));
      },
    );
    testWidgets('button press clears range without taking editor focus $size', (
      t,
    ) async {
      final s = source(text: '```\n\tfirst\n\nlast\n```');
      final selection = SelectionController();
      final editor = TextAreaController();
      addTearDown(selection.dispose);
      addTearDown(editor.dispose);
      final copies = <String>[];
      await t.pumpWidget(
        SelectionArea(
          controller: selection,
          selectionStyle: const Style(inverse: true),
          child: Column(
            children: [
              Markdown.fromSelectionSource(
                s,
                onCopyCodeBlock: (block) => copies.add(block.text),
              ),
              TextArea(controller: editor, autofocus: true),
            ],
          ),
        ),
        size: size,
      );
      final focus = t.focusManager.primaryFocus;
      final first = cell(t, 'first');
      await t.mouse(primary(MouseEventKind.press, first));
      await t.mouse(primary(MouseEventKind.move, Offset(first.x + 4, first.y)));
      await t.mouse(
        primary(MouseEventKind.release, Offset(first.x + 4, first.y)),
      );
      expect(selection.snapshot()!.text, 'first');
      final at = cell(t, '[copy]');
      await t.mouse(primary(MouseEventKind.press, at));
      expect(selection.value.phase, SelectionPhase.none);
      expect(copies, isEmpty);
      await t.mouse(primary(MouseEventKind.release, at));
      expect(copies, ['\tfirst\n\nlast']);
      expect(t.focusManager.primaryFocus, same(focus));
    });
    testWidgets(
      'range-clear observer can replace button down with a fresh capture $size',
      (t) async {
        final selection = SelectionController();
        addTearDown(selection.dispose);
        var replace = false, copies = 0;
        late Offset at;
        await t.pumpWidget(
          SelectionArea(
            controller: selection,
            selectionStyle: const Style(inverse: true),
            onSelectionChanged: (value) {
              if (replace && value.phase == SelectionPhase.none) {
                replace = false;
                t.host.handleMouse(primary(MouseEventKind.press, at));
              }
            },
            child: Markdown.fromSelectionSource(
              source(),
              onCopyCodeBlock: (_) => copies++,
            ),
          ),
          size: size,
        );
        final text = cell(t, 'copy payload');
        await t.mouse(primary(MouseEventKind.press, text));
        await t.mouse(primary(MouseEventKind.move, Offset(text.x + 3, text.y)));
        await t.mouse(
          primary(MouseEventKind.release, Offset(text.x + 3, text.y)),
        );
        at = cell(t, '[copy]');
        replace = true;
        await t.mouse(primary(MouseEventKind.press, at));
        await t.mouse(primary(MouseEventKind.release, at));
        expect(copies, 1);
        await t.mouse(primary(MouseEventKind.press, at));
        await t.mouse(primary(MouseEventKind.release, Offset(at.x, at.y + 1)));
        expect(copies, 1);
      },
    );
    testWidgets('motion outside and back never clicks $size', (t) async {
      var copies = 0;
      await t.pumpWidget(
        Markdown.fromSelectionSource(
          source(),
          onCopyCodeBlock: (_) => copies++,
        ),
        size: size,
      );
      final at = cell(t, '[copy]');
      await t.mouse(primary(MouseEventKind.press, at));
      await t.mouse(primary(MouseEventKind.move, Offset(0, size.height - 1)));
      await t.mouse(primary(MouseEventKind.move, at));
      await t.mouse(primary(MouseEventKind.release, at));
      expect(copies, 0);
      await click(t, at);
      expect(copies, 1);
    });
    testWidgets(
      'revision replacement, reflow away and disposal cancel old click $size',
      (t) async {
        final initial = source();
        final value = ValueNotifier((initial, 0));
        addTearDown(value.dispose);
        final copies = <MarkdownCodeBlock>[];
        await t.pumpWidget(
          ListenableBuilder(
            listenable: value,
            builder: (_) => Padding(
              padding: EdgeInsets.only(left: value.value.$2),
              child: Markdown.fromSelectionSource(
                value.value.$1,
                key: const ValueKey('markdown'),
                onCopyCodeBlock: copies.add,
              ),
            ),
          ),
          size: size,
        );
        final at = cell(t, '[copy]');
        await t.mouse(primary(MouseEventKind.press, at));
        final next = source(revision: 1, previous: initial);
        expect(next.codeBlocks.single.id, initial.codeBlocks.single.id);
        value.value = (next, 0);
        await t.pump();
        await t.mouse(primary(MouseEventKind.release, at));
        expect(copies, isEmpty);
        await t.mouse(primary(MouseEventKind.press, at));
        value.value = (next, 4);
        await t.pump();
        value.value = (next, 0);
        await t.pump();
        await t.mouse(primary(MouseEventKind.release, at));
        expect(copies, isEmpty);
        await click(t, at);
        expect(copies.single.revision, 1);
        await t.mouse(primary(MouseEventKind.press, at));
        await t.pumpWidget(const SizedBox());
        await t.mouse(primary(MouseEventKind.release, at));
        expect(copies, hasLength(1));
      },
    );
    testWidgets(
      'one known covered letter suppresses the whole button until recovery $size',
      (t) async {
        final covered = ValueNotifier(true);
        addTearDown(covered.dispose);
        var copies = 0;
        final s = source(text: '```ts\nx\n```');
        await t.pumpWidget(
          ListenableBuilder(
            listenable: covered,
            builder: (_) => Stack(
              children: [
                Markdown.fromSelectionSource(
                  s,
                  onCopyCodeBlock: (_) => copies++,
                ),
                if (covered.value)
                  Positioned(left: 9, top: 0, child: Text('X')),
              ],
            ),
          ),
          size: size,
        );
        final at = const Offset(7, 0);
        await click(t, at);
        expect(copies, 0);
        covered.value = false;
        await t.pump();
        await click(t, at);
        expect(copies, 1);
      },
    );
    testWidgets(
      'one clipped letter suppresses full button and unknown coverage never guesses $size',
      (t) async {
        final columns = ValueNotifier(12);
        addTearDown(columns.dispose);
        final s = source(text: '```ts\nx\n```');
        var copies = 0;
        await t.pumpWidget(
          ListenableBuilder(
            listenable: columns,
            builder: (_) => _Clip(
              columns.value,
              child: Markdown.fromSelectionSource(
                s,
                onCopyCodeBlock: (_) => copies++,
              ),
            ),
          ),
          size: size,
        );
        await click(t, const Offset(7, 0));
        expect(copies, 0);
        columns.value = 15;
        await t.pump();
        await click(t, const Offset(7, 0));
        expect(copies, 1);
        final unknown = ValueNotifier(true);
        addTearDown(unknown.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: unknown,
            builder: (_) => Stack(
              children: [
                Markdown.fromSelectionSource(
                  s,
                  onCopyCodeBlock: (_) => copies++,
                ),
                if (unknown.value)
                  Positioned(
                    left: 0,
                    top: 1,
                    child: _Unknown(child: SizedBox(width: 1, height: 1)),
                  ),
              ],
            ),
          ),
          size: size,
        );
        await click(t, const Offset(7, 0));
        expect(copies, 1);
        unknown.value = false;
        await t.pump();
        await click(t, const Offset(7, 0));
        expect(copies, 2);
      },
    );
    testWidgets(
      'visible-only Markdown outside lazy list uses live framework descriptors $size',
      (t) async {
        final selection = SelectionController(), scroll = ScrollController();
        final shown = ValueNotifier(true);
        addTearDown(selection.dispose);
        addTearDown(scroll.dispose);
        addTearDown(shown.dispose);
        final text = SelectionSource.text(
          id: 'listed',
          revision: 0,
          text: const TextSpan('listed plain text'),
        );
        final outside = source(text: '```\nvisible-only code\n```');
        final delegate = SelectionChildDelegate(
          itemCount: 1,
          idAt: (_) => text.id,
          indexOfId: (id) => id == text.id ? 0 : null,
          sourceAt: (_) => text,
        );
        final copies = <String>[];
        await t.pumpWidget(
          SelectionArea(
            controller: selection,
            selectionStyle: const Style(inverse: true),
            child: ListenableBuilder(
              listenable: shown,
              builder: (_) => Column(
                children: [
                  SizedBox(
                    height: 3,
                    child: ListView.builder(
                      controller: scroll,
                      itemCount: 1,
                      selectionDelegate: delegate,
                      itemBuilder: (_, _) => Text.fromSelectionSource(text),
                    ),
                  ),
                  if (shown.value)
                    Markdown.fromSelectionSource(
                      outside,
                      onCopyCodeBlock: (b) => copies.add(b.text),
                    ),
                ],
              ),
            ),
          ),
          size: size,
        );
        expect(selection.visibleCodeBlocks().map((g) => g.block.id), [
          outside.codeBlocks.single.id,
        ]);
        await click(t, cell(t, '[copy]'));
        expect(copies, ['visible-only code']);
        shown.value = false;
        await t.pump();
        expect(selection.visibleCodeBlocks(), isEmpty);
        expect(outside.codeBlocks.single.complete, isTrue);
      },
    );
    testWidgets(
      'copy callback can start next capture without old-up cleanup cancelling it $size',
      (t) async {
        var copies = 0;
        late Offset at;
        await t.pumpWidget(
          Markdown.fromSelectionSource(
            source(),
            onCopyCodeBlock: (_) {
              copies++;
              if (copies == 1) {
                t.host.handleMouse(primary(MouseEventKind.press, at));
              }
            },
          ),
          size: size,
        );
        at = cell(t, '[copy]');
        await click(t, at);
        expect(copies, 1);
        await t.mouse(primary(MouseEventKind.release, at));
        expect(copies, 2);
      },
    );
    for (final (name, palette) in [
      ('dark', ThemeData.dark()),
      ('light', ThemeData.light()),
      ('plain', ThemeData.plain()),
    ]) {
      testWidgets(
        'picked code border label/button use current $name presentation $size',
        (t) async {
          final s = source(text: '```ts\nx\n```');
          final picked = ValueNotifier<CodeBlockId?>(null);
          addTearDown(picked.dispose);
          await t.pumpWidget(
            Theme(
              data: palette,
              child: ListenableBuilder(
                listenable: picked,
                builder: (_) => Markdown.fromSelectionSource(
                  s,
                  selectedCodeBlock: picked.value,
                  onCopyCodeBlock: (_) {},
                ),
              ),
            ),
            size: size,
          );
          expect(t.screen.styleAt(0, 0), palette.border);
          final at = cell(t, '[copy]');
          expect(t.screen.styleAt(at.x, at.y).isBold, isFalse);
          picked.value = s.codeBlocks.single.id;
          await t.pump();
          expect(t.screen.styleAt(0, 0), palette.accent);
          expect(t.screen.styleAt(2, 0), palette.accent);
          expect(
            t.screen.styleAt(at.x, at.y),
            palette.accent.merge(Style.bold),
          );
        },
      );
    }
  }
}
