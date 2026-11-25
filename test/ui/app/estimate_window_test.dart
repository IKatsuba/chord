// The status line's mark on a context chord worked out, in the real window
// on the original's fake agent reporting tokens only.
@Tags(['fake_agent'])
library;

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/start.dart';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;
import 'selection_window_test.dart' show selectionConnection, selectionLaunch;

void main() {
  group('tester: CTUI-29 estimate provenance transitions', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'replayed estimate gives way to the agent report and cost-only provenance at $size',
        (t) async {
          final connection = selectionConnection();
          addTearDown(connection.close);
          final past = recordActions([
            {
              'type': 'update',
              'turnId': 'past',
              'update': {
                'sessionUpdate': 'usage_update',
                'used': 10,
                'size': 100,
                '_meta': {
                  'chord/filled': ['used', 'size', 'cost', 'foreign'],
                },
              },
            },
          ]);
          connection.app.value = reduceApp(
            connection.app.value,
            HistoryReplayed(past.actions, state: connection.app.value.agent),
          );
          await t.pumpWidget(
            StartWindow(launch: selectionLaunch, connection: connection),
            size: size,
          );
          expect(connection.app.value.transcript.usage!.estimated, [
            'used',
            'size',
            'cost',
          ]);
          expect(
            t.screen.lines.lastWhere((line) => line.contains('used')),
            contains('~10%'),
          );
          for (final filled in [
            <String>[],
            ['cost'],
            ['size'],
            <String>[],
          ]) {
            connection.app.value = reduceApp(
              connection.app.value,
              Transcribed(
                model.UpdateAction(
                  'current',
                  acp.SessionUpdate.fromJson({
                    'sessionUpdate': 'usage_update',
                    'used': 20,
                    'size': 100,
                    '_meta': {'chord/filled': filled},
                  }),
                ),
              ),
            );
            await t.pump();
            final line = t.screen.lines.lastWhere(
              (line) => line.contains('used'),
            );
            expect(line.contains('~'), filled.contains('size'));
            expect(connection.app.value.transcript.usage!.estimated, filled);
            expect(line, contains('20%'));
          }
          await t.resize(const Size(1, 1));
          await t.resize(size);
          final line = t.screen.lines.lastWhere(
            (line) => line.contains('used'),
          );
          expect(line, contains('20%'));
          expect(line, isNot(contains('~')));
        },
      );
    }
  });
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('a context from the turn and the model is marked ~ at $size', (
      t,
    ) async {
      final connection = await fixture.connected(
        t,
        size,
        flags: const ['--tokens-only'],
      );
      await fixture.sent(t, connection, 'hello');
      await t.pump();
      final usage = connection.app.value.transcript.usage!;
      expect(usage.estimated, containsAll(['used', 'cost', 'size']));
      expect(usage.size, 400000);
      final status = t.screen.lines.lastWhere((l) => l.contains('used'));
      expect(status, matches(RegExp(r'~\d+% (context )?used')));
    }, skip: fakeAgentSkip);
  }

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets("the agent's own context is not marked at $size", (t) async {
      final connection = await fixture.connected(t, size);
      await fixture.sent(t, connection, 'hello');
      await t.pump();
      expect(connection.app.value.transcript.usage!.estimated, isEmpty);
      final status = t.screen.lines.lastWhere((l) => l.contains('used'));
      expect(status, isNot(contains('~')));
      expect(status, matches(RegExp(r'\d+% (context )?used')));
    }, skip: fakeAgentSkip);
  }
}
