import 'config.dart';
import 'efforts.dart';
import 'models.dart';
import 'parameters.dart';

/// One accepted model and/or moved effort, applied in that order.
final class ModelChoice {
  const ModelChoice({this.model, this.effort});
  final AgentModel? model;
  final PendingEffort? effort;
}

/// The effort call against the options after the model's answer.
({String option, String value, String name})? effortStep(
  ModelChoice choice,
  Object? options,
) {
  final asked = choice.effort;
  final efforts = effortsFrom(options);
  if (asked == null ||
      efforts == null ||
      (choice.model == null && efforts.option != asked.option) ||
      !efforts.available.any((e) => e.id == asked.value)) {
    return null;
  }
  return (
    option: efforts.option,
    value: asked.value,
    name: optionName(options, efforts.option),
  );
}

/// Text held while the first step waits for the agent.
String pendingText(ModelChoice choice, Object? options) => choice.model != null
    ? 'Switching to ${choice.model!.name}…'
    : 'Setting ${optionName(options, choice.effort?.option ?? '')} to ${choice.effort?.name ?? ''}…';

/// The outcome of the two independent setting steps.
final class ChoiceResult {
  const ChoiceResult({
    this.model,
    this.effort = 'unmoved',
    this.option,
    this.reason,
  });
  final String? model;
  final String effort;
  final String? option;
  final String? reason;
}

/// The outcome replacing a choice's pending command note.
({String text, bool failed}) choiceNote(
  ModelChoice choice,
  ChoiceResult result,
  Object? after,
  String inUse,
) {
  final asked = choice.effort?.name ?? '';
  final model = choice.model?.name;
  final efforts = effortsFrom(after);
  String? on;
  for (final e in efforts?.available ?? <AgentEffort>[]) {
    if (e.id == efforts?.current) on = e.name;
  }
  if (result.model == 'refused') {
    return (
      text: 'Could not switch to ${model ?? ''}: ${result.reason}',
      failed: true,
    );
  }
  return switch (result.effort) {
    'unmoved' => (text: 'Switched to ${model ?? ''}', failed: false),
    'set' => (
      text: model == null
          ? '${optionName(after, efforts?.option ?? '')} set to ${on ?? asked}'
          : 'Switched to $model · ${on ?? asked} effort',
      failed: false,
    ),
    'refused' => (
      text: model == null
          ? 'Could not set ${result.option} to $asked: ${result.reason}'
          : 'Switched to $model; could not set ${result.option} to $asked: ${result.reason}',
      failed: true,
    ),
    _ => (
      text: model == null
          ? '$asked effort was not sent: $inUse no longer offers it${on == null ? '.' : '; it is on $on.'}'
          : 'Switched to $model; it offers no $asked effort${on == null ? '.' : ', it is on $on.'}',
      failed: false,
    ),
  };
}
