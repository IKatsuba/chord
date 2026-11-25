import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/cli.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/permission.dart';

const launch = Launch(
  name: 'test',
  agent: null,
  agentCommand: 'unused',
  version: '0.0.1',
  directory: '.',
);

void show(
  StartConnection connection,
  model.TurnState turn, {
  bool furniture = false,
  List<model.Entry> entries = const [],
}) {
  connection.app.value = AppState(
    start: const StartState(phase: StartPhase.connected),
    attended: connection.app.value.attended,
    queue: furniture ? [const QueuedPrompt('q', 'queued message')] : [],
    transcript: model.Transcript(
      entries: entries,
      turn: turn,
      plan: furniture
          ? [
              acp.PlanEntry.fromJson({
                'content': 'A live step',
                'status': 'pending',
                'priority': 'medium',
              }),
            ]
          : [],
    ),
  );
}

void main() {
  testWidgets('a request held between turns keeps ? for shortcuts while the '
      'draft is empty, as the original Status.tsx', (t) async {
    final connection = StartConnection(command: 'unused', cwd: '.');
    show(connection, const model.Idle());
    await t.pumpWidget(
      TranscriptWindow(launch: launch, connection: connection),
      size: const Size(120, 40),
    );
    show(
      connection,
      model.AwaitingPermission('t', 0, [permissionFixture()], between: true),
    );
    await t.pump();
    final status = t.screen.lines.last;
    expect(status, contains('● permission asked between turns'));
    expect(status, contains('? for shortcuts'));
    await t.type('draft');
    expect(t.screen.lines.last, isNot(contains('? for shortcuts')));
    t.dispose();
    await connection.close();
  });
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'permission follows plan and queue and returns draft focus at $size',
      (t) async {
        final connection = StartConnection(command: 'unused', cwd: '.');
        show(connection, const model.Idle());
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: connection),
          size: size,
        );
        await t.type('draft');
        await t.press('left');
        show(
          connection,
          model.AwaitingPermission('t', 0, [permissionFixture(mode: 'review')]),
          furniture: true,
        );
        await t.pump();
        final lines = t.screen.lines;
        final plan = lines.indexWhere((line) => line.contains('A live step'));
        final queue = lines.indexWhere(
          (line) => line.contains('queued message'),
        );
        final title = lines.indexWhere(
          (line) => line.contains('Write notes.txt'),
        );
        final prompt = lines.indexWhere((line) => line.contains('│ › draft'));
        expect(plan, greaterThanOrEqualTo(0));
        expect(queue, greaterThan(plan));
        expect(title, greaterThan(queue));
        expect(prompt, greaterThan(title));
        expect(t.screen, shows('The safety review held this:'));
        expect(t.screen, shows('3. Deny'));
        expect(
          t.screen,
          shows('Esc to reject · denied by itself in 5 minutes'),
        );
        await t.type('X');
        expect(t.screen, shows('│ › draft'));
        expect(t.screen, isNot(shows('drafXt')));
        final bindings = {
          for (final b in t.focusManager.activeBindings)
            b.chord.toString(): b.description,
        };
        expect(bindings['pageup'], 'Read permission above');
        expect(bindings['shift+pagedown'], 'Read permission below');
        // Read the long proposal at a size with room for request rows.
        show(
          connection,
          model.AwaitingPermission('t', 0, [permissionFixture()]),
        );
        await t.pump();
        await t.press('pagedown shift+pagedown');
        expect(t.screen, shows('pageup to scroll'));
        await t.press('shift+pageup pageup');
        expect(t.screen, shows('pagedown to scroll'));
        show(connection, const model.Idle());
        await t.pump();
        await t.type('Y');
        expect(t.screen, shows('│ › drafYt'));
        await t.press('ctrl+z');
        expect(t.screen, shows('│ › draft'));
        t.dispose();
        await connection.close();
      },
    );

    testWidgets(
      'all scroll keys target only an overflowing active request at $size',
      (t) async {
        final connection = StartConnection(command: 'unused', cwd: '.');
        show(
          connection,
          model.AwaitingPermission('t', 0, [permissionFixture()]),
        );
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: connection),
          size: size,
        );
        var bindings = {
          for (final b in t.focusManager.activeBindings)
            b.chord.toString(): b.description,
        };
        expect(bindings['end'], 'Read permission to bottom');
        expect(bindings['shift+home'], 'Read permission from top');
        expect(bindings['shift+up'], 'Read permission above');
        expect(bindings['shift+down'], 'Read permission below');
        await t.press('end');
        expect(t.screen, shows('proposed line 60'));
        await t.press('shift+home');
        expect(t.screen, shows('pagedown to scroll'));
        expect(t.screen, isNot(shows('pageup to scroll')));
        await t.press('shift+down');
        expect(t.screen, shows('↑ 1 line above'));
        await t.press('shift+up');
        expect(t.screen, isNot(shows('pageup to scroll')));
        await t.press('shift+end');
        expect(t.screen, shows('proposed line 60'));
        await t.press('home');
        expect(t.screen, shows('pagedown to scroll'));
        final history = [
          for (var i = 0; i < 60; i++) model.UserEntry('past', 'history $i'),
        ];
        show(
          connection,
          model.AwaitingPermission('t', 0, [
            model.PermissionWait(
              'fit',
              title: 'A short request',
              options: permissionFixture().options,
            ),
          ]),
          entries: history,
        );
        await t.pump();
        bindings = {
          for (final b in t.focusManager.activeBindings)
            b.chord.toString(): b.description,
        };
        expect(bindings['pageup'], 'Scroll up a page');
        expect(bindings['shift+down'], 'Scroll down a line');
        expect(bindings['end'], 'Scroll to the bottom');
        expect(t.screen, shows('history 59'));
        final before = t.screen.lines.take(4).toList();
        await t.press('pageup');
        expect(t.screen.lines.take(4).toList(), isNot(before));
        await t.press('home');
        expect(t.screen, shows('chord v0.0.1'));
        expect(connection.app.value.scroll.offset, 0);
        await t.press('end');
        expect(t.screen, shows('history 59'));
        t.dispose();
        await connection.close();
      },
    );

    testWidgets(
      'between-turns request leaves draft keys until ctrl+x a at $size',
      (t) async {
        final connection = StartConnection(command: 'unused', cwd: '.');
        show(connection, const model.Idle());
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: connection),
          size: size,
        );
        await t.type('draft');
        show(
          connection,
          model.AwaitingPermission('t', 0, [
            permissionFixture(),
          ], between: true),
        );
        await t.pump();
        expect(t.screen, shows('main asks · between turns'));
        expect(t.screen, shows('ctrl+x a to answer'));
        expect(t.screen.lines.last, contains('● permission'));
        expect(t.screen, isNot(shows('❯')));
        await t.type('1');
        expect(t.screen, shows('│ › draft1'));
        await t.press('ctrl+x a');
        expect(connection.app.value.attended, 'fixture');
        expect(t.screen.lines.last, isNot(contains('● permission')));
        expect(t.screen, shows('Esc to reject'));
        expect(t.screen, shows('❯ 1. Allow once'));
        await t.type('2');
        expect(t.screen, shows('│ › draft1'));
        show(connection, const model.Idle());
        await t.pump();
        await t.type('X');
        expect(t.screen, shows('│ › draft1X'));
        t.dispose();
        await connection.close();
      },
    );
  }
  test('attention belongs to the oldest request id and survives events', () {
    final wait = permissionFixture();
    final state = AppState(
      transcript: model.Transcript(
        turn: model.AwaitingPermission('t', 0, [wait], between: true),
      ),
    );
    expect(heldBack(state), isTrue);
    final attended = attendRequest(state);
    expect(heldBack(attended), isFalse);
    expect(attendRequest(attended), same(attended));
    expect(attended.transcript, same(state.transcript));
    expect(heldBack(const AppState()), isFalse);
    expect(attendRequest(const AppState()).attended, isNull);
  });
}
