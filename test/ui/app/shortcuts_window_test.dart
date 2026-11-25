import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/shortcuts/keys.dart' as catalog;
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import 'package:fake_async/fake_async.dart';

import 'quit_window_test.dart' show settled;

import 'window_layout_test.dart' show launch, agent;
import '../../../tool/permission.dart';
import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;
import 'editor_window_test.dart' show EditorTerminal;
import 'front_routing_test.dart' show window;

StartConnection connection({model.TurnState turn = const model.Idle()}) =>
    StartConnection(command: 'unused', cwd: '.')
      ..app.value = AppState(
        start: const StartState(phase: StartPhase.connected),
        transcript: model.Transcript(
          turn: turn,
          entries: [
            for (var i = 0; i < 100; i++)
              model.UserEntry('t$i', 'background row $i'),
          ],
        ),
      );

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'help floats opaquely without moving prompt, focus or scroll at $size',
      (t) async {
        final c = connection();
        addTearDown(c.close);
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: c),
          size: size,
        );
        final prompt = t.screen.lines.indexWhere(
          (line) => line.startsWith('╭'),
        );
        final focus = t.focusManager.primaryFocus;
        final scroll = c.app.value.scroll;
        expect(t.screen.lines.last, contains('? for shortcuts'));
        await t.press('?');
        expect(c.app.value.shortcuts.help, isTrue);
        expect(c.app.value.draft, '');
        expect(t.focusManager.primaryFocus, same(focus));
        expect(
          t.screen.lines.indexWhere((line) => line.startsWith('╭')),
          prompt,
        );
        expect(c.app.value.scroll, scroll);
        final lines = catalog.shortcuts.map(catalog.shortcutLine).toList();
        final rows = catalog.panelRows(
          lines,
          catalog.columnCount(lines, size.width),
        );
        final first = t.screen.lines.indexWhere(
          (line) => line == '  ${rows.first}',
        );
        expect(first, greaterThan(0));
        expect(t.screen.lines[first - 1], ' ${'─' * (size.width - 2)}');
        // With the list keys' lines the panel is two rows taller than
        // 80x24 leaves it, and scrolls; whole at 120x40.
        final shown = t.screen.lines
            .skip(first)
            .take(rows.length)
            .takeWhile((line) => !line.startsWith('  ── ↓'))
            .toList();
        expect(c.app.value.shortcuts.panelOverflows, size.height < 40);
        expect(shown, rows.take(shown.length).map((row) => '  $row'));
        if (size.height >= 40) expect(shown, hasLength(rows.length));
        expect(t.screen.lines[first - 1].contains('background'), isFalse);
        await t.press('?');
        expect(c.app.value.shortcuts.help, isFalse);
        expect(t.focusManager.primaryFocus, same(focus));
        expect(c.app.value.scroll, scroll);
      },
    );
    testWidgets(
      'native question-mark typing and same-frame clear/help are exact at $size',
      (t) async {
        final c = connection();
        addTearDown(c.close);
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: c),
          size: size,
        );
        await t.type('draft?');
        expect(c.app.value.draft, 'draft?');
        expect(c.app.value.shortcuts.help, isFalse);
        expect(t.screen.lines.last, isNot(contains('? for shortcuts')));
        await t.press('ctrl+z');
        expect(c.app.value.draft, 'draft');
        t.host.handleKey(KeyCombo.parse('ctrl+c').toEvent());
        t.host.handleKey(KeyCombo.parse('?').toEvent());
        await t.pump();
        expect(c.app.value.draft, '');
        expect(c.app.value.shortcuts.help, isTrue);
        await t.press('esc');
        expect(c.app.value.shortcuts.help, isFalse);
        await t.type(' ?');
        expect(c.app.value.draft, ' ?');
        expect(c.app.value.shortcuts.help, isFalse);
      },
    );
    testWidgets(
      'Escape leaves help before touching an active permission at $size',
      (t) async {
        final c = connection(
          turn: model.AwaitingPermission('turn', 0, [permissionFixture()]),
        );
        addTearDown(c.close);
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: c),
          size: size,
        );
        final focus = t.focusManager.primaryFocus;
        await t.press('?');
        expect(c.app.value.shortcuts.help, isTrue);
        expect(t.focusManager.primaryFocus, same(focus));
        await t.press('esc');
        expect(c.app.value.shortcuts.help, isFalse);
        expect(c.app.value.transcript.turn, isA<model.AwaitingPermission>());
      },
    );
  }
  testWidgets(
    'overflow scrolls panel first, clamps resize, and reopens at top',
    (t) async {
      final c = connection();
      addTearDown(c.close);
      await t.pumpWidget(
        TranscriptWindow(launch: launch, connection: c),
        size: const Size(40, 12),
      );
      await t.press('?');
      expect(c.app.value.shortcuts.panelOverflows, isTrue);
      final scroll = c.app.value.scroll;
      expect(t.screen, shows('enter to send'));
      await t.press('end');
      expect(t.screen, shows('any key to quit the crash screen'));
      expect(t.screen, shows('lines above'));
      expect(c.app.value.scroll, scroll);
      await t.press('home');
      expect(t.screen, shows('enter to send'));
      await t.press('shift+down');
      expect(t.screen, shows('1 line above'));
      await t.press('end');
      await t.resize(const Size(120, 40));
      expect(c.app.value.shortcuts.panelOverflows, isFalse);
      expect(t.screen, shows('enter to send'));
      await t.resize(const Size(40, 12));
      await t.press('end esc ?');
      expect(t.screen, shows('enter to send'));
      await t.resize(Size.zero);
      expect(t.screen.text, '');
      await t.resize(const Size(80, 24));
      expect(t.screen, shows('enter to send'));
    },
  );
  test(
    'status observes framework chord completion, rejection and exact timeout',
    () {
      fakeAsync((async) {
        final t = WidgetTester();
        final c = connection();
        try {
          settled(
            async,
            t.pumpWidget(TranscriptWindow(launch: launch, connection: c)),
          );
          settled(async, t.press('ctrl+x'));
          expect(t.screen.lines.last, contains('ctrl+x …'));
          expect(t.focusManager.pendingChord, hasLength(1));
          async.elapse(const Duration(milliseconds: 2999));
          settled(async, t.pump());
          expect(t.screen.lines.last, contains('ctrl+x …'));
          async.elapse(const Duration(milliseconds: 1));
          settled(async, t.pump());
          expect(t.focusManager.pendingChord, isEmpty);
          expect(t.screen.lines.last, contains('? for shortcuts'));
          settled(async, t.press('ctrl+x a'));
          expect(t.focusManager.pendingChord, isEmpty);
          expect(c.app.value.draft, '');
          // Nothing waits: the line says so until the draft is touched.
          expect(t.screen.lines.last, contains('Nothing waits on you'));
          settled(async, t.press('ctrl+x esc'));
          expect(t.focusManager.pendingChord, isEmpty);
          expect(t.screen.lines.last, contains('Nothing waits on you'));
        } finally {
          t.dispose();
          settled(async, c.close());
        }
        expect(async.pendingTimers, isEmpty);
      });
    },
  );
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'pending leader hint stands alone instead of model facts at $size',
      (t) async {
        final c = connection();
        c.app.value = const AppState(
          start: StartState(phase: StartPhase.connected),
          agent: agent,
        );
        addTearDown(c.close);
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: c),
          size: size,
        );
        expect(t.screen.lines.last, contains('Fixture model'));
        await t.press('ctrl+x');
        expect(
          t.screen.lines.last,
          '  ctrl+x …  b a code block · a the one that waits · esc never mind',
        );
        await t.press('esc');
        expect(t.focusManager.pendingChord, isEmpty);
        expect(c.app.value.shortcuts.help, isFalse);
        expect(t.screen.lines.last, contains('Fixture model'));
        await t.press('? ctrl+x esc');
        expect(c.app.value.shortcuts.help, isTrue);
        expect(t.focusManager.pendingChord, isEmpty);
      },
    );
  }
  for (final (width, expected) in [
    (40, 'ctrl+x …  b block · a waits'),
    (20, 'ctrl+x …'),
    (12, 'ctrl+x …'),
  ]) {
    testWidgets(
      'pending leader reduces whole items in a $width-column window',
      (t) async {
        final c = connection();
        addTearDown(c.close);
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: c),
          size: Size(width, 24),
        );
        await t.press('ctrl+x');
        expect(t.screen.lines.last, '  $expected');
        await t.press('esc');
        expect(t.focusManager.pendingChord, isEmpty);
      },
    );
  }
  group(
    'help over the original fake permission',
    skip: fakeAgentSkip,
    tags: ['fake_agent'],
    () {
      for (final size in [const Size(120, 40), const Size(80, 24)]) {
        testWidgets(
          'help dismissal preserves request, then real choice resolves once at $size',
          (t) async {
            final c = await fixture.connected(t, size);
            await t.type('permission');
            await t.press('enter');
            await fixture.until(
              () => c.app.value.transcript.turn is model.AwaitingPermission,
            );
            await t.pump();
            await t.press('?');
            expect(c.app.value.shortcuts.help, isTrue);
            await t.press('esc');
            expect(c.app.value.shortcuts.help, isFalse);
            expect(
              c.app.value.transcript.turn,
              isA<model.AwaitingPermission>(),
            );
            await t.press('1');
            await fixture.until(
              () => c.app.value.transcript.turn is model.Idle,
            );
            await t.pump();
            expect(
              c.app.value.transcript.entries.whereType<model.PermissionEntry>(),
              hasLength(1),
            );
            await t.type('draft?');
            expect(c.app.value.draft, 'draft?');
            expect(c.app.value.shortcuts.help, isFalse);
          },
        );
      }
    },
  );

  group('tester: actual window shortcuts contexts', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'every catalog alias is registered in a real window context at $size',
        (t) async {
          final reached = <Chord>{};
          final wait = model.PermissionWait(
            'nine',
            title: 'Nine choices',
            options: [
              for (var i = 1; i <= 9; i++)
                acp.PermissionOption.fromJson({
                  'optionId': 'option$i',
                  'name': 'Choice $i',
                  'kind': 'allow_once',
                }),
            ],
          );
          for (final turn in <model.TurnState>[
            const model.Idle(),
            const model.Working('turn', 0),
            model.AwaitingPermission('turn', 0, [wait], between: true),
            model.AwaitingPermission('turn', 0, [wait]),
          ]) {
            final c = connection(turn: turn);
            addTearDown(c.close);
            await t.pumpWidget(
              TranscriptWindow(launch: launch, connection: c),
              size: size,
            );
            reached.addAll(
              t.focusManager.activeBindings.map((binding) => binding.chord),
            );
            final focus = t.focusManager.primaryFocus;
            await t.press('?');
            expect(c.app.value.shortcuts.help, isTrue);
            expect(t.focusManager.primaryFocus, same(focus));
            reached.addAll(
              t.focusManager.activeBindings.map((binding) => binding.chord),
            );
            await t.press('esc');
            expect(c.app.value.shortcuts.help, isFalse);
          }
          final picking = connection();
          addTearDown(picking.close);
          picking.app.value = AppState(
            start: picking.app.value.start,
            transcript: model.Transcript(
              entries: [
                model.AssistantEntry(
                  'pick',
                  TextRun.empty.plus('```text\ncatalog code body\n```'),
                ),
              ],
            ),
          );
          final copies = <String>[];
          await t.pumpWidget(
            TranscriptWindow(
              launch: launch,
              connection: picking,
              copy: (text, _) {
                copies.add(text);
                return const copy.CopyResult.sent();
              },
            ),
            size: size,
          );
          await t.press('ctrl+x b');
          final pickBindings = t.focusManager.activeBindings
              .map((binding) => binding.chord)
              .toList();
          expect(pickBindings, contains(Chord.parse('c')));
          expect(copies, isEmpty);
          reached.addAll(pickBindings);
          // The list of agents with the keys: its moves, its way back and
          // its close.
          final listed = await window(t, size, EditorTerminal());
          await t.press('down');
          expect(listed.connection.app.value.agentsFocus, isTrue);
          reached.addAll(
            t.focusManager.activeBindings.map((binding) => binding.chord),
          );
          for (final row in catalog.shortcuts) {
            for (final alias in row.presses) {
              expect(
                reached,
                contains(Chord.parse(alias)),
                reason: '${row.key}: $alias',
              );
            }
          }
        },
      );
    }

    testWidgets(
      'every overflowing panel scroll alias leaves transcript scroll untouched',
      (t) async {
        final c = connection();
        addTearDown(c.close);
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: c),
          size: const Size(40, 12),
        );
        await t.press('?');
        final before = c.app.value.scroll;
        for (final key in [
          'pageup',
          'shift+pageup',
          'pagedown',
          'shift+pagedown',
          'shift+up',
          'shift+down',
          'home',
          'shift+home',
          'end',
          'shift+end',
        ]) {
          await t.press(key);
          expect(c.app.value.scroll, before, reason: key);
        }
        await t.press('esc ?');
        expect(t.screen, shows('enter to send'));
      },
    );

    test(
      'removing help with a live pending chord cancels callbacks into its session',
      () {
        fakeAsync((async) {
          final t = WidgetTester();
          final c = connection();
          var changes = 0;
          c.app.addListener(() => changes++);
          try {
            settled(
              async,
              t.pumpWidget(TranscriptWindow(launch: launch, connection: c)),
            );
            settled(async, t.press('? ctrl+x'));
            expect(c.app.value.shortcuts.help, isTrue);
            expect(t.focusManager.pendingChord, hasLength(1));
            t.dispose();
            final before = changes;
            async.elapse(const Duration(seconds: 10));
            expect(changes, before);
            expect(async.pendingTimers, isEmpty);
          } finally {
            t.dispose();
            settled(async, c.close());
          }
        });
      },
    );
  });
  // CTUI-82: at 80x24 the panel has the original's room, 17 rows of keys
  // between its rule and the line saying how many are below, as the
  // original's capture at the same size has them.
  testWidgets('at 80x24 the panel lists 17 rows, as the original', (t) async {
    final c = connection();
    addTearDown(c.close);
    await t.pumpWidget(
      TranscriptWindow(launch: launch, connection: c),
      size: const Size(80, 24),
    );
    await t.press('?');
    final lines = t.screen.lines;
    final rule = lines.indexOf(' ${'─' * 78}');
    final below = lines.indexWhere((line) => line.startsWith('  ── ↓ '));
    expect(rule, greaterThanOrEqualTo(0), reason: t.screen.text);
    expect(below - rule - 1, 17, reason: t.screen.text);
  });
}
