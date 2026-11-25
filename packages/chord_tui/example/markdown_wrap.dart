import 'package:chord_tui/chord_tui.dart';

/// The original fake reply's two reported wrapping cases.
const wrappingSample =
    r'''The **session layer** wraps *the SDK* so the interface never touches a
process. Start with `src/session/session.ts`, then see the
[ACP spec](https://agentclientprotocol.com) for the wire format.

| Module | Holds | Tested by |
| --- | --- | --- |
| `session.ts` | opening, prompting and closing a session | `session_test.ts` |
| `processes.ts` | the promise that a closed agent is gone | `processes_test.ts` |
| `transcript.ts` | the reducer from events to what is drawn | `transcript_test.ts` |
''';

void main(List<String> args) => runApp(
  Builder(
    builder: (context) => Actions(
      bindings: [Binding('ctrl+q', 'Quit', () => exitApp(context))],
      child: args.contains('--narrow')
          ? const Markdown(
              '| Holds |\n|---|\n| alpha with abcdefgh |\n| one two three four |',
            )
          : const Padding(
              padding: EdgeInsets.only(left: 3, right: 1),
              child: Markdown(wrappingSample),
            ),
    ),
  ),
);
