import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import 'markdown_controls_test.dart' show cell, primary, click;

SelectionSource source({
  Object revision = 0,
  SelectionSource? previous,
  String text = '```custom\npayload\n```',
  Set<String> languages = const {'custom'},
}) => SelectionSource.markdown(
  id: 'run',
  revision: revision,
  text: text,
  copyCodeBlocks: true,
  runCodeBlockLanguages: languages,
  previous: previous,
);

class _Unknown extends SingleChildRenderObjectWidget {
  const _Unknown({required super.child});
  @override
  RenderBox createRenderObject(BuildContext context) => _UnknownBox();
}

class _UnknownBox extends RenderProxyBox {}

void main() {
  test('bound run policy validates set equality and callback presence', () {
    final s = source(languages: {'custom', 'second'});
    expect(
      () => Markdown.fromSelectionSource(
        s,
        onCopyCodeBlock: (_) {},
        onRunCodeBlock: (_) {},
        runCodeBlockLanguages: {'second', 'custom'},
      ),
      returnsNormally,
    );
    expect(
      () => Markdown.fromSelectionSource(s, onCopyCodeBlock: (_) {}),
      throwsArgumentError,
    );
    expect(
      () => Markdown.fromSelectionSource(
        s,
        onCopyCodeBlock: (_) {},
        onRunCodeBlock: (_) {},
        runCodeBlockLanguages: {'Custom', 'second'},
      ),
      throwsArgumentError,
    );
    final noRun = source(languages: {});
    expect(
      () => Markdown.fromSelectionSource(
        noRun,
        onCopyCodeBlock: (_) {},
        onRunCodeBlock: (_) {},
      ),
      throwsArgumentError,
    );
  });
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'copy and run route current complete descriptor independently $size',
      (t) async {
        final s = source(),
            copied = <MarkdownCodeBlock>[],
            ran = <MarkdownCodeBlock>[];
        await t.pumpWidget(
          Markdown.fromSelectionSource(
            s,
            onCopyCodeBlock: copied.add,
            onRunCodeBlock: ran.add,
          ),
          size: size,
        );
        await click(t, cell(t, '[run]'));
        await click(t, cell(t, '[copy]'));
        expect(ran.single, same(s.codeBlocks.single));
        expect(copied.single, same(s.codeBlocks.single));
        expect(ran.single.text, 'payload');
        expect(ran.single.language, 'custom');
      },
    );
    testWidgets(
      'run-only ordinary config keeps value-equal source revisions $size',
      (t) async {
        final update = ValueNotifier(0), ran = <MarkdownCodeBlock>[];
        addTearDown(update.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: update,
            builder: (_) => Markdown(
              '```custom\nx\n```',
              runCodeBlockLanguages: update.value == 0
                  ? {'custom', 'other'}
                  : {'other', 'custom'},
              onRunCodeBlock: ran.add,
            ),
          ),
          size: size,
        );
        expect(t.screen.text, isNot(contains('[copy]')));
        await click(t, cell(t, '[run]'));
        update.value++;
        await t.pump();
        await click(t, cell(t, '[run]'));
        expect(ran[1].revision, ran[0].revision);
        expect(ran[1].id, ran[0].id);
      },
    );
    testWidgets(
      'run press cancels for motion cross-button reflow and revision $size',
      (t) async {
        final update = ValueNotifier(0), runs = <MarkdownCodeBlock>[];
        addTearDown(update.dispose);
        final old = source();
        await t.pumpWidget(
          ListenableBuilder(
            listenable: update,
            builder: (_) => Markdown.fromSelectionSource(
              update.value == 0
                  ? old
                  : source(
                      revision: 1,
                      previous: old,
                      text: '```custom\nchanged\n```',
                    ),
              onCopyCodeBlock: (_) {},
              onRunCodeBlock: runs.add,
            ),
          ),
          size: size,
        );
        var at = cell(t, '[run]');
        await t.mouse(primary(MouseEventKind.press, at));
        await t.mouse(primary(MouseEventKind.release, cell(t, '[copy]')));
        expect(runs, isEmpty);
        await t.mouse(primary(MouseEventKind.press, at));
        await t.mouse(primary(MouseEventKind.move, Offset(at.x + 1, at.y)));
        await t.mouse(primary(MouseEventKind.release, at));
        expect(runs, isEmpty);
        await t.mouse(primary(MouseEventKind.press, at));
        update.value++;
        await t.pump();
        await t.mouse(primary(MouseEventKind.release, cell(t, '[run]')));
        expect(runs, isEmpty);
        at = cell(t, '[run]');
        await t.mouse(primary(MouseEventKind.press, at));
        await t.resize(Size(20, size.height));
        await t.mouse(primary(MouseEventKind.release, at));
        expect(runs, isEmpty);
      },
    );
    testWidgets(
      'lazy run policy uses current offscreen source on reveal $size',
      (t) async {
        final selection = SelectionController(), scroll = ScrollController();
        addTearDown(selection.dispose);
        addTearDown(scroll.dispose);
        final sources = [
          for (var i = 0; i < 50; i++)
            SelectionSource.markdown(
              id: i,
              revision: 0,
              text: '```custom\nx$i\n```',
              copyCodeBlocks: true,
              runCodeBlockLanguages: {'custom'},
            ),
        ];
        final ran = <MarkdownCodeBlock>[];
        await t.pumpWidget(
          SelectionArea(
            controller: selection,
            selectionStyle: const Style(inverse: true),
            child: ListView.builder(
              itemCount: sources.length,
              controller: scroll,
              itemVersion: (i) => sources[i].revision,
              selectionDelegate: SelectionChildDelegate(
                itemCount: sources.length,
                idAt: (i) => i,
                indexOfId: (id) => id is int ? id : null,
                sourceAt: (i) => sources[i],
              ),
              itemBuilder: (_, i) => Markdown.fromSelectionSource(
                sources[i],
                onCopyCodeBlock: (_) {},
                onRunCodeBlock: ran.add,
              ),
            ),
          ),
          size: size,
        );
        final last = sources.last.codeBlocks.single;
        expect(selection.codeBlockGeometry(last.id), isNull);
        expect(selection.revealCodeBlock(last.id), isTrue);
        final bounds = selection.codeBlockGeometry(last.id)!.bounds;
        expect(bounds.width, 25);
        await click(t, Offset(bounds.right - 7, bounds.top));
        expect(ran.single.id, last.id);
        expect(ran.single.text, 'x49');
      },
    );
    testWidgets('removing run eligibility cancels a held run control $size', (
      t,
    ) async {
      final enabled = ValueNotifier(true), ran = <MarkdownCodeBlock>[];
      addTearDown(enabled.dispose);
      final old = source();
      await t.pumpWidget(
        ListenableBuilder(
          listenable: enabled,
          builder: (_) => Markdown.fromSelectionSource(
            enabled.value
                ? old
                : source(revision: 1, previous: old, languages: {}),
            onCopyCodeBlock: (_) {},
            onRunCodeBlock: enabled.value ? ran.add : null,
          ),
        ),
        size: size,
      );
      final at = cell(t, '[run]');
      await t.mouse(primary(MouseEventKind.press, at));
      enabled.value = false;
      await t.pump();
      await t.mouse(primary(MouseEventKind.release, at));
      expect(ran, isEmpty);
      expect(t.screen.text, isNot(contains('[run]')));
    });

    testWidgets('unknown geometry and unmount never activate run $size', (
      t,
    ) async {
      var runs = 0;
      final s = source();
      Widget markdown() => Markdown.fromSelectionSource(
        s,
        onCopyCodeBlock: (_) {},
        onRunCodeBlock: (_) => runs++,
      );
      await t.pumpWidget(_Unknown(child: markdown()), size: size);
      await click(t, cell(t, '[run]'));
      expect(runs, 0);
      await t.pumpWidget(markdown(), size: size);
      final at = cell(t, '[run]');
      await t.mouse(primary(MouseEventKind.press, at));
      await t.pumpWidget(Text('gone'), size: size);
      await t.mouse(primary(MouseEventKind.release, at));
      expect(runs, 0);
    });

    testWidgets(
      'ordinary mismatch fails at source derivation and const API stays valid $size',
      (t) async {
        Object? error;
        await t.pumpWidget(
          ErrorBoundary(
            onError: (value, _) => error = value,
            errorBuilder: (_, _, _) => Text('invalid run config'),
            child: const Markdown(
              '```custom\nx\n```',
              runCodeBlockLanguages: {'custom'},
            ),
          ),
          size: size,
        );
        expect(error, isA<ArgumentError>());
        expect(t.screen, shows('invalid run config'));
        await t.pumpWidget(const Markdown('ordinary'), size: size);
        expect(t.screen, shows('ordinary'));
      },
    );
  }
}
