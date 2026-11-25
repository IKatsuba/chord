import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/selection.dart';
import 'package:test/test.dart';

import '../../session/transcript/fold.dart';

void main() {
  test(
    'current source cache is lazy, stable per revision and drops removed roots',
    () {
      final entries = appended([], [
        for (var i = 0; i < 100; i++)
          model.AssistantEntry('t$i', TextRun.empty.plus('```\ncode $i\n```')),
      ]);
      final cache = TranscriptSources(Object());
      cache.retain(entries);
      expect(cache.cachedEntryCount, 0);
      final first = cache.source(entries[0], width: 80);
      expect(cache.cachedEntryCount, 1);
      expect(cache.source(entries[0], width: 80), same(first));
      expect(first.codeBlocks.single.text, 'code 0');
      final changed = replacedAt(
        entries,
        0,
        model.AssistantEntry('t0', TextRun.empty.plus('```\nchanged\n```')),
      );
      final next = cache.source(changed[0], width: 80);
      expect(next.id, first.id);
      expect(next, isNot(same(first)));
      expect(next.codeBlocks.single.id, first.codeBlocks.single.id);
      expect(next.codeBlocks.single.text, 'changed');
      expect(first.codeBlocks.single.text, 'code 0');
      expect(cache.cachedEntryCount, 1);
      cache.retain(changed.skip(1).toList());
      expect(cache.cachedEntryCount, 0);
      final reused = appended([], [entries[0]]).single;
      expect(cache.id(reused), isNot(first.id));
      expect(cache.id(entries[0]), first.id);
    },
  );

  test(
    'streaming fragments share domain identity but removed and new runs do not inherit',
    () {
      final cache = TranscriptSources(Object());
      var state = fold([
        const model.PromptAction('t', 'p', 0),
        say('t', '```\nold\n```'),
      ]);
      final before = cache.source(state.entries.last, width: 80);
      final issuedCodeId = before.codeBlocks.single.id;
      state = reduceTranscript(state, say('t', '\n\nnext paragraph'));
      final next = cache.source(state.entries.last, width: 80);
      expect(next.id, before.id);
      expect(next.codeBlocks.single.id, issuedCodeId);
      state = reduceTranscript(state, think('t', 'thinking'));
      state = reduceTranscript(state, say('t', '```\nold\n```'));
      final other = cache.source(state.entries.last, width: 80);
      expect(other.id, isNot(before.id));
      expect(other.codeBlocks.single.id, isNot(before.codeBlocks.single.id));
      cache.retain(state.entries.take(1).toList());
      expect(cache.cachedEntryCount, 0);
    },
  );

  test(
    'excluded client entry roots contain no selectable content or code catalog',
    () {
      final cache = TranscriptSources(Object());
      for (final entry in <model.Entry>[
        const model.ReportEntry('r', 'status', [
          (label: 'Agent', text: 'not eligible'),
        ]),
        const model.NotedEntry('n', 'config', 'not eligible'),
        const model.PermissionEntry('p', title: 'not eligible'),
        const model.CancelledEntry('c'),
        const model.StoppedEntry('s', 'not eligible'),
        const model.ErrorEntry('e', 'not eligible'),
        const model.WarningEntry('w', 'not eligible'),
      ]) {
        final source = cache.source(entry, width: 80);
        // Outcomes and failures hold their rows, for a subagent's work
        // drawn after them; agents_selection_test shows they copy nothing.
        expect(
          source.children.every((child) => child.codeBlocks.isEmpty),
          isTrue,
        );
        expect(source.codeBlocks, isEmpty);
      }
    },
  );
  test(
    'mounted and listed clients share one current source including control geometry options',
    () {
      final entries = appended([], [
        model.AssistantEntry('a', TextRun.empty.plus('```ts\nx\n```')),
      ]);
      final transcript = model.Transcript(entries: entries);
      final cache = TranscriptSources(Object())..retain(entries);
      final mounted = cache.entryAt(
        transcript,
        0,
        width: 80,
        copyCodeBlocks: true,
      );
      final listed = cache.entryAt(
        transcript,
        0,
        width: 80,
        copyCodeBlocks: true,
      );
      expect(listed, same(mounted));
      final descriptor = mounted.codeBlocks.single;
      final plain = cache.entryAt(transcript, 0, width: 80);
      expect(plain, isNot(same(mounted)));
      expect(plain.codeBlocks.single.id, descriptor.id);
      expect(mounted.codeBlocks.single.text, 'x');
      final current = cache.entryAt(
        transcript,
        0,
        width: 80,
        copyCodeBlocks: true,
      );
      expect(
        cache.entryAt(transcript, 0, width: 80, copyCodeBlocks: true),
        same(current),
      );
      expect(current.codeBlocks.single.id, descriptor.id);
      expect(cache.cachedEntryCount, 1);
    },
  );
  test(
    'code IDs resolve current occurrence positions without retained entries or session reuse',
    () {
      final entries = appended([], [
        for (var i = 0; i < 2; i++)
          model.AssistantEntry('a$i', TextRun.empty.plus('```\ncode $i\n```')),
      ]);
      final transcript = model.Transcript(entries: entries);
      final cache = TranscriptSources(Object())..retain(entries);
      final first = cache
          .entryAt(transcript, 0, width: 80)
          .codeBlocks
          .single
          .id;
      final second = cache
          .entryAt(transcript, 1, width: 80)
          .codeBlocks
          .single
          .id;
      expect(cache.indexOfCodeBlock(first), 0);
      expect(cache.indexOfCodeBlock(second), 1);
      expect(cache.ownsCodeBlock(first, entries[0]), isTrue);
      expect(cache.ownsCodeBlock(first, entries[1]), isFalse);
      cache.retain([entries[1]]);
      expect(cache.indexOfCodeBlock(first), isNull);
      expect(cache.indexOfCodeBlock(second), 0);
      expect(cache.cachedEntryCount, 1);
      final replaced = TranscriptSources(Object())..retain(entries);
      expect(replaced.indexOfCodeBlock(second), isNull);
      cache.retain([]);
      expect(cache.cachedEntryCount, 0);
      expect(cache.indexOfCodeBlock(second), isNull);
    },
  );
}
