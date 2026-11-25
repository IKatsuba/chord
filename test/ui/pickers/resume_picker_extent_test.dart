import 'package:chord/session/sessions.dart';
import 'package:chord/ui/pickers/picker.dart';
import 'package:chord/ui/pickers/pickers.dart';
import 'package:chord/ui/pickers/state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

EarlierSession saved(int i, {String? title, String cwd = 'project'}) =>
    EarlierSession(
      resume: Resume(sessionId: 'session-$i', cwd: cwd),
      lastUsedAt: '2000-01-01T00:00:00Z',
      prompt: title ?? 'Saved request $i 界😀',
    );
ResumePickerState snapshot(
  List<EarlierSession> sessions, {
  bool all = false,
  Object opening = 'opening',
}) => ResumePickerState(
  sessions: sessions,
  cwd: 'project',
  opening: opening,
  openedAt: DateTime.utc(2000, 1, 2).millisecondsSinceEpoch,
  everywhere: all,
);

void expectNoWork() {
  expect(resumePickerWorkDiagnostics, (
    choiceCalls: 0,
    projectedChoices: 0,
    linePasses: 0,
    overflowPasses: 0,
    rowShapes: 0,
  ));
}

void main() {
  _testerResumeExtentBoundaries();
  test(
    'work counters separate choices, no-edge/edge sizing and shared shaping',
    () {
      resetResumePickerWorkDiagnostics();
      final choices = sessionChoices([saved(0), saved(1)], 0);
      final first = sessionListLines(choices, 80);
      sessionListLines(choices, 80, overflow: true);
      expect(resumePickerWorkDiagnostics, (
        choiceCalls: 1,
        projectedChoices: 2,
        linePasses: 1,
        overflowPasses: 1,
        rowShapes: 4,
      ));
      resetResumePickerWorkDiagnostics();
      expectNoWork();
      expect(sessionListLines(choices, 80), first);
      expect(resumePickerWorkDiagnostics.rowShapes, 2);
    },
  );

  for (final count in [2000, 10000]) {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'resume $count choices reuse projection across stable input at $size',
        (t) async {
          final state = snapshot([for (var i = 0; i < count; i++) saved(i)]);
          final changes = ValueNotifier(0);
          var active = true;
          final picks = <String>[];
          final other = FocusNode();
          resetResumePickerWorkDiagnostics();
          await t.pumpWidget(
            ListenableBuilder(
              listenable: changes,
              builder: (_) => Column(
                children: [
                  Expanded(
                    child: ResumePicker(
                      picker: state,
                      agent: 'fake',
                      rows: 8,
                      room: size.height,
                      active: active,
                      onToggleScope: () {},
                      onCanceled: () {},
                      onSelected: (choice) =>
                          picks.add(choice.resume.sessionId),
                    ),
                  ),
                  Focus(focusNode: other, child: Text('Other control')),
                ],
              ),
            ),
            size: size,
          );
          expect(resumePickerWorkDiagnostics.choiceCalls, 1);
          expect(resumePickerWorkDiagnostics.projectedChoices, count);
          expect(resumePickerWorkDiagnostics.linePasses, 0);
          expect(resumePickerWorkDiagnostics.overflowPasses, 0);
          expect(resumePickerWorkDiagnostics.rowShapes, count);
          resetResumePickerWorkDiagnostics();
          await t.press('down enter');
          expect(picks, ['session-1']);
          expectNoWork();
          changes.value++;
          await t.pump();
          expectNoWork();
          other.requestFocus();
          await t.pump();
          expectNoWork();
          active = false;
          changes.value++;
          await t.pump();
          expectNoWork();
          active = true;
          changes.value++;
          await t.pump();
          expectNoWork();
          await t.resize(Size(size.width == 120 ? 80 : 120, size.height));
          expect(resumePickerWorkDiagnostics.choiceCalls, 0);
          expect(resumePickerWorkDiagnostics.linePasses, 0);
          expect(resumePickerWorkDiagnostics.overflowPasses, 0);
          expect(resumePickerWorkDiagnostics.rowShapes, count);
          resetResumePickerWorkDiagnostics();
          await t.resize(Size(t.size.width, size.height - 2));
          expectNoWork();
          t.dispose();
          changes.dispose();
          other.dispose();
        },
      );
    }
  }

  testWidgets('new snapshot content, home and scope invalidate frozen labels', (
    t,
  ) async {
    final changes = ValueNotifier(0);
    var state = snapshot([saved(0), saved(1)]);
    var home = 'home';
    await t.pumpWidget(
      ListenableBuilder(
        listenable: changes,
        builder: (_) => ResumePicker(
          picker: state,
          agent: 'fake',
          home: home,
          rows: 6,
          room: 24,
          onToggleScope: () {},
          onSelected: (_) {},
          onCanceled: () {},
        ),
      ),
    );
    state = snapshot([
      saved(2, title: 'Replacement title', cwd: 'home/界/😀'),
    ], all: true);
    resetResumePickerWorkDiagnostics();
    changes.value++;
    await t.pump();
    expect(resumePickerWorkDiagnostics.choiceCalls, 1);
    expect(t.screen, shows('Replacement title'));
    expect(t.screen, isNot(shows('Saved request 0')));
    expect(t.screen, shows('~/界/😀'));
    home = 'elsewhere';
    resetResumePickerWorkDiagnostics();
    changes.value++;
    await t.pump();
    expect(resumePickerWorkDiagnostics.choiceCalls, 1);
    expect(t.screen, shows('home/界/😀'));
    state = snapshot([saved(3, title: 'New opening')], opening: 'other');
    resetResumePickerWorkDiagnostics();
    changes.value++;
    await t.pump();
    expect(resumePickerWorkDiagnostics.choiceCalls, 1);
    expect(t.screen, shows('New opening'));
    t.dispose();
    changes.dispose();
  });

  for (final width in [4, 8, 16, 24, 31, 32, 35, 36, 37, 54, 55, 56, 80, 120]) {
    testWidgets(
      'shared exact resume shaping matches rendered Unicode rows at width $width',
      (t) async {
        final state = snapshot([
          saved(
            0,
            title:
                '界 café é 😀 title with a very-long-unbroken-tail\nand hard break',
            cwd: 'home/界/😀/directory',
          ),
          saved(1, title: '', cwd: 'other'),
        ], all: true);
        await t.pumpWidget(
          ResumePicker(
            picker: state,
            agent: 'fake',
            home: 'home',
            rows: 8,
            room: 40,
            onToggleScope: () {},
            onSelected: (_) {},
            onCanceled: () {},
          ),
          size: Size(width, 40),
        );
        // Every mounted row is validated against its promised height by ListView.
        expect(t.screen.text, isNot(contains('StateError')));
        expect(t.screen.text, isNot(contains('Negative content height')));
        await t.press('down up');
      },
    );
  }
}

void _testerResumeExtentBoundaries() {
  group('tester: U54c2 frozen resume snapshot boundaries', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'cwd and age snapshots replace labels and acceptance at $size',
        (t) async {
          final changes = ValueNotifier(0);
          final sessions = [
            saved(1),
            saved(2, title: 'Other directory', cwd: 'other'),
          ];
          var state = snapshot(sessions);
          final picks = <EarlierSession>[];
          await t.pumpWidget(
            ListenableBuilder(
              listenable: changes,
              builder: (_) => ResumePicker(
                picker: state,
                agent: 'fake',
                rows: 8,
                room: size.height,
                onToggleScope: () {},
                onCanceled: () {},
                onSelected: picks.add,
              ),
            ),
            size: size,
          );
          expect(t.screen, shows('yesterday'));
          expect(t.screen, shows('Saved request 1'));
          state = ResumePickerState(
            sessions: sessions,
            cwd: 'other',
            opening: 'next',
            openedAt: DateTime.utc(2000, 1, 3).millisecondsSinceEpoch,
          );
          resetResumePickerWorkDiagnostics();
          changes.value++;
          await t.pump();
          expect(resumePickerWorkDiagnostics.choiceCalls, 1);
          expect(t.screen, shows('2 days ago'));
          expect(t.screen, shows('Other directory'));
          expect(t.screen.text, isNot(contains('Saved request 1')));
          await t.press('enter');
          expect(picks, [same(sessions[1])]);
          resetResumePickerWorkDiagnostics();
          changes.value++;
          await t.pump();
          expectNoWork();
          t.dispose();
          changes.dispose();
        },
      );

      testWidgets(
        'a thousand hidden snapshots cannot accept an obsolete choice at $size',
        (t) async {
          final changes = ValueNotifier(0);
          var state = snapshot([saved(0)]);
          var room = size.height;
          final picks = <EarlierSession>[];
          await t.pumpWidget(
            ListenableBuilder(
              listenable: changes,
              builder: (_) => ResumePicker(
                picker: state,
                agent: 'fake',
                rows: 8,
                room: room,
                onToggleScope: () {},
                onCanceled: () {},
                onSelected: picks.add,
              ),
            ),
            size: size,
          );
          room = 0;
          changes.value++;
          await t.pump();
          for (var i = 1; i <= 1000; i++) {
            state = snapshot([saved(i)], opening: i);
            changes.value++;
          }
          await t.press('down j k 1 enter');
          expect(picks, isEmpty);
          room = size.height;
          changes.value++;
          await t.pump();
          expect(picks, isEmpty);
          expect(t.screen, shows('Saved request 1000'));
          await t.press('enter');
          expect(picks.single.resume.sessionId, 'session-1000');
          await t.pumpWidget(const SizedBox());
          await t.press('1 enter');
          expect(picks, hasLength(1));
          t.dispose();
          changes.dispose();
        },
      );

      testWidgets(
        'number gutter and Unicode snapshots equal a fresh picker at $size',
        (t) async {
          final changes = ValueNotifier(0);
          var state = snapshot([saved(0)]);
          final picks = <EarlierSession>[];
          Widget frame(Key key) => ResumePicker(
            key: key,
            picker: state,
            agent: 'fake',
            rows: 8,
            room: size.height,
            home: 'home',
            onToggleScope: () {},
            onCanceled: () {},
            onSelected: picks.add,
          );
          await t.pumpWidget(
            ListenableBuilder(
              listenable: changes,
              builder: (_) => frame(const ValueKey('retained')),
            ),
            size: size,
          );
          for (final count in [9, 10, 99, 100]) {
            state = snapshot([
              for (var i = 0; i < count; i++)
                saved(
                  i,
                  title: '$i 界🙂e\u0301\x1b[31mTitle\x1b[0m ${'word ' * 8}',
                  cwd: i.isEven ? 'project' : 'home/界/🙂',
                ),
            ], all: true);
            changes.value++;
            await t.pump();
            final retained = t.screen.text;
            await t.press('enter');
            expect(picks.last.resume.sessionId, 'session-0');
            await t.pumpWidget(frame(ValueKey(count)), size: size);
            expect(t.screen.text, retained);
            expect(t.screen.text, isNot(contains('\x1b')));
            await t.pumpWidget(
              ListenableBuilder(
                listenable: changes,
                builder: (_) => frame(const ValueKey('retained')),
              ),
              size: size,
            );
          }
          t.dispose();
          changes.dispose();
        },
      );
    }
  });
}
