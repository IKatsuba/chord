/// A release that goes on from its state, as the original's
/// `scripts/dev/release/continue.ts`: the guards a run with a state passes
/// before npm authentication, and the acts a killed run left pending,
/// settled by reading git or GitHub once. Nothing else is inferred from
/// them: what the state does not record is refused.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'archive.dart';
import 'runner.dart';
import 'state.dart';

/// The manifest the version is read from at a commit, from the root.
const manifestPath = 'pubspec.yaml';

/// The tag of [version].
String tagName(String version) => 'v$version';

Never _refuse(String name, String why) => die('$why; ${abandon(name)}');

Future<String> _git(ReleaseRunner runner, List<String> args) async {
  final ran = await runner.run('git', args);
  if (ran.status != 0) die('git ${args.join(' ')} failed: ${said(ran.stderr)}');
  return said(ran.stdout);
}

Future<bool> _holds(ReleaseRunner runner, List<String> args) async =>
    (await runner.run('git', args)).status == 0;

/// What a pending version commit turned out to be.
sealed class VersionCommit {
  const VersionCommit();
}

/// No version commit is pending.
final class NoVersionCommit extends VersionCommit {
  /// None pending.
  const NoVersionCommit();
}

/// One was left pending that never happened: HEAD is still the base.
final class VersionCommitAtBase extends VersionCommit {
  /// Never made.
  const VersionCommitAtBase();
}

/// One was made before the run was killed, at [sha].
final class VersionCommitMade extends VersionCommit {
  /// Made at [sha].
  const VersionCommitMade(this.sha);

  /// The commit.
  final String sha;
}

/// The version commit as the state and HEAD have it: none to make, one left
/// pending that never happened, or one made before the run was killed
/// (HEAD's parent is the base, and it holds exactly the files the release
/// recorded, by their sha256). Anything else is refused.
Future<VersionCommit> versionCommit(
  ReleaseRunner runner,
  ReleaseState state,
) async {
  final commit = state['versionCommit'] as Map?;
  if (commit == null || commit['state'] != 'pending') {
    return const NoVersionCommit();
  }
  final name = state['package']! as String;
  final base = state['base']! as String;
  final head = await _git(runner, ['rev-parse', 'HEAD']);
  if (head == base) return const VersionCommitAtBase();
  final parent = await runner.run('git', ['rev-parse', 'HEAD~1']);
  final files = (commit['files'] as Map?)?.cast<String, String>();
  if (parent.status == 0 &&
      said(parent.stdout) == base &&
      await _recorded(runner, base, head, files)) {
    return VersionCommitMade(head);
  }
  _refuse(
    name,
    'the version commit of $name ${state['version']} was left pending on '
    '$base, and HEAD $head is neither that commit nor it plus exactly the '
    'files the release recorded',
  );
}

/// Whether [head] holds exactly [files], each with its recorded sha256.
Future<bool> _recorded(
  ReleaseRunner runner,
  String base,
  String head,
  Map<String, String>? files,
) async {
  if (files == null) return false;
  final changed = (await _git(runner, [
    'diff',
    '--name-only',
    base,
    head,
  ])).split('\n').where((path) => path.isNotEmpty).toList()..sort();
  if (changed.join('\n') != (files.keys.toList()..sort()).join('\n')) {
    return false;
  }
  for (final path in changed) {
    // The recorded files are text (pubspec files, lib/version.dart), so
    // git's answer as text is their bytes.
    final blob = await runner.run('git', ['show', '$head:$path']);
    if (blob.status != 0 ||
        sha256.convert(utf8.encode(blob.stdout)).toString() != files[path]) {
      return false;
    }
  }
  return true;
}

/// The version [manifestPath] holds at [commit], if it holds one.
Future<String?> versionAt(ReleaseRunner runner, String commit) async {
  final shown = await runner.run('git', ['show', '$commit:$manifestPath']);
  if (shown.status != 0) return null;
  try {
    final yaml = loadYaml(shown.stdout);
    return yaml is Map ? yaml['version']?.toString() : null;
  } on YamlException {
    return null;
  }
}

/// What the guards are asked of a run with a state: the commit the stages
/// build from, whether a stage before publish is left, whether publish is
/// left, the done stages that stay done (their sums must hold), and whether
/// the run may record HEAD as the new built commit.
typedef Continuation = ({
  String built,
  bool building,
  bool publishing,
  List<String> kept,
  bool rebuild,
});

/// The guards before npm authentication: a clean tree, the built commit in
/// HEAD's history at the state's version, HEAD at it while a stage before
/// publish is left, the branch level with origin and no tag the state did
/// not make while publish is left, and every recorded sum still holding.
Future<void> guarded(
  ReleaseRunner runner,
  String root,
  ReleaseState state,
  Continuation at,
) async {
  final name = state['package']! as String;
  final version = state['version']! as String;
  final dirty = await _git(runner, [
    'status',
    '--porcelain',
    '--untracked-files=all',
  ]);
  if (dirty.isNotEmpty) _refuse(name, 'the tree is not clean:\n$dirty');
  final head = await _git(runner, ['rev-parse', 'HEAD']);
  if (!await _holds(runner, [
    'merge-base',
    '--is-ancestor',
    at.built,
    'HEAD',
  ])) {
    _refuse(
      name,
      "$name $version was built from ${at.built}, which is not in HEAD "
      "$head's history",
    );
  }
  final commit = state['versionCommit'] as Map?;
  final builtVersion = await versionAt(runner, at.built);
  if (commit?['state'] != 'pending' && builtVersion != version) {
    _refuse(
      name,
      '$manifestPath at ${at.built} is ${builtVersion ?? 'without a version'}, '
      'not $name $version',
    );
  }
  // Building again from HEAD: it must still be the state's version.
  if (at.rebuild && head != at.built) {
    final now = await versionAt(runner, head);
    if (now != version) {
      _refuse(
        name,
        '$manifestPath at HEAD $head is ${now ?? 'without a version'}, not '
        '$name $version, so it cannot be built again from HEAD',
      );
    }
  }
  if (at.building && head != at.built && !at.rebuild) {
    _refuse(
      name,
      'HEAD $head is not ${at.built}, which $name $version is built from, '
      'and a stage before publish is left: the stages build from it',
    );
  }
  if (at.publishing) {
    await _level(runner, state, head);
    await _foreignTag(runner, state, at.built);
  }
  // A path a later stage records again (sign over compile's macOS
  // binaries) holds by the later stage's sum; with that stage cleared to
  // run again, the earlier one's applies.
  final stages = ((state['stages'] as Map?) ?? const {})
      .cast<String, Object?>();
  final latest = <String, ({String stage, String sum})>{};
  for (final stage in at.kept) {
    final outputs = ((stages[stage] as Map?)?['outputs'] as Map?) ?? const {};
    for (final MapEntry(:key, :value) in outputs.entries) {
      latest[key as String] = (stage: stage, sum: value as String);
    }
  }
  for (final MapEntry(key: path, value: (:stage, :sum)) in latest.entries) {
    final file = p.join(root, path);
    if (!File(file).existsSync()) {
      _refuse(
        name,
        '$path, which $stage left, is gone; run $stage again with --from '
        '$stage',
      );
    }
    final now = sha256Of(file);
    if (now != sum) {
      _refuse(
        name,
        '$path is not what $stage left: its sha256 is $now, the state '
        'recorded $sum; run $stage again with --from $stage',
      );
    }
  }
}

/// The state's branch checked out and level with origin, or, with the
/// version commit made and not pushed, origin at its parent.
Future<void> _level(
  ReleaseRunner runner,
  ReleaseState state,
  String head,
) async {
  final name = state['package']! as String;
  final branch = state['branch']! as String;
  final current = said(
    (await runner.run('git', ['symbolic-ref', '--short', 'HEAD'])).stdout,
  );
  if (current != branch) {
    _refuse(
      name,
      '$name ${state['version']} publishes from $branch; HEAD is '
      '${current.isEmpty ? head : current}',
    );
  }
  await _git(runner, ['fetch', 'origin']);
  final origin = await _git(runner, ['rev-parse', 'origin/$branch']);
  final commit = state['versionCommit'] as Map?;
  // A version commit made and not recorded pushed: origin before the push,
  // or after one the run did not live to record. Only while HEAD is that
  // commit: past it, origin must be HEAD like any other.
  final want =
      commit?['state'] == 'made' &&
          commit?['sha'] is String &&
          commit!['sha'] == head
      ? [
          await _git(runner, ['rev-parse', '${commit['sha']}~1']),
          commit['sha']! as String,
        ]
      : [head];
  if (!want.contains(origin)) {
    _refuse(
      name,
      '$branch is not level with origin/$branch: $branch is $head, '
      'origin/$branch is $origin',
    );
  }
}

/// Where [tag] points, here and on origin, peeled to its commit.
Future<({String? here, String? origin})> tagAt(
  ReleaseRunner runner,
  String tag,
) async {
  final here = await runner.run('git', [
    'rev-parse',
    '-q',
    '--verify',
    'refs/tags/$tag^{commit}',
  ]);
  final remote = [
    for (final line in (await _git(runner, [
      'ls-remote',
      '--tags',
      'origin',
    ])).split('\n'))
      if (line.split('\t') case [
        final sha,
        final ref,
      ] when ref == 'refs/tags/$tag' || ref == 'refs/tags/$tag^{}')
        (sha: sha, ref: ref),
  ];
  // An annotated tag lists its object, then the commit it peels to.
  final origin =
      remote.where((entry) => entry.ref.endsWith('^{}')).firstOrNull ??
      remote.firstOrNull;
  return (
    here: here.status == 0 && said(here.stdout).isNotEmpty
        ? said(here.stdout)
        : null,
    origin: origin?.sha,
  );
}

/// A tag of the version the state did not make, or one on another commit,
/// is refused.
Future<void> _foreignTag(
  ReleaseRunner runner,
  ReleaseState state,
  String built,
) async {
  final name = state['package']! as String;
  final tag = tagName(state['version']! as String);
  final (:here, :origin) = await tagAt(runner, tag);
  final found = [?here, ?origin];
  if (found.isEmpty) return;
  if (state['tag'] == null) {
    _refuse(name, '$tag is a tag already, which this release did not make');
  }
  if (found.where((sha) => sha != built).firstOrNull case final other?) {
    _refuse(
      name,
      '$tag is on $other, not on $built, which $name ${state['version']} is '
      'built from',
    );
  }
}

/// The URL of the draft of [tag] on GitHub, or null when there is none.
Future<String?> draftAt(ReleaseRunner runner, String tag) async {
  final view = await runner.run('gh', [
    'release',
    'view',
    tag,
    '--json',
    'url',
    '--jq',
    '.url',
  ]);
  return view.status == 0 ? said(view.stdout) : null;
}
