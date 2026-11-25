/// The release's state, as the original's `scripts/dev/release/state.ts`:
/// what chord's release has done, written as it does it, so a stopped
/// release resumes from what it recorded rather than from what npm and git
/// suggest. Kept in `.release/chord/state.json`, gitignored, outside
/// build/, which a build may wipe while npm already has part of a release.
/// This module reads, writes and judges it; it runs no process and asks no
/// git. The original's zod schema is json_schema's here.
library;

import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;

import 'runner.dart';

/// The format this release reads and writes.
const stateFormat = 1;

const _progress = {
  'enum': ['pending', 'made', 'pushed'],
};
const _sums = {
  'type': 'object',
  'additionalProperties': {'type': 'string'},
};

final _schema = JsonSchema.create({
  'type': 'object',
  'required': [
    'format',
    'package',
    'version',
    'channel',
    'branch',
    'base',
    'built',
    'stages',
    'npm',
  ],
  'properties': {
    'format': {'const': stateFormat},
    'package': {'type': 'string'},
    'version': {'type': 'string'},
    'channel': {
      'type': ['string', 'null'],
    },
    'branch': {'type': 'string'},
    'base': {'type': 'string'},
    'versionCommit': {
      'type': 'object',
      'required': ['state'],
      'properties': {
        'state': _progress,
        'sha': {'type': 'string'},
        'files': _sums,
      },
    },
    'built': {'type': 'string'},
    'stages': {
      'type': 'object',
      'additionalProperties': {
        'type': 'object',
        'required': ['at', 'outputs'],
        'properties': {
          'at': {'type': 'string'},
          'outputs': _sums,
        },
      },
    },
    'npm': {
      'type': 'object',
      'additionalProperties': {
        'enum': ['pending', 'sent', 'answered'],
      },
    },
    'tag': {
      'type': 'object',
      'required': ['state'],
      'properties': {'state': _progress},
    },
    'draft': {
      'type': 'object',
      'required': ['state'],
      'properties': {
        'state': {
          'enum': ['pending', 'made'],
        },
        'url': {'type': 'string'},
      },
    },
  },
});

/// chord's release in progress, as `.release/chord/state.json` holds it: the
/// JSON object itself, checked against the schema whenever it is read or
/// written.
typedef ReleaseState = Map<String, Object?>;

/// The folder of [name]'s state, from the root.
String stateDir(String name) => p.join('.release', name);

/// What every refusal a state causes says last.
String abandon(String name) => 'rm -r ${stateDir(name)} abandons it';

String _stateFile(String root, String name) =>
    p.join(root, stateDir(name), 'state.json');

/// [name]'s state under [root], or null. A state of another format, another
/// package or a broken one is refused, naming the file, and left as it is.
ReleaseState? readState(String root, String name) {
  final file = File(_stateFile(root, name));
  if (!file.existsSync()) return null;
  final Object? data;
  try {
    data = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    die('${file.path} is not JSON: ${error.message}; ${abandon(name)}');
  }
  final format = data is Map ? data['format'] : null;
  if (format != stateFormat) {
    die(
      '${file.path} has format ${jsonEncode(format)}; this release reads '
      'format $stateFormat; ${abandon(name)}',
    );
  }
  final checked = _schema.validate(data);
  if (!checked.isValid) {
    final issue = checked.errors.first;
    // json_schema names a missing property in its message, after the whole
    // object; the path to it is said instead, as zod says it.
    final missing = RegExp(
      r'^required prop missing: (\S+)',
    ).firstMatch(issue.message);
    final path = [
      if (issue.instancePath.isNotEmpty)
        issue.instancePath.replaceFirst('/', '').replaceAll('/', '.'),
      ?missing?[1],
    ].join('.');
    final where = path.isEmpty ? 'the file' : path;
    final why = missing == null ? issue.message : 'required';
    die(
      "${file.path} is not a release's state: $where: $why; "
      '${abandon(name)}',
    );
  }
  final state = (data! as Map).cast<String, Object?>();
  if (state['package'] != name) {
    die(
      "${file.path} is ${state['package']}'s state, not $name's; "
      '${abandon(name)}',
    );
  }
  return state;
}

/// Writes [state] whole: to a `.tmp` beside the file, flushed, then renamed
/// over it, so a kill leaves the old state or the new one, never half.
/// [rename] is a test's way to stop one before the rename.
void writeState(
  String root,
  ReleaseState state, {
  void Function(File from, String to)? rename,
}) {
  final checked = _schema.validate(state);
  if (!checked.isValid) {
    throw ArgumentError.value(state, 'state', checked.errors.join('; '));
  }
  final name = state['package']! as String;
  final file = _stateFile(root, name);
  Directory(p.join(root, stateDir(name))).createSync(recursive: true);
  final temporary = File('$file.tmp');
  final open = temporary.openSync(mode: FileMode.write);
  try {
    open.writeStringSync(
      '${const JsonEncoder.withIndent('  ').convert(state)}\n',
    );
    open.flushSync();
  } finally {
    open.closeSync();
  }
  (rename ?? (from, to) => from.renameSync(to))(temporary, file);
}

/// Removes [name]'s state, once its release is done.
void clearState(String root, String name) {
  final dir = Directory(p.join(root, stateDir(name)));
  if (dir.existsSync()) dir.deleteSync(recursive: true);
}

Map<String, Object?> _map(ReleaseState state, String key) =>
    ((state[key] as Map?) ?? const {}).cast<String, Object?>();

String? _stateOf(ReleaseState state, String key) =>
    (state[key] as Map?)?['state'] as String?;

/// Whether everything of the release is done: npm, the tag and the draft.
bool finished(ReleaseState state, List<String> npm, bool githubRelease) =>
    npm.every((name) => _map(state, 'npm')[name] == 'answered') &&
    _stateOf(state, 'tag') == 'pushed' &&
    (!githubRelease || _stateOf(state, 'draft') == 'made');

/// How a refusal names a state's progress: its version, done stages and npm.
String described(ReleaseState state, List<String> npm) {
  final done = _map(state, 'stages').keys.toList();
  final answered = npm
      .where((name) => _map(state, 'npm')[name] == 'answered')
      .length;
  return '${state['package']} ${state['version']} is in progress (done: '
      '${done.isEmpty ? 'nothing' : done.join(', ')}; npm $answered of '
      '${npm.length})';
}

/// A run's selection, as the release judges it against a state.
typedef Selection = ({
  List<String> stages,
  List<String> selected,
  bool named,
  bool dryRun,
  String? bump,
  String? channel,
  List<String> npm,
  bool githubRelease,
});

/// What is left of publish: the npm names not answered, and whether the tag
/// and the draft are still to make.
typedef PublishLeft = ({List<String> npm, bool tag, bool draft});

/// What a run with a state does: the done stages [cleared] to run again,
/// the [stages] to run (publish left out), and what is left of [publish]
/// when it is selected.
typedef Left = ({
  List<String> cleared,
  List<String> stages,
  PublishLeft? publish,
});

/// What a run with [state] does under [selection]: the selected stages not
/// done, then, when publish is selected, what of it is not done. Refusals
/// name the state's way out; [command] is how a person continues it.
Left left(ReleaseState state, Selection selection, {required String command}) {
  final name = state['package']! as String;
  Never refuse(String why) => die('$why; ${abandon(name)}');
  if (selection.dryRun) {
    refuse(
      '--dry-run is refused while ${described(state, selection.npm)}: '
      '`$command` continues it',
    );
  }
  if (selection.bump != null && selection.bump != state['version']) {
    refuse(
      '--bump ${selection.bump} is refused while '
      '${described(state, selection.npm)}: `$command` continues it',
    );
  }
  if (selection.channel != null && selection.channel != state['channel']) {
    refuse(
      '--channel ${selection.channel} is not '
      "${described(state, selection.npm)}'s channel, "
      '${state['channel'] ?? 'none'}',
    );
  }
  final stagesDone = _map(state, 'stages');
  bool done(String stage) => stagesDone.containsKey(stage);
  final publish = selection.selected.contains('publish');
  final built = [
    for (final stage in selection.selected)
      if (stage != 'publish') stage,
  ];
  final again = selection.named ? built.where(done).toList() : <String>[];
  final cleared = again.isEmpty
      ? <String>[]
      : [
          for (final stage in selection.stages.sublist(
            selection.stages.indexOf(again.first),
          ))
            if (stage != 'publish' && done(stage)) stage,
        ];
  if (cleared.isNotEmpty &&
      _map(state, 'npm').values.any((each) => each != 'pending')) {
    refuse(
      '${_listed(cleared)} cannot run again: npm has $name '
      "${state['version']}'s bytes from ${described(state, selection.npm)}",
    );
  }
  final stages = [
    for (final stage in built)
      if (cleared.contains(stage) || !done(stage)) stage,
  ];
  if (publish) {
    // The stage before publish leaves what it sends: pack's output.
    final at = selection.stages.indexOf('publish');
    final before = at > 0 ? selection.stages[at - 1] : null;
    if (before != null &&
        (!done(before) || cleared.contains(before)) &&
        !stages.contains(before)) {
      refuse(
        "publish needs $before's output; $before is not done in $name "
        '${state['version']}',
      );
    }
  }
  return (
    cleared: cleared,
    stages: stages,
    publish: publish
        ? (
            npm: [
              for (final npm in selection.npm)
                if (_map(state, 'npm')[npm] != 'answered') npm,
            ],
            tag: _stateOf(state, 'tag') != 'pushed',
            draft:
                selection.githubRelease && _stateOf(state, 'draft') != 'made',
          )
        : null,
  );
}

/// [state] with [stages] no longer done.
ReleaseState cleared(ReleaseState state, List<String> stages) => {
  ...state,
  'stages': {
    for (final MapEntry(:key, :value) in _map(state, 'stages').entries)
      if (!stages.contains(key)) key: value,
  },
};

/// `a`, `a and b`, `a, b and c`.
String _listed(List<String> names) => names.length < 2
    ? names.join()
    : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
