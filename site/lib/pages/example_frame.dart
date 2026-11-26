import 'package:chord_tui/chord_tui.dart';

/// A framework example running in a frame under a one-line [caption].
///
/// Ctrl+Q and Ctrl+C are taken before the example sees them and go [home]:
/// every example quits by them, and the site never quits.
class ExampleFrame extends StatelessWidget {
  /// [child] framed under [caption], titled [title].
  const ExampleFrame({
    super.key,
    required this.title,
    required this.caption,
    required this.home,
    required this.child,
  });

  /// The frame's title.
  final String title;

  /// What the example is, and the way out of it.
  final String caption;

  /// Goes home.
  final void Function() home;

  /// Builds the example for the room inside the frame.
  final Widget Function(BoxConstraints constraints) child;

  static final _quits = [KeyCombo.parse('ctrl+q'), KeyCombo.parse('ctrl+c')];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 1, right: 1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(caption, style: Theme.of(context).dim, softWrap: false),
        Expanded(
          child: Box(
            title: title,
            child: Focus(
              onKeyCapture: (event) {
                if (!_quits.contains(event.combo)) return false;
                home();
                return true;
              },
              child: LayoutBuilder(builder: (context, c) => child(c)),
            ),
          ),
        ),
      ],
    ),
  );
}
