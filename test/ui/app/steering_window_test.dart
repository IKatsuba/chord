import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import '../../../tool/steering.dart';
import 'window_fake_test.dart' show until;

Future<SteeringFixture> connected(
  WidgetTester t,
  Size size, {
  bool supported = true,
  bool cutsCalls = false,
}) async {
  final f = await SteeringFixture.create(
    supported: supported,
    cutsCalls: cutsCalls,
  );
  addTearDown(() async {
    await f.close();
    expect(await f.directory.exists(), isFalse);
    expect(f.agents.every((a) => a.process.exited), isTrue);
  });
  await t.pumpWidget(f.view(), size: size);
  await until(() => f.connection.app.value.start.phase == StartPhase.connected);
  await t.pump();
  return f;
}

Future<void> send(WidgetTester t, String text) async {
  await t.type(text);
  await t.press('enter');
  await t.pump();
}

void main() {
  _testerSteeringWindowBoundaries();
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'Tab preserves Unicode draft and serializes oldest rows at $size',
      (t) async {
        final f = await connected(t, size);
        await send(t, 'running');
        await send(t, 'oldest');
        await send(t, 'second');
        await t.type('draft 界😀');
        await t.press('left');
        final before = f.connection.app.value;
        await t.press('tab');
        await until(() => f.agent.pendingSteers.length == 1);
        expect(f.connection.app.value.draft, before.draft);
        expect(f.connection.app.value.cursor, before.cursor);
        expect(f.connection.app.value.queue.first.taken, isTrue);
        expect(
          f.connection.app.value.transcript.entries
              .whereType<model.UserEntry>(),
          hasLength(1),
        );
        await t.press('tab');
        expect(f.connection.app.value.queue.every((q) => q.taken), isTrue);
        expect(f.agent.pendingSteers, hasLength(1));
        f.agent.answerSteer();
        await until(() => f.agent.pendingSteers.length == 1);
        f.agent.answerSteer();
        await until(() => f.connection.app.value.queue.isEmpty);
        await t.pump();
        final state = f.connection.app.value;
        expect(state.draft, before.draft);
        expect(state.cursor, before.cursor);
        expect(
          state.transcript.entries.whereType<model.UserEntry>().map(
            (e) => e.text,
          ),
          ['running', 'oldest', 'second'],
        );
        expect(state.transcript.turn, isNot(isA<model.Idle>()));
        await t.press('tab');
        expect(f.connection.app.value.draft, before.draft);
        expect(f.agent.pendingSteers, isEmpty);
      },
    );
    testWidgets('pending label and refused row at $size', (t) async {
      final f = await connected(t, size);
      await send(t, 'running');
      await send(t, 'queued');
      await t.press('tab');
      await until(() => f.agent.pendingSteers.isNotEmpty);
      await t.pump(const Duration(milliseconds: 550));
      expect(t.screen, shows('into the running turn: queued'));
      await t.press('f3');
      await until(() => f.connection.app.value.steerRefused != null);
      await t.pump();
      expect(f.connection.app.value.queue.single.taken, isFalse);
      expect(t.screen, shows('Not taken into the running turn'));
      expect(
        f.connection.app.value.transcript.entries.whereType<model.UserEntry>(),
        hasLength(1),
      );
    });
    testWidgets('explicit call hold restores through Escape at $size', (
      t,
    ) async {
      final f = await connected(t, size, cutsCalls: true);
      await send(t, 'running');
      await t.press('f5');
      await t.pump();
      await send(t, 'held row');
      await t.type('draft');
      await t.press('tab');
      await until(() => f.connection.app.value.queue.single.afterCalls);
      expect(f.agent.pendingSteers, isEmpty);
      expect(t.screen, shows('after the running calls: held row'));
      await t.press('esc');
      expect(f.connection.app.value.queue, isEmpty);
      expect(f.connection.app.value.draft, 'held row\ndraft');
      await t.press('f5');
      await t.pump();
      expect(f.agent.pendingSteers, isEmpty);
    });
    testWidgets('held shell and mention survive taken Escape once at $size', (
      t,
    ) async {
      final f = await connected(t, size);
      await send(t, 'running');
      await send(t, '!echo notes');
      await until(() => f.connection.app.value.held.isNotEmpty);
      final held = List<String>.of(f.connection.app.value.held);
      await send(t, 'see @notes.txt ');
      expect(f.connection.app.value.held, isEmpty);
      expect(f.connection.app.value.queue.single.held, held);
      await t.type('unsent');
      await t.press('tab');
      await until(() => f.agent.pendingSteers.isNotEmpty);
      final wire = f.agent.pendingSteers.single['params'] as Map;
      final prompt = wire['prompt'] as List;
      expect(
        prompt.whereType<Map>().first['text'],
        contains('<bash-input>echo notes</bash-input>'),
      );
      expect(
        prompt.whereType<Map>().first['text'],
        contains('recorded held output'),
      );
      expect(prompt.whereType<Map>().first['text'], endsWith('see @notes.txt'));
      expect(
        prompt.whereType<Map>().where((p) => p['type'] == 'resource_link'),
        hasLength(1),
      );
      await t.press('esc');
      expect(f.connection.app.value.draft, 'unsent');
      expect(f.connection.app.value.held, isEmpty);
      f.agent.answerSteer();
      await until(() => f.connection.app.value.queue.isEmpty);
      await t.pump();
      final users = f.connection.app.value.transcript.entries
          .whereType<model.UserEntry>();
      expect(users.map((e) => e.text), ['running', 'see @notes.txt']);
      expect(f.connection.app.value.draft, 'unsent');
      expect(
        f.agent.requests.where((r) => r['method'] == '_session/steering'),
        hasLength(1),
      );
    });

    testWidgets(
      'pending ownership survives resize and zero-room recovery at $size',
      (t) async {
        final f = await connected(t, size);
        await send(t, 'running');
        await send(t, 'queued');
        await t.type('draft');
        await t.press('tab');
        await until(() => f.agent.pendingSteers.isNotEmpty);
        await t.resize(const Size(8, 3));
        await t.press('tab');
        await t.resize(
          size == const Size(120, 40)
              ? const Size(80, 24)
              : const Size(120, 40),
        );
        expect(f.agent.pendingSteers, hasLength(1));
        expect(f.connection.app.value.draft, 'draft');
        await t.press('f2');
        await until(() => f.connection.app.value.queue.isEmpty);
        await t.pump();
        expect(
          f.connection.app.value.transcript.entries
              .whereType<model.UserEntry>(),
          hasLength(2),
        );
        expect(
          f.agent.requests.where((r) => r['method'] == '_session/steering'),
          hasLength(1),
        );
      },
    );

    testWidgets('unsupported leaves row and draft owned at $size', (t) async {
      final f = await connected(t, size, supported: false);
      await send(t, 'running');
      await send(t, 'queued');
      await t.type('draft');
      await t.press('tab');
      expect(f.connection.app.value.steerRefused?.refused, isFalse);
      expect(f.connection.app.value.queue.single.text, 'queued');
      expect(f.connection.app.value.draft, 'draft');
      expect(f.agent.pendingSteers, isEmpty);
      expect(t.screen, shows('This agent does not take messages'));
      await t.press('tab');
      expect(f.connection.app.value.steerRefused?.id, 2);
    });
    testWidgets('completion and permission own Tab at $size', (t) async {
      final f = await connected(t, size);
      await send(t, 'running');
      await send(t, 'queued');
      await t.type('/re');
      await t.press('tab');
      expect(f.agent.pendingSteers, isEmpty);
      expect(f.connection.app.value.draft, isNot('/re'));
      await t.press('ctrl+c');
      await t.press('f6');
      await until(() => f.agent.hasPermission);
      await t.pump();
      await t.press('tab');
      expect(f.agent.pendingSteers, isEmpty);
      await t.press('esc');
      await until(() => !f.agent.hasPermission);
      await t.press('tab');
      await until(() => f.agent.pendingSteers.isNotEmpty);
    });
  }
  testWidgets('latest note expiry and disposal retire timers', (t) async {
    final f = await connected(t, const Size(120, 40), supported: false);
    await send(t, 'running');
    await send(t, 'queued');
    await t.press('tab');
    await t.pump(const Duration(milliseconds: 1600));
    await t.press('tab');
    await t.pump(const Duration(milliseconds: 1600));
    expect(f.connection.app.value.steerRefused?.id, 2);
    await t.pump(const Duration(milliseconds: 1500));
    expect(f.connection.app.value.steerRefused, isNull);
    await t.press('tab');
    await t.pumpWidget(const SizedBox());
    await f.close();
    await t.pump(const Duration(milliseconds: 3100));
  });
}

void _testerSteeringWindowBoundaries() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets(
      'tester: expired unsupported note stays gone after modal and resize $size',
      (t) async {
        final f = await connected(t, size, supported: false);
        await send(t, 'running');
        await send(t, 'queued 界😀 é');
        await t.type('draft');
        await t.press('tab');
        final note = f.connection.app.value.steerRefused;
        expect(note, isNotNull);
        await t.press('f1');
        await t.press('tab');
        expect(f.connection.app.value.steerRefused, note);
        expect(f.agent.pendingSteers, isEmpty);
        await t.resize(const Size(32, 6));
        await t.pump(const Duration(milliseconds: 3100));
        expect(f.connection.app.value.steerRefused, isNull);
        await t.press('f1');
        await t.resize(size);
        expect(f.connection.app.value.steerRefused, isNull);
        expect(f.connection.app.value.draft, 'draft');
        expect(f.connection.app.value.queue.single.text, 'queued 界😀 é');
        expect(f.agent.pendingSteers, isEmpty);
        await t.press('tab');
        expect(f.connection.app.value.steerRefused?.id, greaterThan(note!.id));
      },
    );

    testWidgets(
      'tester: zero-room and fixture modal cannot dispatch a second personal row $size',
      (t) async {
        final f = await connected(t, size);
        await send(t, 'running');
        await send(t, 'first');
        await send(t, 'second');
        await t.type('draft 界😀 é');
        final before = f.connection.app.value;
        await t.press('tab');
        await until(() => f.agent.pendingSteers.length == 1);
        await t.resize(Size.zero);
        await t.press('tab');
        expect(
          f.connection.app.value.queue.where((q) => q.taken),
          hasLength(1),
          reason: 'zero-room Tab must not take the second row',
        );
        await t.resize(size);
        await t.press('f1');
        await t.press('tab enter');
        expect(f.agent.pendingSteers, hasLength(1));
        expect(
          f.connection.app.value.queue.where((q) => q.taken),
          hasLength(1),
        );
        expect(f.connection.app.value.draft, before.draft);
        expect(f.connection.app.value.cursor, before.cursor);
        await t.press('f1');
        await t.press('tab');
        expect(f.connection.app.value.queue.every((q) => q.taken), isTrue);
        f.agent.answerSteer();
        await until(() => f.agent.pendingSteers.length == 1);
        f.agent.answerSteer();
        await until(() => f.connection.app.value.queue.isEmpty);
        expect(
          f.connection.app.value.transcript.entries
              .whereType<model.UserEntry>()
              .map((e) => e.text),
          ['running', 'first', 'second'],
        );
        expect(f.connection.app.value.draft, before.draft);
      },
    );
  }
}
