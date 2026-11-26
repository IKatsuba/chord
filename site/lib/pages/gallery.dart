import 'package:chord_tui/chord_tui.dart';

import '../gallery.dart';
import '../menu.dart';
import '../router.dart';
import 'example_frame.dart';

/// The list of the framework's examples, each opened in place.
class GalleryPage extends StatelessWidget {
  /// [gallery]'s list, opening an example through [open].
  const GalleryPage(this.gallery, this.open, {super.key});

  /// The examples.
  final Gallery gallery;

  /// Opens a route.
  final void Function(SiteRoute route) open;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2, top: 1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "The framework's examples, running here, as they are in "
          'example/.',
        ),
        Text(''),
        SiteMenu([
          for (final entry in gallery.entries)
            SiteMenuItem(
              entry.name,
              () => open(ExampleRoute(entry.name)),
              description: entry.description,
            ),
        ]),
      ],
    ),
  );
}

/// One gallery example running in its frame.
class ExamplePage extends StatelessWidget {
  /// [entry] running; [home] goes home.
  const ExamplePage(this.entry, this.home, {super.key});

  /// The example.
  final GalleryEntry entry;

  /// Goes home.
  final void Function() home;

  @override
  Widget build(BuildContext context) {
    return ExampleFrame(
      title: 'example/${entry.name}.dart',
      caption: entry.ownsEscape
          ? '${entry.description} · esc is the example\'s here; ctrl+q home'
          : '${entry.description} · esc back to the gallery',
      home: home,
      child: entry.build,
    );
  }
}
