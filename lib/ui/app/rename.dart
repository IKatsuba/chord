/// What `/rename` says under the command as typed, by the state the session
/// it acts on is in: the window draws it and dispatches. From the
/// original's `ui/app/rename.ts`.
library;

import 'package:chord_tui/chord_tui.dart' show stripAnsi;

import '../../session/sessions.dart' show titleLine;

/// An agent's string as a note draws it: its escapes gone, on one line.
String _clean(String text) => titleLine(stripAnsi(text));

/// A note's words and whether it reads as an error.
typedef RenameNote = ({String text, bool failed});

/// Why `/rename` cannot act on the session in front.
enum RenameRefusal { starting, exited, task }

/// The note for a session `/rename` refuses; [name] is the agent's.
RenameNote refusedNote(RenameRefusal refusal, String name) => switch (refusal) {
  RenameRefusal.starting => (
    text: 'The session is not open yet; rename it once it is.',
    failed: true,
  ),
  RenameRefusal.exited => (
    text: '$name has exited; its session cannot be renamed.',
    failed: true,
  ),
  RenameRefusal.task => (
    text: '$name is a task; it keeps the title it was given.',
    failed: true,
  ),
};

/// The note for `/rename` with no title: how, and the title it has.
RenameNote unnamedNote(String? title) => (
  text:
      'Name the session: /rename <title>'
      '${title == null ? '' : '. Now: ${_clean(title)}'}',
  failed: false,
);

/// The note while the agent has the rename.
RenameNote renamingNote(String title) =>
    (text: 'Renaming to ${_clean(title)}…', failed: false);

/// The note once the session is renamed: by the agent, to the title it
/// answered, or in chord only, for an agent that takes no title.
RenameNote renamedNote(String title, String agent, bool taken) => (
  text: taken
      ? 'Renamed to ${_clean(title)}'
      : 'Renamed to ${_clean(title)} in chord only: $agent takes no title, '
            'and its own may replace it',
  failed: false,
);

/// The note for a rename the agent refused, in its own words.
RenameNote refusedByAgentNote(String agent, String message) => (
  text: 'Could not rename: $agent refused it: ${_clean(message)}',
  failed: true,
);
