import 'dart:math' as math;

import '../../images.dart' show PastedImage;

/// Sent prompts, oldest first, and the draft kept aside during a walk.
class History {
  const History({
    this.prompts = const [],
    this.index,
    this.draft = '',
    this.images = const {},
  });

  final List<String> prompts;
  final int? index;
  final String draft;

  /// The images a prompt sent, by its text, so a recalled prompt brings
  /// them back with its placeholders.
  final Map<String, List<PastedImage>> images;
}

/// A prompt was sent: end the walk, keeping no consecutive duplicate.
History recorded(History history, String prompt) =>
    recordedWith(history, prompt, const []);

/// A prompt was sent with [images], which come back when it is recalled.
History recordedWith(
  History history,
  String prompt,
  List<PastedImage> images,
) => History(
  prompts: history.prompts.isNotEmpty && history.prompts.last == prompt
      ? history.prompts
      : List.unmodifiable([...history.prompts, prompt]),
  images: Map.unmodifiable({
    for (final MapEntry(:key, :value) in history.images.entries)
      if (key != prompt) key: value,
    if (images.isNotEmpty) prompt: List<PastedImage>.unmodifiable(images),
  }),
);

/// The images [prompt] took when it was sent; none for most.
List<PastedImage> recalledImages(History history, String prompt) =>
    history.images[prompt] ?? const [];

/// Leave a history walk, so the next up starts at the newest prompt.
History left(History history) => history.index == null
    ? history
    : History(prompts: history.prompts, images: history.images);

/// One step in history and the text the prompt should show: the agent's
/// kept draft [kept] when it is one, else a prompt sent or the draft the
/// walk began on.
class Walked {
  const Walked(this.history, this.text, {this.kept});

  final History history;
  final String text;

  /// Which of the agent's kept drafts, oldest first, [text] is; none for a
  /// prompt or the walk's own draft.
  final int? kept;
}

/// Where the walk stands among the prompts and then [kept] drafts, the
/// agent's own set aside, oldest first: past them is the box's draft. A
/// place past the drafts there are, as one taken off the stack leaves it,
/// stands at the draft.
int _standing(History history, int kept) {
  final end = history.prompts.length + kept;
  return math.min(history.index ?? end, end);
}

/// What the walk shows at [index], among the prompts and [kept].
({String text, int? kept})? _at(History history, int index, List<String> kept) {
  if (index < 0) return null;
  if (index < history.prompts.length) {
    return (text: history.prompts[index], kept: null);
  }
  final own = index - history.prompts.length;
  return own < kept.length ? (text: kept[own], kept: own) : null;
}

/// One step older, the agent's newest [kept] draft first, saving the draft
/// when the walk begins; null at the oldest prompt.
Walked? older(History history, String draft, [List<String> kept = const []]) {
  final index = _standing(history, kept.length) - 1;
  final shown = _at(history, index, kept);
  if (shown == null) return null;
  return Walked(
    History(
      prompts: history.prompts,
      index: index,
      draft: history.index == null ? draft : history.draft,
      images: history.images,
    ),
    shown.text,
    kept: shown.kept,
  );
}

/// One step newer: a newer prompt, or the agent's next [kept] draft, or
/// after them the draft the walk began on; null off the walk.
Walked? newer(History history, [List<String> kept = const []]) {
  if (history.index == null) return null;
  final index = _standing(history, kept.length) + 1;
  final shown = _at(history, index, kept);
  if (shown == null) {
    return Walked(
      History(prompts: history.prompts, images: history.images),
      history.draft,
    );
  }
  return Walked(
    History(
      prompts: history.prompts,
      index: index,
      draft: history.draft,
      images: history.images,
    ),
    shown.text,
    kept: shown.kept,
  );
}

/// Whether an untouched recall lets arrows walk history from any line. A
/// kept draft never does: it is the agent's own, edited as any draft.
bool walking(History history, String draft) {
  final index = history.index;
  return index != null &&
      index < history.prompts.length &&
      history.prompts[index] == draft;
}

/// An agent's place in the walk: a prompt sent, by its index, or one of the
/// agent's own kept drafts, by its; with the draft the walk began on. Kept
/// apart from the prompts, which every agent shares, so a prompt another
/// agent sends never moves it onto another draft.
final class Walk {
  const Walk({this.prompt, this.kept, this.draft = ''});

  final int? prompt;
  final int? kept;
  final String draft;
}

/// Where [history] stands, as an agent keeps it; none off the walk.
Walk? walkOf(History history) {
  final index = history.index;
  if (index == null) return null;
  return index < history.prompts.length
      ? Walk(prompt: index, draft: history.draft)
      : Walk(kept: index - history.prompts.length, draft: history.draft);
}

/// The prompts [sent], walked from an agent's place [walk].
History walkedIn(History sent, Walk? walk) => History(
  prompts: sent.prompts,
  index: walk == null
      ? null
      : walk.prompt ?? sent.prompts.length + (walk.kept ?? 0),
  draft: walk?.draft ?? '',
  images: sent.images,
);
