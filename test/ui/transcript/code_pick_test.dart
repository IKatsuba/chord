import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/ui/transcript/code_pick.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

SelectionSource code(Object id, String text) =>
    SelectionSource.markdown(id: id, revision: 0, text: text);
CodeBlockGeometry visible(MarkdownCodeBlock block, int top, {int left = 0}) =>
    CodeBlockGeometry(
      block: block,
      bounds: Rect(left, top, 20, 3),
      visibleRects: [Rect(left, top, 20, 1)],
    );
void main() {
  test(
    'listed current assistant descriptors exclude other current plain entry types and open code',
    () {
      final assistant = code(
        'a',
        '```ts\none\n```\n\n> ```\n> two\n> ```\n\n```\nopen',
      );
      final entries = <model.Entry>[
        model.AssistantEntry('a', TextRun.empty.plus('unused')),
        const model.UserEntry('u', '```\nnot listed\n```'),
        const model.FinishedPlanEntry('p', []),
      ];
      final calls = <int>[];
      final listed = listedBlocks(entries, (i) {
        calls.add(i);
        return assistant;
      });
      expect(calls, [0]);
      expect(listed.map((b) => b.block.text), ['one', 'two']);
      expect(listed.map((b) => b.entry), [0, 0]);
    },
  );
  test(
    'catalog orders listed then visible-only by entry and outside geometry, deduplicating IDs',
    () {
      final sources = [
        for (var i = 0; i < 5; i++) code(i, '```\ncode $i\n```'),
      ];
      final blocks = sources.map((s) => s.codeBlocks.single).toList();
      final listed = [
        CodeTarget(block: blocks[0], order: 0, entry: 0, listed: true),
        CodeTarget(block: blocks[1], order: 0, entry: 2, listed: true),
      ];
      final catalog = pickableBlocks(listed, [
        visible(blocks[0], 10),
        visible(blocks[2], 9),
        visible(blocks[3], 6),
        visible(blocks[4], 2),
      ], entryOf: (id) => id == blocks[2].id ? 0 : null);
      expect(catalog.targets.map((t) => t.block.id), [
        blocks[0].id,
        blocks[2].id,
        blocks[1].id,
        blocks[4].id,
        blocks[3].id,
      ]);
      expect(catalog.shown, {
        blocks[0].id,
        blocks[2].id,
        blocks[3].id,
        blocks[4].id,
      });
      expect(() => catalog.targets.clear(), throwsUnsupportedError);
      expect(() => catalog.shown.clear(), throwsUnsupportedError);
    },
  );
  test(
    'start prefers newest shown, moves clamp, missing target falls back, and empty ends',
    () {
      final blocks = [
        for (var i = 0; i < 3; i++) code(i, '```\n$i\n```').codeBlocks.single,
      ];
      final targets = [
        for (final (i, b) in blocks.indexed)
          CodeTarget(block: b, order: 0, entry: i, listed: true),
      ];
      final catalog = CodeCatalog(targets, {blocks[0].id, blocks[1].id});
      var pick = reduceCodePick(null, CodePickStarted(catalog));
      expect(pick, blocks[1].id);
      pick = reduceCodePick(pick, CodePickMoved(-1, catalog));
      expect(pick, blocks[0].id);
      expect(reduceCodePick(pick, CodePickMoved(-1, catalog)), pick);
      expect(
        reduceCodePick(blocks.last.id, CodePickMoved(1, catalog)),
        blocks.last.id,
      );
      final removed = CodeCatalog(targets.sublist(1), {});
      expect(reduceCodePick(pick, CodePickMoved(-1, removed)), blocks.last.id);
      expect(
        reduceCodePick(pick, CodePickMoved(1, CodeCatalog([], {}))),
        isNull,
      );
      expect(reduceCodePick(null, CodePickMoved(1, catalog)), isNull);
      expect(reduceCodePick(pick, const CodePickEnded()), isNull);
      expect(
        reduceCodePick(null, CodePickStarted(CodeCatalog(targets, {}))),
        blocks.last.id,
      );
    },
  );
  test(
    'stale visible descriptor cannot mark current listed revision shown',
    () {
      final old = code('id', '```\nold\n```');
      final oldBlock = old.codeBlocks.single;
      final next = SelectionSource.markdown(
        id: 'id',
        revision: 1,
        text: '```\nnew\n```',
        previous: old,
      );
      final current = next.codeBlocks.single;
      expect(current.id, oldBlock.id);
      final catalog = pickableBlocks(
        [CodeTarget(block: current, order: 0, entry: 0, listed: true)],
        [visible(oldBlock, 0)],
        entryOf: (_) => 0,
      );
      expect(catalog.shown, isEmpty);
      expect(catalog.target(current.id)!.block.text, 'new');
    },
  );
  test(
    'hint uses whole items and live rebound labels at both sizes and narrow fallbacks',
    () {
      for (final width in [120, 80]) {
        expect(pickHint(width: width), '↑ ↓ another block · c copy · esc done');
      }
      expect(pickHint(width: 35), '↑ ↓ block · c copy · esc done');
      expect(pickHint(width: 8), 'c copy');
      expect(pickHint(width: 3), 'esc');
      expect(
        pickHint(width: 30, up: null, down: null, copy: null, cancel: null),
        'picking a code block',
      );
      final rebound = pickHint(
        width: 20,
        up: 'ctrl + shift + up',
        down: null,
        copy: 'alt + y',
        cancel: 'ctrl + q',
      );
      expect(rebound, 'alt + y copy');
      expect(cellWidth(pickHint(width: 2)), lessThanOrEqualTo(2));
    },
  );
  test(
    'pick owner invalidates old operations while clamped/no-op state stays notification-free',
    () {
      final block = code('id', '```\ncurrent\n```').codeBlocks.single;
      final catalog = CodeCatalog([
        CodeTarget(block: block, order: 0, entry: 0, listed: true),
      ], {});
      final picker = CodePicker();
      var changes = 0;
      picker.addListener(() => changes++);
      picker.dispatch(CodePickStarted(catalog));
      expect(picker.value, block.id);
      expect(changes, 1);
      final epoch = picker.epoch;
      picker.dispatch(CodePickMoved(-1, catalog));
      expect(picker.epoch, epoch + 1);
      expect(changes, 1);
      picker.dispatch(const CodePickEnded());
      expect(picker.value, isNull);
      expect(changes, 2);
      picker.dispose();
      final done = picker.epoch;
      picker.dispatch(CodePickStarted(catalog));
      expect(picker.epoch, done);
      expect(picker.value, isNull);
    },
  );
}
