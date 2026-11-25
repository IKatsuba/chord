/// The release's last stage, as the original's `scripts/dev/release/
/// publish.ts` with lib.ts' `waitPublished` and source.ts' `draftRelease`:
/// the packed tarballs published to npm, the platform packages first, then,
/// once npm answers for each, the main one; then, once npm answers for all,
/// the built commit tagged and the tag pushed, and a draft GitHub release
/// made of it with the archives and their SHA256SUMS. Each act is recorded
/// in the release's state, so a stopped publish is finished from what it
/// recorded. Never unpublish, and never publish the draft: that is the
/// owner's. npm asks to authorise each publish in the terminal and the
/// browser, so each `npm publish` gets the terminal and is waited on.
library;

import 'dart:io';

import 'package:chord/channel.dart';
import 'package:path/path.dart' as p;

import '../targets.dart';
import 'archive.dart';
import 'continue.dart';
import 'pack.dart';
import 'preflight.dart';
import 'runner.dart';
import 'state.dart';

/// npm's arguments to publish [file] at [version]. The tag comes from the
/// version and nowhere else, as npm moves latest for a publish with no tag.
List<String> publishArguments(String version, String file) => [
  'publish',
  '--access',
  'public',
  file,
  if (channelOf(version) case final channel?) ...['--tag', channel],
];

/// The release's state as publish reads and writes it: before and after
/// every act npm, git or GitHub cannot take back.
final class Recorder {
  /// A state written now, in [root], then again at every change.
  Recorder(this.root, ReleaseState first) : _state = first {
    writeState(root, _state);
  }

  /// The repository's root.
  final String root;

  ReleaseState _state;

  /// The state as last recorded.
  ReleaseState get state => _state;

  /// Records [change] of the state, written at once.
  void record(ReleaseState Function(ReleaseState state) change) {
    _state = change(_state);
    writeState(root, _state);
  }
}

/// How many times [waitPublished] asks, and how long apart.
const waitAttempts = 60;

/// How long apart [waitPublished] asks.
const waitBetween = Duration(seconds: 15);

/// Waits until [name] answers npm view at [version]: npm can hold a package
/// it accepted in validation for minutes. Each miss is said through [err];
/// answers false when the attempts run out.
Future<bool> waitPublished(
  ReleaseRunner runner,
  String name,
  String version, {
  required Future<void> Function(Duration) sleep,
  required void Function(String line) err,
}) async {
  for (var attempt = 1; attempt <= waitAttempts; attempt++) {
    if (await published(runner, name, version)) return true;
    err(
      'release: waiting for $name@$version to answer npm view '
      '($attempt/$waitAttempts)',
    );
    if (attempt < waitAttempts) await sleep(waitBetween);
  }
  return false;
}

/// The command a person reruns to continue.
const continueCommand = 'dart run tool/release.dart chord';

/// The files the draft carries: every archive and their SHA256SUMS.
final draftFiles = [
  for (final target in targets) p.join(archivesFolder, target.archive),
  p.join(archivesFolder, sums),
];

/// Publishes what the state does not have answered, the main npm name
/// last, then tags the built commit and drafts the GitHub release in
/// origin's repository, which preflight has checked is the release's, each
/// recorded.
Future<void> publish(
  ReleaseRunner runner,
  String root, {
  required String version,
  required Recorder recorded,
  required List<String> npmNames,
  required bool tty,
  required Future<void> Function(Duration) sleep,
  required void Function(String line) out,
  required void Function(String line) err,
}) async {
  final name = recorded.state['package']! as String;
  final main = npmNames.last;
  final tag = tagName(version);
  String? npmState(String npm) =>
      ((recorded.state['npm'] as Map?) ?? const {})[npm] as String?;
  void npmRecord(String npm, String to) => recorded.record(
    (state) => {
      ...state,
      'npm': {...?(state['npm'] as Map?)?.cast<String, Object?>(), npm: to},
    },
  );

  // Before anything npm cannot take back: the archives the draft carries,
  // each as SHA256SUMS recorded it.
  if (_stateOf(recorded.state, 'draft') != 'made') {
    for (final target in targets) {
      final file = p.join(root, archivesFolder, target.archive);
      if (!File(file).existsSync()) {
        die('no $file for the draft; run pack again with --from pack');
      }
      checkSum(file);
    }
  }

  var asked = false;
  Future<void> publishOne(String npm) async {
    // One a killed run left pending: npm's answer settles it, as npm
    // refuses one version twice.
    if (npmState(npm) == 'pending' && await published(runner, npm, version)) {
      npmRecord(npm, 'answered');
    }
    if (npmState(npm) != null && npmState(npm) != 'pending') return;
    // Not started by this release, so npm having it is someone else's.
    if (npmState(npm) == null && await published(runner, npm, version)) {
      die(
        'npm has $npm@$version, which this release did not publish; '
        '${abandon(name)}',
      );
    }
    final file = p.join(root, tgzFolder, tarballName(npm, version));
    if (!File(file).existsSync()) {
      die('no $file to publish; nothing of this run is left to resume from');
    }
    checkSum(file);
    if (!asked) {
      if (!tty) {
        die(
          'npm publish asks in the terminal to authorise each publish; run '
          'this with stdin and stdout on a terminal',
        );
      }
      out(
        'npm will ask to authorise each publish: press Enter when it asks, '
        'then approve in the browser',
      );
      asked = true;
    }
    npmRecord(npm, 'pending');
    final [command, ...args] = ['npm', ...publishArguments(version, file)];
    if ((await runner.run(command, args, loud: true)).status != 0) {
      die('npm publish of $file failed');
    }
    npmRecord(npm, 'sent');
  }

  Future<bool> answered(String npm) async {
    if (npmState(npm) == 'answered') return true;
    if (!await waitPublished(runner, npm, version, sleep: sleep, err: err)) {
      return false;
    }
    npmRecord(npm, 'answered');
    return true;
  }

  final platforms = npmNames.sublist(0, npmNames.length - 1);
  for (final npm in platforms) {
    await publishOne(npm);
  }
  // The main package only once every other answers at the version: one
  // published while a platform package is still in npm's validation
  // installs with no binary.
  for (final npm in platforms) {
    if (!await answered(npm)) {
      die(
        '$npm@$version did not answer npm view in 15 minutes; $main was not '
        'published. Rerun `$continueCommand` once `npm view $npm@$version '
        'version` answers, and it resumes from there',
      );
    }
  }
  await publishOne(main);
  if (!await answered(main)) {
    die(
      '$main@$version did not answer npm view in 15 minutes; $tag was not '
      'tagged. Once `npm view $main@$version version` answers, tag it with: '
      'git tag -a $tag -m "$name v$version" ${recorded.state['built']} && '
      'git push origin $tag, or run `$continueCommand` to continue',
    );
  }
  await _tagged(runner, recorded, tag, '$name v$version');

  if (_stateOf(recorded.state, 'draft') != 'made') {
    // A draft a killed run left pending may be on GitHub already.
    var url = _stateOf(recorded.state, 'draft') == 'pending'
        ? await draftAt(runner, tag)
        : null;
    recorded.record(
      (state) => {
        ...state,
        'draft': {'state': 'pending'},
      },
    );
    if (url == null) {
      try {
        url = await draftRelease(
          runner,
          version,
          tag,
          '$name $tag',
          draftFiles,
          out: out,
        );
      } on ReleaseError catch (error) {
        die('${error.message}\nor run `$continueCommand` to continue');
      }
    }
    final made = url;
    recorded.record(
      (state) => {
        ...state,
        'draft': {'state': 'made', 'url': made},
      },
    );
  }
}

String? _stateOf(ReleaseState state, String key) =>
    (state[key] as Map?)?['state'] as String?;

/// [name] made on the state's built commit, annotated with [message], and
/// pushed to origin, each recorded.
Future<void> _tagged(
  ReleaseRunner runner,
  Recorder recorded,
  String name,
  String message,
) async {
  void tag(String to) => recorded.record(
    (state) => {
      ...state,
      'tag': {'state': to},
    },
  );
  if (_stateOf(recorded.state, 'tag') == 'pushed') return;
  final built = recorded.state['built']! as String;
  // One a killed run left pending: where the tag is settles it.
  if (_stateOf(recorded.state, 'tag') == 'pending') {
    final (:here, :origin) = await tagAt(runner, name);
    if ([here, origin].where((sha) => sha != null && sha != built).firstOrNull
        case final elsewhere?) {
      die('$name is on $elsewhere, not on $built, which the release built');
    }
    if (origin == built) {
      tag('pushed');
      return;
    }
    if (here == built) tag('made');
  }
  if (_stateOf(recorded.state, 'tag') != 'made') {
    tag('pending');
    final made = await runner.run('git', [
      'tag',
      '-a',
      name,
      '-m',
      message,
      built,
    ]);
    if (made.status != 0) {
      die('git tag -a $name failed: ${said(made.stderr)}');
    }
    tag('made');
  }
  final pushed = await runner.run('git', ['push', 'origin', name]);
  if (pushed.status != 0) {
    die('git push origin $name failed: ${said(pushed.stderr)}');
  }
  tag('pushed');
}

/// A draft GitHub release of [tag] with [files] attached, answering its
/// URL. Never more than a draft: the owner writes the notes and publishes
/// it. A channel's is marked a pre-release, so it cannot become the
/// repository's latest release. By then npm has the version and origin the
/// tag, so a failure says how to finish by hand.
Future<String> draftRelease(
  ReleaseRunner runner,
  String version,
  String tag,
  String title,
  List<String> files, {
  required void Function(String line) out,
}) async {
  final args = [
    'release',
    'create',
    tag,
    '--draft',
    if (channelOf(version) != null) '--prerelease',
    '--verify-tag',
    '--title',
    title,
    '--notes',
    '',
    ...files,
  ];
  final made = await runner.run('gh', args);
  if (made.status != 0) {
    die(
      '$tag is on npm and tagged, but its draft release failed: '
      '${said(made.stderr)}\nFinish it with: ${_quote(['gh', ...args])}',
    );
  }
  out('drafted $tag, with its archives: ${said(made.stdout)}');
  return said(made.stdout);
}

final _plain = RegExp(r'^[A-Za-z0-9_./:@=+-]+$');

/// [argv] as a POSIX shell takes it.
String _quote(List<String> argv) => argv
    .map(
      (arg) => _plain.hasMatch(arg) ? arg : "'${arg.replaceAll("'", r"'\''")}'",
    )
    .join(' ');
