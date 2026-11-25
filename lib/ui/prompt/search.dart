/// Reverse prompt search: literal, case-sensitive, newest distinct prompt first.
class Search {
  const Search({this.query = '', this.match, this.failed = false});
  final String query;
  final int? match;
  final bool failed;
}

/// No query yet: the prompt continues to show the saved draft.
const emptySearch = Search();

int? _find(List<String> prompts, String query, int before) {
  if (query.isEmpty) return null;
  for (var index = before - 1; index >= 0; index--) {
    final prompt = prompts[index];
    if (prompt.contains(query) && prompts.lastIndexOf(prompt) == index) {
      return index;
    }
  }
  return null;
}

/// A changed query restarts at newest; a miss retains the last match.
Search searched(Search search, List<String> prompts, String query) {
  final match = _find(prompts, query, prompts.length);
  return match == null
      ? Search(
          query: query,
          match: query.isEmpty ? null : search.match,
          failed: query.isNotEmpty,
        )
      : Search(query: query, match: match);
}

/// Ctrl+R takes the next older distinct match, retaining it at exhaustion.
Search searchedOlder(Search search, List<String> prompts) {
  final match = _find(prompts, search.query, search.match ?? prompts.length);
  if (match == null) {
    return search.query.isEmpty || search.failed
        ? search
        : Search(query: search.query, match: search.match, failed: true);
  }
  return Search(query: search.query, match: match);
}

/// The shown full prompt, or null while the saved draft remains visible.
String? matched(Search search, List<String> prompts) {
  final index = search.match;
  return index == null || index < 0 || index >= prompts.length
      ? null
      : prompts[index];
}

final _firstLine = RegExp(r'\r?\n|\r');
final _controls = RegExp(r'[\x00-\x1f\x7f-\x9f]');

/// One query edit; modified non-edit keys and empty/control input return null.
String? editedQuery(
  String query,
  String input, {
  bool ctrl = false,
  bool meta = false,
  bool backspace = false,
  bool delete = false,
}) {
  if (backspace || delete) {
    final points = query.runes.toList();
    return String.fromCharCodes(
      points.take(points.isEmpty ? 0 : points.length - 1),
    );
  }
  if (ctrl || meta) return null;
  final text = input.split(_firstLine).first.replaceAll(_controls, '');
  return text.isEmpty ? null : query + text;
}

/// Original search status words, retaining the match after a failed step.
String searchLabel(Search search) =>
    search.failed ? 'no matching prompt:' : 'search prompts:';

/// Escapes a query for literal global matching through RegExp.allMatches.
RegExp? queryPattern(String query) =>
    query.isEmpty ? null : RegExp(RegExp.escape(query));

/// A source-text run and whether the literal query found it.
typedef FoundPiece = ({String text, bool found});

/// All nonoverlapping literal hits; no wrapping, normalization or fuzzy match.
List<FoundPiece> foundPieces(String text, String query) {
  final pattern = queryPattern(query);
  final pieces = <FoundPiece>[];
  var at = 0;
  for (final match in pattern?.allMatches(text) ?? const <RegExpMatch>[]) {
    if (match.start > at) {
      pieces.add((text: text.substring(at, match.start), found: false));
    }
    pieces.add((text: match[0]!, found: true));
    at = match.end;
  }
  if (at < text.length || pieces.isEmpty) {
    pieces.add((text: text.substring(at), found: false));
  }
  return pieces;
}
