import 'package:chord/session/sessions.dart';
import 'package:chord/ui/app/start.dart';
import 'package:chord/ui/app/start_layout.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import '../../../tool/resume.dart' show resumeFixtureState;

ResumeStartPage page(
  List<EarlierSession> picked, {
  void Function()? canceled,
  List<String> flags = const [],
}) => ResumeStartPage(
  version: 'test',
  directory: 'project',
  agent: 'fake',
  cwd: 'project',
  home: 'home',
  sessions: resumeFixtureState(flags).sessions,
  openedAt: 946771200000,
  onPicked: picked.add,
  onCanceled: canceled,
);

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('startup resume shares title and frame sizing $size', (
      t,
    ) async {
      final picks = <EarlierSession>[];
      await t.pumpWidget(page(picks), size: size);
      expect(t.screen, shows('Resume a session'));
      expect(t.screen, shows('vtest · fake · project'));
      expect(
        t.screen,
        size.height == 40 ? shows(tagline) : isNot(shows(tagline)),
      );
      final frame = t.screen.lines.singleWhere((line) => line.contains('╭'));
      expect(frame.trim().length, size.width == 120 ? 84 : 78);
      await t.press('down');
      await t.resize(
        size == const Size(120, 40) ? const Size(80, 24) : const Size(120, 40),
      );
      await t.press('enter');
      expect(picks.single.resume.sessionId, 'saved-2');
      expect(t.exitRequested, isTrue);
    });
    testWidgets(
      'startup local empty toggles to remote scope before any acceptance $size',
      (t) async {
        final picks = <EarlierSession>[];
        await t.pumpWidget(page(picks, flags: ['--empty']), size: size);
        expect(t.screen, shows('No earlier sessions in this directory.'));
        await t.press('enter');
        await t.press('1');
        expect(picks, isEmpty);
        await t.press('ctrl+a');
        expect(t.screen, shows('this directory'));
        await t.press('1');
        expect(picks.single.resume.sessionId, 'saved-0');
      },
    );
    testWidgets(
      'startup same-batch acceptance/cancellation settles once $size',
      (t) async {
        final picks = <EarlierSession>[];
        var canceled = 0;
        await t.pumpWidget(page(picks, canceled: () => canceled++), size: size);
        for (final key in ['enter', '2', 'esc', 'ctrl+a']) {
          t.host.handleKey(Chord.parse(key).combos.single.toEvent());
        }
        await t.pump();
        expect(picks, hasLength(1));
        expect(canceled, 0);
        await t.pumpWidget(page(picks, canceled: () => canceled++), size: size);
        for (final key in ['esc', 'enter', '1']) {
          t.host.handleKey(Chord.parse(key).combos.single.toEvent());
        }
        await t.pump();
        expect(picks, hasLength(1));
        expect(canceled, 1);
      },
    );
  }
  testWidgets(
    'narrow startup retains visible choice ahead of clipped hint and border',
    (t) async {
      final picks = <EarlierSession>[];
      await t.pumpWidget(page(picks), size: const Size(32, 10));
      expect(t.screen, shows('just now'));
      expect(t.screen, isNot(shows('Inspect the saved')));
      await t.press('enter');
      await t.press('1');
      expect(t.screen, shows('just now'));
      expect(picks, hasLength(1));
      expect(picks.single.resume.sessionId, 'saved-0');
      await t.resize(const Size(120, 40));
      expect(picks, hasLength(1));
      await t.press('ctrl+d');
      expect(t.exitRequested, isTrue);
    },
  );
}
