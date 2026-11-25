import 'package:chord/ui/prompt/commands.dart';
import 'package:chord/ui/prompt/state.dart';
import 'package:test/test.dart';

void main() {
  const items = [
    CommandItem('alpha', 'a'),
    CommandItem('beta', 'b'),
    CommandItem('gamma', 'c'),
  ];
  test(
    'completion wraps and preserves dismissal only until the draft changes',
    () {
      var menu = commandMenu(null, '/', items)!;
      menu = moveCommandMenu(menu, -1, 2);
      expect(menu.selected?.name, 'gamma');
      expect(menu.top, 1);
      menu = dismissCommandMenu(menu);
      expect(commandMenu(menu, '/', items)!.dismissed, isTrue);
      menu = commandMenu(menu, '/be', items)!;
      expect(menu.dismissed, isFalse);
      expect(menu.selected?.name, 'beta');
      expect(menu.top, 0);
      expect(commandMenu(menu, '/beta ', items), isNull);
      expect(commandMenu(menu, '/beta\n', items), isNull);
    },
  );
  test(
    'advertisements retain semantic highlight and remove stale selections',
    () {
      var menu = moveCommandMenu(commandMenu(null, '/', items)!, 1, 2);
      menu = commandMenu(menu, '/', [items[2], items[1]])!;
      expect(menu.selected?.name, 'beta');
      menu = commandMenu(menu, '/', [items[2]])!;
      expect(menu.selected?.name, 'gamma');
      menu = commandMenu(menu, '/', [])!;
      expect(menu.selected, isNull);
      expect(moveCommandMenu(menu, 1, 0), same(menu));
      expect(commandMenu(null, '/no-match', items)!.selected, isNull);
    },
  );
}
