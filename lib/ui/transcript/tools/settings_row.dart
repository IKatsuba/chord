/// The `settings` tool's call on the transcript: its rows, a value wrapped
/// at the cell under its own column and never folded, as the row is what
/// the person reads it in. From the original's
/// `ui/transcript/tools/settings_row.ts`.
library;

import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';

import '../../../session/transcript/types.dart';
import '../../../settings.dart' show shownValue;
import 'chord.dart' show chordHeadline, settingsPathOf;
import 'tools.dart' show Headline, headlineRows;

/// How a settings row's text is drawn.
enum SettingsTone { text, dim, warning, success }

/// One row under the call: a label and what it says, in a role's colour.
typedef SettingsRow = ({String label, String text, SettingsTone tone});

Map<String, Object?> _record(Object? value) =>
    value is Map<String, Object?> ? value : const {};

/// Whether [call] is a read of every key, the one that folds.
bool readsEveryKey(ChordCall call) =>
    call.tool == ChordTool.settings &&
    call.answer != null &&
    call.input['action'] == 'read' &&
    settingsPathOf(call).isEmpty;

/// A read of every key's headline, which says the key that opens it.
Headline foldedSettingsNote(
  Headline line,
  ChordCall? call, {
  required bool expanded,
  String? key,
}) => call != null && !expanded && key != null && readsEveryKey(call)
    ? Headline(
        line.name,
        arg: line.arg,
        tag: line.tag,
        note: '${line.note ?? ''} ($key to expand)',
        sent: line.sent,
      )
    : line;

/// [label] and [text], the rows past the first under the text's own column.
List<SettingsRow> _labelled(
  String label,
  String text,
  int width, [
  SettingsTone tone = SettingsTone.text,
]) {
  final labelWidth = cellWidth(label);
  final room = math.max(width - labelWidth, 1);
  final rows = TextLayout.wrapAnsi(
    TextSpan(text),
    room,
    hard: true,
    trim: false,
    wordWrap: false,
  ).lines;
  return [
    for (final (index, row) in (rows.isEmpty ? [<Glyph>[]] : rows).indexed)
      (
        label: index == 0 ? label : ' ' * labelWidth,
        text: [for (final glyph in row) glyph.text].join(),
        tone: tone,
      ),
  ];
}

/// A value as drawn, an absent one in words.
String _valueWords(Map<String, Object?> answer, String key) =>
    answer.containsKey(key) ? shownValue(answer[key]) : 'not set';

/// A `set` or `remove`: what it changes, then what became of it.
List<SettingsRow> _changeRows(Map<String, Object?> answer, int width) {
  final shadow = answer['shadowedBy'] is String
      ? _labelled(
          '',
          '${answer['shadowedBy']} sets this too, and wins here',
          width,
          SettingsTone.warning,
        )
      : const <SettingsRow>[];
  if (answer['unchanged'] == true) {
    final held = answer.containsKey('before')
        ? 'Already ${shownValue(answer['before'])}'
        : 'Not set';
    return [
      ..._labelled('', '$held; nothing to change', width, SettingsTone.dim),
      ...shadow,
    ];
  }
  return [
    ..._labelled('Now    ', _valueWords(answer, 'before'), width),
    ..._labelled('After  ', _valueWords(answer, 'after'), width),
    ...shadow,
    if (answer['saved'] == true)
      ..._labelled(
        '',
        'Saved to ${answer['file']} · takes effect '
            '${answer['takesEffect'] == 'now' ? 'now' : 'at the next start'}',
        width,
        SettingsTone.success,
      )
    else if (answer['saved'] == false)
      ..._labelled(
        '',
        'Not saved · the person will say what to change',
        width,
        SettingsTone.dim,
      ),
  ];
}

/// The rows under a served `settings` call; none for one with no answer
/// yet or a refusal, which the transcript draws as any of chord's. [width]
/// is the room beside the gutter.
List<SettingsRow>? settingsRows(
  ChordCall call, {
  required bool expanded,
  required int width,
}) {
  if (call.tool != ChordTool.settings || call.answer == null) return null;
  final answer = _record(call.answer);
  if (call.input['action'] != 'read') return _changeRows(answer, width);
  if (!readsEveryKey(call)) {
    return [
      ..._labelled('Effective  ', _valueWords(answer, 'effective'), width),
      ..._labelled('User       ', _valueWords(answer, 'user'), width),
      ..._labelled('Project    ', _valueWords(answer, 'project'), width),
    ];
  }
  if (expanded) {
    return [
      for (final line in shownValue(call.answer, 2).split('\n'))
        ..._labelled(
          ' ' * (line.length - line.trimLeft().length),
          line.trimLeft(),
          width,
        ),
    ];
  }
  final problems = switch (answer['problems']) {
    final List<Object?> list => list.length,
    _ => 0,
  };
  return [
    ..._labelled('User     ', call.settingsFiles?.user ?? '', width),
    ..._labelled('Project  ', call.settingsFiles?.project ?? '', width),
    if (problems > 0)
      ..._labelled(
        '',
        '$problems ${problems == 1 ? 'problem' : 'problems'}',
        width,
        SettingsTone.warning,
      ),
  ];
}

/// Whether the `settings` change a box is about, by its call's [asked],
/// draws taller than the transcript's [room], so that following the bottom
/// shows only its tail; a value has no length limit and its row is never
/// folded. A box about no such call never does. [width] is what each call
/// has beside its marker.
bool settingsChangeOverflows(
  List<Entry> entries,
  String? asked,
  int width,
  int room,
) {
  if (asked == null) return false;
  for (final entry in entries) {
    if (entry case ToolEntry(:final call)) {
      final chord = call.chord;
      if (chord == null ||
          chord.tool != ChordTool.settings ||
          !chord.pending ||
          chord.asked != asked) {
        continue;
      }
      final body =
          settingsRows(
            chord,
            expanded: false,
            width: math.max(width - 5, 1),
          )?.length ??
          0;
      return headlineRows(chordHeadline(chord), math.max(width, 1)).length +
              body >
          room;
    }
  }
  return false;
}
