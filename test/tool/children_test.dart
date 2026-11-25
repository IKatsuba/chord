// The no-agent children fixture draws each flag's state in the real
// window at both sizes, its mark in sight (design CTUI-35, interface I12).
import 'package:chord/session/window_agents.dart' show maxChildren;
import 'package:chord/ui/app/state.dart' show SessionShown;
import 'package:chord/ui/agents/agents_view.dart' show AgentsClock;
import 'package:clock/clock.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../tool/children.dart';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 10));
  }
}

/// What each flag shows, as the list or the transcript draws it.
const _marks = {
  '': ['    main    fake', '    parser  fake · fake-small', '◦ idle'],
  '--asking': ['● docs needs your permission', '● permission'],
  '--unseen': ['✓ new reply', '← new message', '✗ turn failed'],
  '--exited': ['✗ exited'],
  '--failed': ['lexer', '✗ failed to start'],
  '--tall': ['Summarise the release'],
  '--many': ['… +'],
  '--held': [
    '← from @main · after the running calls: Then the docs, once the',
    '← from @docs · fake: The README names the old flag. …',
  ],
  // CTUI-116: a child on another runtime than main's.
  '--codex': ['    main    fake', '    parser  codex · fake-small'],
  '--tasks': [
    '⏺ Running 2 agents…',
    'Agent(Watch the build) · fake',
    '2 agents still running',
  ],
};

void main() {
  group('tester CTUI-120: fixture clock ages', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('a fixed fixture clock determines age at $size', (t) async {
        await withClock(Clock.fixed(DateTime.utc(2045, 3, 4, 12)), () async {
          final fixture = childrenFixture(['--held', '--codex']);
          addTearDown(fixture.close);
          await Future<void>.delayed(Duration.zero);
          childrenStates(fixture, ['--held', '--codex']);
          final preview = childrenPreview(fixture);
          await t.pumpWidget(preview, size: size);
          await _settle(t);
          expect(t.screen.lines.first, contains('opened by main 18m ago'));
          fixture.connection.fold.dispatch(SessionShown(fixture.keys['docs']!));
          await _settle(t);
          expect(t.screen.lines.first, contains('opened by main 16m ago'));
          await t.pumpWidget(preview, size: const Size(1, 1));
          await t.pumpWidget(preview, size: size);
          await _settle(t);
          expect(t.screen.lines.first, contains('opened by main 16m ago'));
          await t.pumpWidget(const SizedBox());
          await fixture.close();
          await t.pump(const Duration(seconds: 2));
          expect(AgentsClock.subscribers, 0);
          expect(AgentsClock.running, isFalse);
        });
      });
    }
  });

  group('tester: combined children fixture admission', () {
    for (var mask = 0; mask < 8; mask++) {
      test('named children survive many fill for combination $mask', () async {
        final flags = [
          '--many',
          if (mask & 1 != 0) '--tall',
          if (mask & 2 != 0) '--failed',
          if (mask & 4 != 0) '--unseen',
        ];
        for (final args in [flags, flags.reversed.toList()]) {
          final fixture = childrenFixture(args);
          try {
            await Future<void>.delayed(Duration.zero);
            expect(fixture.keys, hasLength(maxChildren));
            expect(fixture.keys.values.toSet(), hasLength(maxChildren));
            expect(fixture.keys.keys, containsAll(['parser', 'docs']));
            if (args.contains('--tall')) {
              expect(fixture.keys, contains(tallName));
            }
            if (args.contains('--failed')) {
              expect(fixture.keys, contains('lexer'));
              expect(fixture.sessions, isNot(contains('lexer')));
            }
            expect(
              fixture.sessions.keys.every(fixture.keys.containsKey),
              isTrue,
            );
          } finally {
            await fixture.close();
          }
        }
      });
    }

    testWidgets('combined fixture resizes and unmounts with tasks live', (
      t,
    ) async {
      final args = ['--many', '--tall', '--failed', '--unseen', '--tasks'];
      final fixture = childrenFixture(args);
      addTearDown(fixture.close);
      await Future<void>.delayed(Duration.zero);
      childrenStates(fixture, args);
      final preview = childrenPreview(fixture);
      for (final size in const [Size(120, 40), Size(80, 24), Size(120, 40)]) {
        await t.pumpWidget(preview, size: size);
        await _settle(t);
        expect(t.screen.text, contains('… +'));
        expect(t.screen.text, contains('2 agents still running'));
      }
      await t.pumpWidget(const SizedBox());
      await fixture.close();
      await t.pump(const Duration(seconds: 2));
      expect(AgentsClock.subscribers, 0);
      expect(AgentsClock.running, isFalse);
    });
  });

  _testerFixtureLifetime();
  // CTUI-120: the children opened minutes ago, two apart, not at the epoch.
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('each child\'s line says it opened minutes ago, at $size', (
      t,
    ) async {
      final fixture = childrenFixture(['--many']);
      addTearDown(fixture.close);
      await Future<void>.delayed(Duration.zero);
      await t.pumpWidget(childrenPreview(fixture), size: size);
      await _settle(t);
      final names = fixture.keys.keys.toList();
      for (final (index, name) in names.indexed) {
        fixture.connection.fold.dispatch(SessionShown(fixture.keys[name]!));
        await _settle(t);
        expect(
          t.screen.lines.first,
          contains('opened by main ${18 - 2 * index}m ago'),
          reason: name,
        );
      }
    });
  }
  // CTUI-106: --many fills the window's limit, so --tall's child was one
  // past it and its open refused, which the fixture did not expect.
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('--many beside the named children keeps to the limit, the '
        'list folded and the tasks drawn, at $size', (t) async {
      final args = ['--many', '--tall', '--tasks', '--failed', '--unseen'];
      final fixture = childrenFixture(args);
      addTearDown(fixture.close);
      expect(fixture.keys, hasLength(maxChildren));
      expect(fixture.keys.keys, containsAll(['lexer', tallName, 'other']));
      await Future<void>.delayed(Duration.zero);
      childrenStates(fixture, args);
      await t.pumpWidget(childrenPreview(fixture), size: size);
      await _settle(t);
      for (final mark in [..._marks['--many']!, ..._marks['--tasks']!]) {
        expect(t.screen.text, contains(mark), reason: t.screen.text);
      }
    });
  }
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    for (final MapEntry(key: flag, value: marks) in _marks.entries) {
      testWidgets('${flag.isEmpty ? 'no flag' : flag} draws its state at '
          '$size', (t) async {
        final args = [if (flag.isNotEmpty) flag];
        final fixture = childrenFixture(args);
        addTearDown(fixture.close);
        await Future<void>.delayed(Duration.zero);
        childrenStates(fixture, args);
        await t.pumpWidget(childrenPreview(fixture), size: size);
        await _settle(t);
        for (final mark in marks) {
          expect(t.screen.text, contains(mark), reason: t.screen.text);
        }
      });
    }
  }
}

void _testerFixtureLifetime() {
  group('CTUI-35 tester: children fixture resize and cleanup', () {
    for (final flag in ['', ...childrenFlags]) {
      testWidgets(
        '$flag survives tiny room and resize, then releases every timed widget',
        (t) async {
          final args = [if (flag.isNotEmpty) flag];
          final fixture = childrenFixture(args);
          addTearDown(fixture.close);
          await Future<void>.delayed(Duration.zero);
          childrenStates(fixture, args);
          final preview = childrenPreview(fixture);
          await t.pumpWidget(preview, size: const Size(0, 1));
          await t.pumpWidget(preview, size: const Size(1, 1));
          for (final size in const [
            Size(120, 40),
            Size(80, 24),
            Size(120, 40),
          ]) {
            await t.pumpWidget(preview, size: size);
            await _settle(t);
            for (final mark in _marks[flag]!) {
              expect(t.screen.text, contains(mark), reason: '$flag at $size');
            }
          }
          await t.pumpWidget(const SizedBox(), size: const Size(80, 24));
          await fixture.close();
          await t.pump(const Duration(seconds: 2));
          expect(AgentsClock.subscribers, 0);
          expect(AgentsClock.running, isFalse);
          expect(t.screen.lines.every((line) => line.trim().isEmpty), isTrue);
        },
      );
    }
  });
}
