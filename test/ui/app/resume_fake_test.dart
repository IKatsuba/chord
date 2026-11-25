@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'resume_window_test.dart' show Fixture;
import 'window_fake_test.dart' as fake;

const target = '22222222-2222-4222-8222-222222222222';

void main() {
  group(
    'live resume through the original text/permission/slow scenarios',
    skip: fakeAgentSkip,
    () {
      for (final size in [const Size(120, 40), const Size(80, 24)]) {
        testWidgets(
          'permission ownership, selected load and live continuation $size',
          (t) async {
            final pids = <int>[];
            final c = await fake.connected(
              t,
              size,
              onPid: pids.add,
              flags: ['--step-ms', '0'],
            );
            final records = Fixture(Directory(c.cwd));
            await records.saved(target, agent: 'fake');
            await t.pumpWidget(
              TranscriptWindow(
                launch: fake.launch,
                connection: c,
                readSessionRecords: records.read,
              ),
              size: size,
            );
            await t.type('/resume');
            await t.press('enter');
            await t.pump();
            expect(t.screen, shows('Resume a session'));
            final snapshot = c.app.value.resumePicker;
            c.conversation.send('permission');
            await fake.until(
              () => c.app.value.transcript.turn is model.AwaitingPermission,
            );
            await t.pump();
            expect(t.screen, isNot(shows('Resume a session')));
            expect(c.app.value.resumePicker, same(snapshot));
            await t.press('ctrl+a');
            expect(c.app.value.resumePicker?.everywhere, isFalse);
            await t.press('1');
            await fake.until(() => c.app.value.transcript.turn is model.Idle);
            await t.pump();
            expect(t.screen, shows('Resume a session'));
            await t.press('enter');
            await fake.until(
              () =>
                  c.app.value.start.phase == StartPhase.connected &&
                  c.app.value.start.sessionId == target,
            );
            await t.pump();
            expect(pids, hasLength(2));
            expect(t.screen, shows('Saved past $target'));
            expect(c.app.value.resumed?.sessionId, target);
            await fake.sent(t, c, 'text');
            expect(t.screen, shows('Hello, world.'));
            await c.close();
            expect(
              pids.where(
                (pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0,
              ),
              isEmpty,
            );
          },
        );
        testWidgets(
          'fresh read rechecks actual busy turn without cutting it off $size',
          (t) async {
            final c = await fake.connected(
              t,
              size,
              flags: ['--step-ms', '100'],
            );
            final records = Fixture(Directory(c.cwd));
            await records.saved(target, agent: 'fake');
            records.deferred = Completer();
            await t.pumpWidget(
              TranscriptWindow(
                launch: fake.launch,
                connection: c,
                readSessionRecords: records.read,
              ),
              size: size,
            );
            await t.type('/resume');
            await t.press('enter');
            await t.type('retained draft');
            c.conversation.send('slow');
            records.deferred!.complete(records.records);
            await t.pump();
            expect(c.app.value.resumePicker, isNull);
            expect(t.screen, shows('A turn is running.'));
            expect(c.app.value.draft, 'retained draft');
            expect(c.app.value.start.sessionId, isNot(target));
            await c.close();
          },
        );
      }
    },
  );
}
