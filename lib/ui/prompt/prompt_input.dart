import 'package:chord_tui/chord_tui.dart';

import 'named_top.dart';
import 'prompt.dart';
import '../shortcuts/bindings.dart';
import '../theme/theme.dart';

/// The rounded prompt editor, its row gutter following the actual viewport.
class PromptInput extends StatefulWidget {
  const PromptInput({
    super.key,
    required this.controller,
    required this.windowRows,
    required this.onSubmit,
    required this.onOlder,
    required this.onNewer,
    this.walking = false,
    this.bash = false,
    this.completing = false,
    this.onChanged,
    this.autofocus = true,
    this.enabled = true,
    this.handleContinuation = true,
    this.unhandledKeys = const {},
    this.shouldHandleKey,
    this.onLayoutChanged,
    this.textSpanBuilder,
    this.keymap,
    this.chords = const [],
    this.over = const {},
    this.agent,
    this.onPressed,
  });

  final TextAreaController controller;
  final int windowRows;
  final void Function(String) onSubmit;
  final void Function() onOlder;
  final void Function() onNewer;
  final bool walking;
  final bool bash;
  final bool completing;
  final void Function(String)? onChanged;
  final bool autofocus;
  final bool enabled;
  final bool handleContinuation;
  final Set<String> unhandledKeys;
  final bool Function(KeyEvent)? shouldHandleKey;
  final void Function(TextAreaLayout)? onLayoutChanged;
  final TextSpan Function(BuildContext, String)? textSpanBuilder;

  /// The keybindings file over chord's keys; the defaults when null.
  final Keybindings? keymap;

  /// The window's chords that would run now: a text area key that begins
  /// one is left to them.
  final List<Chord> chords;

  /// The contexts open over the prompt, a completion list's or the
  /// shortcuts panel's, which take every key they bind ahead of it.
  final Set<KeyContext> over;

  /// The child the prompt goes to, named on the box's top and colouring its
  /// edge; none for main, which is never named.
  final PromptAgent? agent;

  /// A pointer press on the box, border included: the original's
  /// `onMouseDown`, which gives the keys back from the agents list.
  final void Function()? onPressed;

  @override
  State<PromptInput> createState() => _PromptInputState();
}

class _PromptInputState extends State<PromptInput> {
  TextAreaLayout? _viewport;
  final _node = FocusNode(debugLabel: 'prompt');
  final _gate = FocusNode(canRequestFocus: false);

  @override
  void didUpdateWidget(PromptInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      context.owner.afterLayout(() {
        if (mounted && widget.enabled) _node.requestFocus();
      });
    }
  }

  /// The window's focus manager, heard for its pending chord.
  FocusManager? _manager;

  /// Whether a chord waits for its next key: the prompt hides its cursor
  /// meanwhile, as the original's box gives up its keys.
  bool _chordWaits = false;

  void _pendingChanged() {
    final waits = _manager?.pendingChord.isNotEmpty ?? false;
    if (waits != _chordWaits && mounted) setState(() => _chordWaits = waits);
  }

  @override
  void dispose() {
    _manager?.removeListener(_pendingChanged);
    _node.dispose();
    _gate.dispose();
    super.dispose();
  }

  void _layoutChanged(TextAreaLayout layout) {
    setState(() => _viewport = layout);
    widget.onLayoutChanged?.call(layout);
  }

  /// Whether ↑ and ↓ reach history, as the file binds them; a list shown
  /// takes them whatever history's keys are.
  bool _upOlder = true, _downNewer = true;

  /// The prompt's own keys, which the text area does not type.
  Set<KeyCombo> _own = const {};

  /// What the prompt's one-key bindings do, by key, for a shifted character
  /// that is no letter, which the framework does not match to them.
  Map<KeyCombo, void Function()> _ownActions = const {};

  void _send() {
    if (!widget.handleContinuation || !widget.controller.continueLine()) {
      widget.onSubmit(widget.controller.text);
    }
  }

  bool _capture(KeyEvent event) {
    final plain = _plain(event);
    if (plain == event.combo ||
        context.owner.focusManager.pendingChord.isNotEmpty) {
      return false;
    }
    final action = _ownActions[plain];
    if (action == null) return false;
    action();
    return true;
  }

  void _edge(TextAreaDirection direction) {
    if (direction == TextAreaDirection.up) {
      if (_upOlder) widget.onOlder();
    } else if (_downNewer) {
      widget.onNewer();
    }
  }

  /// cmd+↑ and cmd+↓, which the original's box reads as ↑ and ↓: history's
  /// while walking or on the text's first or last row; otherwise nothing,
  /// the text area's own move to the text's ends being held from it.
  void _super(TextAreaDirection direction) {
    final layout = _viewport;
    final edge = layout == null
        ? true
        : direction == TextAreaDirection.up
        ? layout.cursorRow == 0
        : layout.cursorRow >= layout.rows.length - 1;
    if (widget.walking || edge) _edge(direction);
  }

  bool _onKey(KeyEvent event) {
    if (event.shift || (event.key != 'up' && event.key != 'down')) {
      return false;
    }
    // The original's press reads ↑ and ↓ with any modifier but shift as
    // ↑ and ↓, and its textarea binds none of these: history's while
    // walking or on the text's first or last row, else nothing. cmd has
    // its own bindings; a key the prompt binds stays the binding's.
    if ((event.ctrl || event.alt || event.meta || event.hyper) &&
        !event.superKey) {
      if (widget.completing || _own.contains(event.combo)) return false;
      _super(event.key == 'up' ? TextAreaDirection.up : TextAreaDirection.down);
      return true;
    }
    if (!widget.walking) return false;
    if (event.key == 'up' && _upOlder) {
      widget.onOlder();
      return true;
    }
    if (event.key == 'down' && _downNewer) {
      widget.onNewer();
      return true;
    }
    return false;
  }

  /// [event] as a binding names it: a character that is no letter carries
  /// its shift in itself, as the original's keystrokeOf reads it.
  static KeyCombo _plain(KeyEvent e) {
    final c = e.combo;
    return c.shift &&
            c.key.runes.length == 1 &&
            c.key.toUpperCase() == c.key.toLowerCase()
        ? KeyCombo.normalized(
            c.key,
            ctrl: c.ctrl,
            alt: c.alt,
            superKey: c.superKey,
            hyper: c.hyper,
            meta: c.meta,
          )
        : c;
  }

  @override
  Widget build(BuildContext context) {
    if (_manager == null) {
      _manager = context.owner.focusManager..addListener(_pendingChanged);
      _chordWaits = _manager!.pendingChord.isNotEmpty;
    }
    final theme = Theme.of(context);
    final edge = promptEdge(
      bash: widget.bash,
      bashStyle: chordThemeOf(context).bash,
      border: theme.border,
      agent: widget.agent?.colour,
    );
    final shown = _viewport?.shownRows ?? const <TextAreaRow>[];
    _gate.descendantsAreFocusable = widget.enabled;
    final keymap = widget.keymap ?? defaultKeymap;
    // The prompt's own chords hold their first keys from the text area, as
    // the window's do.
    final ownChords = [
      for (final action in const [
        'chat:submit',
        'chat:newline',
        'history:previous',
        'history:next',
      ])
        for (final keys in keysOf(keymap, action))
          if (keys.length > 1) Chord.parse(frameworkKeys(keys)),
    ];
    final off = textareaKeysOff(keymap, [...widget.chords, ...ownChords]);
    final completing = widget.completing;
    // A completion list shown takes its keys ahead of the prompt's, as the
    // original's Autocomplete context does.
    List<String> list(String action) => completing
        ? [for (final keys in keysOf(keymap, action)) frameworkKeys(keys)]
        : const [];
    final previous = list('autocomplete:previous');
    final next = list('autocomplete:next');
    final listed = {...previous, ...next};
    // Every key a context open over the prompt binds, and any chord
    // overlapping one, is that context's, whichever action it does.
    final yielded = [
      for (final b in keymap.bindings)
        if (widget.over.contains(b.context)) Chord.parse(frameworkKeys(b.keys)),
    ];
    bool overlaps(Chord a, Chord b) =>
        a == b || a.startsWith(b.combos) || b.startsWith(a.combos);
    List<String> prompt(List<String> keys) => [
      for (final k in keys)
        if (!yielded.any((y) => overlaps(y, Chord.parse(k)))) k,
    ];
    final newline = prompt(promptKeys(keymap, 'chat:newline', off));
    final older = prompt(promptKeys(keymap, 'history:previous', off));
    final newer = prompt(promptKeys(keymap, 'history:next', off));
    final submit = prompt([
      for (final keys in keysOf(keymap, 'chat:submit')) frameworkKeys(keys),
    ]);
    // ↑ and ↓ are the box's own unless the file gave one another action.
    final taken = {...submit, ...newline, ...older, ...newer, ...listed};
    _upOlder = completing
        ? previous.contains('up')
        : bound(keymap, 'history:previous', const [Keystroke('up')]);
    _downNewer = completing
        ? next.contains('down')
        : bound(keymap, 'history:next', const [Keystroke('down')]);
    _own = {
      for (final keys in taken) Chord.parse(keys).combos.first,
      for (final y in yielded) y.combos.first,
    };
    _ownActions = {
      for (final (list, action) in [
        (submit, _send),
        (newline, widget.controller.newline),
        (older, widget.onOlder),
        (newer, widget.onNewer),
        (previous, widget.onOlder),
        (next, widget.onNewer),
      ])
        for (final keys in list)
          if (Chord.parse(keys).length == 1)
            Chord.parse(keys).combos.first: action,
    };
    return Focus(
      focusNode: _gate,
      canRequestFocus: false,
      onKeyCapture: _capture,
      child: Actions(
        bindings: [
          // The text area never sends: every key of chat:submit is the
          // prompt's, Enter included.
          for (final keys in submit) Binding(keys, 'Send prompt', _send),
          for (final keys in newline)
            Binding(keys, 'Insert newline', widget.controller.newline),
          for (final keys in older)
            Binding(keys, 'Previous prompt', widget.onOlder),
          for (final keys in newer)
            Binding(keys, 'Next prompt', widget.onNewer),
          for (final keys in previous)
            Binding(keys, 'Previous completion', widget.onOlder),
          for (final keys in next)
            Binding(keys, 'Next completion', widget.onNewer),
          if (!completing && !taken.contains('up') && _upOlder)
            Binding('up', 'Previous prompt', widget.onOlder),
          if (!completing && !taken.contains('down') && _downNewer)
            Binding('down', 'Next prompt', widget.onNewer),
          if (!completing && !taken.contains('super+up') && _upOlder)
            Binding(
              'super+up',
              'Previous prompt',
              () => _super(TextAreaDirection.up),
            ),
          if (!completing && !taken.contains('super+down') && _downNewer)
            Binding(
              'super+down',
              'Next prompt',
              () => _super(TextAreaDirection.down),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.only(top: 1),
          child: _named(
            edge,
            _pressed(
              Box(
                border: Border.rounded.withStyle(edge.style),
                padding: const EdgeInsets.symmetric(horizontal: 1),
                // The viewport gutter follows the editor without sizing its parent.
                // A stale row count must not defer the transcript's new height.
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: TextArea(
                        cursorStyle: CursorStyle.steadyBlock,
                        showCursor: !_chordWaits,
                        controller: widget.controller,
                        autofocus: widget.autofocus && widget.enabled,
                        focusNode: _node,
                        maxHeight: promptRows(widget.windowRows),
                        onSubmit: widget.onSubmit,
                        onChanged: widget.onChanged,
                        onEdge: _edge,
                        onKey: _onKey,
                        // A key the prompt binds types nothing, as the original
                        // takes back what a bound key typed.
                        shouldHandleKey: (event) =>
                            !_own.contains(_plain(event)) &&
                            (widget.shouldHandleKey?.call(event) ?? true),
                        onLayoutChanged: _layoutChanged,
                        textSpanBuilder: widget.textSpanBuilder,
                        // The draft's selection takes the palette's, as the
                        // original's useSelectable gives it.
                        selectionStyle: chordThemeOf(context).selection,
                        unhandledKeys: {
                          ...widget.unhandledKeys,
                          ...off,
                          ...textareaKeysNotReached,
                          // The prompt's own keys, an arrow given another action
                          // included, are not the text area's.
                          for (final keys in taken)
                            '${Chord.parse(keys).combos.first}',
                          for (final y in yielded) '${y.combos.first}',
                          'enter',
                          'esc',
                          'home',
                          'end',
                          'shift+home',
                          'shift+end',
                          'shift+up',
                          'shift+down',
                          'pageup',
                          'pagedown',
                          'shift+pageup',
                          'shift+pagedown',
                        },
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 2,
                      child: SelectionContainer.disabled(
                        child: Column(
                          children: [
                            for (final row in shown)
                              Text(
                                '${widget.bash && gutterMark(row, shown) == '›' ? '!' : gutterMark(row, shown)} ',
                                style: gutterMark(row, shown) == '›'
                                    ? widget.bash
                                          ? chordThemeOf(context).bash
                                          : theme.text
                                    : theme.dim,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// [box], told [PromptInput.onPressed] of a pointer press on it.
  Widget _pressed(Widget box) {
    final pressed = widget.onPressed;
    return pressed == null
        ? box
        : Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => pressed(),
            child: box,
          );
  }

  /// [box] with the agent's name over its top border; the box alone for
  /// main. The original draws the name as a row of its own because its
  /// border title takes no colour; a row over the border draws the same.
  /// The box stays the stack's first child either way, so a switch keeps
  /// the text area it holds.
  Widget _named(PromptEdge edge, Widget box) {
    final agent = widget.agent;
    return Stack(
      children: [
        box,
        if (agent != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 1,
            child: NamedTop(name: agent.name, edge: edge, team: agent.team),
          ),
      ],
    );
  }
}
