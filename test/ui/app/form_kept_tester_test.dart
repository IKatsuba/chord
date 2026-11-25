import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/form.dart' show formPreview;
import '../../../tool/wheel.dart' show wheelPermission;
import 'selection_window_test.dart';

const _form = model.FormWait(
  'form',
  'Input',
  schema: {
    'type': 'object',
    'properties': {
      'name': {'type': 'string', 'title': 'Name'},
    },
  },
);
void _set(
  StartConnection c, {
  model.TurnState turn = const model.Working('t', 0),
  bool asked = true,
  List<model.PlanAsk> plans = const [],
}) {
  c.app.value = AppState(
    start: c.app.value.start,
    transcript: model.Transcript(
      turn: turn,
      asking: asked ? const [_form] : const [],
      planAsks: plans,
    ),
  );
}

Form _visible(WidgetTester t) {
  Form? result;
  void visit(Element e) {
    if (e.widget case final Form form) result = form;
    e.visitChildren(visit);
  }

  visit(t.host.rootElement);
  expect(result, isNotNull);
  return result!;
}

void main() {
  group('tester pending form controller ownership', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'permission and plan covers retain cursor then settlement disposes controller $size',
        (t) async {
          final c = selectionConnection();
          addTearDown(c.close);
          _set(c);
          await t.pumpWidget(
            TranscriptWindow(launch: selectionLaunch, connection: c),
            size: size,
          );
          final controller = _visible(t).controller;
          await t.paste('alpha界🙂e\u0301omega');
          await t.press('home right right');
          expect(controller.value.cursor, 2);
          for (final plan in [false, true]) {
            _set(
              c,
              turn: plan
                  ? const model.Working('t', 0)
                  : model.AwaitingPermission('t', 0, [wheelPermission()]),
              plans: plan
                  ? const [
                      model.PlanAsk(
                        't',
                        model.PlanWait(
                          'p',
                          model.PlanAgent.cursor,
                          toolCallId: 'call',
                          plan: 'A plan',
                        ),
                      ),
                    ]
                  : const [],
            );
            await t.pump();
            expect(controller.isDisposed, isFalse);
            _set(c);
            await t.pump();
            expect(_visible(t).controller, same(controller));
            expect(controller.value.cursor, 2);
            expect(controller.value.focus, const FormFocus.field(0));
          }
          await t.type('X');
          expect(controller.value.values['name'], 'alXpha界🙂e\u0301omega');
          _set(c, asked: false);
          await t.pump();
          expect(controller.isDisposed, isTrue);
          expect(controller.hasListeners, isFalse);
          _set(c);
          await t.pump();
          final fresh = _visible(t).controller;
          expect(fresh, isNot(same(controller)));
          expect(fresh.value.values, isEmpty);
          await t.pumpWidget(const SizedBox(), size: size);
          expect(fresh.isDisposed, isTrue);
        },
      );

      testWidgets(
        'held link survives narrow resize and attention restores its choices $size',
        (t) async {
          final c = StartConnection(command: 'unused', cwd: '.');
          addTearDown(c.close);
          await t.pumpWidget(formPreview(c, const ['--long-link']), size: size);
          expect(t.screen.text, contains('ctrl+x a to answer'));
          for (final next in [
            Size.zero,
            const Size(1, 1),
            const Size(24, 12),
            size,
          ]) {
            await t.resize(next);
          }
          expect(t.screen.text, contains('ctrl+x a to answer'));
          await t.press('ctrl+x a');
          expect(requestHasKeys(c.app.value), isTrue);
          expect(t.screen.text, contains('1. Open in the browser'));
          expect(t.screen.text, isNot(contains('more lines')));
          await t.press('down');
          expect(t.screen.text, contains('❯ 2. Decline'));
        },
      );
    }
  });
}
