import 'package:chord_tui/chord_tui.dart';

/// The one line a fixture shows once it is answered: the answer, then `r`
/// to ask again, which a fixture binds.
class AnswerLine extends StatelessWidget {
  /// The line for [answer].
  const AnswerLine(this.answer, {super.key});

  /// What was chosen.
  final String answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        '',
        children: [
          TextSpan(answer, style: theme.text.merge(Style.bold)),
          TextSpan('  ·  ', style: theme.dim),
          TextSpan('r', style: theme.text.merge(Style.bold)),
          TextSpan(' ask again', style: theme.dim),
        ],
      ),
      softWrap: false,
    );
  }
}
