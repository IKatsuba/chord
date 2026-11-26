import 'package:chord_tui/chord_tui.dart';

/// One example of the gallery: its file's name, what it shows, and how it
/// is built for the room it gets.
class GalleryEntry {
  /// The example in `example/<name>.dart`.
  const GalleryEntry(
    this.name,
    this.description,
    this.build, {
    this.ownsEscape = false,
    String? title,
    String? blurb,
    this.preview = const [],
  }) : title = title ?? name,
       blurb = blurb ?? description;

  /// The example's file name, and its path under `/chord_tui`.
  final String name;

  /// What it shows, in a few words.
  final String description;

  /// Builds the example for [constraints], the room inside its frame.
  final Widget Function(BoxConstraints constraints) build;

  /// Whether the example binds Esc itself, so Esc does not go up there.
  final bool ownsEscape;

  /// Its name on a gallery card, `Text area` for `text_area`.
  final String title;

  /// What it shows, as a card says it in a sentence.
  final String blurb;

  /// The card's still picture of it: four rows of plain text.
  final List<String> preview;
}

/// The framework's examples the site runs. They live in the framework's
/// `example/`, outside this package's `lib/`, so the entrypoint that can
/// import them (`web/gallery.dart`) hands them in.
class Gallery {
  /// The gallery of [entries], in menu order, and README's example.
  const Gallery(this.entries, this.readme);

  /// No examples, for tests that do not open them.
  static final none = Gallery(const [], () => const SizedBox());

  /// The examples.
  final List<GalleryEntry> entries;

  /// README's example, as `example/main.dart` has it.
  final Widget Function() readme;

  /// The entry called [name], if there is one.
  GalleryEntry? operator [](String name) {
    for (final entry in entries) {
      if (entry.name == name) return entry;
    }
    return null;
  }
}
