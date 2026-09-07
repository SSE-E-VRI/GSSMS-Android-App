import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/domain/models/maintenance_register_entry.dart';

sealed class ReportsState extends Equatable {
  const ReportsState();

  @override
  List<Object?> get props => [];
}

class ReportsLoading extends ReportsState {
  const ReportsLoading();
}

class ReportsLoaded extends ReportsState {
  const ReportsLoaded({
    required this.entries,
    required this.startDate,
    required this.endDate,
    this.infraType = InfraFilterType.all,
    this.infraId,
    this.infraOptions = const [],
    this.orgScope = OrgScopeSelection.empty,
  });

  final List<MaintenanceRegisterEntry> entries;
  final DateTime startDate;
  final DateTime endDate;
  final InfraFilterType infraType;
  final int? infraId;
  final List<InfrastructureOption> infraOptions;

  /// Depot/Station selection from the org-scope bar. Only `depotId`/
  /// `stationId` are ever populated — the bar is used with
  /// `enableZoneDivision: false` here since `register_report` has no
  /// zone/division filter param.
  final OrgScopeSelection orgScope;

  ReportsLoaded copyWith({
    List<MaintenanceRegisterEntry>? entries,
    DateTime? startDate,
    DateTime? endDate,
    InfraFilterType? infraType,
    int? infraId,
    bool clearInfraId = false,
    List<InfrastructureOption>? infraOptions,
    OrgScopeSelection? orgScope,
  }) {
    return ReportsLoaded(
      entries: entries ?? this.entries,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      infraType: infraType ?? this.infraType,
      infraId: clearInfraId ? null : (infraId ?? this.infraId),
      infraOptions: infraOptions ?? this.infraOptions,
      orgScope: orgScope ?? this.orgScope,
    );
  }

  @override
  List<Object?> get props =>
      [entries, startDate, endDate, infraType, infraId, infraOptions, orgScope];
}

class ReportsError extends ReportsState {
  const ReportsError(this.message, {this.previousLoaded});

  final String message;

  /// Carries the last successfully loaded filters through the error so a
  /// retry/filter change issued from here doesn't silently reset them.
  final ReportsLoaded? previousLoaded;

  @override
  List<Object?> get props => [message, previousLoaded];
}
