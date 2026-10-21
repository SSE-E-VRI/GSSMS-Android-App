import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// One entry in [BatchConvertResult.results] — the ticket number (and
/// eventually other fields) for a single created Job Work.
class BatchConvertResultItem extends Equatable {
  const BatchConvertResultItem({this.ticketNumber});
  final String? ticketNumber;

  factory BatchConvertResultItem.fromJson(Map<String, dynamic> json) {
    return BatchConvertResultItem(
      ticketNumber: asJsonString(json['ticket_number']),
    );
  }

  @override
  List<Object?> get props => [ticketNumber];
}

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

/// Response shape shared by the batch-conversion endpoints
/// (create_from_complaints, create_from_inspections,
/// create_batch_work_orders, create_rectification).
class BatchConvertResult extends Equatable {
  const BatchConvertResult({
    this.workOrderIds = const [],
    this.results = const [],
    this.itemResults = const [],
    this.message,
  });

  final List<int> workOrderIds;

  /// Per-Job-Work detail objects from the server (contains ticket_number).
  final List<BatchConvertResultItem> results;

  final String? message;
  final List<BatchItemResult> itemResults;
  List<BatchItemResult> get failures =>
      itemResults.where((item) => !item.converted).toList();

  int get count => workOrderIds.length;

  /// Ticket numbers extracted from results, filtered to non-empty strings.
  List<String> get tickets =>
      results.map((r) => r.ticketNumber).whereType<String>().toList();

  factory BatchConvertResult.fromJson(Map<String, dynamic> json) {
    final rawIds = json['work_order_ids'];
    final ids = rawIds is List
        ? rawIds.map((e) => asJsonInt(e)).whereType<int>().toList()
        : <int>[];
    final rawResults = json['results'];
    final resultItems = rawResults is List
        ? rawResults
            .whereType<Map>()
            .map((e) =>
                BatchConvertResultItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <BatchConvertResultItem>[];
    final items = rawResults is List
        ? rawResults
            .whereType<Map>()
            .where((item) =>
                item.containsKey("schedule_id") || item.containsKey("created"))
            .map((item) =>
                BatchItemResult.fromJson(Map<String, dynamic>.from(item)))
            .toList()
        : <BatchItemResult>[];
    return BatchConvertResult(
      workOrderIds: ids,
      results: resultItems,
      itemResults: items,
      message: asJsonString(json['message']),
    );
  }

  @override
  List<Object?> get props => [workOrderIds, results, message, itemResults];
}
