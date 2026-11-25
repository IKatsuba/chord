@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/app/state.dart' show AgentOpened;
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import '../../fixtures/fake_harness.dart';
import '../../session/conversation_fake.dart';
import 'window_fake_test.dart' as fixture;
import 'mentions_window_test.dart' show settle;

void main() {
  group('real mention window on original fake', skip: fakeAgentSkip, () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('pending Enter no matches sends current literal text $size', (
        t,
      ) async {
        final c = await fixture.connected(t, size),
            pending = Completer<List<String>?>();
        await t.pumpWidget(
          TranscriptWindow(
            launch: fixture.launch,
            connection: c,
            walkFiles: (cwd, {cancellationToken}) async => ['alpha'],
            matchMentions: (names, q) =>
                q.isEmpty ? Future.value(names) : pending.future,
          ),
          size: size,
        );
        await t.type('@');
        await settle(t);
        await t.type('zzz');
        await settle(t);
        await t.press('enter');
        expect(
          c.app.value.transcript.entries.whereType<model.UserEntry>(),
          isEmpty,
        );
        pending.complete([]);
        await settle(t);
        await fixture.until(
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
        expect(c.app.value.draft, isEmpty);
      });
      testWidgets(
        'picked valid file remains text and fake receives one link; agents add none $size',
        (t) async {
          final c = await fixture.connected(t, size);
          await File('${c.cwd}/notes.md').writeAsString('');
          // Main's open child, which `@@` offers from main.
          c.agents.openChild(
            const ChildInfo(
              id: 'a1',
              name: 'parser',
              runtime: 'fake',
              openedAt: 0,
            ),
            (emit, key) {
              c.fold.dispatch(AgentOpened(key));
              final session = ScriptedSession();
              return Conversation(
                ({required onTraffic, required cancellationToken}) async =>
                    session,
              )..listen(emit);
            },
          );
          await t.pumpWidget(
            TranscriptWindow(
              launch: fixture.launch,
              connection: c,
              walkFiles: (cwd, {cancellationToken}) async => ['notes.md'],
            ),
            size: size,
          );
          await t.type('@');
          await settle(t);
          await t.press('tab');
          expect(c.app.value.draft, '@notes.md ');
          await t.type('@@');
          await settle(t);
          await t.press('tab');
          expect(c.app.value.draft, '@notes.md @@parser ');
          await t.press('enter');
          await fixture.until(
            () =>
                c.app.value.transcript.turn is model.Idle &&
                c.app.value.transcript.entries
                    .whereType<model.AssistantEntry>()
                    .isNotEmpty,
          );
          await t.pump();
          expect(
            c.app.value.transcript.entries
                .whereType<model.UserEntry>()
                .single
                .text,
            '@notes.md @@parser',
          );
          final reply = c.app.value.transcript.entries
              .whereType<model.AssistantEntry>()
              .map((e) => e.text.text)
              .join();
          expect('Received a link:'.allMatches(reply), hasLength(1));
          expect(reply, contains('Received a link: notes.md'));
        },
      );
      testWidgets(
        'default empty agents Enter submits normally and Tab does nothing $size',
        (t) async {
          final c = await fixture.connected(t, size);
          await t.type('@@');
          await settle(t);
          expect(t.screen, shows('No agents to mention'));
          await t.press('tab');
          expect(c.app.value.draft, '@@');
          await t.press('enter');
          await fixture.until(
            () => c.app.value.transcript.entries
                .whereType<model.UserEntry>()
                .isNotEmpty,
          );
          expect(
            c.app.value.transcript.entries
                .whereType<model.UserEntry>()
                .single
                .text,
            '@@',
          );
        },
      );
    }
  });
}
