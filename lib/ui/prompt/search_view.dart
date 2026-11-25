import 'package:chord_tui/chord_tui.dart';

import 'prompt_input.dart';
import 'search.dart';

/// The original passive full prompt, styled through its actual editor viewport.
class SearchPrompt extends StatefulWidget {
  const SearchPrompt({
    super.key,
    required this.text,
    required this.cursor,
    required this.query,
    required this.windowRows,
    required this.bash,
    required this.onLayoutChanged,
  });
  final String text, query;
  final int cursor, windowRows;
  final bool bash;
  final void Function(TextAreaLayout) onLayoutChanged;
  @override
  State<SearchPrompt> createState() => _SearchPromptState();
}

class _SearchPromptState extends State<SearchPrompt> {
  late final _shown = TextAreaController(text: widget.text)
    ..cursor = widget.cursor;
  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
    child: PromptInput(
      controller: _shown,
      windowRows: widget.windowRows,
      bash: widget.bash,
      enabled: false,
      autofocus: false,
      onLayoutChanged: widget.onLayoutChanged,
      textSpanBuilder: (_, text) => TextSpan(
        '',
        children: [
          for (final piece in foundPieces(text, widget.query))
            TextSpan(piece.text, style: piece.found ? Style.inverse : null),
        ],
      ),
      onSubmit: (_) {},
      onOlder: () {},
      onNewer: () {},
    ),
  );
}

/// The passive query row and dim rule over the transcript, outside footer flow.
class SearchLine extends StatelessWidget {
  const SearchLine({super.key, required this.search});
  final Search search;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, room) {
      final rows = room.maxHeight.clamp(0, 2);
      if (rows == 0 || room.maxWidth <= 0) return const SizedBox();
      final theme = Theme.of(context);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Text(
              '─' * (room.maxWidth - 2).clamp(0, unbounded),
              style: theme.dim,
              softWrap: false,
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ),
          if (rows > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text.rich(
                TextSpan(
                  '',
                  children: [
                    TextSpan(searchLabel(search), style: theme.dim),
                    TextSpan(' ${search.query}'),
                    const TextSpan(' ', style: Style.inverse),
                  ],
                ),
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.middle,
              ),
            ),
        ],
      );
    },
  );
}
