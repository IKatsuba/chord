/// chord's release, run: as the original's `scripts/dev/release/stages.ts`
/// `runRelease`, its stages in order, each checked before the next, on the
/// owner's arm64 Mac, guarded as the owner decided. The last line printed
/// is the published version, printed only when everything held and the
/// version is tagged.
library;

import 'package:chord/channel.dart';
import 'package:chord/distribution.dart';

import 'authenticate.dart';
import 'bump.dart';
import 'continue.dart';
import 'lock.dart';
import 'pack.dart';
import 'preflight.dart';
import 'publish.dart';
import 'runner.dart';
import 'select.dart';
import 'stages.dart';
import 'state.dart';
import 'version.dart';

const _package = 'chord';

/// The stage names, in order, publish last.

/// Runs [stages] of chord's release with [options] at [wanted] (a version
/// or a bump of pubspec.yaml's, or pubspec.yaml's own if null), holding
/// the checkout's release lock from before any guard to the end.
Future<void> runRelease(
  Release release,
  List<String> stages,
  ReleaseOptions options, {
  String? wanted,
}) async {
  final unlock = await holdRelease(release.runner, release.root);
  try {
    await _locked(release, stages, options, wanted);
  } finally {
    await unlock();
  }
}

Future<String> _head(ReleaseRunner runner) async {
  final at = await runner.run('git', ['rev-parse', 'HEAD']);
  if (at.status != 0) die('git rev-parse HEAD failed: ${said(at.stderr)}');
  return said(at.stdout);
}

Map<String, String> _recordedOutputs(ReleaseState? state, String stage) =>
    ((((state?['stages'] as Map?)?[stage] as Map?)?['outputs'] as Map?) ??
            const {})
        .cast<String, String>();

Future<void> _readies(Release release, Iterable<Stage> stages) async {
  final seen = <Object>{};
  for (final stage in stages) {
    if (stage.ready case final ready? when seen.add(ready)) {
      await ready(release);
    }
  }
}

Future<void> _locked(
  Release release,
  List<String> stages,
  ReleaseOptions options,
  String? wanted,
) async {
  final runner = release.runner;
  bool has(String stage) => stages.contains(stage);
  final selected = release.stages.where((stage) => has(stage.name)).toList();

  // A state an earlier run left: a finished one is cleared, and the run
  // goes on without it; the run goes on from an unfinished one.
  final earlier = readState(release.root, _package);
  if (earlier != null) {
    if (!finished(earlier, npmNames, true)) {
      return _continued(release, earlier, stages, options, wanted);
    }
    release.out('$_package ${earlier['version']} is released');
    clearState(release.root, _package);
  }
  onMachine(stages, release.platform, release.stages);

  final current = packageVersion(release.root);
  final next = await _target(runner, current, wanted, options.channel);
  // The version enters what is published at compile: a run without it
  // would pack or publish what was built at pubspec.yaml's.
  if (next != current && !has('compile')) {
    die(
      "a new version needs the compile stage: $next is not pubspec.yaml's "
      '$current',
    );
  }
  final version = await preflight(
    runner,
    release.root,
    publish: has(publishStage),
    version: next,
    env: release.env,
  );
  await authenticate(runner, tty: release.tty, out: release.out);
  await _readies(release, selected);
  // What publish sends is what pack left, recorded as it runs: never bytes
  // no run recorded. Refused before the first change to the world.
  if (has(publishStage) && !has('pack')) {
    die("publish needs pack's output; pack is not done in $_package $version");
  }

  // The first change to the world: a run that publishes, or one at
  // pubspec.yaml's version, keeps a state from here; a dry run, or a run
  // without publish that makes a new version, keeps none.
  final base = await _head(runner);
  final recorded = !options.dryRun && (has(publishStage) || version == current)
      ? Recorder(release.root, {
          'format': stateFormat,
          'package': _package,
          'version': version,
          'channel': channelOf(version),
          'branch': channelOf(version) ?? 'main',
          'base': base,
          'built': base,
          'stages': <String, Object?>{},
          'npm': <String, Object?>{},
        })
      : null;

  Held? held;
  if (version != current) {
    if (recorded == null) {
      held = holdVersion(
        runner,
        await commitVersion(runner, release.root, version),
        err: release.err,
      );
    } else {
      recorded.record(
        (state) => {
          ...state,
          'versionCommit': {'state': 'pending'},
        },
      );
      await commitVersion(
        runner,
        release.root,
        version,
        committing: (files) => recorded.record(
          (state) => {
            ...state,
            'versionCommit': {'state': 'pending', 'files': files},
          },
        ),
      );
      final sha = await _head(runner);
      recorded.record(
        (state) => {
          ...state,
          'versionCommit': {'state': 'made', 'sha': sha},
          'built': sha,
        },
      );
      if (has(publishStage)) {
        await pushVersion(runner, version);
        recorded.record(
          (state) => {
            ...state,
            'versionCommit': {'state': 'pushed', 'sha': sha},
          },
        );
      }
    }
  }
  try {
    await _ran(release, selected, has(publishStage), version, recorded);
    if (options.dryRun) {
      // A channel's run shows what would publish, so a dry run from its
      // branch proves the tags before the owner's first real publish.
      if (channelOf(version) != null) {
        release.out('dry run: ran ${stages.join(', ')}');
        for (final name in npmNames) {
          release.out(
            'dry run: npm ${publishArguments(version, '$tgzFolder/${tarballName(name, version)}').join(' ')}',
          );
        }
      }
      release.out(
        has('pack')
            ? 'dry run: $npmPackage $version is packed in $tgzFolder, not '
                  'published'
            : 'dry run: $npmPackage $version, ran ${stages.join(', ')}; not '
                  'published',
      );
    }
  } finally {
    await held?.drop();
  }
}

/// [selected] in order on [version], each done stage recorded with its
/// outputs' sums (this run's kept too, for a run without a state); publish
/// last, after which the state is removed and the version printed last.
Future<void> _ran(
  Release release,
  List<Stage> selected,
  bool publishing,
  String version,
  Recorder? recorded,
) async {
  final thisRun = <String, Map<String, String>>{};
  for (final stage in selected) {
    await stage.run(
      release,
      version,
      (name) => thisRun[name] ?? _recordedOutputs(recorded?.state, name),
    );
    final sums = outputSums(release.root, stage, version);
    thisRun[stage.name] = sums;
    recorded?.record(
      (state) => {
        ...state,
        'stages': {
          ...?(state['stages'] as Map?)?.cast<String, Object?>(),
          stage.name: {
            'at': DateTime.now().toUtc().toIso8601String(),
            'outputs': sums,
          },
        },
      },
    );
  }
  if (publishing) {
    await publish(
      release.runner,
      release.root,
      version: version,
      recorded: recorded!,
      npmNames: npmNames,
      tty: release.tty,
      sleep: release.sleep,
      out: release.out,
      err: release.err,
    );
    clearState(release.root, _package);
    release.out(version);
  }
}

/// A run that goes on from [state]: what is left of it under the options,
/// past the guards, the version commit a killed run left settled, then the
/// stages left and what is left of publish.
Future<void> _continued(
  Release release,
  ReleaseState state,
  List<String> stages,
  ReleaseOptions options,
  String? wanted,
) async {
  final runner = release.runner;
  final version = state['version']! as String;
  final plan = left(state, (
    stages: _namesOf(release),
    selected: stages,
    named: options.only != null || options.from != null,
    dryRun: options.dryRun,
    bump: wanted,
    channel: options.channel,
    npm: npmNames,
    githubRelease: true,
  ), command: continueCommand);
  onMachine(plan.stages, release.platform, release.stages);
  final commit = await versionCommit(runner, state);
  final at = await _head(runner);
  // The state as the guards judge it: a pending version commit found made
  // is made, and the stages build from it.
  final settled = commit is VersionCommitMade
      ? {
          ...state,
          'versionCommit': {'state': 'made', 'sha': commit.sha},
          'built': commit.sha,
        }
      : state;
  final versionState = (settled['versionCommit'] as Map?)?['state'];
  // Nothing of the release is out yet: --from its first stage may build
  // again from HEAD, after a merge, say.
  final rebuild =
      options.from == _namesOf(release).first &&
      versionState != 'pushed' &&
      ((state['npm'] as Map?) ?? const {}).isEmpty &&
      state['tag'] == null;
  final done = ((state['stages'] as Map?) ?? const {}).keys;
  await guarded(runner, release.root, settled, (
    built: settled['built']! as String,
    building: plan.stages.isNotEmpty,
    publishing: plan.publish != null,
    kept: [
      for (final name in _namesOf(release))
        if (done.contains(name) && !plan.cleared.contains(name)) name,
    ],
    rebuild: rebuild,
  ));
  if (plan.publish != null) await originIsRelease(runner, env: release.env);
  if (plan.publish?.draft ?? false) {
    final gh = await runner.run('gh', ['auth', 'status']);
    if (gh.status != 0) {
      die(
        '`gh auth status` failed, and publishing makes a draft GitHub '
        'release with it: ${said(gh.stderr)}',
      );
    }
  }
  await pinsOnNpm(runner);
  await authenticate(runner, tty: release.tty, out: release.out);
  final selected = release.stages
      .where((stage) => plan.stages.contains(stage.name))
      .toList();
  await _readies(release, selected);

  final recorded = Recorder(release.root, state);
  if (commit is VersionCommitAtBase) {
    await commitVersion(
      runner,
      release.root,
      version,
      committing: (files) => recorded.record(
        (now) => {
          ...now,
          'versionCommit': {'state': 'pending', 'files': files},
        },
      ),
    );
  }
  if (commit is! NoVersionCommit) {
    final sha = commit is VersionCommitMade ? commit.sha : await _head(runner);
    recorded.record(
      (now) => {
        ...now,
        'versionCommit': {'state': 'made', 'sha': sha},
        'built': sha,
      },
    );
  }
  if (rebuild && at != settled['built']) {
    recorded.record((now) => {...now, 'built': at});
  }
  final made = recorded.state['versionCommit'] as Map?;
  if (plan.publish != null && made?['state'] == 'made') {
    await pushVersion(runner, version);
    recorded.record(
      (now) => {
        ...now,
        'versionCommit': {'state': 'pushed', 'sha': made!['sha']},
      },
    );
  }
  if (plan.cleared.isNotEmpty) {
    recorded.record((now) => cleared(now, plan.cleared));
  }
  await _ran(release, selected, plan.publish != null, version, recorded);
}

/// The version [wanted] makes of [current], or the release dies saying
/// why. Its channel is asked here too, so a label no channel can have, in a
/// pubspec.yaml edited by hand, stops before the guards that follow it.
Future<String> _target(
  ReleaseRunner runner,
  String current,
  String? wanted,
  String? channel,
) async {
  // npm's latest stable is asked only for a bump on a channel.
  final stable = channel != null && wanted != null && Bump.named(wanted) != null
      ? await _latestStable(runner)
      : null;
  try {
    final version = releaseVersion(
      current,
      wanted,
      channel: channel,
      stable: stable == null ? null : () => stable,
    );
    channelOf(version);
    return version;
  } on VersionError catch (error) {
    die(error.message);
  }
}

/// npm's latest stable version of the main package, which a bump on a
/// channel counts from.
Future<String> _latestStable(ReleaseRunner runner) async {
  final view = await runner.run('npm', [
    'view',
    npmPackage,
    'dist-tags.latest',
  ]);
  if (view.status != 0) {
    die('npm view $npmPackage dist-tags.latest failed: ${said(view.stderr)}');
  }
  return said(view.stdout);
}

/// The stage names of [release], in order, publish last.
List<String> _namesOf(Release release) => [
  for (final stage in release.stages) stage.name,
  publishStage,
];
