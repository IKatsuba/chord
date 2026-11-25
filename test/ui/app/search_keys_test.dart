import 'package:chord/ui/app/keys.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/history.dart';
import 'package:chord/ui/prompt/search.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

KeyContext context(AppState state, {bool canEdit = true, bool shown = true}) =>
    KeyContext(
      state: state,
      history: const History(prompts: ['alpha', '!echo alpha', '/review']),
      rows: 40,
      canEdit: canEdit,
      searchEnabled: shown,
    );
void main() {
  test(
    'active search bindings describe cancellation and recall by their real aliases',
    () {
      Map<String, String> labels(AppState state) => {
        for (final binding in windowBindings(() => context(state), (_) {}))
          binding.chord.toString(): binding.description,
      };
      final active = labels(const AppState(search: emptySearch));
      expect(active['escape'], 'Cancel search');
      expect(active['ctrl+c'], 'Cancel search');
      expect(active['enter'], 'Take search match');
      expect(active['tab'], 'Take search match');
      expect(active['ctrl+r'], 'Older matching prompt');
      expect(
        labels(const AppState())['escape'],
        'Interrupt turn or stop command',
      );
    },
  );
  test('search open and older keys use the original literal state', () {
    final opening = keySteps(Chord.parse('ctrl+r'), context(const AppState()));
    expect(
      ((opening.single as Dispatch).action as SearchChangedAction).search,
      same(emptySearch),
    );
    final state = AppState(
      search: searched(emptySearch, [
        'alpha',
        '!echo alpha',
        '/review',
      ], 'alpha'),
    );
    final older = keySteps(Chord.parse('ctrl+r'), context(state));
    expect(
      ((older.single as Dispatch).action as SearchChangedAction).search?.match,
      0,
    );
  });
  test(
    'accept recalls bash and closes completions without sending/steering',
    () {
      final state = AppState(
        draft: 'saved',
        search: const Search(query: 'alpha', match: 1),
      );
      for (final key in ['enter', 'tab']) {
        final steps = keySteps(Chord.parse(key), context(state));
        expect((steps.first as Dispatch).action, isA<SearchChangedAction>());
        expect(steps.whereType<Send>(), isEmpty);
        expect(steps.whereType<Steer>(), isEmpty);
        expect(steps.whereType<ShowDraft>().single.text, 'echo alpha');
        expect(steps.whereType<CloseCompletions>(), hasLength(1));
        expect(steps.whereType<HistoryStep>().single.history.index, isNull);
        expect(
          steps
              .whereType<Dispatch>()
              .map((s) => s.action)
              .whereType<BashModeAction>()
              .single
              .on,
          isTrue,
        );
      }
    },
  );
  test('cancel/no-match leaves saved text cursor and history untouched', () {
    final state = AppState(draft: 'saved', cursor: 2, search: emptySearch);
    for (final key in ['escape', 'ctrl+c', 'enter', 'tab']) {
      final steps = keySteps(Chord.parse(key), context(state));
      expect(steps, hasLength(1));
      expect(
        ((steps.single as Dispatch).action as SearchChangedAction).search,
        isNull,
      );
    }
    expect(keySteps(Chord.parse('tab'), context(state, shown: false)), isEmpty);
  });
  test('modal and query editing guards preserve original action priority', () {
    const state = AppState(search: emptySearch);
    const closing = AppState(search: emptySearch, closing: true);
    expect(keySteps(Chord.parse('ctrl+r'), context(closing)), isEmpty);
    expect(searchEditSteps('late', context(closing)), isEmpty);
    expect(
      keySteps(Chord.parse('ctrl+r'), context(state, canEdit: false)),
      isEmpty,
    );
    expect(searchEditSteps('hello', context(state, canEdit: false)), isEmpty);
    expect(searchEditSteps('x', context(state), ctrl: true), isEmpty);
    final edited = searchEditSteps('alpha\nignored', context(state));
    expect(
      ((edited.single as Dispatch).action as SearchChangedAction).search?.query,
      'alpha',
    );
    expect(
      (keySteps(Chord.parse('ctrl+o'), context(state)).single as Dispatch)
          .action,
      isA<ToggleExpandedAction>(),
    );
  });
}
