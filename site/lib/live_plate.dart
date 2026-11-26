import 'package:chord_tui/chord_tui.dart';

import 'palette.dart';
import 'site.dart' show siteKeys;

/// Whether a live plate on the page is entered, which the shell reads: while
/// one is, the shell's own letter and digit keys step aside for the example.
class LiveScope extends InheritedWidget {
  /// [entered] for the plates under [child].
  const LiveScope({super.key, required this.entered, required super.child});

  /// True while a plate holds the keys.
  final ValueNotifier<bool> entered;

  /// The nearest scope's notifier, if there is one.
  static ValueNotifier<bool>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LiveScope>()?.entered;

  @override
  bool updateShouldNotify(LiveScope oldWidget) => entered != oldWidget.entered;
}

/// Enters and leaves a [LivePlate] from the page that holds the focus.
class LivePlateController extends ChangeNotifier {
  _LivePlateState? _plate;

  /// Whether the plate holds the keys.
  bool get entered => _plate?._entered ?? false;

  /// Gives the plate's example the keys.
  void enter() => _plate?._enter();

  /// Gives the keys back to the page.
  void leave() => _plate?._leave();
}

/// A live example in a cream FIG. plate: it draws and runs while the page
/// holds the focus, and takes the keys only once entered (Tab, through its
/// [controller]). Esc leaves, or Ctrl+Q where the example binds Esc; F1,
/// Ctrl+Q and Ctrl+C never reach the example.
class LivePlate extends StatefulWidget {
  /// FIG. [figure], [title], [rows] tall inside, running [child].
  const LivePlate({
    super.key,
    required this.controller,
    required this.figure,
    this.figureDigits = 1,
    required this.title,
    this.idle,
    required this.rows,
    this.focusNode,
    this.onEscape,
    required this.home,
    required this.child,
    this.ownsEscape = false,
  });

  /// Enters and leaves it.
  final LivePlateController controller;

  /// The figure's number on its page.
  final int figure;

  /// The digits the figure's number takes: 2 writes `01`.
  final int figureDigits;

  /// What it shows, in caps on the caption row.
  final String title;

  /// The example's rows.
  final int rows;

  /// The caption while not entered; [title] and how to enter by default.
  final String? idle;

  /// The node a page's Tab focuses the plate with; Enter enters it then,
  /// and its caption says so. None: the plate takes no focus of its own.
  final FocusNode? focusNode;

  /// Esc on the focused plate, not entered: the page takes the focus back.
  final void Function()? onEscape;

  /// Goes home: Ctrl+Q inside, where Esc leaves.
  final void Function() home;

  /// Builds the example for the room inside the plate.
  final Widget Function(BoxConstraints constraints) child;

  /// Whether the example binds Esc, so Ctrl+Q leaves instead.
  final bool ownsEscape;

  static final _esc = KeyCombo.parse('esc');
  static final _scrolls = {
    for (final key in ['up', 'down', 'pageup', 'pagedown', 'home', 'end'])
      KeyCombo.parse(key),
  };
  static final _quits = {KeyCombo.parse('ctrl+q'), KeyCombo.parse('ctrl+c')};

  /// The keys the site takes before the example: its quits, and F1.
  static final taken = {..._quits, KeyCombo.parse('f1')};

  @override
  State<LivePlate> createState() => _LivePlateState();
}

class _LivePlateState extends State<LivePlate> {
  final _scope = FocusScopeNode(debugLabel: 'live plate', active: false);
  var _entered = false;
  ValueNotifier<bool>? _live;

  @override
  void initState() {
    super.initState();
    widget.controller._plate = this;
    widget.focusNode?.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(LivePlate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_focusChanged);
      widget.focusNode?.addListener(_focusChanged);
    }
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller._plate == this) {
        oldWidget.controller._plate = null;
      }
      widget.controller._plate = this;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _live = LiveScope.maybeOf(context);
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_focusChanged);
    if (widget.controller._plate == this) widget.controller._plate = null;
    if (_entered) _live?.value = false;
    _scope.dispose();
    super.dispose();
  }

  void _enter() {
    if (_entered || !mounted) return;
    context.owner.focusManager.setScopeActive(_scope, true, takeFocus: true);
    setState(() => _entered = true);
    _live?.value = true;
    widget.controller.notifyListeners();
  }

  void _leave() {
    if (!_entered || !mounted) return;
    context.owner.focusManager.setScopeActive(_scope, false);
    setState(() => _entered = false);
    _live?.value = false;
    widget.controller.notifyListeners();
  }

  bool _capture(KeyEvent event) {
    if (!_entered) return false;
    final key = event.combo;
    if (key == LivePlate._esc && !widget.ownsEscape) {
      _leave();
      return true;
    }
    if (LivePlate._quits.contains(key)) {
      if (widget.ownsEscape) {
        _leave();
      } else {
        _leave();
        widget.home();
      }
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<SitePalette>() ?? const SitePalette();
    final cream = theme.text.merge(const Style(inverse: true));
    final bold = cream.merge(Style.bold);
    final orange = theme.accent.merge(const Style(bold: true, inverse: true));
    final leaves = widget.ownsEscape ? 'CTRL+Q LEAVES' : 'ESC LEAVES';
    final focused = widget.focusNode?.hasPrimaryFocus ?? false;
    final tag = _entered ? leaves : (focused ? '⏎ ENTER' : null);
    final plate = Box(
      background: cream,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    '',
                    children: [
                      // Orange on the cream: the colours swapped back by inverse.
                      TextSpan(
                        'FIG. ${widget.figure.toString().padLeft(widget.figureDigits, '0')} ',
                        style: Style(
                          fg: SiteColors.cream,
                          bg: theme.accent.fg,
                          bold: true,
                          inverse: true,
                        ),
                      ),
                      TextSpan(
                        _entered
                            ? widget.title.toUpperCase()
                            : (widget.idle ?? '${widget.title} · TAB TO ENTER')
                                  .toUpperCase(),
                        style: bold,
                      ),
                    ],
                  ),
                  softWrap: false,
                ),
              ),
              // On the right of the caption row: how to leave, or Enter.
              if (tag != null) Text(' $tag ', style: orange, softWrap: false),
            ],
          ),
          Text('', style: cream),
          SizedBox(
            height: widget.rows,
            // Entered, the room keeps the wheel: the example's own scrolling
            // takes it, and the page under it does not move.
            child: Listener(
              absorbPointerSignal: _entered,
              child: Box(
                background: palette.ink,
                child: Focus(
                  canRequestFocus: false,
                  onKeyCapture: _capture,
                  // What the capture does, for the help row, over the shell's
                  // own Esc and Ctrl+Q: the inner ones shadow them.
                  child: Actions(
                    bindings: [
                      if (!widget.ownsEscape)
                        Binding('esc', 'leave', _leave, id: '${siteKeys}leave'),
                      for (final key in ['ctrl+q', 'ctrl+c'])
                        Binding(
                          key,
                          widget.ownsEscape ? 'leave' : 'home',
                          () {},
                          id: widget.ownsEscape
                              ? '${siteKeys}leave'
                              : '${siteKeys}home',
                        ),
                    ],
                    child: KeyHelpBoundary(
                      taken: LivePlate.taken,
                      // A key the entered example leaves goes no further than
                      // the plate, save the page's scroll keys: the arrows go
                      // to the example first and scroll the page otherwise.
                      child: Focus(
                        canRequestFocus: false,
                        onKey: (event) =>
                            _entered &&
                            !LivePlate._scrolls.contains(event.combo),
                        child: FocusScope(
                          node: _scope,
                          child: LayoutBuilder(
                            builder: (context, c) => widget.child(c),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final node = widget.focusNode;
    if (node == null) return plate;
    // Focused and not entered, Enter enters and Esc gives the page back;
    // entered, these step aside for the example's own.
    final waiting = focused && !_entered;
    return Actions(
      bindings: [
        Binding('enter', 'enter it', _enter, enabled: waiting),
        if (widget.onEscape case final back?)
          Binding('esc', 'back to the page', back, enabled: waiting),
      ],
      child: Focus(focusNode: node, child: plate),
    );
  }
}
