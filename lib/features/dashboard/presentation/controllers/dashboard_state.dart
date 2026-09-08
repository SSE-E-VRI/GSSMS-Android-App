import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/dashboard/domain/models/dashboard_models.dart';

sealed class DashboardState extends Equatable {
  const DashboardState();

  @override
  List<Object?> get props => [];
}

class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

class DashboardLoaded extends DashboardState {
  const DashboardLoaded({
    required this.attention,
    required this.summary,
    this.orgScope = OrgScopeSelection.empty,
  });

  final AttentionSummary attention;
  final DashboardSummary summary;

  /// Only `depotId` is ever populated — the summary read model filters by
  /// depot alone, so the filter bar is rendered depot-only to keep the two
  /// cards on screen describing the same set of work.
  final OrgScopeSelection orgScope;

  DashboardLoaded copyWith({
    AttentionSummary? attention,
    DashboardSummary? summary,
    OrgScopeSelection? orgScope,
  }) {
    return DashboardLoaded(
      attention: attention ?? this.attention,
      summary: summary ?? this.summary,
      orgScope: orgScope ?? this.orgScope,
    );
  }

  @override
  List<Object?> get props => [attention, summary, orgScope];
}

class DashboardError extends DashboardState {
  const DashboardError(this.message, {this.previousLoaded});

  final String message;

  /// Last good load, kept so a failed depot change doesn't reset the filter
  /// bar the user is still looking at.
  final DashboardLoaded? previousLoaded;

  @override
  List<Object?> get props => [message, previousLoaded];
}
