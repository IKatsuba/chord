/// An agent's `notice`, from the original's `session/transcript/notices.ts`:
/// advice the agent sends a client that declared `session.notices`, in place
/// of the reply text it sends otherwise. Each is a line of its own, never
/// merged: notices carry no id.
library;

import '../../acp/schema.dart' as acp;
import 'entries.dart';
import 'types.dart';

/// [state] with [notice] as its last entry. A severity ACP's schema leaves
/// open draws as `info`; a description omitted, null or empty is none.
Transcript addNotice(
  Transcript state,
  String turnId,
  acp.SessionUpdate notice,
) {
  final json = notice.toJson();
  final title = json['title'];
  if (title is! String) throw const FormatException('A notice has no title.');
  final severity =
      NoticeSeverity.values
          .where((each) => each.name == json['severity'])
          .firstOrNull ??
      NoticeSeverity.info;
  final description = switch (json['description']) {
    final String text when text.isNotEmpty => text,
    _ => null,
  };
  return state.withEntries(
    appended(state.entries, [
      NoticeEntry(turnId, severity, title, description: description),
    ]),
  );
}
