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
  GalleryEntry(
    'demo',
    'themes, text and layout',
    (_) => const demo.Demo(),
    title: 'Demo',
    blurb: 'The framework tour: layout, focus and keys.',
    preview: const [
      '┌ left ─┐┌ right ──┐',
      '│ one   ││ focused  │',
      '│ two   ││ ❯ three  │',
      '└───────┘└──────────┘',
    ],
  ),
  GalleryEntry(
    'markdown',
    'Markdown, and a streamed reply',
    (_) => const markdown.MarkdownExample(),
    title: 'Markdown',
    blurb: 'Headings, lists, tables and code, streamed as it arrives.',
    preview: const [
      '# Release notes',
      '',
      '- **Plans** you can edit',
      '- Faster `resume`',
    ],
  ),
  GalleryEntry(
    'picker',
    'numbered choices with a fuzzy filter',
    (_) => const picker.PickerExample(),
    ownsEscape: true,
    title: 'Picker',
    blurb: 'Numbered choices with a fuzzy filter as you type.',
    preview: const [
      '› clau█',
      '',
      '› 1 claude    opus',
      '  2 claude    sonnet',
    ],
  ),
  GalleryEntry(
    'form',
    'validated fields, choices and buttons',
    // A short room scrolls the fields, as `--narrow` does.
    (constraints) =>
        form.FormExample(maxRows: constraints.maxHeight < 20 ? 8 : null),
    ownsEscape: true,
    title: 'Form',
    blurb: 'Validated fields, choices and buttons.',
    preview: const [
      'Name   chord█',
      'Agent  ( ) codex (•) claude',
      '',
      '[ Save ]  [ Cancel ]',
    ],
  ),
  GalleryEntry(
    'text_area',
    'multiline editing, wrapping and scrolling',
    (_) => const text_area.TextAreaExample(),
    title: 'Text area',
    blurb: 'Multiline editing with wrapping and scrolling.',
    preview: const [
      'The quick brown fox',
      'jumps over the lazy█',
      '',
      '3:20  wrapped',
    ],
  ),
  GalleryEntry(
    'diff',
    'numbered, highlighted, wrapped diffs',
    (_) => const diff.DiffExample(),
    title: 'Diff',
    blurb: 'Numbered, highlighted, wrapped unified diffs.',
    preview: const [
      '12  - final store = Store();',
      '12  + final store = Records();',
      '13    store.open(dir);',
      '',
    ],
  ),
  GalleryEntry(
    'dialog',
    'a framed question over the window',
    (_) => const dialog.DialogExample(),
    ownsEscape: true,
    title: 'Dialog',
    blurb: 'A framed question over the window.',
    preview: const [
      '┌ Delete session? ──┐',
      '│ It cannot return. │',
      '│ › Yes    No       │',
      '└───────────────────┘',
    ],
  ),
  GalleryEntry(
    'layers',
    'anchored layers over a streaming list',
    // Esc closes its picker while one is open, and goes up otherwise.
    (_) => const layers.Layers(),
    title: 'Layers',
    blurb: 'Anchored layers over a streaming list.',
    preview: const [
      'row 18  streaming…',
      'row 19  ┌ hint ─────',
      'row 20  │ Tab: more',
      'row 21  └───────────',
    ],
  ),
  GalleryEntry(
    'mouse',
    'pointer reports and the wheel',
    (_) => const mouse.MouseExample(),
    title: 'Mouse',
    blurb: 'Pointer reports and the wheel, logged.',
    preview: const [
      'press  12,4  left',
      'drag   14,5',
      'wheel  down',
      'release 14,5',
    ],
  ),
];
