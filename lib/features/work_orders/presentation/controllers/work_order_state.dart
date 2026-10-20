import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_action.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_audit.dart';

// --- Work Order List State ---

/// Per-instance cache for [WorkOrderListLoaded.filteredOrders]; keeps the
/// state class const/Equatable.
final Expando<List<WorkOrder>> _filteredCache = Expando<List<WorkOrder>>();
sealed class WorkOrderListState extends Equatable {
  const WorkOrderListState();

  @override
  List<Object?> get props => [];
}

class WorkOrderListLoading extends WorkOrderListState {
  const WorkOrderListLoading();
}

class WorkOrderListLoaded extends WorkOrderListState {
  const WorkOrderListLoaded({
    required this.workOrders,
    this.selectedStatusFilter,
    this.selectedTypeFilter,
    this.searchQuery = '',
    this.dateFrom,
    this.dateTo,
    this.orgScope = OrgScopeSelection.empty,
    this.infraType = InfraFilterType.all,
    this.infraName,
  });

  final List<WorkOrder> workOrders;
  final WorkOrderStatus? selectedStatusFilter;
  // Web Job Works chips: All / Corrective / Preventive (+ Closed is a status).
  final WorkOrderType? selectedTypeFilter;
  final String searchQuery;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final OrgScopeSelection orgScope;
  // Web filter row: Infra Type + Infra Name (client-side until the API
  // offers server params — WorkOrderViewSet only takes zone/div/depot/station).
  final InfraFilterType infraType;
  final String? infraName;

  /// Distinct infra/location names present in the loaded page, for the
  /// Infra Name dropdown (mirrors web's Infra Name options without an extra
  /// API call, and works offline).
  List<String> get availableInfraNames {
    final names = <String>{};
    for (final wo in workOrders) {
      for (final n in [wo.infrastructureName, wo.stationName]) {
        if (n != null && n.trim().isNotEmpty) names.add(n.trim());
      }
    }
    return names.toList()..sort();
  }

  static bool _matchesInfraType(WorkOrder wo, InfraFilterType type) {
    if (type == InfraFilterType.all) return true;
    final raw = (wo.infrastructureType ?? '').toUpperCase();
    // Station rows often leave infrastructure_type empty and carry only a
    // station name — treat those as Station so the filter is useful.
    if (raw.isEmpty) {
      return type == InfraFilterType.station &&
          (wo.stationName?.isNotEmpty ?? false);
    }
    switch (type) {
      case InfraFilterType.station:
        return raw.contains('STATION');
      case InfraFilterType.lcGate:
        return raw.contains('LC');
      case InfraFilterType.serviceBuilding:
        return raw.contains('SERVICE') || raw.contains('SB');
      case InfraFilterType.staffQuarter:
        return raw.contains('STAFF') || raw.contains('QUARTER') || raw.contains('SQ');
      case InfraFilterType.all:
        return true;
    }
  }

  /// Filtered rows, computed once per state instance (see [_filteredCache]).
  List<WorkOrder> get filteredOrders =>
      _filteredCache[this] ??= _computeFilteredOrders();

  List<WorkOrder> _computeFilteredOrders() {
    final status = selectedStatusFilter;
    final type = selectedTypeFilter;
    final infra = infraType;
    final nameQ = infraName?.trim().toLowerCase();
    final hasName = nameQ != null && nameQ.isNotEmpty;
    final q = searchQuery.trim().toLowerCase();
    final hasQuery = q.isNotEmpty;
    return workOrders.where((wo) {
      if (status != null && wo.status != status) return false;
      if (type != null && wo.type != type) return false;
      if (infra != InfraFilterType.all && !_matchesInfraType(wo, infra)) {
        return false;
      }
      if (hasName &&
          !((wo.infrastructureName?.toLowerCase() == nameQ) ||
              (wo.stationName?.toLowerCase() == nameQ))) {
        return false;
      }
      if (hasQuery) {
        return wo.displayTitle.toLowerCase().contains(q) ||
            (wo.assetName ?? '').toLowerCase().contains(q) ||
            (wo.stationName ?? '').toLowerCase().contains(q) ||
            (wo.infrastructureName ?? '').toLowerCase().contains(q) ||
            (wo.ticketNumber ?? '').toLowerCase().contains(q) ||
            wo.id.toString().contains(q);
      }
      return true;
    }).toList(growable: false);
  }

  WorkOrderListLoaded copyWith({
    List<WorkOrder>? workOrders,
    WorkOrderStatus? selectedStatusFilter,
    bool clearStatusFilter = false,
    WorkOrderType? selectedTypeFilter,
    bool clearTypeFilter = false,
    String? searchQuery,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearDateRange = false,
    OrgScopeSelection? orgScope,
    InfraFilterType? infraType,
    String? infraName,
    bool clearInfraName = false,
  }) {
    return WorkOrderListLoaded(
      workOrders: workOrders ?? this.workOrders,
      selectedStatusFilter: clearStatusFilter ? null : (selectedStatusFilter ?? this.selectedStatusFilter),
      selectedTypeFilter: clearTypeFilter ? null : (selectedTypeFilter ?? this.selectedTypeFilter),
      searchQuery: searchQuery ?? this.searchQuery,
      dateFrom: clearDateRange ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateRange ? null : (dateTo ?? this.dateTo),
      orgScope: orgScope ?? this.orgScope,
      infraType: infraType ?? this.infraType,
      infraName: clearInfraName ? null : (infraName ?? this.infraName),
    );
  }

  @override
  List<Object?> get props => [
        workOrders,
        selectedStatusFilter,
        selectedTypeFilter,
        searchQuery,
        dateFrom,
        dateTo,
        orgScope,
        infraType,
        infraName,
      ];
}

class WorkOrderListError extends WorkOrderListState {
  const WorkOrderListError(this.message, {this.previousLoaded});

  final String message;

  /// The last successfully loaded state's filters, carried through the
  /// error so a retry or filter change issued from here doesn't silently
  /// reset date range / org scope / status filter / search back to
  /// defaults — the user never asked to clear them, the request just failed.
  final WorkOrderListLoaded? previousLoaded;

  @override
  List<Object?> get props => [message, previousLoaded];
}

// --- Work Order Detail State ---
sealed class WorkOrderDetailState extends Equatable {
  const WorkOrderDetailState();

  @override
  List<Object?> get props => [];
}

class WorkOrderDetailLoading extends WorkOrderDetailState {
  const WorkOrderDetailLoading();
}

class WorkOrderDetailLoaded extends WorkOrderDetailState {
  const WorkOrderDetailLoaded({
    required this.workOrder,
    this.isTransitioning = false,
    this.actionMessage,
    this.errorMessage,
    this.actions,
    this.audit,
  });

  final WorkOrder workOrder;
  final bool isTransitioning;
  final String? actionMessage;
  final String? errorMessage;

  /// Transitions the server permits. Null until loaded, and left null when the
  /// lookup fails so the UI can distinguish "not known" from "none allowed".
  final WorkOrderActionSet? actions;

  /// Full status history, loaded alongside the detail.
  final WorkOrderAudit? audit;

  WorkOrderDetailLoaded copyWith({
    WorkOrder? workOrder,
    bool? isTransitioning,
    String? actionMessage,
    String? errorMessage,
    WorkOrderActionSet? actions,
    WorkOrderAudit? audit,
  }) {
    return WorkOrderDetailLoaded(
      workOrder: workOrder ?? this.workOrder,
      isTransitioning: isTransitioning ?? this.isTransitioning,
      actionMessage: actionMessage,
      errorMessage: errorMessage,
      actions: actions ?? this.actions,
      audit: audit ?? this.audit,
    );
  }

  @override
  List<Object?> get props =>
      [workOrder, isTransitioning, actionMessage, errorMessage, actions, audit];
}

class WorkOrderDetailError extends WorkOrderDetailState {
  const WorkOrderDetailError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

// --- Checklist Execution State ---
sealed class ChecklistState extends Equatable {
  const ChecklistState();

  @override
  List<Object?> get props => [];
}

class ChecklistLoading extends ChecklistState {
  const ChecklistLoading();
}

class ChecklistLoaded extends ChecklistState {
  const ChecklistLoaded({
    required this.record,
    this.isSubmitting = false,
    this.activeSubCategory,
    this.successMessage,
    this.errorMessage,
    this.savingGroupKeys = const {},
  });

  final MaintenanceRecord record;
  final bool isSubmitting;
  final String? activeSubCategory;
  final String? successMessage;
  final String? errorMessage;

  /// Keys of asset groups whose check-out/un-check request is in flight.
  final Set<String> savingGroupKeys;

  /// Equipment groups present on this record, used as the subsystem filter.
  List<String> get subCategories {
    final categories = <String>{};
    for (final g in record.assetGroups) {
      if (g.categoryLabel.isNotEmpty) categories.add(g.categoryLabel);
    }
    return categories.toList()..sort();
  }

  /// Asset groups to show (checked out or not), filtered by the subsystem
  /// selection against each group's category label.
  List<ChecklistAssetGroup> get displayedGroups {
    final groups = record.assetGroups;
    if (activeSubCategory == null || activeSubCategory!.isEmpty) {
      return groups;
    }
    return groups.where((g) => g.categoryLabel == activeSubCategory).toList();
  }

  /// Lines to show: excluded lines are not part of this record's work, so they
  /// stay out of the checklist just as they do in the web register.
  List<MaintenanceRecordLine> get displayedLines {
    final lines = record.activeLines;
    if (activeSubCategory == null || activeSubCategory!.isEmpty) {
      return lines;
    }
    return lines.where((l) => l.assetCategory == activeSubCategory).toList();
  }

  /// Number of required lines that have not yet been completed.
  /// If lines explicitly specify [isRequired], only those count; otherwise all active lines count.
  int get remainingRequired {
    final explicitRequired = record.activeLines.where((l) => l.isRequired);
    if (explicitRequired.isNotEmpty) {
      return explicitRequired.where((l) => !l.isCompleted).length;
    }
    return record.activeLines.where((l) => !l.isCompleted).length;
  }

  /// Whether all required lines are completed and the record can be submitted.
  bool get canSubmit => remainingRequired == 0;

  /// The first incomplete required line in display order of [displayedGroups]
  /// or [record.assetGroups] (checked-out, non-excluded lines; reuses
  /// [record.activeLines] and the same isRequired/isCompleted rules as
  /// [remainingRequired]).
  MaintenanceRecordLine? get firstIncompleteRequiredLine {
    final active = record.activeLines;
    if (active.isEmpty) return null;
    final hasExplicit = active.any((l) => l.isRequired);
    bool isIncompleteRequired(MaintenanceRecordLine l) {
      if (l.isCompleted) return false;
      return hasExplicit ? l.isRequired : true;
    }

    // Check displayedGroups first (if user is viewing an active subsystem filter):
    for (final group in displayedGroups) {
      final legacy = group.lines.every((l) => l.checkedOut == null);
      if (!legacy && !group.checkedOut) continue;
      for (final line in group.lines) {
        if (!line.excluded && line.isCheckedOut && isIncompleteRequired(line)) {
          return line;
        }
      }
    }

    // Check across all record.assetGroups if nothing incomplete in displayedGroups:
    for (final group in record.assetGroups) {
      final legacy = group.lines.every((l) => l.checkedOut == null);
      if (!legacy && !group.checkedOut) continue;
      for (final line in group.lines) {
        if (!line.excluded && line.isCheckedOut && isIncompleteRequired(line)) {
          return line;
        }
      }
    }
    return null;
  }

  ChecklistLoaded copyWith({
    MaintenanceRecord? record,
    bool? isSubmitting,
    String? activeSubCategory,
    bool clearCategoryFilter = false,
    String? successMessage,
    String? errorMessage,
    Set<String>? savingGroupKeys,
  }) {
    return ChecklistLoaded(
      savingGroupKeys: savingGroupKeys ?? this.savingGroupKeys,
      record: record ?? this.record,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      activeSubCategory: clearCategoryFilter ? null : (activeSubCategory ?? this.activeSubCategory),
      successMessage: successMessage,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        record,
        isSubmitting,
        activeSubCategory,
        successMessage,
        errorMessage,
        savingGroupKeys,
      ];
}

class ChecklistCompleted extends ChecklistState {
  const ChecklistCompleted({this.queued = false});

  /// True when completion is only saved on this device (outbox) and has not
  /// reached the server yet — the UI must not call it "completed".
  final bool queued;

  @override
  List<Object?> get props => [queued];
}

class ChecklistError extends ChecklistState {
  const ChecklistError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
