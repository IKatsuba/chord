import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/shortcuts/state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  // The original's tests/ui/shortcuts/state_test.ts.
  test('/help opens the shortcuts, and stays open when they are', () {
    final open = reduceShortcuts(const ShortcutsState(), const HelpOpened());
    expect(open.help, isTrue);
    expect(reduceShortcuts(open, const HelpOpened()), same(open));
  });
  test('toggle opens, close resets overflow, reopen starts fresh', () {
    const initial = ShortcutsState();
    expect(reduceShortcuts(initial, const HelpClosed()), same(initial));
    expect(
      reduceShortcuts(initial, const PanelOverflowed(true)),
      same(initial),
    );
    final open = reduceShortcuts(initial, const HelpToggled());
    expect(open.help, isTrue);
    final overflow = reduceShortcuts(open, const PanelOverflowed(true));
    expect(overflow.panelOverflows, isTrue);
    expect(
      reduceShortcuts(overflow, const PanelOverflowed(true)),
      same(overflow),
    );
    final closed = reduceShortcuts(overflow, const HelpToggled());
    expect(closed.help, isFalse);
    expect(closed.panelOverflows, isFalse);
    final reopened = reduceShortcuts(closed, const HelpToggled());
    expect(reopened.help, isTrue);
    expect(reopened.panelOverflows, isFalse);
    expect(
      reduceShortcuts(overflow, const HelpClosed()).panelOverflows,
      isFalse,
    );
  });
  test(
    'pending keys are copied immutable values and clear independently of help',
    () {
      final keys = [KeyCombo.parse('ctrl+x')];
      final pending = reduceShortcuts(
        const ShortcutsState(help: true),
        KeysPending(keys),
      );
      keys.clear();
      expect(pending.pendingKeys, [KeyCombo.parse('ctrl+x')]);
      expect(() => pending.pendingKeys.clear(), throwsUnsupportedError);
      expect(
        reduceShortcuts(pending, KeysPending([KeyCombo.parse('ctrl+x')])),
        same(pending),
      );
      final cleared = reduceShortcuts(pending, const KeysPending([]));
      expect(cleared.pendingKeys, isEmpty);
      expect(cleared.help, isTrue);
      expect(reduceShortcuts(cleared, const KeysPending([])), same(cleared));
    },
  );
  test('fitting after resize clears overflow without closing help', () {
    const over = ShortcutsState(help: true, panelOverflows: true);
    final fits = reduceShortcuts(over, const PanelOverflowed(false));
    expect(fits.help, isTrue);
    expect(fits.panelOverflows, isFalse);
  });
  test(
    'quit arming closes help and clears panel overflow in the same state change',
    () {
      const before = AppState(
        shortcuts: ShortcutsState(help: true, panelOverflows: true),
      );
      final armed = reduceWindow(before, const QuitArmedAction());
      expect(armed.quitArmed, isTrue);
      expect(armed.shortcuts.help, isFalse);
      expect(armed.shortcuts.panelOverflows, isFalse);
      expect(
        reduceWindow(armed, const QuitDisarmedAction()).shortcuts.help,
        isFalse,
      );
    },
  );
  test(
    'panel actions preserve session state and unchanged actions retain identity',
    () {
      const before = AppState();
      expect(
        reduceWindow(before, const ShortcutsChangedAction(HelpClosed())),
        same(before),
      );
      final after = reduceWindow(
        before,
        const ShortcutsChangedAction(HelpToggled()),
      );
      expect(after.shortcuts.help, isTrue);
      expect(after.transcript, same(before.transcript));
      expect(after.queue, same(before.queue));
    },
  );

  group('tester: shortcuts reducer isolation', () {
    test('close and quit-arm retain the framework pending chord snapshot', () {
      final pending = reduceShortcuts(
        const ShortcutsState(help: true, panelOverflows: true),
        KeysPending([KeyCombo.parse('ctrl+x')]),
      );
      final closed = reduceShortcuts(pending, const HelpClosed());
      expect(closed.pendingKeys, same(pending.pendingKeys));
      expect(closed.help, isFalse);
      expect(closed.panelOverflows, isFalse);
      final armed = reduceWindow(
        AppState(shortcuts: pending),
        const QuitArmedAction(),
      );
      expect(armed.shortcuts.pendingKeys, same(pending.pendingKeys));
      expect(armed.shortcuts.help, isFalse);
      expect(armed.shortcuts.panelOverflows, isFalse);
      expect(pending.help, isTrue);
      expect(pending.panelOverflows, isTrue);
    });

    test(
      'a thousand panel toggles leave another session and retained keys unchanged',
      () {
        final first = reduceShortcuts(
          const ShortcutsState(),
          KeysPending([KeyCombo.parse('ctrl+x')]),
        );
        const second = ShortcutsState();
        var next = first;
        for (var i = 0; i < 1000; i++) {
          next = reduceShortcuts(next, const HelpToggled());
          next = reduceShortcuts(next, const PanelOverflowed(true));
        }
        expect(next.help, isFalse);
        expect(next.panelOverflows, isFalse);
        expect(next.pendingKeys, same(first.pendingKeys));
        expect(first.help, isFalse);
        expect(second.pendingKeys, isEmpty);
        expect(second.help, isFalse);
        expect(second.panelOverflows, isFalse);
      },
    );
  });
}
