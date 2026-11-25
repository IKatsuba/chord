/// chord's one-time notices (the original's docs/design/CHD-434.md):
/// dimcode's, that it can start other agents with their approvals bypassed
/// once its `permission` option leaves `read-only`; what it says, when it is
/// due, and the record of its dismissal in chord's user directory, beside
/// the user settings file, per machine.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'session/config.dart' show AgentOption;

/// The notice's id in the record, once dismissed.
const dimcodeNotice = 'dimcode-agents';

/// What the notice says: its title, then its two paragraphs.
const dimcodeWords = (
  title: 'dimcode can start other agents',
  paragraphs: [
    'With its permission option at full-access, dimcode may start other '
        'agent CLIs it finds on your PATH, such as claude, codex and cursor, '
        'as subagents of its own, with their approvals bypassed and on your '
        'own accounts. At workspace-write it asks you first, and once you '
        "allow it, the same holds. Nothing those agents do reaches chord's "
        'permission box.',
    'To turn a CLI off, set externalAgents.<type>.enabled to false in '
        '~/.dimcode/v2/config.json (claude-code, codex, cursor, …), or use '
        "/external-agents in dimcode's own TUI. Or keep the permission option "
        'at read-only in /config, where dimcode refuses its agent tool.',
  ],
);

/// One of the notice's answers: its key, what it says, and its value.
typedef NoticeChoice = ({String key, String label, String value});

/// The notice's two answers: dismissed for good on this machine, or later.
const List<NoticeChoice> noticeChoices = [
  (key: 'dismiss', label: "Got it, don't show this again", value: 'dismiss'),
  (key: 'later', label: 'Show it again next time', value: 'later'),
];

/// dimcode's config option that says what its `agent` tool may do.
const _permission = 'permission';

/// The one value at which dimcode refuses its `agent` tool without asking.
const _readOnly = 'read-only';

/// Whether a session of [agent], by the name chord runs it as, has
/// dimcode's `permission` option at anything but `read-only`: the moment
/// the notice is about. None from any other agent, or with no such option
/// yet.
bool dimcodeAtRisk(String agent, List<AgentOption> options) {
  final permission = options.where((o) => o.id == _permission).firstOrNull;
  return agent == 'dimcode' &&
      permission != null &&
      permission.current != _readOnly;
}

/// Which sessions the notice's moment holds for, by an id of chord's for
/// each, kept apart, so one session's options leaving `read-only` makes it
/// due whatever any other is at, and a session at it still says so after
/// the person answered "show it again" for another. Each time one comes due
/// it is given a ticket, which the record's read then shows for only while
/// that session is still at risk: not once it went back to `read-only`,
/// closed, or was cleared for a session of its own under the same id.
class NoticeWatch {
  /// The ticket of each session at risk now.
  final _atRisk = <String, int>{};
  var _tickets = 0;

  /// Hears session [id], of [agent], with its options now [options]; when
  /// the notice came due, as it is at risk now and was not before, its
  /// ticket.
  int? heard(String id, String agent, List<AgentOption> options) {
    if (!dimcodeAtRisk(agent, options)) {
      _atRisk.remove(id);
      return null;
    }
    if (_atRisk.containsKey(id)) return null;
    _tickets += 1;
    _atRisk[id] = _tickets;
    return _tickets;
  }

  /// Forgets session [id], closed or cleared: it is at risk no longer, and
  /// a session after it under the same id comes due of its own.
  void gone(String id) => _atRisk.remove(id);

  /// Whether the session [ticket] was given to is still at risk as it was.
  bool holds(String id, int ticket) => _atRisk[id] == ticket;
}

/// Where a window's notices come due and are dismissed, so the record's
/// reads and its write never cross: one dismissed in the window shows no
/// more from that moment, whatever a read begun before it, or before the
/// write lands, finds; one whose write failed is given back, to show the
/// next time it comes due, the side a failure errs on.
class NoticeGate {
  /// A gate over the record's [read] and [write].
  NoticeGate(this._read, this._write);

  final Future<Set<String>> Function() _read;
  final Future<void> Function(String id) _write;
  final _dismissed = <String>{};
  // Moves on each dismissal, so a read begun before one shows nothing.
  var _generation = 0;

  /// Whether notice [id], come due, is to show: the record read, a record
  /// that does not read showing it, and [holds] still true once it is.
  Future<bool> due(String id, bool Function() holds) async {
    // Come due while dismissed here, its write pending or done, it is
    // spent: a write that fails after gives back the next time, not this
    // one.
    if (_dismissed.contains(id)) return false;
    final generation = _generation;
    Set<String> recorded;
    try {
      recorded = await _read();
    } catch (_) {
      recorded = const {};
    }
    return generation == _generation &&
        !_dismissed.contains(id) &&
        !recorded.contains(id) &&
        holds();
  }

  /// Dismisses notice [id] for good: at once here, then in the record.
  Future<void> dismiss(String id) async {
    _dismissed.add(id);
    _generation += 1;
    try {
      await _write(id);
    } catch (_) {
      _dismissed.remove(id);
    }
  }
}

/// The record of dismissed notices, beside the user settings file; none
/// without a config home.
String? noticesFile(String? configHome) =>
    configHome == null ? null : p.join(configHome, 'chord', 'notices.json');

/// The notices dismissed on this machine, as [file] records them; none when
/// there is no file, or one that does not read, which is shown again rather
/// than lost. A file that cannot be opened at all, a directory, throws.
Future<Set<String>> dismissedNotices(String? file) async {
  if (file == null) return {};
  final Object? read;
  try {
    read = jsonDecode(
      utf8.decode(await File(file).readAsBytes(), allowMalformed: true),
    );
  } on PathNotFoundException {
    return {};
  } on FormatException {
    return {};
  }
  if (read case {
    'dismissed': final List<Object?> dismissed,
  } when dismissed.every((id) => id is String)) {
    return {...dismissed.cast<String>()};
  }
  return {};
}

/// Records notice [id] dismissed in [file], beside any others there: to a
/// file beside it renamed over the old, so a failed write leaves nothing
/// half-written.
Future<void> dismissNotice(String file, String id) async {
  final dismissed = {...await dismissedNotices(file), id};
  final temporary = '$file.${const Uuid().v4()}.tmp';
  await Directory(p.dirname(file)).create(recursive: true);
  try {
    await File(temporary).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'dismissed': dismissed.toList()})}\n',
    );
    await File(temporary).rename(file);
  } catch (_) {
    try {
      await File(temporary).delete();
    } on FileSystemException {
      // Nothing was left to remove.
    }
    rethrow;
  }
}
