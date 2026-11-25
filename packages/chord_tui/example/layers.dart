import 'dart:async';

import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const Layers());

/// What ctrl+t picks: the terminal's own theme, or one forced over it.
enum _ThemeChoice { auto, dark, light, plain }

/// A streaming transcript with layers anchored above its prompt: a framed,
/// focused picker and frameless, passive completions, over a page that is
/// not rebuilt or relaid out by them.
class Layers extends StatefulWidget {
  /// The fixture; [stream] starts the transcript growing on a timer.
  const Layers({super.key, this.stream = true});

  /// Whether the transcript grows by itself from the start.
  final bool stream;

  /// How many times the page itself has been built.
  static var pageBuilds = 0;

  @override
  State<Layers> createState() => LayersState();
}

/// The fixture's state: the transcript, the anchor and the open layers.
class LayersState extends State<Layers> {
  final transcript = _Transcript();
  final scroll = ScrollController(follow: Follow.bottom);
  final link = LayerLink();

  /// Whether the anchor above the prompt is mounted.
  final anchored = ValueNotifier(true);

  /// How many rows the prompt takes; more rows move the anchor up.
  final promptRows = ValueNotifier(1);

  Timer? _timer;
  var _choice = _ThemeChoice.auto;
  late OverlayState _overlay;
  OverlayEntry? _picker, _completions;

  @override
  void initState() {
    super.initState();
    for (var i = 1; i <= 60; i++) {
      transcript.add(
        'line $i of the transcript, ${'scrolled back ' * (i % 4)}',
      );
    }
    if (widget.stream) _toggleStream();
  }

  void _toggleStream() => setState(() {
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
    } else {
      _timer = Timer.periodic(
        const Duration(milliseconds: 300),
        (_) => transcript.stream(),
      );
    }
  });

  /// Opens the picker, [tall] with more rows than fit; closes it when open.
  void togglePicker({bool tall = false}) {
    if (_closePicker()) return;
    final entry = OverlayEntry(
      builder: (_) => CompositedTransformFollower(
        link: link,
        followerAnchor: Alignment.bottomLeft,
        child: _Picker(
          tall: tall,
          onChosen: (choice) {
            transcript.add('chose $choice');
            _closePicker();
          },
          onClosed: _closePicker,
        ),
      ),
    );
    _overlay.insert(entry);
    _picker = entry;
  }

  bool _closePicker() {
    final entry = _picker;
    if (entry == null) return false;
    _picker = null;
    entry
      ..remove()
      ..dispose();
    return true;
  }

  /// Opens the completions, which leave focus on the prompt; closes them.
  void toggleCompletions() {
    final open = _completions;
    if (open != null) {
      _completions = null;
      open
        ..remove()
        ..dispose();
      return;
    }
    final entry = OverlayEntry(
      requestFocus: false,
      builder: (_) => CompositedTransformFollower(
        link: link,
        followerAnchor: Alignment.bottomLeft,
        child: const _Completions(),
      ),
    );
    _overlay.insert(entry);
    _completions = entry;
  }

  @override
  void dispose() {
    _timer?.cancel();
    transcript.dispose();
    scroll.dispose();
    anchored.dispose();
    promptRows.dispose();
    super.dispose();
  }

  ThemeData? _forced(BuildContext context) {
    final brightness = Theme.backgroundOf(context).brightness;
    return switch (_choice) {
      _ThemeChoice.auto => null,
      _ when Theme.noColorOf(context) => ThemeData.plain(
        brightness: brightness,
      ),
      _ThemeChoice.dark => ThemeData.dark(),
      _ThemeChoice.light => ThemeData.light(),
      _ThemeChoice.plain => ThemeData.plain(brightness: brightness),
    };
  }

  @override
  Widget build(BuildContext context) {
    final overlay = Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) {
            _overlay = Overlay.of(context);
            return _Page(this);
          },
        ),
      ],
    );
    final forced = _forced(context);
    return Actions(
      bindings: [
        Binding('ctrl+p', 'Picker', togglePicker),
        Binding('ctrl+x p', 'Tall picker', () => togglePicker(tall: true)),
        Binding('ctrl+o', 'Completions', toggleCompletions),
        Binding('ctrl+x a', 'Anchor', () => anchored.value = !anchored.value),
        Binding(
          'ctrl+x g',
          'Grow prompt',
          () => promptRows.value = promptRows.value % 4 + 1,
        ),
        Binding('ctrl+s', 'Stream', _toggleStream),
        Binding(
          'ctrl+t',
          'Theme',
          () => setState(
            () => _choice = _ThemeChoice
                .values[(_choice.index + 1) % _ThemeChoice.values.length],
          ),
        ),
        Binding('ctrl+q', 'Quit', () => exitApp(context)),
        ...scrollBindings(scroll),
      ],
      // Above the overlay, so the layers inherit it; always the same
      // wrapper, so a theme change keeps the overlay and its open layers.
      child: Theme(data: forced ?? Theme.of(context), child: overlay),
    );
  }
}

/// Lines that a stream appends to and extends.
class _Transcript extends ChangeNotifier {
  final List<String> lines = [];
  var _words = 0;

  void add(String line) {
    lines.add(line);
    _words = 0;
    notifyListeners();
  }

  void stream() {
    if (_words == 0 || _words >= 12) {
      lines.add('streamed');
      _words = 1;
    } else {
      lines[lines.length - 1] += ' word${lines.length}';
      _words++;
    }
    notifyListeners();
  }
}

class _Page extends StatelessWidget {
  const _Page(this.app);

  final LayersState app;

  @override
  Widget build(BuildContext context) {
    Layers.pageBuilds++;
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: app.transcript,
            builder: (_) => ListView.builder(
              controller: app.scroll,
              itemCount: app.transcript.lines.length,
              itemVersion: (i) => app.transcript.lines[i],
              itemBuilder: (_, i) => Text(app.transcript.lines[i]),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: app.anchored,
          builder: (_) => app.anchored.value
              ? CompositedTransformTarget(
                  link: app.link,
                  child: const SizedBox(height: 0),
                )
              : const SizedBox(),
        ),
        Text(''),
        ListenableBuilder(
          listenable: app.promptRows,
          builder: (_) => Focus(
            autofocus: true,
            debugLabel: 'prompt',
            child: Column(
              children: [
                for (var i = 0; i < app.promptRows.value; i++)
                  Text(
                    i == 0 ? '> /model' : '  more prompt',
                    style: theme.text,
                  ),
              ],
            ),
          ),
        ),
        _Status(app),
        const KeyHelp(),
      ],
    );
  }
}

/// The page's own numbers, which the layers must not change.
class _Status extends StatefulWidget {
  const _Status(this.app);

  final LayersState app;

  @override
  State<_Status> createState() => _StatusState();
}

class _StatusState extends State<_Status> {
  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.app.transcript.addListener(_changed);
    widget.app.scroll.addListener(_changed);
  }

  @override
  void dispose() {
    widget.app.transcript.removeListener(_changed);
    widget.app.scroll.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.app.scroll;
    return Text(
      'page builds ${Layers.pageBuilds} · rows ${s.contentRows} · '
      'offset ${s.offset} · ${s.isFollowing ? 'following' : 'scrolled back'}',
      style: Theme.of(context).dim,
      softWrap: false,
    );
  }
}

const _choices = ['Careful', 'Balanced', 'Quick', 'Thorough'];

/// A framed list of choices; it takes focus, and Esc closes it.
class _Picker extends StatelessWidget {
  const _Picker({
    required this.tall,
    required this.onChosen,
    required this.onClosed,
  });

  final bool tall;
  final void Function(String choice) onChosen;
  final void Function() onClosed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choices = [
      for (var i = 0; i < (tall ? 40 : _choices.length); i++)
        tall ? 'Choice ${i + 1}' : _choices[i],
    ];
    return Actions(
      bindings: [Binding('esc', 'Close', onClosed)],
      child: Box(
        border: Border.rounded.withStyle(theme.focus),
        title: 'Models',
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, c) in choices.indexed)
              _Choice(c, autofocus: i == 0, onChosen: () => onChosen(c)),
            Text('Esc to close', style: theme.dim),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatefulWidget {
  const _Choice(this.label, {required this.autofocus, required this.onChosen});

  final String label;
  final bool autofocus;
  final void Function() onChosen;

  @override
  State<_Choice> createState() => _ChoiceState();
}

class _ChoiceState extends State<_Choice> {
  late final node = FocusNode(debugLabel: widget.label);

  @override
  void dispose() {
    node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Actions(
      bindings: [Binding('enter', 'Choose', widget.onChosen)],
      child: Focus(
        focusNode: node,
        autofocus: widget.autofocus,
        child: ListenableBuilder(
          listenable: node,
          builder: (_) => node.hasPrimaryFocus
              ? Text('❯ ${widget.label}', style: theme.focus.merge(Style.bold))
              : Text('  ${widget.label}'),
        ),
      ),
    );
  }
}

/// Frameless completions under a dim rule; they take no focus.
class _Completions extends StatelessWidget {
  const _Completions();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (_, room) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('─' * room.maxWidth, style: theme.dim, softWrap: false),
          for (final c in const ['/clear', '/compact', '/config']) Text('  $c'),
        ],
      ),
    );
  }
}
