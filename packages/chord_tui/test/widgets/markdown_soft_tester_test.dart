import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester soft Markdown geometry', () {
    for (final bars in [false, true]) {
      for (final width in [120, 80, 12]) {
        testWidgets(
          'height matches mounted rows with quoteBars=$bars width=$width',
          (t) async {
            final source = SelectionSource.markdown(
              id: 'soft',
              revision: 0,
              quoteBars: bars,
              text:
                  'Before\n\n> **界🙂e\u0301**\n> > inner\n\n```sh\necho safe\n```\n\nAfter',
            );
            await t.pumpWidget(
              Row(
                children: [
                  SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Markdown.fromSelectionSource(source),
                        Text('sentinel'),
                      ],
                    ),
                  ),
                ],
              ),
              size: const Size(120, 40),
            );
            final row = t.screen.lines.indexWhere(
              (l) => l.contains('sentinel'),
            );
            expect(
              row,
              Markdown.heightOf(source, width),
              reason: t.screen.text,
            );
            expect(t.screen.text, contains('界🙂e\u0301'));
            if (!bars) {
              expect(t.screen.text, isNot(contains('│ │ inner')));
            }
          },
        );
      }
    }

    testWidgets(
      'zero one and unbounded constraints recover soft quote geometry',
      (t) async {
        final source = SelectionSource.markdown(
          id: 'm',
          revision: 0,
          quoteBars: false,
          text: '> 界👩‍💻e\u0301',
        );
        await t.pumpWidget(
          Markdown.fromSelectionSource(source),
          size: const Size(80, 24),
        );
        for (final size in [Size.zero, const Size(1, 1), const Size(120, 40)]) {
          await t.resize(size);
        }
        expect(t.screen.text, contains('界👩‍💻e\u0301'));
        await t.pumpWidget(
          Row(children: [Markdown.fromSelectionSource(source), Text('end')]),
        );
        expect(t.screen.text, contains('界👩‍💻e\u0301end'));
        expect(Markdown.heightOf(source, unbounded), 1);
        expect(Markdown.heightOf(source, 0), greaterThanOrEqualTo(0));
      },
    );

    testWidgets(
      'a thousand soft quote revisions settle and unmount detaches updates',
      (t) async {
        final text = ValueNotifier('> start');
        addTearDown(text.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: text,
            builder: (_) =>
                Markdown(text.value, quoteBars: false, growing: true),
          ),
        );
        for (var i = 0; i < 1000; i++) {
          text.value = '> update $i 界👩‍💻e\u0301';
        }
        await t.pump();
        expect(t.screen.text, contains('update 999 界👩‍💻e\u0301'));
        expect(t.screen.text, isNot(contains('│')));
        await t.pumpWidget(const SizedBox());
        expect(text.hasListeners, isFalse);
        text.value = '> late update';
        await t.pump();
        expect(t.screen.text, isNot(contains('late update')));
      },
    );

    test('height rejects non-Markdown selection geometry', () {
      final source = SelectionSource.text(
        id: 'text',
        revision: 0,
        text: const TextSpan('plain'),
      );
      expect(() => Markdown.heightOf(source, 80), throwsArgumentError);
    });
  });
}
