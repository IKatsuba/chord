import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/selection_layout.dart';

void main() {
  final open = SelectionSource.markdown(
    id: 'reply',
    revision: 0,
    text: '> - item\n>\n>   ~~~sh\n>   \techo',
  );
  final before = open.codeBlocks.single;
  final closed = SelectionSource.markdown(
    id: 'reply',
    revision: 1,
    text: '> - item\n>\n>   ~~~sh\n>   \techo\n>   ~~~~',
    previous: open,
  );
  final after = closed.codeBlocks.single;
  if (before.complete ||
      !after.complete ||
      before.id != after.id ||
      after.text != '\techo') {
    throw StateError('Nested closure adapter or immutable descriptor failed.');
  }
  for (final width in [120, 80]) {
    final source = SelectionSource.markdown(
      id: 'plain',
      revision: 0,
      text: 'first\n\n```sh\n\techo 👩‍💻 e\u0301 界\n\nend\n```',
    );
    final shape = shapeSelectionSource(source, width: width);
    if (shape.selectedText != 'first\n \n\techo 👩‍💻 e\u0301 界\n\nend') {
      throw StateError('Semantic source projection failed.');
    }
  }
  print('SELECTION_SOURCE_PASS');
}
