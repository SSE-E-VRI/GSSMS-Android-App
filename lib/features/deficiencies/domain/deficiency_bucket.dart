import 'package:gssms_mobile/features/deficiencies/domain/models/deficiency.dart';

/// Lifecycle bucket a pending deficiency falls into (web utils/deficiencyBucket.js).
///
/// Rules:
/// - RESOLVED -> awaitingClosure
/// - active_remedial_work_order present OR status IN_PROGRESS -> inProgress
/// - otherwise -> needsAction
enum PendingBucket {
  needsAction('Needs action'),
  inProgress('In progress'),
  awaitingClosure('Awaiting closure');

  const PendingBucket(this.label);
  final String label;
}

/// Web utils/deficiencyBucket.js.
PendingBucket deficiencyBucket(Deficiency d) {
  if (d.status == DeficiencyStatus.resolved) return PendingBucket.awaitingClosure;
  if (d.hasActiveRemedial || d.status == DeficiencyStatus.inProgress) {
    return PendingBucket.inProgress;
  }
  return PendingBucket.needsAction;
}
