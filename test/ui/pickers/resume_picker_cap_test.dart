import 'dart:math' as math;

import 'package:chord/session/sessions.dart';
import 'package:chord/ui/pickers/picker.dart';
import 'package:chord/ui/pickers/pickers.dart';
import 'package:chord/ui/pickers/state.dart';
import 'package:chord/ui/prompt/overlay.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

ResumePickerState saved(int count, String title) => ResumePickerState(
  sessions: [
    for (var i = 0; i < count; i++)
      EarlierSession(
        resume: Resume(sessionId: '$i', cwd: 'project'),
        lastUsedAt: '2000-01-01T00:00:00Z',
        prompt: title,
      ),
  ],
  cwd: 'project',
  opening: 'cap',
  openedAt: 946771200000,
);

void main() {
  _testerResumeCapBoundaries();
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final count in [5, 6, 7]) {
      for (final (kind, title) in [
        ('short', 'Short title'),
        ('empty', ''),
        ('tall', [for (var i = 0; i < 20; i++) 'Tall title $i'].join('\n')),
      ]) {
        testWidgets(
          'exact cap count $count/$kind matches uncapped geometry at $size',
          (t) async {
            final state = saved(count, title);
            resetResumePickerWorkDiagnostics();
            await t.pumpWidget(
              ResumePicker(
                picker: state,
                agent: 'fake',
                rows: 6,
                room: size.height,
                onToggleScope: () {},
                onSelected: (_) {},
                onCanceled: () {},
              ),
              size: size,
            );
            final work = resumePickerWorkDiagnostics;
            if (count > 6) {
              expect(work.linePasses, 0);
              expect(work.overflowPasses, 0);
              expect(work.rowShapes, count);
            } else {
              expect(work.linePasses, 1);
              expect(work.overflowPasses, kind == 'tall' ? 1 : 0);
            }
            final choices = sessionChoices(state.sessions, state.openedAt);
            final listed = framedRows(6, size.height, count);
            final first = sessionListLines(choices, size.width);
            final expected = math.min(
              listed,
              first > listed
                  ? sessionListLines(choices, size.width, overflow: true)
                  : first,
            );
            final pickers = <Picker<SessionChoice>>[];
            final viewports = <RenderListViewport>[];
            void visit(Element element) {
              if (element.widget case final Picker<SessionChoice> picker) {
                pickers.add(picker);
              }
              if (element is RenderObjectElement &&
                  element.renderObject is RenderListViewport) {
                viewports.add(element.renderObject as RenderListViewport);
              }
              element.visitChildren(visit);
            }

            visit(t.host.rootElement);
            expect(pickers.single.maxVisibleRows, expected);
            expect(
              viewports.single.size.height +
                  (t.screen.text.contains('… +') ? 1 : 0),
              expected,
            );
            expect(t.screen.text, isNot(contains('StateError')));
          },
        );
      }
    }
    testWidgets('zero room skips sizing and never defers a choice at $size', (
      t,
    ) async {
      final room = ValueNotifier(0);
      final state = saved(7, 'Restored title');
      final picks = <String>[];
      resetResumePickerWorkDiagnostics();
      await t.pumpWidget(
        ListenableBuilder(
          listenable: room,
          builder: (_) => ResumePicker(
            picker: state,
            agent: 'fake',
            rows: 6,
            room: room.value,
            onToggleScope: () {},
            onSelected: (session) => picks.add(session.resume.sessionId),
            onCanceled: () {},
          ),
        ),
        size: size,
      );
      expect(resumePickerWorkDiagnostics.linePasses, 0);
      expect(resumePickerWorkDiagnostics.overflowPasses, 0);
      expect(resumePickerWorkDiagnostics.rowShapes, 0);
      await t.press('enter 1 down');
      expect(picks, isEmpty);
      room.value = size.height;
      await t.pump();
      expect(picks, isEmpty);
      await t.press('enter');
      expect(picks, ['0']);
      t.dispose();
      room.dispose();
    });
  }
}

void _testerResumeCapBoundaries() {
  group('tester: U54c2 cap available-room boundaries', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'empty choices skip sizing but keep scope and cancel at $size',
        (t) async {
          var scopes = 0, cancels = 0, picks = 0;
          resetResumePickerWorkDiagnostics();
          await t.pumpWidget(
            ResumePicker(
              picker: saved(0, ''),
              agent: 'fake',
              rows: 10,
              room: size.height,
              onToggleScope: () => scopes++,
              onCanceled: () => cancels++,
              onSelected: (_) => picks++,
            ),
            size: size,
          );
          expect(resumePickerWorkDiagnostics.linePasses, 0);
          expect(resumePickerWorkDiagnostics.overflowPasses, 0);
          expect(resumePickerWorkDiagnostics.rowShapes, 0);
          expect(t.screen, shows('No earlier sessions in this directory.'));
          await t.press('down j k 1 enter ctrl+a esc');
          expect(picks, 0);
          expect(scopes, 1);
          expect(cancels, 1);
        },
      );

      testWidgets(
        'room cap below configured rows transitions to exact equality at $size',
        (t) async {
          final room = ValueNotifier(10);
          final state = saved(4, 'Short');
          final picks = <String>[];
          resetResumePickerWorkDiagnostics();
          await t.pumpWidget(
            ListenableBuilder(
              listenable: room,
              builder: (_) => ResumePicker(
                picker: state,
                agent: 'fake',
                rows: 10,
                room: room.value,
                onToggleScope: () {},
                onCanceled: () {},
                onSelected: (session) => picks.add(session.resume.sessionId),
              ),
            ),
            size: size,
          );
          expect(resumePickerWorkDiagnostics.linePasses, 0);
          expect(resumePickerWorkDiagnostics.overflowPasses, 0);
          resetResumePickerWorkDiagnostics();
          room.value = 11;
          await t.pump();
          expect(resumePickerWorkDiagnostics.choiceCalls, 0);
          expect(resumePickerWorkDiagnostics.linePasses, 1);
          expect(resumePickerWorkDiagnostics.overflowPasses, 0);
          await t.press('down enter');
          expect(picks, ['1']);
          room.value = 7;
          await t.pump();
          await t.press('down 1 enter');
          expect(picks, ['1']);
          resetResumePickerWorkDiagnostics();
          room.value = 10;
          await t.pump();
          expect(resumePickerWorkDiagnostics.linePasses, 0);
          expect(resumePickerWorkDiagnostics.overflowPasses, 0);
          expect(picks, ['1']);
          await t.press('1');
          expect(picks, ['1', '0']);
          t.dispose();
          room.dispose();
        },
      );
    }
  });
}
