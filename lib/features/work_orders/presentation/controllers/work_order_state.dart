import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_action.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_audit.dart';

// --- Work Order List State ---
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
    this.searchQuery = '',
  });

  final List<WorkOrder> workOrders;
  final WorkOrderStatus? selectedStatusFilter;
  final String searchQuery;

  List<WorkOrder> get filteredOrders {
    var result = workOrders;
    if (selectedStatusFilter != null) {
      result = result.where((wo) => wo.status == selectedStatusFilter).toList();
    }
    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase();
      result = result.where((wo) {
        final title = wo.displayTitle.toLowerCase();
        final asset = (wo.assetName ?? '').toLowerCase();
        final station = (wo.stationName ?? '').toLowerCase();
        final idStr = wo.id.toString();
        return title.contains(q) || asset.contains(q) || station.contains(q) || idStr.contains(q);
      }).toList();
    }
    return result;
  }

  WorkOrderListLoaded copyWith({
    List<WorkOrder>? workOrders,
    WorkOrderStatus? selectedStatusFilter,
    bool clearStatusFilter = false,
    String? searchQuery,
  }) {
    return WorkOrderListLoaded(
      workOrders: workOrders ?? this.workOrders,
      selectedStatusFilter: clearStatusFilter ? null : (selectedStatusFilter ?? this.selectedStatusFilter),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  List<Object?> get props => [workOrders, selectedStatusFilter, searchQuery];
}

class WorkOrderListError extends WorkOrderListState {
  const WorkOrderListError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
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
    this.actions,
    this.audit,
  });

  final WorkOrder workOrder;
  final bool isTransitioning;
  final String? actionMessage;

  /// Transitions the server permits. Null until loaded, and left null when the
  /// lookup fails so the UI can distinguish "not known" from "none allowed".
  final WorkOrderActionSet? actions;

  /// Full status history, loaded alongside the detail.
  final WorkOrderAudit? audit;

  WorkOrderDetailLoaded copyWith({
    WorkOrder? workOrder,
    bool? isTransitioning,
    String? actionMessage,
    WorkOrderActionSet? actions,
    WorkOrderAudit? audit,
  }) {
    return WorkOrderDetailLoaded(
      workOrder: workOrder ?? this.workOrder,
      isTransitioning: isTransitioning ?? this.isTransitioning,
      actionMessage: actionMessage,
      actions: actions ?? this.actions,
      audit: audit ?? this.audit,
    );
  }

  @override
  List<Object?> get props =>
      [workOrder, isTransitioning, actionMessage, actions, audit];
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
  });

  final MaintenanceRecord record;
  final bool isSubmitting;
  final String? activeSubCategory;
  final String? successMessage;
  final String? errorMessage;

  /// Equipment groups present on this record, used as the subsystem filter.
  List<String> get subCategories {
    final categories = <String>{};
    for (final line in record.activeLines) {
      final category = line.assetCategory;
      if (category != null && category.isNotEmpty) {
        categories.add(category);
      }
    }
    return categories.toList()..sort();
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

  ChecklistLoaded copyWith({
    MaintenanceRecord? record,
    bool? isSubmitting,
    String? activeSubCategory,
    bool clearCategoryFilter = false,
    String? successMessage,
    String? errorMessage,
  }) {
    return ChecklistLoaded(
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
      ];
}

class ChecklistCompleted extends ChecklistState {
  const ChecklistCompleted();
}

class ChecklistError extends ChecklistState {
  const ChecklistError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
