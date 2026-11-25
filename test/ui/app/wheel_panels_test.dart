import 'package:chord/ui/dialogs/permission_prompt.dart';
import 'package:chord/ui/dialogs/permission_scroll.dart';
import 'package:chord/ui/shortcuts/shortcuts.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import '../../../tool/wheel.dart' show wheelPermission;
import 'wheel_window_test.dart' show wheel;

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final permission in [false, true]) {
      for (final fitting in [false, true]) {
        testWidgets(
          'body-only wheel permission=$permission fitting=$fitting at $size',
          (t) async {
            final scroll = PermissionScroll();
            var bubbled = 0, chosen = 0;
            final panel = permission
                ? PermissionPrompt(
                    wait: wheelPermission(fitting: fitting),
                    windowRows: size.height,
                    maxRows: fitting ? size.height : 16,
                    scroll: scroll,
                    onChoose: (_) => chosen++,
                    onReject: () => chosen++,
                  )
                : SizedBox(
                    height: fitting ? size.height : 6,
                    child: ShortcutsPanel(scroll: scroll, onOverflow: (_) {}),
                  );
            await t.pumpWidget(
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerSignal: (_) => bubbled++,
                child: Column(children: [panel]),
              ),
              size: size,
            );
            expect(scroll.overflows, !fitting);
            final body = permission && fitting
                ? t.screen.lines.lastIndexWhere(
                    (line) => line.contains('notes'),
                  )
                : t.screen.lines.indexWhere(
                    (line) => line.contains(
                      permission ? 'proposed line 1' : 'enter to send',
                    ),
                  );
            expect(body, greaterThanOrEqualTo(0));
            if (permission) {
              await t.press('down');
              expect(t.screen, shows('❯ 2. Always allow'));
            }
            final focus = t.focusManager.primaryFocus;
            await t.mouse(wheel(size.width - 4, body, 1));
            expect(scroll.top, fitting ? 0 : 1);
            expect(bubbled, fitting ? 1 : 0);
            expect(t.focusManager.primaryFocus, same(focus));
            expect(chosen, 0);
            if (permission) expect(t.screen, shows('❯ 2. Always allow'));
            if (!fitting) {
              final above = t.screen.lines.indexWhere(
                (line) => line.contains('1 line above'),
              );
              expect(above, greaterThanOrEqualTo(0));
              await t.mouse(wheel(3, above, 1));
              expect(scroll.top, 1);
              expect(bubbled, 1);
              final below = t.screen.lines.indexWhere(
                (line) => line.contains('lines below'),
              );
              if (below >= 0) {
                await t.mouse(wheel(3, below, 1));
                expect(scroll.top, 1);
                expect(bubbled, 2);
              }
            }
            if (permission && !fitting) {
              final currentBody = t.screen.lines.indexWhere(
                (line) => line.contains('proposed line 2'),
              );
              await t.mouse(wheel(3, currentBody));
              expect(scroll.top, 0);
              expect(t.screen, isNot(shows('1 line above')));
              expect(t.focusManager.primaryFocus, same(focus));
              expect(t.screen, shows('❯ 2. Always allow'));
            }
            if (permission) {
              for (final outside in [
                t.screen.lines.indexWhere((line) => line.contains('Write')),
                t.screen.lines.indexWhere(
                  (line) => line.contains('❯ 2. Always allow'),
                ),
              ]) {
                expect(outside, greaterThanOrEqualTo(0));
                final before = bubbled, top = scroll.top;
                await t.mouse(wheel(3, outside, 1));
                expect(bubbled, before + 1);
                expect(scroll.top, top);
                expect(t.focusManager.primaryFocus, same(focus));
                expect(t.screen, shows('❯ 2. Always allow'));
              }
            }
            final before = bubbled;
            await t.mouse(wheel(0, 0, 1));
            expect(bubbled, before + 1);
            expect(chosen, 0);
            t.dispose();
            scroll.dispose();
          },
        );
        testWidgets(
          'queued wheel sees fresh closing permission=$permission fitting=$fitting at $size',
          (t) async {
            final scroll = PermissionScroll();
            var closing = false, bubbled = 0;
            scroll.addListener(() => closing = true);
            final panel = permission
                ? PermissionPrompt(
                    wait: wheelPermission(fitting: fitting),
                    windowRows: size.height,
                    maxRows: fitting ? size.height : 16,
                    scroll: scroll,
                    isClosing: () => closing,
                    onChoose: (_) {},
                    onReject: () {},
                  )
                : SizedBox(
                    height: fitting ? size.height : 6,
                    child: ShortcutsPanel(
                      scroll: scroll,
                      onOverflow: (_) {},
                      isClosing: () => closing,
                    ),
                  );
            await t.pumpWidget(
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerSignal: (_) {
                  if (!closing) {
                    bubbled++;
                    closing = true;
                  }
                },
                child: Column(children: [panel]),
              ),
              size: size,
            );
            final body = permission && fitting
                ? t.screen.lines.lastIndexWhere(
                    (line) => line.contains('notes'),
                  )
                : t.screen.lines.indexWhere(
                    (line) => line.contains(
                      permission ? 'proposed line 1' : 'enter to send',
                    ),
                  );
            expect(body, greaterThanOrEqualTo(0));
            final chunk = InputParser().feed(
              '\x1b[<65;4;${body + 1}M\x1b[<65;4;${body + 1}M',
            );
            for (final event in chunk.whereType<MouseEvent>()) {
              t.host.handleMouse(event);
            }
            expect(closing, isTrue);
            expect(scroll.top, fitting ? 0 : 1);
            expect(bubbled, fitting ? 1 : 0);
            await t.pump();
            final text = t.screen.text;
            await t.mouse(wheel(3, body));
            expect(t.screen.text, text);
            t.dispose();
            scroll.dispose();
          },
        );
      }
    }
  }
}
