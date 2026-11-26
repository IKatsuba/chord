import 'package:chord_tui/chord_tui.dart';

/// One row of a [SiteMenu]: a label, what it leads to, and what opening it
/// does.
class SiteMenuItem {
  /// A row called [label], described by [description], doing [onOpen].
  const SiteMenuItem(this.label, this.onOpen, {this.description = ''});

  /// The row's name.
  final String label;

  /// What it leads to, beside the name.
  final String description;

  /// What opening it does.
  final void Function() onOpen;
}

/// A numbered menu: up and down move, Enter opens, a digit opens its row,
/// and a tap opens the row tapped.
class SiteMenu extends StatefulWidget {
  /// A menu of [items]; [numbered] puts each row's digit before it.
  const SiteMenu(this.items, {super.key, this.numbered = true});

  /// The rows.
  final List<SiteMenuItem> items;

  /// Whether rows carry digits.
  final bool numbered;

  @override
  State<SiteMenu> createState() => _SiteMenuState();
}

class _SiteMenuState extends State<SiteMenu> {
  var _selected = 0;

  void _move(int by) => setState(
    () => _selected = (_selected + by).clamp(0, widget.items.length - 1),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = widget.items;
    final width = items.fold(
      0,
      (w, i) => i.label.length > w ? i.label.length : w,
    );
    return Actions(
      bindings: [
        Binding('up', 'move', () => _move(-1)),
        Binding('down', 'move', () => _move(1)),
        Binding('enter', 'open', () => items[_selected].onOpen()),
        if (widget.numbered)
          for (var n = 1; n <= items.length && n <= 9; n++)
            Binding('$n', 'jump', items[n - 1].onOpen),
      ],
      // The menu holds the page's focus, so its keys and the shell's above
      // it are the ones in scope.
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++)
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => items[i].onOpen(),
                child: Text.rich(
                  TextSpan(
                    '',
                    children: [
                      TextSpan(
                        i == _selected ? '❯ ' : '  ',
                        style: theme.accent,
                      ),
                      TextSpan(
                        '${widget.numbered ? '${i + 1}. ' : ''}'
                        '${items[i].label.padRight(width)}',
                        style: i == _selected
                            ? theme.text.merge(Style.bold)
                            : theme.text,
                      ),
                      if (items[i].description.isNotEmpty)
                        TextSpan(
                          '    ${items[i].description}',
                          style: theme.dim,
                        ),
                    ],
                  ),
                  softWrap: false,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
