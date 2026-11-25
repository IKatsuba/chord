import 'dart:async';

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/prompt/prompt.dart';
import 'package:chord/ui/prompt/state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fake;
import 'mentions_window_test.dart' show settle, flushResult;
import 'selection_window_test.dart';

void main() {
  group('tester: pending mention publication uses current window ownership', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'unpumped roster replacement rejects old acceptance and requires a new pick $size',
        (t) async {
          final c = selectionConnection();
          addTearDown(c.close);
          final roster = ValueNotifier(const [MentionRecipient('alpha')]);
          addTearDown(roster.dispose);
          final old = Completer<List<String>?>(),
              fresh = Completer<List<String>?>();
          await t.pumpWidget(
            ListenableBuilder(
              listenable: roster,
              builder: (_) => TranscriptWindow(
                launch: selectionLaunch,
                connection: c,
                recipients: roster.value,
                matchMentions: (names, query) => query.isEmpty
                    ? Future.value(names)
                    : names.first == 'alpha'
                    ? old.future
                    : fresh.future,
              ),
            ),
            size: size,
          );
          await t.type('@@a');
          await settle(t);
          await t.press('tab');
          roster.value = const [MentionRecipient('beta')];
          old.complete(['alpha']);
          await flushResult();
          expect(c.app.value.draft, '@@a');
          fresh.complete(['beta']);
          await settle(t);
          expect(c.app.value.draft, '@@a');
          await t.press('tab');
          expect(c.app.value.draft, '@@beta ');
        },
      );

      testWidgets(
        'joined trigger marks insert full file and agent names in the real editor $size',
        (t) async {
          final c = selectionConnection();
          addTearDown(c.close);
          const file = '\u0301 name.md', agent = '\u0301 parser';
          await t.pumpWidget(
            TranscriptWindow(
              launch: selectionLaunch,
              connection: c,
              recipients: const [MentionRecipient(agent)],
              walkFiles: (_, {cancellationToken}) async => [file],
            ),
            size: size,
          );
          await t.paste('@\u0301');
          await settle(t);
          await t.press('tab');
          expect(c.app.value.draft, '@"$file" ');
          expect(c.app.value.cursor, endOf('@"$file" '));
          await t.press('ctrl+c');
          await t.paste('@@\u0301');
          await settle(t);
          await t.press('tab');
          expect(c.app.value.draft, '@@"$agent" ');
          expect(c.app.value.cursor, endOf('@@"$agent" '));
        },
      );

      for (final zero in [Size(0, size.height), Size(size.width, 5)]) {
        testWidgets(
          'no-match pending Enter drops unpumped $zero and submits only on new Enter $size',
          (t) async {
            final c = await fake.connected(t, size);
            final pending = Completer<List<String>?>();
            await t.pumpWidget(
              TranscriptWindow(
                launch: fake.launch,
                connection: c,
                walkFiles: (_, {cancellationToken}) async => ['alpha'],
                matchMentions: (names, query) =>
                    query.isEmpty ? Future.value(names) : pending.future,
              ),
              size: size,
            );
            await t.type('@zzz');
            await settle(t);
            await t.press('enter');
            t.host.updateSize(zero);
            pending.complete([]);
            await flushResult();
            expect(
              c.app.value.transcript.entries.whereType<model.UserEntry>(),
              isEmpty,
            );
            expect(c.app.value.draft, '@zzz');
            t.host.updateSize(size);
            await settle(t);
            expect(
              c.app.value.transcript.entries.whereType<model.UserEntry>(),
              isEmpty,
            );
            expect(c.app.value.draft, '@zzz');
            await t.press('enter');
            await fake.until(
              () => c.app.value.transcript.entries
                  .whereType<model.UserEntry>()
                  .isNotEmpty,
            );
            expect(
              c.app.value.transcript.entries
                  .whereType<model.UserEntry>()
                  .single
                  .text,
              '@zzz',
            );
          },
          skip: fakeAgentSkip,
        );
      }
    }
  });
}
