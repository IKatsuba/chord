import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/dialogs/permission_prompt.dart';
import 'package:chord/ui/dialogs/permission_scroll.dart';
import 'package:chord/ui/shortcuts/shortcuts.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/wheel.dart' show wheelPermission;
import 'wheel_window_test.dart' show seed, wheel;
import 'window_layout_test.dart' show launch;

// runApp merges a batch of wheel reports into one with the summed delta;
// every wheel consumer must move by that size, not by one row.
void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('a merged report scrolls the transcript by its size at $size', (
      t,
    ) async {
      final c = seed();
      addTearDown(c.close);
      await t.pumpWidget(
        TranscriptWindow(launch: launch, connection: c),
        size: size,
      );
      final bottom = c.app.value.scroll.offset;
      await t.mouse(wheel(0, 0, -3));
      expect(c.app.value.scroll.offset, bottom - 3);
      expect(c.app.value.scroll.following, isFalse);
      await t.mouse(wheel(0, 0, 2));
      expect(c.app.value.scroll.offset, bottom - 1);
      await t.mouse(wheel(0, 0, 5));
      expect(c.app.value.scroll.offset, bottom);
      expect(c.app.value.scroll.following, isTrue);
    });

    for (final permission in [false, true]) {
      testWidgets(
        'a merged report scrolls the overflowing '
        '${permission ? 'permission' : 'shortcuts'} body by its size at $size',
        (t) async {
          final scroll = PermissionScroll();
          final panel = permission
              ? PermissionPrompt(
                  wait: wheelPermission(),
                  windowRows: size.height,
                  maxRows: 16,
                  scroll: scroll,
                  onChoose: (_) {},
                  onReject: () {},
                )
              : SizedBox(
                  height: 6,
                  child: ShortcutsPanel(scroll: scroll, onOverflow: (_) {}),
                );
          await t.pumpWidget(Column(children: [panel]), size: size);
          expect(scroll.overflows, isTrue);
          final body = t.screen.lines.indexWhere(
            (line) =>
                line.contains(permission ? 'proposed line 1' : 'enter to send'),
          );
          expect(body, greaterThanOrEqualTo(0));
          await t.mouse(wheel(size.width - 4, body, 3));
          expect(scroll.top, 3);
          // The scrolled body's first row now says what is above it.
          await t.mouse(wheel(size.width - 4, body + 2, -2));
          expect(scroll.top, 1);
        },
      );
    }
  }
}
