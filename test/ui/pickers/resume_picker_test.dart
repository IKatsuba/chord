import 'package:chord/session/sessions.dart';
import 'package:chord/ui/pickers/picker.dart';
import 'package:chord/ui/pickers/pickers.dart';
import 'package:chord/ui/pickers/state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

EarlierSession saved(
  String id,
  String title, {
  String cwd = 'project',
  String? at,
}) => EarlierSession(
  resume: Resume(sessionId: id, cwd: cwd),
  lastUsedAt: at ?? '2000-01-01T00:00:00Z',
  prompt: title,
);
ResumePickerState snapshot(List<EarlierSession> sessions, {bool all = false}) =>
    ResumePickerState(
      sessions: sessions,
      cwd: 'project',
      opening: 'opening',
      openedAt: DateTime.utc(2000, 1, 2).millisecondsSinceEpoch,
      everywhere: all,
    );
Widget frame(
  ResumePickerState state, {
  int rows = 6,
  int room = 40,
  void Function(EarlierSession)? selected,
  void Function()? toggled,
  void Function()? canceled,
}) => Align(
  alignment: Alignment.bottomLeft,
  child: ResumePicker(
    picker: state,
    agent: 'fake',
    home: 'home',
    rows: rows,
    room: room,
    onSelected: selected ?? (_) {},
    onToggleScope: toggled ?? () {},
    onCanceled: canceled ?? () {},
  ),
);

void main() {
  test(
    'snapshot scope and ages stay immutable and preserve original UTF-16 hang',
    () {
      final rows = [
        saved('a', '第一 title', cwd: 'home/😀/界'),
        saved('b', 'next'),
      ];
      final state = snapshot(rows);
      rows.clear();
      expect(resumeChoices(state).single.resume.sessionId, 'b');
      final all = toggledResumeScope(state, state.openedAt + 60000);
      expect(resumeChoices(all).length, 2);
      expect(all.opening, same(state.opening));
      expect(() => all.sessions.clear(), throwsUnsupportedError);
      final choices = sessionChoices(
        all.sessions,
        all.openedAt,
        directories: true,
        home: 'home',
      );
      expect(choices.first.label.substring(choices.first.hang), '第一 title');
      expect(
        choices.first.label.substring(0, choices.first.hang),
        contains('~/😀/界'),
      );
      expect(
        choices.first.hang,
        isNot(cellWidth(choices.first.label.substring(0, choices.first.hang))),
      );
      expect(
        cellWidth(choices[0].label.substring(0, choices[0].hang)),
        cellWidth(choices[1].label.substring(0, choices[1].hang)),
      );
      expect(choices.first.label, startsWith('yesterday'));
    },
  );
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'numbered wrapped titles clamp and preserve selection on resize $size',
      (t) async {
        final a = saved('a', 'First saved title');
        final b = saved('b', 'Second saved title');
        final state = snapshot([a, b]);
        EarlierSession? chosen;
        var toggles = 0, cancels = 0;
        Widget build() => frame(
          state,
          selected: (s) => chosen = s,
          toggled: () => toggles++,
          canceled: () => cancels++,
        );
        await t.pumpWidget(build(), size: size);
        expect(t.screen, shows('1. yesterday  First saved title'));
        await t.press('up');
        await t.press('enter');
        expect(chosen, same(a));
        await t.press('down');
        await t.resize(
          size == const Size(120, 40)
              ? const Size(80, 24)
              : const Size(120, 40),
        );
        await t.press('enter');
        expect(chosen, same(b));
        await t.press('down');
        await t.press('enter');
        expect(chosen, same(b));
        await t.press('ctrl+a');
        await t.press('esc');
        expect(toggles, 1);
        expect(cancels, 1);
      },
    );
    testWidgets('local empty and zero rows only own scope and cancel $size', (
      t,
    ) async {
      var accepts = 0, toggles = 0, cancels = 0;
      final state = snapshot([
        saved('remote', 'Remote title', cwd: 'elsewhere'),
      ]);
      await t.pumpWidget(
        frame(
          state,
          selected: (_) => accepts++,
          toggled: () => toggles++,
          canceled: () => cancels++,
        ),
        size: size,
      );
      expect(t.screen, shows('No earlier sessions in this directory.'));
      expect(t.screen, isNot(shows('Enter to resume')));
      await t.press('enter');
      await t.press('1');
      await t.press('down');
      await t.press('ctrl+a');
      await t.press('esc');
      expect(accepts, 0);
      expect(toggles, 1);
      expect(cancels, 1);
      await t.pumpWidget(
        frame(
          snapshot([saved('a', 'hidden')]),
          rows: 0,
          selected: (_) => accepts++,
        ),
        size: size,
      );
      await t.press('enter');
      await t.press('1');
      expect(accepts, 0);
      expect(t.screen, isNot(shows('hidden')));
      expect(t.screen, isNot(shows('Enter to resume')));
    });
    testWidgets('tall selected title reads before moving choices $size', (
      t,
    ) async {
      final first = saved(
        'a',
        [for (var n = 0; n < 30; n++) 'title line $n'].join('\n'),
      );
      final second = saved('b', 'Next title');
      EarlierSession? chosen;
      await t.pumpWidget(
        frame(
          snapshot([first, second]),
          rows: 4,
          room: size.height,
          selected: (s) => chosen = s,
        ),
        size: size,
      );
      await t.press('down');
      await t.press('enter');
      expect(chosen, same(first));
      for (var i = 0; i < 35; i++) {
        await t.press('down');
      }
      await t.press('enter');
      expect(chosen, same(second));
    });
  }
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('six-row tall cap keeps footer inside budget $size', (t) async {
      final tall = saved(
        'a',
        [for (var i = 0; i < 40; i++) 'Tall title $i'].join('\n'),
      );
      EarlierSession? chosen;
      await t.pumpWidget(
        frame(
          snapshot([tall, saved('b', 'Next title')]),
          rows: 6,
          room: size.height,
          selected: (s) => chosen = s,
        ),
        size: size,
      );
      expect(
        t.screen.lines.where((line) => line.contains('Tall title')),
        hasLength(6),
      );
      expect(t.screen, isNot(shows('more')));
      await t.press('enter');
      expect(chosen, same(tall));
      await t.pumpWidget(
        frame(
          snapshot([for (var i = 0; i < 6; i++) saved('$i', 'Short title $i')]),
          rows: 3,
          room: size.height,
          selected: (s) => chosen = s,
        ),
        size: size,
      );
      expect(
        t.screen.lines.where((line) => line.contains('Short title')),
        hasLength(2),
      );
      expect(t.screen, shows('+4 more'));
      await t.press('2');
      expect(chosen?.resume.sessionId, '1');
    });
  }
  for (final width in [31, 32, 33, 54, 55, 56]) {
    testWidgets('Unicode metadata stays one row at threshold width $width', (
      t,
    ) async {
      final state = snapshot([
        saved(
          'a',
          'Wrapped-title-界😀-with-an-unbroken-tail',
          cwd: 'home/😀/界/long-directory',
        ),
        saved('b', '短 title'),
      ], all: true);
      await t.pumpWidget(frame(state, room: 20), size: Size(width, 20));
      expect(t.screen, shows('Resume a session'));
      expect(
        t.screen.lines.where((line) => line.contains('yesterday')).length,
        2,
      );
      await t.press('2');
    });
  }
  for (final width in [35, 36, 37]) {
    testWidgets('hanging threshold uses actual post-number content at $width', (
      t,
    ) async {
      await t.pumpWidget(
        frame(
          snapshot([saved('a', 'Title one'), saved('b', 'Title two')]),
          room: 20,
        ),
        size: Size(width, 20),
      );
      final row = t.screen.lines.singleWhere(
        (line) => line.contains('Title one'),
      );
      expect(row.contains('yesterday'), width >= 36);
      expect(t.screen, shows('directory.'));
      expect(t.screen, shows("fake's earlier"));
    });
  }
  testWidgets(
    'suspension drops bindings and preserves highlight until reactivated',
    (t) async {
      final state = snapshot([saved('a', 'first'), saved('b', 'second')]);
      final enabled = ValueNotifier(true);
      addTearDown(enabled.dispose);
      String? chosen;
      var toggles = 0;
      await t.pumpWidget(
        ListenableBuilder(
          listenable: enabled,
          builder: (context) => ResumePicker(
            picker: state,
            agent: 'fake',
            rows: 6,
            room: 24,
            active: enabled.value,
            onToggleScope: () => toggles++,
            onCanceled: () {},
            onSelected: (s) => chosen = s.resume.sessionId,
          ),
        ),
        size: const Size(80, 24),
      );
      await t.press('down');
      enabled.value = false;
      await t.pump();
      await t.press('enter');
      await t.press('1');
      await t.press('ctrl+a');
      expect(chosen, isNull);
      expect(toggles, 0);
      enabled.value = true;
      await t.pump();
      await t.press('enter');
      expect(chosen, 'b');
    },
  );
  testWidgets(
    'fitting and overflowing resume frames bubble every wheel region',
    (t) async {
      var forwarded = 0;
      for (final count in [1, 8]) {
        await t.pumpWidget(
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (_) => forwarded++,
            child: frame(
              snapshot([
                for (var i = 0; i < count; i++) saved('$i', 'Choice $i'),
              ]),
              rows: 3,
            ),
          ),
          size: const Size(80, 24),
        );
        final title = t.screen.lines.indexWhere(
          (line) => line.contains('Resume a session'),
        );
        final choice = t.screen.lines.indexWhere(
          (line) => line.contains('Choice'),
        );
        for (final y in [title - 1, title, title + 1, choice]) {
          final before = forwarded;
          await t.mouse(
            MouseEvent(
              MouseEventKind.wheel,
              position: Offset(5, y),
              scrollDelta: const Offset(0, -1),
            ),
          );
          expect(forwarded, before + 1);
          expect(t.screen, shows('Choice 0'));
        }
      }
    },
  );
  testWidgets('32x10 clipped chrome never leaves hidden acceptance', (t) async {
    var accepts = 0, toggles = 0;
    await t.pumpWidget(
      frame(
        snapshot([saved('a', 'invisible')]),
        room: 5,
        selected: (_) => accepts++,
        toggled: () => toggles++,
      ),
      size: const Size(32, 10),
    );
    await t.press('enter');
    await t.press('1');
    await t.press('ctrl+a');
    expect(accepts, 0);
    expect(toggles, 1);
    expect(t.screen, isNot(shows('Enter to resume')));
  });
}
