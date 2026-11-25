/// Which of a package's release stages a run's options leave, as the
/// original's `scripts/dev/release/select.ts`; the bumps `--bump` takes
/// are in version.dart.
library;

/// A stage choice the parser shows with the help, as Cliffy's
/// `ValidationError`.
final class UsageError implements Exception {
  /// A refusal of the options, saying [message].
  const UsageError(this.message);

  /// What is wrong with the options.
  final String message;

  @override
  String toString() => message;
}

/// A release run's options, as parsed.
final class ReleaseOptions {
  /// The options a run was given.
  const ReleaseOptions({
    this.dryRun = false,
    this.skip,
    this.only,
    this.from,
    this.to,
    this.channel,
  });

  /// `--dry-run`: every stage but publish.
  final bool dryRun;

  /// `--skip`: stages left out.
  final List<String>? skip;

  /// `--only`: the stages run, in the release's order.
  final List<String>? only;

  /// `--from`: the first stage run.
  final String? from;

  /// `--to`: the last stage run.
  final String? to;

  /// `--channel`: the channel of a pre-release.
  final String? channel;
}

/// A package's name and its release's stage names, in order.
typedef Stages = ({String name, List<String> stages});

/// The stages of [of] the [options] leave, in the package's order. What
/// the parser cannot say of the values themselves is refused here: a stage
/// the package does not have.
List<String> selectStages(Stages of, ReleaseOptions options) {
  final named = [
    ...?options.skip,
    ...?options.only,
    ?options.from,
    ?options.to,
  ];
  for (final stage in named) {
    if (!of.stages.contains(stage)) {
      throw UsageError(
        '${of.name} has no stage "$stage"; its stages are '
        '${of.stages.join(', ')}',
      );
    }
  }
  if (options.dryRun && (options.only?.contains('publish') ?? false)) {
    throw const UsageError(
      '--dry-run stops before publish, so --only publish has nothing to run.',
    );
  }
  final from = of.stages.indexOf(options.from ?? of.stages.first);
  final to = of.stages.indexOf(options.to ?? of.stages.last);
  final stages = [
    for (final (at, stage) in of.stages.indexed)
      if ((options.only == null
              ? at >= from && at <= to
              : options.only!.contains(stage)) &&
          !(options.skip?.contains(stage) ?? false) &&
          !(options.dryRun && stage == 'publish'))
        stage,
  ];
  if (stages.isEmpty) {
    throw const UsageError('The options leave no stage to run.');
  }
  return stages;
}
