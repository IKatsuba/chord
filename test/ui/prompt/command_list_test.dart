import 'package:chord/ui/prompt/command_list.dart';
import 'package:chord/ui/prompt/commands.dart';
import 'package:chord/ui/prompt/state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'completion floats with one rule and bounded unnumbered rows at $size',
      (t) async {
        final menu = commandMenu(null, '/', [
          for (var i = 0; i < 20; i++) CommandItem('item$i', 'description$i'),
        ])!;
        var room = -1;
        await t.pumpWidget(
          Align(
            alignment: Alignment.bottomLeft,
            child: CommandList(
              menu: menu,
              windowRows: size.height,
              onRoom: (n) => room = n,
            ),
          ),
          size: size,
        );
        expect(room, size.height ~/ 4);
        expect(
          t.screen.lines.where((line) => line.contains('/item')),
          hasLength(room),
        );
        expect(
          t.screen.lines.last,
          '  /item${room - 1}${' ' * 3}description${room - 1}',
        );
        expect(t.screen, isNot(shows('❯')));
        expect(t.screen, isNot(shows('more')));
      },
    );
  }
  testWidgets(
    'long wide names and descriptions retain identifying tails at forty columns',
    (t) async {
      final menu = commandMenu(null, '/', [
        CommandItem(
          '${'界👩‍💻' * 15}tail',
          '${'long description 界' * 12}ending',
        ),
      ])!;
      await t.pumpWidget(
        Align(
          alignment: Alignment.bottomLeft,
          child: CommandList(menu: menu, windowRows: 24, onRoom: (_) {}),
        ),
        size: const Size(40, 24),
      );
      expect(t.screen, shows('tail'));
      expect(t.screen, shows('ending'));
      expect(t.screen, shows('...'));
    },
  );
  testWidgets('zero item room reports zero and resize restores bounded items', (
    t,
  ) async {
    final menu = commandMenu(null, '/', const [
      CommandItem('model', 'Switch the model'),
    ])!;
    var room = -1;
    await t.pumpWidget(
      CommandList(menu: menu, windowRows: 24, onRoom: (n) => room = n),
      size: const Size(40, 1),
    );
    expect(room, 0);
    expect(t.screen, isNot(shows('/model')));
    await t.resize(const Size(80, 24));
    expect(room, 1);
    expect(t.screen, shows('/model'));
  });
}
