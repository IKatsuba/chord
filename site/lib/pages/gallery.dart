import 'package:chord_tui/chord_tui.dart';

import '../gallery.dart';
import 'example_frame.dart';

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
