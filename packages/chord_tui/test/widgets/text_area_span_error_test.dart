import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in const [Size(120, 40), Size(80, 24), Size(0, 0)]) {
    for (final callbackThrows in [false, true]) {
      testWidgets(
        'initial span rejection uses normal outer build boundary $callbackThrows $size',
        (t) async {
          final c = TextAreaController(text: 'unchanged');
          Object? caught;
          await t.pumpWidget(
            ErrorBoundary(
              onError: (error, _) => caught = error,
              errorBuilder: (_, error, stack) => Text('Projection rejected'),
              child: TextArea(
                controller: c,
                autofocus: true,
                textSpanBuilder: (_, text) {
                  if (callbackThrows) {
                    throw StateError('span callback failed');
                  }
                  return TextSpan('$text changed');
                },
              ),
            ),
            size: size,
          );
          expect(caught, callbackThrows ? isStateError : isArgumentError);
          expect(c.text, 'unchanged');
          expect(
            t.focusManager.activeBindings.where((b) => b.description == 'Undo'),
            isEmpty,
          );
          await t.paste('hidden');
          expect(c.text, 'unchanged');
          t.dispose();
          c.dispose();
        },
      );
    }
  }

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    for (final callbackThrows in [false, true]) {
      testWidgets(
        'valid invalid valid spans never leave stale editor handlers $callbackThrows $size',
        (t) async {
          final c = TextAreaController(text: 'draft');
          final invalid = ValueNotifier(false);
          final changes = <String>[], submitted = <String>[];
          final onChanged = changes.add, onSubmit = submitted.add;
          await t.pumpWidget(
            ListenableBuilder(
              listenable: invalid,
              builder: (_) => TextArea(
                controller: c,
                autofocus: true,
                onChanged: onChanged,
                onSubmit: onSubmit,
                textSpanBuilder: (_, text) {
                  if (invalid.value) {
                    if (callbackThrows) {
                      throw StateError('span callback failed');
                    }
                    return TextSpan('$text changed');
                  }
                  return TextSpan(text, style: Style.inverse);
                },
              ),
            ),
            size: size,
          );
          await t.type('!');
          final saved = (c.text, c.cursor);
          invalid.value = true;
          await t.pump();
          expect(
            t.screen,
            shows(callbackThrows ? 'span callback failed' : 'textSpanBuilder'),
          );
          expect(
            t.focusManager.activeBindings.where((b) => b.description == 'Undo'),
            isEmpty,
          );
          await t.type('hidden');
          await t.paste('paste');
          await t.press('enter backspace ctrl+z');
          expect((c.text, c.cursor), saved);
          expect(changes, ['draft!']);
          expect(submitted, isEmpty);
          invalid.value = false;
          await t.pump();
          expect(t.screen, shows('draft!'));
          expect((c.text, c.cursor), saved);
          expect(submitted, isEmpty);
          await t.press('ctrl+z');
          expect(c.text, 'draft');
          await t.press('ctrl+y');
          expect(c.text, 'draft!');
          await t.press('enter');
          expect(submitted, ['draft!']);
          t.dispose();
          c.dispose();
          invalid.dispose();
        },
      );
    }
  }
}
