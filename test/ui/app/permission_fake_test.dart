@Tags(['fake_agent'])
library;

import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

Future<model.AwaitingPermission> ask(
  WidgetTester t,
  StartConnection connection,
  String scenario, {
  int count = 1,
}) async {
  await t.type(scenario);
  await t.press('enter');
  await fixture.until(() {
    final turn = connection.app.value.transcript.turn;
    return turn is model.AwaitingPermission && turn.permissions.length == count;
  });
  await t.pump();
  return connection.app.value.transcript.turn as model.AwaitingPermission;
}

Future<void> idle(WidgetTester t, StartConnection connection) async {
  await fixture.until(() => connection.app.value.transcript.turn is model.Idle);
  await t.pump();
}

void main() {
  group('permission window through original fake', skip: fakeAgentSkip, () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      for (final (keys, option) in [
        ('1', 'allow'),
        ('down enter', 'always'),
        ('esc', 'deny'),
      ]) {
        testWidgets('permission $keys answers wire option $option at $size', (
          t,
        ) async {
          final connection = await fixture.connected(t, size);
          await ask(t, connection, 'permission');
          expect(t.screen, shows('Write notes.txt'));
          expect(t.screen, shows('1. Allow'));
          expect(t.screen, shows('3. Deny'));
          await t.press(keys);
          await idle(t, connection);
          final entry = connection.app.value.transcript.entries
              .whereType<model.PermissionEntry>()
              .single;
          expect(entry.option?.optionId, keys == 'esc' ? null : option);
          expect(t.screen, shows('Permission: $option.'));
          await t.type('next draft');
          expect(t.screen, shows('│ › next draft'));
        });
      }

      testWidgets(
        'bigask can be read to last argument above reachable answers at $size',
        (t) async {
          final connection = await fixture.connected(t, size);
          await ask(t, connection, 'bigask');
          expect(t.screen, shows('path: docs/release.md'));
          expect(t.screen, shows('pagedown to scroll'));
          for (var i = 0; i < 30; i++) {
            await t.press(i.isEven ? 'pagedown' : 'shift+pagedown');
          }
          expect(t.screen, shows('mode: overwrite'));
          expect(t.screen, shows('pageup to scroll'));
          expect(t.screen, shows('Esc to reject'));
          expect(t.screen, shows('1. Yes'));
          await t.press('shift+pageup');
          expect(t.screen, isNot(shows('mode: overwrite')));
          await t.press('1');
          await idle(t, connection);
          expect(t.screen, shows('Permission: allow.'));
        },
      );

      testWidgets('twins selects option id rather than shared kind at $size', (
        t,
      ) async {
        final connection = await fixture.connected(t, size);
        await ask(t, connection, 'twins');
        expect(t.screen, shows('Allow once in this folder'));
        await t.press('j enter');
        await idle(t, connection);
        expect(
          connection.app.value.transcript.entries
              .whereType<model.PermissionEntry>()
              .single
              .option
              ?.optionId,
          'allow-here',
        );
        expect(t.screen, shows('Permission: allow-here.'));
      });

      testWidgets('second concurrent request waits behind first at $size', (
        t,
      ) async {
        final connection = await fixture.connected(t, size);
        final first = await ask(t, connection, 'bigasktwice', count: 2);
        final id = first.permissions.first.id;
        expect(t.screen, shows('path: docs/release.md'));
        expect(t.screen, isNot(shows('path: docs/changes.md')));
        await t.press('1');
        await fixture.until(() {
          final turn = connection.app.value.transcript.turn;
          return turn is model.AwaitingPermission &&
              turn.permissions.first.id != id;
        });
        await t.pump();
        expect(t.screen, shows('path: docs/changes.md'));
        expect(t.screen, shows('❯ 1. Yes'));
        await t.press('esc');
        await idle(t, connection);
        expect(
          connection.app.value.transcript.entries
              .whereType<model.PermissionEntry>()
              .map((entry) => entry.option?.optionId),
          ['allow', null],
        );
      });

      testWidgets('permissionmeta is answerable with fallback title at $size', (
        t,
      ) async {
        final connection = await fixture.connected(t, size);
        await ask(t, connection, 'permissionmeta');
        expect(t.screen, shows('Tool call'));
        expect(t.screen, shows('1. Deny'));
        await t.press('1');
        await idle(t, connection);
        expect(
          connection.app.value.transcript.entries
              .whereType<model.PermissionEntry>()
              .single
              .option
              ?.optionId,
          'deny',
        );
      });

      testWidgets(
        'held request status notice clears after attention at $size',
        (t) async {
          final connection = await fixture.connected(
            t,
            size,
            flags: ['--step-ms', '1'],
          );
          await ask(t, connection, 'bigaskleft');
          await fixture.until(() {
            final turn = connection.app.value.transcript.turn;
            return turn is model.AwaitingPermission && turn.between;
          });
          await t.pump();
          expect(t.screen.lines.last, contains('● permission'));
          expect(t.screen.lines.last, contains('ctrl+x a to answer'));
          await t.type('draft1');
          expect(t.screen, shows('│ › draft1'));
          await t.press('ctrl+x a');
          expect(t.screen.lines.last, isNot(contains('● permission')));
          await t.press('esc');
          await idle(t, connection);
          await t.type('X');
          expect(t.screen, shows('│ › draft1X'));
        },
      );

      testWidgets(
        'review reason and static deadline survive narrow window at $size',
        (t) async {
          final connection = await fixture.connected(t, size);
          await ask(t, connection, 'reviewpermission');
          expect(t.screen, shows('The safety review held this:'));
          expect(t.screen, shows('Fixture safety review: caution.'));
          expect(
            t.screen.lines.any((line) => line.contains('Waiting…')),
            isFalse,
          );
          expect(
            t.screen,
            shows('Esc to reject · denied by itself in 5 minutes'),
          );
          expect(t.screen, shows('1. Allow once'));
          await t.press('down enter');
          await idle(t, connection);
          expect(t.screen, shows('Review permission: deny.'));
        },
      );
    }
  });
}
