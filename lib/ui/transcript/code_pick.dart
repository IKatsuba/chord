import 'package:chord_tui/chord_tui.dart';

import '../../session/transcript/types.dart' as model;
import 'message.dart' show messageHidden;

/// Exact fenced language words accepted by the port's bash prompt.
const runnableCodeLanguages = {'sh', 'bash'};

/// Complete quoted blocks remain keyboard-eligible without frame controls.
bool runnableCode(MarkdownCodeBlock block) =>
    block.complete && runnableCodeLanguages.contains(block.language);

/// A current code target, listed by the session or exposed only while drawn.
class CodeTarget {
  const CodeTarget({
    required this.block,
    required this.order,
    required this.listed,
    this.entry,
    this.geometry,
  });
  final MarkdownCodeBlock block;
  final int order;
  final int? entry;
  final bool listed;
  final CodeBlockGeometry? geometry;
}

/// One immutable ordered catalog, with current exposed targets distinguished.
class CodeCatalog {
  CodeCatalog(List<CodeTarget> targets, Set<CodeBlockId> shown)
    : targets = List.unmodifiable(targets),
      shown = Set.unmodifiable(shown);
  final List<CodeTarget> targets;
  final Set<CodeBlockId> shown;
  CodeTarget? target(CodeBlockId id) =>
      targets.where((t) => t.block.id == id).firstOrNull;
}

/// Current supported messages use the framework snapshot's revision cache.
List<CodeTarget> listedBlocks(
  List<model.Entry> entries,
  SelectionSource Function(int) sourceAt,
) => [
  for (final (index, entry) in entries.indexed)
    if (entry is model.AssistantEntry)
      for (final (order, block) in sourceAt(index).codeBlocks.indexed)
        if (block.complete)
          CodeTarget(block: block, order: order, entry: index, listed: true),
];

/// The code blocks of launches folded at the item's [width]: none is
/// picked, copied or run until ctrl+o opens it, as the original hands a
/// hidden body's blocks no actions.
Set<CodeBlockId> foldedBlocks(
  List<model.Entry> entries,
  SelectionSource Function(int) sourceAt, {
  required bool expanded,
  required int width,
}) => {
  if (!expanded)
    for (final (index, entry) in entries.indexed)
      if (entry case model.AgentMessageEntry(
        :final text,
        toSubagent: true,
        launch: true,
      ) when messageHidden(text, width, folds: true) > 0)
        for (final block in sourceAt(index).codeBlocks) block.id,
};

/// Merges listed targets and current visible-only geometry without parsing
/// text; a block in [hidden] is no target, drawn or not.
CodeCatalog pickableBlocks(
  List<CodeTarget> listed,
  List<CodeBlockGeometry> visible, {
  required int? Function(CodeBlockId) entryOf,
  Set<CodeBlockId> hidden = const {},
}) {
  final targets = <CodeBlockId, CodeTarget>{
    for (final target in listed)
      if (target.block.complete) target.block.id: target,
  };
  final shown = <CodeBlockId>{};
  for (final geometry in visible) {
    final block = geometry.block;
    if (!block.complete ||
        geometry.visibleRects.isEmpty ||
        hidden.contains(block.id)) {
      continue;
    }
    final known = targets[block.id];
    if (known != null && known.block.revision != block.revision) continue;
    shown.add(block.id);
    targets.putIfAbsent(
      block.id,
      () => CodeTarget(
        block: block,
        order: 0,
        entry: entryOf(block.id),
        listed: false,
        geometry: geometry,
      ),
    );
  }
  final ordered = targets.values.toList()
    ..sort((a, b) {
      final entry = (a.entry ?? unbounded).compareTo(b.entry ?? unbounded);
      if (entry != 0) return entry;
      if (a.listed != b.listed) return a.listed ? -1 : 1;
      if (a.listed) return a.order.compareTo(b.order);
      final top = a.geometry!.bounds.top.compareTo(b.geometry!.bounds.top);
      return top != 0
          ? top
          : a.geometry!.bounds.left.compareTo(b.geometry!.bounds.left);
    });
  return CodeCatalog(ordered, shown);
}

/// A change in code-pick mode, expressed only through current opaque IDs.
sealed class CodePickAction {
  const CodePickAction();
}

class CodePickStarted extends CodePickAction {
  const CodePickStarted(this.catalog);
  final CodeCatalog catalog;
}

class CodePickMoved extends CodePickAction {
  const CodePickMoved(this.by, this.catalog);
  final int by;
  final CodeCatalog catalog;
}

class CodePickEnded extends CodePickAction {
  const CodePickEnded();
}

/// Follows the original newest-visible preference, clamping and removed fallback.
CodeBlockId? reduceCodePick(CodeBlockId? state, CodePickAction action) =>
    switch (action) {
      CodePickStarted(:final catalog) =>
        catalog.targets
                .where((t) => catalog.shown.contains(t.block.id))
                .lastOrNull
                ?.block
                .id ??
            catalog.targets.lastOrNull?.block.id,
      CodePickMoved(:final by, :final catalog) =>
        state == null ? null : _moved(state, by, catalog),
      CodePickEnded() => null,
    };
CodeBlockId? _moved(CodeBlockId state, int by, CodeCatalog catalog) {
  final targets = catalog.targets;
  if (targets.isEmpty) return null;
  final at = targets.indexWhere((t) => t.block.id == state);
  return at < 0
      ? targets.last.block.id
      : targets[(at + by).clamp(0, targets.length - 1)].block.id;
}

/// One window's pure pick state; never retains an Entry or historical snapshot.
class CodePicker extends ChangeNotifier {
  CodeBlockId? _value;
  int _epoch = 0;
  CodeBlockId? get value => _value;
  int get epoch => _epoch;
  void dispatch(CodePickAction action) {
    if (isDisposed) return;
    _epoch++;
    final next = reduceCodePick(_value, action);
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }
}

/// Fits actual action-key labels as complete items, with the original fallback.
String pickHint({
  int width = unbounded,
  String? up = '↑',
  String? down = '↓',
  String? copy = 'c',
  String? run,
  String? cancel = 'esc',
}) {
  final moves = [
    if (up != null && up.isNotEmpty) up,
    if (down != null && down.isNotEmpty) down,
  ].join(' ');
  final parts = [
    if (moves.isNotEmpty) (moves, 'another block', 'block'),
    if (copy != null && copy.isNotEmpty) (copy, 'copy', 'copy'),
    if (run != null && run.isNotEmpty) (run, 'put in the prompt', 'prompt'),
    if (cancel != null && cancel.isNotEmpty) (cancel, 'done', 'done'),
  ];
  String line(bool short) =>
      parts.map((p) => '${p.$1} ${short ? p.$3 : p.$2}').join(' · ');
  final full = line(false);
  if (full.isEmpty) return truncate('picking a code block', width);
  if (cellWidth(full) <= width) return full;
  final kept = <String>[];
  for (final p in parts) {
    final item = '${p.$1} ${p.$3}';
    if (cellWidth([...kept, item].join(' · ')) <= width) kept.add(item);
  }
  return kept.isNotEmpty
      ? kept.join(' · ')
      : truncate(
          cancel == null || cancel.isEmpty ? 'picking a code block' : cancel,
          width,
        );
}

/// The live binding's label, using original arrow and modifier wording.
String pickKeyLabel(Chord chord) => chord.combos
    .map(
      (combo) => combo
          .toString()
          .split('+')
          .map(
            (key) => switch (key) {
              'up' => '↑',
              'down' => '↓',
              'escape' => 'esc',
              _ => key,
            },
          )
          .join(' + '),
    )
    .join(' ');
