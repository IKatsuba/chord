/// A permission's presentation the agent sends under
/// `_meta["chord/permission"]`: a safety review's outcome and reason, which
/// the screens show beside the request and keep on its call.
library;

/// A generic agent's safety review of what a permission asks.
final class PermissionReview {
  const PermissionReview(this.outcome, this.reason);

  /// `caution`, `incomplete` or `failed`.
  final String outcome;

  /// Why, in the reviewer's words.
  final String reason;
}

/// The presentation a request carries: each field present only where it
/// was valid.
final class PermissionPresentation {
  const PermissionPresentation({this.review, this.deadlineAt});

  /// The safety review, when the agent sent a valid one.
  final PermissionReview? review;

  /// The agent's deadline for an answer, epoch milliseconds, as the agent
  /// sent the number.
  final num? deadlineAt;
}

const _outcomes = {'caution', 'incomplete', 'failed'};

/// What a request's [meta] says under `chord/permission`; invalid optional
/// fields never invent a review or a deadline.
PermissionPresentation permissionPresentation(Object? meta) {
  final value = meta is Map ? meta['chord/permission'] : null;

  if (value is! Map) {
    return const PermissionPresentation();
  }

  final review = value['review'];
  final deadline = value['deadlineAt'];

  return PermissionPresentation(
    review:
        review is Map &&
            _outcomes.contains(review['outcome']) &&
            review['reason'] is String
        ? PermissionReview(
            review['outcome'] as String,
            review['reason'] as String,
          )
        : null,
    deadlineAt: deadline is num && deadline.isFinite && deadline >= 0
        ? deadline
        : null,
  );
}
