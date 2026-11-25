import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/keys.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/history.dart' as history;
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

const _plan = model.PlanWait('p', model.PlanAgent.cursor, toolCallId: 'c');
const _asked = AppState(
  transcript: model.Transcript(
    turn: model.Working('t', 0),
    planAsks: [model.PlanAsk('t', _plan)],
  ),
);

KeyContext _context(AppState state, {bool notePages = false}) => KeyContext(
  state: state,
  history: const history.History(),
  rows: 24,
  notePages: notePages,
);

List<Step> _press(String key, AppState state, {bool notePages = false}) =>
    keySteps(Chord.parse(key), _context(state, notePages: notePages));

String _description(String key, AppState state, {bool notePages = false}) =>
    windowBindings(
      () => _context(state, notePages: notePages),
      (_) {},
    ).firstWhere((binding) => '${binding.chord}' == key).description;

void main() {
  group("an overflowing plan Note takes the page keys, as the original's "
      'keyCommand', () {
    test('page up and down page the Note while it overflows', () {
      for (final (key, step) in const [
        ('pageup', ScrollStep.pageUp),
        ('shift+pageup', ScrollStep.pageUp),
        ('pagedown', ScrollStep.pageDown),
        ('shift+pagedown', ScrollStep.pageDown),
      ]) {
        final steps = _press(key, _asked, notePages: true);
        expect((steps.single as ScrollRequest).step, step, reason: key);
        expect(
          _description(key, _asked, notePages: true),
          step == ScrollStep.pageUp ? 'Read note above' : 'Read note below',
        );
        // A Note that fits, or no plan asked: the transcript's.
        for (final (state, pages) in [
          (_asked, false),
          (const AppState(), true),
        ]) {
          final action =
              (_press(key, state, notePages: pages).single as Dispatch).action;
          expect(action, isA<TranscriptScrolledAction>(), reason: key);
        }
      }
    });

    test('the line keys stay the transcript\'s', () {
      for (final key in const ['shift+up', 'shift+down']) {
        final action =
            (_press(key, _asked, notePages: true).single as Dispatch).action;
        expect(action, isA<TranscriptScrolledAction>(), reason: key);
        expect(
          _description(key, _asked, notePages: true),
          isNot(contains('note')),
        );
      }
    });
  });
}
