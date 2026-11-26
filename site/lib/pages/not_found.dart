import 'package:chord_tui/chord_tui.dart';

import '../menu.dart';

/// What a path no page has shows: the path, and the way home. It does not
/// go home by itself, so a mistyped link stays readable.
class NotFoundPage extends StatelessWidget {
  /// Nothing at [path]; [home] goes home.
  const NotFoundPage(this.path, this.home, {super.key});

  /// The path that was asked for.
  final String path;

  /// Goes home.
  final void Function() home;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2, top: 1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nothing here: $path'),
        Text(''),
        SiteMenu([SiteMenuItem('home', home)], numbered: false),
      ],
    ),
  );
}
