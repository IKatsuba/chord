/// One row of an example page's Keys: the keys in bold, then what they do.
/// A row that is not keys at all (`type`) is drawn the same and left out of
/// the check that every key is bound.
typedef KeyRow = ({List<String> keys, String words, bool bound});

KeyRow _keys(List<String> keys, String words) =>
    (keys: keys, words: words, bound: true);

/// What each example page says under its title.
const exampleLedes = {
  'demo':
      'The framework\'s tour: themes, text and layout in one window, with a '
      'log you can clear and fill by a chord of two keys.',
  'markdown':
      'A reply with every block Markdown draws, streamed in chunk by chunk: '
      'headings, lists, quotes, code, tables and links, wrapped to the width '
      'they get.',
  'picker':
      'A searchable picker of thirty choices, some of them two lines tall, '
      'with what was chosen under it. Type to filter; a digit or Enter '
      'chooses.',
  'form':
      'A form of seven fields, one of each kind, checked as you go, with the '
      'values it gave under it.',
  'text_area':
      'A framed multiline editor: Enter sends what is written and clears it, '
      'shift+enter adds a line, and four rows scroll with the cursor.',
  'diff':
      'Diffs of several shapes, numbered, highlighted and wrapped: the '
      'framework\'s Diff widget on its own.',
  'dialog':
      'A dialog anchored above a prompt, the way chord asks for a permission. '
      'Esc or a choice closes it; ctrl+o opens it again.',
  'layers':
      'A streaming transcript with layers anchored above its prompt: a framed '
      'picker and passive completions, over a page they never lay out again.',
  'mouse':
      'Typed mouse reports beside a log the keyboard scrolls and a focused '
      'draft. Click, drag and use the wheel inside the frame.',
};

/// Each example's own keys, as its Keys section lists them.
final exampleKeys = <String, List<KeyRow>>{
  'demo': [
    _keys(['ctrl+t'], 'theme'),
    _keys(['ctrl+x c'], 'clear the log'),
    _keys(['ctrl+x f'], 'fill the log'),
  ],
  'markdown': [
    _keys(['ctrl+s'], 'stream again'),
    _keys(['ctrl+t'], 'theme'),
    _keys(['pageup', 'pagedown'], 'scroll'),
  ],
  'picker': [
    (keys: ['type'], words: 'filter', bound: false),
    _keys(['up', 'down'], 'move'),
    _keys(['enter'], 'choose'),
  ],
  'form': [
    _keys(['tab', 'shift+tab'], 'fields'),
    _keys(['enter'], 'submit'),
  ],
  'text_area': [
    _keys(['enter'], 'send'),
    _keys(['shift+enter'], 'new line'),
  ],
  'diff': [
    _keys(['ctrl+t'], 'theme'),
    _keys(['pageup', 'pagedown'], 'scroll'),
  ],
  'dialog': [
    _keys(['ctrl+o'], 'open'),
    _keys(['esc'], 'close'),
  ],
  'layers': [
    _keys(['ctrl+p'], 'picker'),
    _keys(['ctrl+x p'], 'tall picker'),
    _keys(['ctrl+o'], 'completions'),
    _keys(['ctrl+x a'], 'anchor'),
    _keys(['ctrl+s'], 'stream'),
  ],
  'mouse': [
    _keys(['ctrl+l'], 'clear the log'),
  ],
};

/// The overview's lede.
const overviewLede =
    'The Flutter way, for the terminal: a Dart framework for rich terminal '
    'interfaces, compiled to a native binary or WebAssembly.';

/// The overview's "What it is", a paragraph a string.
const overviewWhat = [
  'Widgets, state, layout in cells, rich text and keyboard actions, with a '
      'headless tester. Written from scratch, with no dependency on another '
      'terminal UI framework.',
  'If you know Flutter you know the names: StatelessWidget, StatefulWidget, '
      'setState, Row, Column, Expanded, Theme.of. It runs on macOS, Linux and '
      'in browsers. This page is a chord_tui app, compiled to WebAssembly.',
];

/// The overview's words over README's example.
const overviewExample =
    "README's example, running: a tool call's output under a fold. Tab enters "
    'it, ctrl+o opens and closes the fold, Esc leaves.';

/// The overview's words over the testing example.
const overviewTesting =
    'Widget tests need no terminal: pump a widget at a size, press keys, '
    'check the screen.';

/// What `dart pub add` installs the framework with.
const pubAddCommand = 'dart pub add chord_tui';

/// chord_tui's API documentation on pub.dev.
const apiDocsUrl = 'https://pub.dev/documentation/chord_tui/latest/';

/// chord_tui's folder in the repository.
const frameworkSourceUrl =
    'https://github.com/IKatsuba/chord/tree/main/packages/chord_tui';

/// An example's file on GitHub, on main.
String exampleSourceUrl(String name) =>
    'https://github.com/IKatsuba/chord/blob/main/packages/chord_tui/example/'
    '$name.dart';
