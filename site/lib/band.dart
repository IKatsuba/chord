import 'package:chord_tui/chord_tui.dart';

/// A green band edge to edge: 3 rows, [slogans] in ink bold on green on
/// the middle one, 2 columns in, repeated to [width] and clipped there.
class Band extends StatelessWidget {
  /// [slogans] across [width] columns.
  const Band(this.slogans, {super.key, required this.width});

  /// What repeats, its own separator at its end.
  final String slogans;

  /// The band's width.
  final int width;

  @override
  Widget build(BuildContext context) {
    final face = Theme.of(
      context,
    ).accent.merge(const Style(bold: true, inverse: true));
    final line = '  ${slogans * (width ~/ slogans.length + 2)}';
    return Box(
      background: face,
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(''),
          Text(line, style: face, softWrap: false),
          Text(''),
        ],
      ),
    );
  }
}
