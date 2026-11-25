import 'package:chord/ui/app/context.dart';
import 'package:chord/ui/dialogs/permission_scroll.dart';
import 'package:chord/ui/shortcuts/shortcuts.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'keys_bound_test.dart' show read;

void main() {
  group('tester: wheel hint survives page-key removal', () {
    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets(
        'unbound page keys leave one wheel entry through resize $size',
        (t) async {
          final scroll = PermissionScroll();
          addTearDown(scroll.dispose);
          await t.pumpWidget(
            Keys(
              keymap: read([
                {
                  'context': 'Scroll',
                  'bindings': {
                    'pageup': null,
                    'shift+pageup': null,
                    'pagedown': null,
                    'shift+pagedown': null,
                  },
                },
              ]),
              child: ShortcutsPanel(scroll: scroll, onOverflow: (_) {}),
            ),
            size: size,
          );
          expect('wheel to scroll'.allMatches(t.screen.text), hasLength(1));
          expect(t.screen.text, isNot(contains('pgup pgdn or wheel')));
          await t.resize(const Size(0, 0));
          await t.resize(size);
          expect('wheel to scroll'.allMatches(t.screen.text), hasLength(1));
        },
      );
    }
  });
}
