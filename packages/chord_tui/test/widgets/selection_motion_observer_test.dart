import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_test.dart' show pointer;

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final operation in ['snapshot', 'release']) {
      testWidgets(
        'explicit scroll plus $operation retains fresh range with rebuilding observer $size',
        (t) async {
          final selection = SelectionController(), scroll = ScrollController();
          final notice = ValueNotifier('none');
          final sources = [
            for (var i = 0; i < 10; i++)
              SelectionSource.text(
                id: i,
                revision: 0,
                text: TextSpan('row $i'),
              ),
          ];
          final finalized = <SelectionValue>[];
          await t.pumpWidget(
            ListenableBuilder(
              listenable: notice,
              builder: (_) => Column(
                children: [
                  Text(notice.value, softWrap: false, maxLines: 1),
                  SizedBox(
                    height: 2,
                    child: SelectionArea(
                      controller: selection,
                      selectionStyle: const Style(inverse: true),
                      onSelectionChanged: (value) =>
                          notice.value = '${value.phase.name}: ${value.text}',
                      onSelectionFinalized: finalized.add,
                      child: ListView.builder(
                        controller: scroll,
                        itemCount: sources.length,
                        selectionDelegate: SelectionChildDelegate(
                          itemCount: sources.length,
                          idAt: (i) => i,
                          indexOfId: (id) =>
                              id is int && id >= 0 && id < sources.length
                              ? id
                              : null,
                          sourceAt: (i) => sources[i],
                        ),
                        itemVersion: (i) => sources[i].revision,
                        itemBuilder: (_, i) =>
                            Text.fromSelectionSource(sources[i]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            size: size,
          );
          t.host.handleMouse(pointer(MouseEventKind.press, 0, 1));
          t.host.handleMouse(pointer(MouseEventKind.move, 2, 1));
          expect(selection.value.text, 'row');
          scroll.jumpTo(1);
          if (operation == 'release') {
            final before = t.inputLayoutPasses;
            t.host.handleMouse(pointer(MouseEventKind.release, 0, 1));
            expect(t.inputLayoutPasses - before, lessThanOrEqualTo(2));
          }
          final before = t.inputLayoutPasses;
          final snapshot = selection.snapshot();
          expect(t.inputLayoutPasses - before, lessThanOrEqualTo(2));
          expect(snapshot!.text, 'row 0\nrow');
          if (operation == 'snapshot') {
            t.host.handleMouse(pointer(MouseEventKind.release, 0, 1));
          }
          expect(finalized, hasLength(1));
          expect(finalized.single.text, 'row 0\nrow');
          selection.dispose();
          scroll.dispose();
          notice.dispose();
        },
      );
    }
    testWidgets(
      'source observer new down supersedes old release without losing new capture $size',
      (t) async {
        final selection = SelectionController();
        final notice = ValueNotifier('none');
        final source = ValueNotifier(
          SelectionSource.text(
            id: 'body',
            revision: 0,
            text: const TextSpan('abcdefgh'),
          ),
        );
        final finalized = <SelectionValue>[];
        var startNew = true;
        await t.pumpWidget(
          ListenableBuilder(
            listenable: source,
            builder: (_) => ListenableBuilder(
              listenable: notice,
              builder: (_) => Column(
                children: [
                  Text(notice.value),
                  SelectionArea(
                    controller: selection,
                    selectionStyle: const Style(inverse: true),
                    onSelectionChanged: (value) {
                      notice.value = '${value.phase.name}: ${value.text}';
                      if (startNew && value.text == 'ABCD') {
                        startNew = false;
                        final before = t.inputLayoutPasses;
                        t.host.handleMouse(pointer(MouseEventKind.press, 4, 1));
                        expect(
                          t.inputLayoutPasses - before,
                          lessThanOrEqualTo(2),
                        );
                      }
                    },
                    onSelectionFinalized: finalized.add,
                    child: Text.fromSelectionSource(source.value),
                  ),
                ],
              ),
            ),
          ),
          size: size,
        );
        t.host.handleMouse(pointer(MouseEventKind.press, 0, 1));
        t.host.handleMouse(pointer(MouseEventKind.move, 3, 1));
        source.value = SelectionSource.text(
          id: 'body',
          revision: 1,
          text: const TextSpan('ABCDEFGH'),
          previous: source.value,
        );
        expect(
          t.host.handleMouse(pointer(MouseEventKind.release, 3, 1)),
          isFalse,
        );
        expect(finalized, isEmpty);
        expect(selection.value.phase, SelectionPhase.changing);
        t.host.handleMouse(pointer(MouseEventKind.move, 7, 1));
        t.host.handleMouse(pointer(MouseEventKind.release, 7, 1));
        expect(finalized, hasLength(1));
        expect(finalized.single.text, 'EFGH');
        selection.dispose();
        notice.dispose();
        source.dispose();
      },
    );
    for (final operation in ['snapshot', 'release']) {
      testWidgets(
        'source update plus $operation stays current with rebuilding observer $size',
        (t) async {
          final selection = SelectionController();
          final notice = ValueNotifier('none');
          final source = ValueNotifier(
            SelectionSource.text(
              id: 'body',
              revision: 0,
              text: const TextSpan('abcdefgh'),
            ),
          );
          final finalized = <SelectionValue>[];
          await t.pumpWidget(
            ListenableBuilder(
              listenable: source,
              builder: (_) => ListenableBuilder(
                listenable: notice,
                builder: (_) => Column(
                  children: [
                    Text(notice.value),
                    SelectionArea(
                      controller: selection,
                      selectionStyle: const Style(inverse: true),
                      onSelectionChanged: (value) =>
                          notice.value = '${value.phase.name}: ${value.text}',
                      onSelectionFinalized: finalized.add,
                      child: Text.fromSelectionSource(source.value),
                    ),
                  ],
                ),
              ),
            ),
            size: size,
          );
          t.host.handleMouse(pointer(MouseEventKind.press, 0, 1));
          t.host.handleMouse(pointer(MouseEventKind.move, 3, 1));
          expect(selection.value.text, 'abcd');
          source.value = SelectionSource.text(
            id: 'body',
            revision: 1,
            text: const TextSpan('ABCDEFGH'),
            previous: source.value,
          );
          if (operation == 'release') {
            final before = t.inputLayoutPasses;
            t.host.handleMouse(pointer(MouseEventKind.release, 3, 1));
            expect(t.inputLayoutPasses - before, lessThanOrEqualTo(2));
          }
          final beforeSnapshot = t.inputLayoutPasses;
          final snapshot = selection.snapshot();
          expect(t.inputLayoutPasses - beforeSnapshot, lessThanOrEqualTo(2));
          expect(snapshot, isNotNull);
          expect(snapshot!.text, 'ABCD');
          if (operation == 'snapshot') {
            t.host.handleMouse(pointer(MouseEventKind.release, 3, 1));
          }
          expect(finalized, hasLength(1));
          expect(finalized.single.text, 'ABCD');
          selection.dispose();
          notice.dispose();
          source.dispose();
        },
      );
    }
    for (final observer in ['controller', 'callback']) {
      testWidgets(
        'same-fragment motion survives parent rebuild from $observer observer $size',
        (t) async {
          final selection = SelectionController();
          final notice = ValueNotifier('none');
          final finalized = <SelectionValue>[];
          void changed(SelectionValue value) =>
              notice.value = '${value.phase.name}: ${value.text}';
          void listener() => changed(selection.value);
          if (observer == 'controller') selection.addListener(listener);
          await t.pumpWidget(
            ListenableBuilder(
              listenable: notice,
              builder: (_) => Column(
                children: [
                  Text(notice.value),
                  SelectionArea(
                    controller: selection,
                    selectionStyle: const Style(inverse: true),
                    onSelectionChanged: observer == 'callback' ? changed : null,
                    onSelectionFinalized: finalized.add,
                    child: Text('single fragment'),
                  ),
                ],
              ),
            ),
            size: size,
          );
          for (final event in [
            pointer(MouseEventKind.press, 0, 1),
            pointer(MouseEventKind.move, 5, 1),
            pointer(MouseEventKind.release, 5, 1),
          ]) {
            final before = t.inputLayoutPasses;
            t.host.handleMouse(event);
            expect(t.inputLayoutPasses - before, lessThanOrEqualTo(2));
          }
          expect(selection.snapshot()!.text, 'single');
          expect(selection.value.phase, SelectionPhase.finalized);
          expect(finalized, hasLength(1));
          expect(finalized.single.text, 'single');
          await t.pump();
          expect(t.screen.styleAt(0, 1).isInverse, isTrue);
          expect(t.screen.styleAt(6, 1).isInverse, isFalse);
          if (observer == 'controller') selection.removeListener(listener);
          selection.dispose();
          notice.dispose();
        },
      );
    }
  }
}
