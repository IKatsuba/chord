import 'dart:io';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/selection.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';

void main(List<String> args) => runApp(
  SteeringReplayFixture(alone: args.contains('--alone')),
  theme: args.contains('--light') ? ThemeData.light() : ThemeData.dark(),
  environment: {
    ...Platform.environment,
    if (args.contains('--plain')) 'NO_COLOR': '1',
  },
);

/// Agent-free personal steering replay and interrupted adapter work.
class SteeringReplayFixture extends StatefulWidget {
  const SteeringReplayFixture({super.key, this.alone = false});
  final bool alone;
  @override
  State<SteeringReplayFixture> createState() => _SteeringReplayFixtureState();
}

class _SteeringReplayFixtureState extends State<SteeringReplayFixture> {
  final _scroll = ScrollController(follow: Follow.bottom);
  final _namespace = Object();
  late final _sources = TranscriptSources(_namespace);
  late model.Transcript _state;
  late bool _alone;
  var _bound = true, _next = false, _late = 0;

  @override
  void initState() {
    super.initState();
    _alone = widget.alone;
    _reset();
  }

  model.UpdateAction _say(String id, String text) => model.UpdateAction(
    id,
    acp.SessionUpdate.fromJson({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': text},
    }),
  );

  void _apply(model.TranscriptAction action) =>
      _state = reduceTranscript(_state, action);
  void _reset() {
    _state = model.Transcript.empty;
    _next = false;
    _late = 0;
    _apply(const model.PromptAction('old', 'Earlier request', 1));
    _apply(_say('old', 'Earlier answer.'));
    _apply(
      const model.PromptAction(
        'queued',
        'Personal message accepted into this turn',
        2,
        into: 'old',
      ),
    );
    _apply(const model.ResultAction('old', model.TurnAnswered('end_turn')));
    if (!_alone) _apply(_say('own', 'Visible self-started work 界😀 é 👩‍💻.'));
    _apply(const model.SelfStartedAction('own'));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _sources.retain(_state.entries);
    return Actions(
      bindings: [
        Binding('ctrl+q', 'Quit', () => exitApp(context)),
        Binding(
          'ctrl+t',
          'Toggle empty self-started turn',
          () => setState(() {
            _alone = !_alone;
            _reset();
          }),
        ),
        Binding('ctrl+n', 'Append late adapter work', () {
          if (!_next) {
            setState(() => _apply(_say('own', ' Late work ${++_late}.')));
          }
        }),
        Binding('ctrl+p', 'Show next queued prompt', () {
          if (!_next) {
            setState(() {
              _next = true;
              _apply(
                const model.PromptAction(
                  'next',
                  'Queued message goes as the next turn',
                  3,
                ),
              );
            });
          }
        }),
        Binding('ctrl+r', 'Reset recorded state', () => setState(_reset)),
        Binding(
          'ctrl+s',
          'Toggle lazy source binding',
          () => setState(() => _bound = !_bound),
        ),
      ],
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            Expanded(
              child: Transcript(
                transcript: _state,
                controller: _scroll,
                bindKeys: false,
                selectionNamespace: _bound ? _namespace : null,
                selectionSources: _bound ? _sources : null,
              ),
            ),
            Text(
              'ctrl+t empty · ctrl+n late · ctrl+p next · ctrl+r reset · ctrl+s source · ctrl+q quit',
              style: Theme.of(context).dim,
              softWrap: false,
            ),
          ],
        ),
      ),
    );
  }
}
