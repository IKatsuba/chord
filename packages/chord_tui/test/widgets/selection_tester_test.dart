import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

MouseEvent _pointer(MouseEventKind kind, int x, int y) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

Widget _area(
  SelectionController controller,
  Widget child, {
  void Function(SelectionValue)? finalized,
}) => SelectionArea(
  controller: controller,
  selectionStyle: Style.inverse,
  onSelectionFinalized: finalized,
  child: child,
);

class _StreamingArea extends StatefulWidget {
  const _StreamingArea(this.controller, this.stream, this.finalized);
  final SelectionController controller;
  final Stream<String> stream;
  final List<SelectionValue> finalized;
  @override
  State<_StreamingArea> createState() => _StreamingState();
}

class _StreamingState extends State<_StreamingArea> {
  late final StreamSubscription<String> subscription;
  String text = 'initial';
  @override
  void initState() {
    super.initState();
    subscription = widget.stream.listen(
      (value) => setState(() => text = value),
    );
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _area(widget.controller, Text(text), finalized: widget.finalized.add);
}

void main() {
  group('tester: live selection boundaries and reentrant lifecycle', () {
    testWidgets('modified and nonprimary drags never start a selection', (
      t,
    ) async {
      final c = SelectionController();
      final finalized = <SelectionValue>[];
      await t.pumpWidget(_area(c, Text('abcdef'), finalized: finalized.add));
      for (var bits = 1; bits < 8; bits++) {
        for (final kind in [
          MouseEventKind.press,
          MouseEventKind.move,
          MouseEventKind.release,
        ]) {
          await t.mouse(
            MouseEvent(
              kind,
              position: Offset(kind == MouseEventKind.press ? 0 : 5, 0),
              button: MouseButton.primary,
              shift: bits & 1 != 0,
              alt: bits & 2 != 0,
              ctrl: bits & 4 != 0,
            ),
          );
        }
        expect(c.value.phase, SelectionPhase.none);
      }
      for (final button in [MouseButton.middle, MouseButton.secondary]) {
        for (final kind in [
          MouseEventKind.press,
          MouseEventKind.move,
          MouseEventKind.release,
        ]) {
          await t.mouse(
            MouseEvent(
              kind,
              position: Offset(kind == MouseEventKind.press ? 0 : 5, 0),
              button: button,
            ),
          );
        }
        expect(c.value.phase, SelectionPhase.none);
      }
      expect(finalized, isEmpty);
      t.dispose();
      c.dispose();
    });

    testWidgets(
      'zero room suppresses selection and one cell distinguishes click from clamp',
      (t) async {
        final c = SelectionController();
        final finalized = <SelectionValue>[];
        await t.pumpWidget(
          _area(c, Text('A'), finalized: finalized.add),
          size: Size.zero,
        );
        await t.mouse(_pointer(MouseEventKind.press, 0, 0));
        expect(c.snapshot(), isNull);
        await t.resize(const Size(1, 1));
        await t.mouse(_pointer(MouseEventKind.press, 0, 0));
        await t.mouse(_pointer(MouseEventKind.release, 0, 0));
        expect(c.snapshot()!.text, isEmpty);
        expect(finalized.single.hasText, isFalse);
        await t.mouse(_pointer(MouseEventKind.press, 0, 0));
        await t.mouse(_pointer(MouseEventKind.move, 10, 10));
        await t.mouse(_pointer(MouseEventKind.release, 10, 10));
        expect(c.snapshot()!.text, 'A');
        expect(finalized.last.text, 'A');
        t.dispose();
        c.dispose();
      },
    );

    testWidgets(
      'unmount cancels a live stream and never finalizes the old drag',
      (t) async {
        var cancellations = 0;
        final stream = StreamController<String>(
          sync: true,
          onCancel: () => cancellations++,
        );
        final c = SelectionController();
        final finalized = <SelectionValue>[];
        await t.pumpWidget(_StreamingArea(c, stream.stream, finalized));
        await t.mouse(_pointer(MouseEventKind.press, 0, 0));
        await t.mouse(_pointer(MouseEventKind.move, 3, 0));
        stream.add('updated');
        await t.pumpWidget(Text('removed'));
        expect(cancellations, 1);
        expect(c.snapshot(), isNull);
        stream.add('late');
        await t.mouse(_pointer(MouseEventKind.release, 3, 0));
        expect(finalized, isEmpty);
        expect(t.screen, shows('removed'));
        await stream.close();
        t.dispose();
        c.dispose();
      },
    );

    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'unbounded adjacent Unicode leaves keep same-row ordering $size',
        (t) async {
          final c = SelectionController();
          await t.pumpWidget(
            _area(
              c,
              Row(
                children: [
                  Text('A界'),
                  SelectionContainer.disabled(child: Text('|')),
                  Text('e\u0301👩‍💻Z'),
                ],
              ),
            ),
            size: size,
          );
          for (final reverse in [false, true]) {
            await t.mouse(_pointer(MouseEventKind.press, reverse ? 7 : 0, 0));
            await t.mouse(_pointer(MouseEventKind.move, reverse ? 0 : 7, 0));
            await t.mouse(_pointer(MouseEventKind.release, 50, 10));
            expect(c.snapshot()!.text, 'A界e\u0301👩‍💻Z');
            expect(t.screen.styleAt(3, 0).isInverse, isFalse);
            expect(t.screen.styleAt(1, 0).isInverse, isTrue);
            expect(t.screen.styleAt(2, 0).isInverse, isTrue);
          }
          t.dispose();
          c.dispose();
        },
      );

      testWidgets(
        'removing both held endpoints retains the middle source $size',
        (t) async {
          final c = SelectionController();
          final changed = ValueNotifier(false);
          final sources = [
            for (final value in ['left', 'middle', 'right'])
              SelectionSource.text(
                id: value,
                revision: 0,
                text: TextSpan(value),
              ),
          ];
          final finalized = <SelectionValue>[];
          await t.pumpWidget(
            ListenableBuilder(
              listenable: changed,
              builder: (_) => _area(
                c,
                Column(
                  children: [
                    for (var i = 0; i < sources.length; i++)
                      if (!changed.value || i == 1)
                        Text.fromSelectionSource(
                          sources[i],
                          key: ValueKey(sources[i].id),
                        ),
                  ],
                ),
                finalized: finalized.add,
              ),
            ),
            size: size,
          );
          await t.mouse(_pointer(MouseEventKind.press, 0, 0));
          await t.mouse(_pointer(MouseEventKind.move, 4, 2));
          changed.value = true;
          t.host.handleMouse(_pointer(MouseEventKind.release, 60, 20));
          expect(c.snapshot()!.text, 'middle');
          expect(finalized.single.text, 'middle');
          t.dispose();
          c.dispose();
          changed.dispose();
        },
      );

      testWidgets(
        'thousand revisions before up copy the latest surviving text $size',
        (t) async {
          final c = SelectionController();
          final revision = ValueNotifier(0);
          var source = SelectionSource.text(
            id: 'text',
            revision: 0,
            text: const TextSpan('ABCD'),
          );
          await t.pumpWidget(
            ListenableBuilder(
              listenable: revision,
              builder: (_) => _area(c, Text.fromSelectionSource(source)),
            ),
            size: size,
          );
          await t.mouse(_pointer(MouseEventKind.press, 0, 0));
          await t.mouse(_pointer(MouseEventKind.move, 3, 0));
          for (var i = 1; i <= 1000; i++) {
            source = SelectionSource.text(
              id: 'text',
              revision: i,
              text: TextSpan('W${i.toString().padLeft(4, '0')}Z'),
              previous: source,
            );
            revision.value = i;
          }
          t.host.handleMouse(_pointer(MouseEventKind.release, 70, 20));
          expect(c.snapshot()!.text, 'W100');
          expect(c.value.phase, SelectionPhase.finalized);
          t.dispose();
          c.dispose();
          revision.dispose();
        },
      );
    }

    testWidgets(
      'finalization callback can clear and begin a second live drag',
      (t) async {
        final c = SelectionController();
        final finalized = <SelectionValue>[];
        await t.pumpWidget(
          _area(
            c,
            Text('abcdef'),
            finalized: (value) {
              finalized.add(value);
              if (finalized.length == 1) {
                c.clear();
                t.host.handleMouse(_pointer(MouseEventKind.press, 3, 0));
              }
            },
          ),
        );
        await t.mouse(_pointer(MouseEventKind.press, 0, 0));
        await t.mouse(_pointer(MouseEventKind.move, 2, 0));
        await t.mouse(_pointer(MouseEventKind.release, 50, 10));
        expect(c.value.phase, SelectionPhase.changing);
        await t.mouse(_pointer(MouseEventKind.move, 5, 0));
        await t.mouse(_pointer(MouseEventKind.release, 0, 0));
        expect(finalized.map((value) => value.text), ['abc', 'def']);
        expect(c.snapshot()!.text, 'def');
        t.dispose();
        c.dispose();
      },
    );
  });
}
