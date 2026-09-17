import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// One item of a batch conversion (S2 §17-C5 `results[]`): either converted
/// ([workOrderId] set) or refused/skipped with a machine-readable [code]
/// (`PM_PENDING_EXISTS`, …) plus the human [error]. Complaint/inspection
/// batches stay all-or-nothing and simply never populate [itemResults].
class BatchItemResult extends Equatable {
  const BatchItemResult({
    required this.scheduleId,
    required this.converted,
    this.workOrderId,
    this.code,
    this.error,
    this.existingTicket,
  });

  final int scheduleId;
  final bool converted;
  final int? workOrderId;
  final String? code;
  final String? error;
  final String? existingTicket;

  factory BatchItemResult.fromJson(Map<String, dynamic> json) {
    return BatchItemResult(
      scheduleId: asJsonInt(json['schedule_id']) ?? -1,
      converted: asJsonBool(json['created']) ?? json['work_order_id'] != null,
      workOrderId: asJsonInt(json['work_order_id']),
      code: asJsonString(json['code']),
      error: asJsonString(json['error']),
      existingTicket: asJsonString(json['existing_ticket']),
    );
  }

  @override
  List<Object?> get props =>
      [scheduleId, converted, workOrderId, code, error, existingTicket];
}

/// Response shape shared by the three batch-conversion endpoints
/// (`create_from_complaints`, `create_from_inspections`,
/// `create_batch_work_orders`) — all all-or-nothing per SSOT §12's
/// conversion contract, so a 2xx response always means every requested id
/// converted.
///
/// S2 exception: the schedules batch (`create_batch_work_orders`) is per-item
/// (§17-C5) and additionally returns `results[]`, parsed into [itemResults];
/// a 2xx there means "processed", and callers must read the items to tell
/// converted from refused.
class BatchConvertResult extends Equatable {
  const BatchConvertResult(
      {this.workOrderIds = const [], this.message, this.itemResults = const []});

  final List<int> workOrderIds;
  final String? message;
  final List<BatchItemResult> itemResults;

  int get count => workOrderIds.length;

  /// Items the server refused or skipped (empty for all-or-nothing batches).
  List<BatchItemResult> get failures =>
      itemResults.where((item) => !item.converted).toList();

  factory BatchConvertResult.fromJson(Map<String, dynamic> json) {
    final rawIds = json['work_order_ids'];
    final ids = rawIds is List
        ? rawIds.map((e) => asJsonInt(e)).whereType<int>().toList()
        : <int>[];
    final rawItems = json['results'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map<String, dynamic>>()
            .map(BatchItemResult.fromJson)
            .toList()
        : <BatchItemResult>[];
    return BatchConvertResult(
      workOrderIds: ids,
      message: asJsonString(json['message']),
      itemResults: items,
    );
  }

  @override
  List<Object?> get props => [workOrderIds, message, itemResults];
}
