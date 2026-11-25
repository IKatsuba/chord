import 'dart:async';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord/ui/transcript/scroll.dart';
import 'package:chord_tui/chord_tui.dart';

// U6 fixture: no agent. New output arrives every 300ms; page up to hold it.
void main() => runApp(const _List());

class _List extends StatefulWidget {
  const _List();
  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> {
  final scroll = ScrollController(follow: Follow.bottom);
  var entries = <model.Entry>[
    model.ThoughtEntry(
      't',
      TextRun.empty.plus('A thought\nwith several\nlines when\nexpanded.'),
    ),
    for (var i = 1; i <= 100; i++)
      model.UserEntry('t', 'Line $i of the transcript.'),
  ];
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      setState(
        () => entries = [
          ...entries,
          model.AssistantEntry(
            't',
            TextRun.empty.plus('New output ${entries.length}'),
          ),
        ],
      );
      applyScrollEffect(scroll, ScrollEffect.news);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [Binding('ctrl+q', 'Quit', () => exitApp(context))],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Transcript(
        transcript: model.Transcript(entries: entries),
        controller: scroll,
        footer: const TextArea(
          autofocus: true,
          maxHeight: 1,
          placeholder:
              'Page up; ctrl+o toggles details; end follows; ctrl+q quits',
          unhandledKeys: {
            'home',
            'end',
            'shift+home',
            'shift+end',
            'shift+up',
            'shift+down',
            'pageup',
            'pagedown',
            'shift+pageup',
            'shift+pagedown',
          },
        ),
      ),
    ),
  );
}
