# chord_tui

The Flutter way, for the terminal: a Dart framework for rich terminal interfaces, compiled to one native binary.

Widgets, state, layout in cells, rich text and keyboard actions, with a headless tester. Written from scratch, with no dependency on another terminal UI framework. Supports macOS and Linux.

## Install

```sh
dart pub add chord_tui
```

Requires Dart 3.11.0 or later. Import `package:chord_tui/chord_tui.dart` in your app. Compile it with `dart compile exe` to run without a Dart runtime.

## The idea

```dart
import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const App());

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  var expanded = false;

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding('ctrl+o', 'Toggle tool details',
          () => setState(() => expanded = !expanded)),
      Binding('ctrl+q', 'Quit', () => exitApp(context)),
    ],
    child: Column(children: [
      Expanded(
        child: Fold(
          title: 'Run checks',
          open: expanded,
          child: Code(r'$ dart analyze', language: 'shell'),
        ),
      ),
      const KeyHelp(),
    ]),
  );
}
```

Ctrl+O opens or closes the fold; Ctrl+Q quits. The same app is in [example/main.dart](example/main.dart).

## What the framework gives

- **Widgets and state:** `StatelessWidget`, `StatefulWidget`, `setState`, `InheritedWidget` and `ErrorBoundary`.
- **Layout in cells:** flex rows and columns, constraints, stacks, anchored overlays and focus scopes. Focus survives eligible moves within a tree; crossing scopes cancels pending chords.
- **Text measured in cells:** graphemes, emoji, CJK and ANSI styles, wrapping and truncation without splitting graphemes.
- **Keys and actions:** bindings, chords, grouped help and runtime rebinding; kitty keyboard support with legacy input.
- **Rich widgets:** Markdown, highlighted code, numbered diffs, virtualised lists with bottom following, multiline editing with selection and movement by logical lines and displayed rows, fuzzy pickers, folds, tables, dialogs and validated forms.
- **Terminal services:** themes, cursors, clipboard copy, external editing, notifications, terminal user variables, system link opening (PowerShell on Windows and supported WSL setups; only failure to start the opener is reported), captured mouse drags and semantic text selection.
- **Rendering and tests:** changed cells are written per frame; widgets can be rendered and driven without a terminal.

`TextArea` binds OpenTUI's default editing keys, with descriptions for key help: character and word moves, word and line deletes, undo/redo and Shift selection. Super/Command+A selects all; Super/Command+Z and Super/Command+Shift+Z undo and redo. `TextArea.editingKeys` lists the bindings; pass keys in `unhandledKeys` to leave them to the app. Home/End are left out by default; pass an empty set to enable them.

Super/Command+Left/Right and Alt+A/Alt+E move to the displayed row's start/end. `TextAreaController.moveToRowStart(layout)` and `moveToRowEnd(layout)` use a `TextAreaLayout`; row end stays before the last grapheme when the line continues. Ctrl+A/Ctrl+E move to logical line ends, stepping over the break when already there; Ctrl+U at a line's start joins the lines.

`TextAreaController.selection` is a `TextSelection` in grapheme offsets; `selectedText` reads it and moves with `select: true` extend it. Typing, paste, character and word deletes replace it. Plain horizontal moves collapse it to an edge; vertical moves clear it before moving. `TextArea.selectionStyle` overrides `Theme.selection` over the text's own styles. No copy key is bound.

`Terminal.setUserVariable(name, value)` sets an OSC 1337 user variable; `StdioTerminal` forwards it through tmux. Names must be nonempty and contain only ASCII letters, digits and underscores. `userVariableBytes` builds the sequence with a base64 UTF-8 value; `tmuxPassthrough` wraps bytes for tmux with `allow-passthrough` enabled.

## Examples

From this package's folder in the [repository](https://github.com/IKatsuba/chord), run `dart pub get`, then `dart run` with a path below:

- Start with [example/main.dart](example/main.dart); [example/demo.dart](example/demo.dart) cycles themes with Ctrl+T.
- Rich text: [Markdown](example/markdown.dart), [recorded copy/run actions](example/markdown_run_controls.dart), [code](example/code.dart), [diffs](example/diff.dart), [selected diff rows](example/diff_view.dart), [middle truncation](example/middle.dart) and [table/URL wrapping](example/markdown_wrap.dart).
- Editing: [text area](example/text_area.dart), [viewport and gutter](example/text_area_viewport.dart), [styled spans](example/text_area_spans.dart) and [key delegation](example/text_area_key_filter.dart).
- Keys, services and mouse: [key help](example/key_help.dart) (`--rebound`), [terminal services](example/terminal_services.dart) (`--scripted-editor`), [mouse](example/mouse.dart) and [selection](example/selection.dart).
- Layers and choices: [layers](example/layers.dart), [overlay visibility](example/overlay_visibility.dart) (`--passive`), [picker](example/picker.dart), [picker preview](example/picker_preview.dart), [fold and table](example/fold.dart), [dialog](example/dialog.dart) and [form](example/form.dart) (`--narrow --long-list`).
- Failure recovery: [error boundary](example/error_boundary.dart).

## Testing

Add `test` as a development dependency with `dart pub add --dev test`. Import `package:chord_tui/testing.dart` to render widgets, press keys and inspect their cells without opening a terminal:

```dart
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('Esc cancels a dialog', (tester) async {
    var canceled = false;
    await tester.pumpWidget(
      Dialog<void>(
        title: Text('Notice'),
        onCanceled: () => canceled = true,
        child: Text('Checks passed'),
      ),
      size: Size(80, 24),
    );
    expect(tester.screen, shows('Checks passed'));
    await tester.press('esc');
    expect(canceled, isTrue);
  });
}
```

Save the test under `test/` and run `dart test`. In the repository, this package's own tests also run with `dart test` from `packages/chord_tui/`.

## Repository and app

[Source, issues and contributing](https://github.com/IKatsuba/chord) live in the chord repository. The [chord app](https://github.com/IKatsuba/chord#readme), a terminal client for ACP coding agents, uses this framework and lives at the repository root.

## Credits

The fuzzy matcher is ported from [fzf-for-js](https://github.com/ajitid/fzf-for-js) by Ajit, under the BSD-3-Clause licence; its notice is retained in [fzf.dart](lib/src/text/fzf.dart).

`TextLayout.wrapAnsi` is ported from [wrap-ansi](https://github.com/chalk/wrap-ansi) 10.0.2 by Sindre Sorhus, under the MIT licence; its notice is retained in [wrap_ansi.dart](lib/src/text/wrap_ansi.dart).
