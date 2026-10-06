/// Job Work status wording for the Pending Actions chips. Mirrors the web
/// (`PENDING_ACTION_EXTRA_STATUS` in DashboardView.jsx layered over
/// `utils/jobWorkStatus.js`), so e.g. `NEW` reads "Unassigned" here exactly
/// as it does on web. Deliberately separate from `WorkOrderStatus.displayName`,
/// which other Job Work screens keep using.
const Map<String, String> _pendingActionStatusLabels = {
  // PENDING_ACTION_EXTRA_STATUS
  'NEW': 'Unassigned',
  'OPEN': 'Open',
  'ACTION_REQUIRED': 'Action Required',
  'CONVERTED': 'Converted',
  'RESOLVED': 'Resolved',
  'PARTIALLY_CONVERTED': 'Partially Converted',
  'UNDER_SUPERVISOR_REVIEW': 'Under Review',
  'REPLACEMENT_PENDING_APPROVAL': 'Replacement Pending Approval',
  'REPLACEMENT_APPROVED': 'Replacement Approved',
  // WO_STATUS_LABELS
  'ASSIGNED': 'Assigned - Not Started',
  'IN_PROGRESS': 'In Progress',
  'REWORK_REQUIRED': 'Rework Required',
  'TECH_COMPLETED': 'Pending Verification',
  'ON_HOLD': 'On Hold',
  'VERIFIED': 'Verified',
  'CLOSED': 'Closed',
  'CANCELLED': 'Cancelled',
};

/// Readable label for a Pending Actions status chip; unknown codes are
/// title-cased ("SOME_CODE" -> "Some Code"), null/blank gives ''.
String pendingActionStatusLabel(String? status) {
  final raw = status?.trim() ?? '';
  if (raw.isEmpty) return '';
  final known = _pendingActionStatusLabels[raw.toUpperCase()];
  if (known != null) return known;
  return raw
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

/// Pending Actions chip label with the linked Job Work's assignee, matching
/// the web's Action-cell wording ("In Progress (krishna)", "Assigned
/// (krishna)"). `NEW` stays "Unassigned" — a NEW Job Work has no technician
/// by definition — and a missing/blank name keeps the bare
/// [pendingActionStatusLabel] (no placeholder).
String pendingActionStatusLabelWithAssignee(
    String? status, String? assignedToName) {
  // Web shows a bare "Rework" chip for REWORK_REQUIRED (no assignee).
  if (status?.trim().toUpperCase() == 'REWORK_REQUIRED') return 'Rework';
  final name = assignedToName?.trim() ?? '';
  if (name.isEmpty) return pendingActionStatusLabel(status);
  switch (status?.trim().toUpperCase()) {
    case 'ASSIGNED':
      return 'Assigned ($name)';
    case 'IN_PROGRESS':
      return 'In Progress ($name)';
    default:
      return pendingActionStatusLabel(status);
  }
}
