import '../foundation/picker_state.dart';
import '../rendering/flex.dart';
import '../text/layout.dart';
import 'basic.dart';
import 'framework.dart';
import 'theme.dart';

/// One choice as Picker and Dialog draw it: the `❯` gutter, an optional
/// edge column, the padded number and the label or [content].
class PickerRow extends StatelessWidget {
  /// Row [index] of [count].
  const PickerRow({
    super.key,
    required this.index,
    required this.count,
    required this.label,
    required this.highlighted,
    this.edgeColumn = false,
    this.showNumbers = true,
    this.content,
  });

  /// Its place among the results, from 0.
  final int index;

  /// How many results there are, which pads the number.
  final int count;

  /// The label, drawn on one line and cut when [content] is null.
  final String label;

  /// Whether it is the highlighted row.
  final bool highlighted;

  /// Whether to leave the two cells the scroll edges are drawn in.
  final bool edgeColumn;

  /// Whether the padded number column is drawn before the content.
  final bool showNumbers;

  /// What to draw instead of the label.
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = pickerNumber(index, count);
    // Marked by colour, not weight, as a list shows its selected row.
    final style = highlighted ? theme.focus : theme.text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 2,
          child: Text(highlighted ? '❯' : ' ', style: theme.focus),
        ),
        if (edgeColumn) const SizedBox(width: 2),
        if (showNumbers)
          SizedBox(
            width: number.length + 1,
            child: Text(number, style: style),
          ),
        // Custom content inherits the row's style, so every line of a
        // highlighted choice takes it; its own styles still win.
        Expanded(
          child: DefaultTextStyle(
            style: DefaultTextStyle.of(context).merge(style),
            child:
                content ??
                Text(label, softWrap: false, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}
