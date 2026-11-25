/// Eligibility guards before authentication or release work, as the
/// original's `scripts/dev/release/preflight.ts` with `pins.ts`, lib.ts'
/// `published` and source.ts' `ghReady`: a clean tree, a new version only
/// once pubspec.yaml's is published under the main npm name, none of the
/// npm names at the version, every agent chord pins on npm; publishing also
/// requires the version's branch, main or its channel's, level with
/// origin, no tag of its form, and `gh` signed in for the draft. Registry
/// reads and the fetch may use the network, but these guards do not log in.
library;

import 'dart:io';

import 'package:chord/channel.dart';
import 'package:chord/chorded.dart';
import 'package:chord/distribution.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../targets.dart';
import 'continue.dart';
import 'runner.dart';

/// The npm names, in the order they are published: the platform packages,
/// then the main one, whose exact-version optional dependencies must
/// resolve.
final npmNames = [for (final target in targets) target.package, npmPackage];

/// The version pubspec.yaml holds in the tree at [root].
String packageVersion(String root) {
  final file = File(p.join(root, manifestPath));
  final Object? version;
  try {
    version = (loadYaml(file.readAsStringSync()) as Map?)?['version'];
  } on Object {
    die('$manifestPath has no version');
  }
  if (version is! String || version.isEmpty) {
    die('$manifestPath has no version');
  }
  return version;
}

/// Whether [name] has [version] on npm: yes, no (a 404, or the package
/// without that version), or a failure to ask, which stops the release.
Future<bool> published(
  ReleaseRunner runner,
  String name,
  String version,
) async {
  // Only stdout is the answer; npm's warnings go to stderr.
  final view = await runner.run('npm', ['view', '$name@$version', 'version']);
  if (view.status == 0) {
    final answer = said(view.stdout);
    if (answer == version) return true;
    if (answer.isEmpty) return false;
    die('npm view $name@$version answered "$answer"');
  }
  if (view.stderr.contains('code E404')) return false;
  die('npm view $name@$version failed: ${said(view.stderr)}');
}

/// Stops on the first agent chord pins that npm does not have at its
/// version, as a person's `npx` fetches it from there.
Future<void> pinsOnNpm(
  ReleaseRunner runner, {
  List<({String package, String version})>? agents,
}) async {
  for (final (:package, :version)
      in agents ??
          [
            for (final agent in chordedAgents)
              (package: agent.package, version: agent.version),
          ]) {
    final viewed = await runner.run('npm', [
      'view',
      '$package@$version',
      'version',
    ]);
    if (viewed.status != 0 || said(viewed.stdout) != version) {
      die(
        'npm has no $package@$version, which lib/chorded.dart pins: release '
        '$package first, or pin a version npm has',
      );
    }
  }
}

/// The guards, answering the version clear to release: [version] when
/// given (before it is written), else pubspec.yaml's. [publish] is whether
/// the run's stages include publish.
Future<String> preflight(
  ReleaseRunner runner,
  String root, {
  required bool publish,
  String? version,
  Map<String, String> env = const {},
}) async {
  // 1. The tree, untracked files included.
  final status = await runner.run('git', [
    'status',
    '--porcelain',
    '--untracked-files=all',
  ]);
  if (status.status != 0) die('git status failed: ${said(status.stderr)}');
  final dirty = said(status.stdout);
  if (dirty.isNotEmpty) die('the tree is not clean:\n$dirty');

  // 2. A new version, refused while pubspec.yaml's never reached npm: a
  // stopped release is finished, not bumped past.
  final current = packageVersion(root);
  final wanted = version ?? current;
  if (wanted != current && !await published(runner, npmPackage, current)) {
    die(
      '$npmPackage@$current is not published yet; '
      '`dart run tool/release.dart chord` without --bump '
      'finishes it',
    );
  }

  // 3. The version, refused if the main package has it.
  if (await published(runner, npmPackage, wanted)) {
    die('$npmPackage@$wanted is on npm already');
  }
  // Any other npm name at it is a release stopped with its state lost:
  // finished by hand, never resumed by guessing.
  for (final name in npmNames.take(npmNames.length - 1)) {
    if (await published(runner, name, wanted)) {
      die('$name@$wanted is on npm already');
    }
  }

  // chord's own: every agent it pins is on npm.
  await pinsOnNpm(runner);

  if (publish) {
    await originIsRelease(runner, env: env);
    await _onBranch(runner, channelOf(wanted));
    await _notTagged(runner, tagName(wanted));
    final gh = await runner.run('gh', ['auth', 'status']);
    if (gh.status != 0) {
      die(
        '`gh auth status` failed, and publishing makes a draft GitHub '
        'release with it: ${said(gh.stderr)}',
      );
    }
  }
  return wanted;
}

/// The branch of [channel], or main for a stable version, checked out, and
/// the same commit as origin's once fetched.
Future<void> _onBranch(ReleaseRunner runner, String? channel) async {
  final wanted = channel ?? 'main';
  final branch = await runner.run('git', ['symbolic-ref', '--short', 'HEAD']);
  if (branch.status != 0 || said(branch.stdout) != wanted) {
    final head = said(branch.stdout).isNotEmpty
        ? said(branch.stdout)
        : said(branch.stderr);
    die(
      channel == null
          ? 'a release that publishes runs from main; HEAD is $head'
          : 'a release on channel $channel publishes only from branch '
                '$channel; HEAD is $head',
    );
  }
  final fetched = await runner.run('git', ['fetch', 'origin']);
  if (fetched.status != 0) {
    die('git fetch origin failed: ${said(fetched.stderr)}');
  }
  final local = await runner.run('git', ['rev-parse', wanted]);
  if (local.status != 0) {
    die('git rev-parse $wanted failed: ${said(local.stderr)}');
  }
  final head = said(local.stdout);
  final origin = await runner.run('git', ['rev-parse', 'origin/$wanted']);
  if (origin.status != 0) {
    die('git rev-parse origin/$wanted failed: ${said(origin.stderr)}');
  }
  if (said(origin.stdout) != head) {
    die(
      '$wanted is not origin/$wanted: $wanted is $head, origin/$wanted is '
      '${said(origin.stdout)}',
    );
  }
}

/// No [tag], here or on origin.
Future<void> _notTagged(ReleaseRunner runner, String tag) async {
  // A failed query names no tag, whatever it printed: a slip of the
  // original, refused here.
  final local = await runner.run('git', ['tag', '--list', tag]);
  if (local.status != 0) {
    die('git tag --list $tag failed: ${said(local.stderr)}');
  }
  if (said(local.stdout).isNotEmpty) die('$tag is a tag already');
  final remote = await runner.run('git', [
    'ls-remote',
    '--tags',
    'origin',
    'refs/tags/$tag',
  ]);
  if (remote.status != 0) {
    die('git ls-remote origin failed: ${said(remote.stderr)}');
  }
  if (said(remote.stdout).isNotEmpty) {
    die('$tag is a tag on origin already: ${said(remote.stdout)}');
  }
}

final _githubUrl = RegExp(
  r'^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)'
  r'([^/]+/[^/]+?)(?:\.git)?/?$',
);

/// The GitHub repository [url] names, `owner/name`, or null.
String? githubRepoOf(String url) => _githubUrl.firstMatch(url.trim())?[1];

/// Refuses a publish unless origin is [githubRepo] for fetch and for every
/// push URL, and gh, through [env], can reach no other repository: the tag
/// goes to origin and the draft is made in origin's repository, as the
/// original's, and the owner's releases are IKatsuba/chord's.
Future<void> originIsRelease(
  ReleaseRunner runner, {
  Map<String, String> env = const {},
}) async {
  if (env['GH_REPO'] case final repo? when repo.isNotEmpty) {
    if (githubRepoOf('https://github.com/$repo')?.toLowerCase() !=
        githubRepo.toLowerCase()) {
      die('GH_REPO is $repo; a release drafts in $githubRepo alone');
    }
  }
  if (env['GH_HOST'] case final host?
      when host.isNotEmpty && host != 'github.com') {
    die('GH_HOST is $host; a release drafts on github.com alone');
  }
  for (final (what, args) in [
    ('origin', ['remote', 'get-url', 'origin']),
    ("origin's push", ['remote', 'get-url', '--push', '--all', 'origin']),
  ]) {
    final url = await runner.run('git', args);
    if (url.status != 0) {
      die('git ${args.join(' ')} failed: ${said(url.stderr)}');
    }
    final urls = said(url.stdout).split('\n');
    for (final each in urls) {
      if (githubRepoOf(each)?.toLowerCase() != githubRepo.toLowerCase()) {
        die(
          'a release that publishes tags origin and drafts its GitHub '
          'release there, and chord is released from $githubRepo; $what is '
          '$each',
        );
      }
    }
  }
}
