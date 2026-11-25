import 'package:characters/characters.dart';
import 'package:chord_tui/chord_tui.dart' show AsyncFzf, FzfCasing, byLengthAsc;

import 'prompt.dart';

/// A word-boundary file trigger, measured in the prompt's grapheme offsets.
class Mention {
  const Mention({required this.query, required this.start});
  final String query;
  final Cursor start;
  bool get quoted => false;

  @override
  bool operator ==(Object other) =>
      other is Mention &&
      runtimeType == other.runtimeType &&
      query == other.query &&
      start == other.start &&
      quoted == other.quoted;
  @override
  int get hashCode => Object.hash(runtimeType, query, start, quoted);
}

/// Agent queries allow spaces after their opening quote.
final class AgentMention extends Mention {
  const AgentMention({
    required super.query,
    required super.start,
    required this.quoted,
  });
  @override
  final bool quoted;
}

String? _before(String draft, Cursor cursor) =>
    cursor < 0 || cursor > draft.characters.length
    ? null
    : draft.characters.take(cursor).toString().split('\n').last;

// Trigger and query graphemes can join (for example @ plus a combining mark).
// Locate the regex's raw boundary before converting the complete prefix once.
Cursor _triggerStart(
  String draft,
  Cursor cursor,
  String line,
  RegExpMatch found,
) {
  final prefix = draft.characters.take(cursor).toString();
  final rawStart = prefix.length - line.length + found.start + found[1]!.length;
  return prefix.substring(0, rawStart).characters.length;
}

/// Single @ excludes emails, a second @, and whitespace before the cursor.
Mention? mentionAt(String draft, Cursor cursor) {
  final before = _before(draft, cursor);
  if (before == null) return null;
  final found = RegExp(r'(^|\s)@(?!@)(\S*)$').firstMatch(before);
  if (found == null) return null;
  final query = found[2]!;
  return Mention(
    query: query,
    start: _triggerStart(draft, cursor, before, found),
  );
}

/// A bare or still-open quoted @@ token at the current cursor.
AgentMention? agentMentionAt(String draft, Cursor cursor) {
  final before = _before(draft, cursor);
  if (before == null) return null;
  final found = RegExp(r'(^|\s)@@(?:"([^"\n]*)|([^\s"]*))$').firstMatch(before);
  if (found == null) return null;
  final quoted = found[2] != null;
  final query = found[2] ?? found[3]!;
  return AgentMention(
    query: query,
    start: _triggerStart(draft, cursor, before, found),
    quoted: quoted,
  );
}

/// Agent triggers, including a closed quote containing @, precede file triggers.
Mention? completionAt(String draft, Cursor cursor) {
  final before = _before(draft, cursor);
  if (before == null || RegExp(r'(^|\s)@@"[^"\n]*"[^\s]*$').hasMatch(before)) {
    return null;
  }
  return agentMentionAt(draft, cursor) ?? mentionAt(draft, cursor);
}

/// Equal literal names retain the first reachable target and source order.
List<T> mentionRecipients<T>(
  Iterable<T> recipients, {
  required String Function(T) nameOf,
}) {
  final seen = <String>{};
  return List.unmodifiable(recipients.where((each) => seen.add(nameOf(each))));
}

/// The discovery-order prefix shown without scoring an empty query.
List<String> firstFiles(List<String> files) =>
    List.unmodifiable(files.take(100));

/// Replaces the current file token, preserving its following separator/suffix.
({String text, Cursor cursor}) insertMention(
  String draft,
  Cursor cursor,
  Mention mention,
  String path,
) => _insert(draft, cursor, mention, path, agent: false);

/// Replaces an agent's entire bare/quoted token, with literal unescaped names.
({String text, Cursor cursor}) insertAgentMention(
  String draft,
  Cursor cursor,
  AgentMention mention,
  String name,
) => _insert(draft, cursor, mention, name, agent: true);

({String text, Cursor cursor}) _insert(
  String draft,
  Cursor cursor,
  Mention mention,
  String name, {
  required bool agent,
}) {
  final chars = draft.characters;
  final before = chars.take(mention.start).toString();
  final tail = chars.skip(cursor).toString();
  final newline = tail.indexOf('\n');
  final lineTail = newline < 0 ? tail : tail.substring(0, newline);
  final following = newline < 0 ? '' : tail.substring(newline);
  final closing = lineTail.indexOf('"');
  final rest = agent && mention.quoted
      ? (closing < 0 ? '' : lineTail.substring(closing + 1))
      : lineTail.replaceFirst(RegExp(r'^\S*'), '');
  final written =
      '${agent ? '@@' : '@'}${RegExp(r'\s').hasMatch(name) ? '"$name"' : name}';
  return (
    text: '$before$written${rest.startsWith(' ') ? rest : ' $rest'}$following',
    cursor: mention.start + written.characters.length + 1,
  );
}

/// Single-@ attachment names in typed order; consume complete agent tokens first.
List<String> mentionsIn(String text) => [
  for (final found in RegExp(
    r'(?:^|\s)(?:@@(?:"[^"\n]*(?:"|$)|\S*)|@(?:"([^"\n]+)"|([^@\s"]\S*)))',
    multiLine: true,
  ).allMatches(text))
    ?(found[1] ?? found[2]),
];

/// One prompt's current candidate snapshot and cancellable original fzf search.
final class MentionMatcher {
  List<String>? _items;
  AsyncFzf<String>? _finder;
  bool _disposed = false;
  int _generation = 0;

  /// Matches case-insensitively, shorter paths first on a tie, at most 100.
  Future<List<String>?> match(List<String> items, String query) async {
    final generation = ++_generation;
    if (_disposed) return null;
    if (!identical(items, _items)) {
      _finder?.dispose();
      _items = items;
      _finder = AsyncFzf(
        items,
        casing: FzfCasing.caseInsensitive,
        limit: 100,
        tiebreakers: [byLengthAsc<String>],
      );
    }
    final finder = _finder!;
    final results = await finder.find(query);
    if (_disposed || generation != _generation || !identical(finder, _finder)) {
      return null;
    }
    return results == null
        ? null
        : List.unmodifiable(results.map((r) => r.item));
  }

  /// Stops pending work; the window creates a new owner for a new lifetime.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _finder?.dispose();
    _finder = null;
    _items = null;
  }
}
