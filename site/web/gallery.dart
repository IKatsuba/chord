import 'package:chord_site/gallery.dart';

// The framework's own examples, imported as they are: each library's main
// is never called, only its widget built.
import '../../packages/chord_tui/example/demo.dart' as demo;
import '../../packages/chord_tui/example/dialog.dart' as dialog;
import '../../packages/chord_tui/example/diff.dart' as diff;
import '../../packages/chord_tui/example/form.dart' as form;
import '../../packages/chord_tui/example/layers.dart' as layers;
import '../../packages/chord_tui/example/main.dart' as main_example;
import '../../packages/chord_tui/example/markdown.dart' as markdown;
import '../../packages/chord_tui/example/mouse.dart' as mouse;
import '../../packages/chord_tui/example/picker.dart' as picker;
import '../../packages/chord_tui/example/text_area.dart' as text_area;

/// The site's gallery, in the order the menu lists it, and README's
/// example.
final siteGallery = Gallery(_entries, () => const main_example.App());

final _entries = [
  GalleryEntry('demo', 'themes, text and layout', (_) => const demo.Demo()),
  GalleryEntry(
    'markdown',
    'Markdown, and a streamed reply',
    (_) => const markdown.MarkdownExample(),
  ),
  GalleryEntry(
    'picker',
    'numbered choices with a fuzzy filter',
    (_) => const picker.PickerExample(),
    ownsEscape: true,
  ),
  GalleryEntry(
    'form',
    'validated fields, choices and buttons',
    // A short room scrolls the fields, as `--narrow` does.
    (constraints) =>
        form.FormExample(maxRows: constraints.maxHeight < 20 ? 8 : null),
    ownsEscape: true,
  ),
  GalleryEntry(
    'text_area',
    'multiline editing, wrapping and scrolling',
    (_) => const text_area.TextAreaExample(),
  ),
  GalleryEntry(
    'diff',
    'numbered, highlighted, wrapped diffs',
    (_) => const diff.DiffExample(),
  ),
  GalleryEntry(
    'dialog',
    'a framed question over the window',
    (_) => const dialog.DialogExample(),
    ownsEscape: true,
  ),
  GalleryEntry(
    'layers',
    'anchored layers over a streaming list',
    // Esc closes its picker while one is open, and goes up otherwise.
    (_) => const layers.Layers(),
  ),
  GalleryEntry(
    'mouse',
    'pointer reports and the wheel',
    (_) => const mouse.MouseExample(),
  ),
];
