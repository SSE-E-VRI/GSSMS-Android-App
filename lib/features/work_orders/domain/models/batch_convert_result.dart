import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// Response shape shared by the three batch-conversion endpoints
/// (`create_from_complaints`, `create_from_inspections`,
/// `create_batch_work_orders`) — all all-or-nothing per SSOT §12's
/// conversion contract, so a 2xx response always means every requested id
/// converted.
class BatchConvertResult extends Equatable {
  const BatchConvertResult({this.workOrderIds = const [], this.message});

  final List<int> workOrderIds;
  final String? message;

  int get count => workOrderIds.length;

  factory BatchConvertResult.fromJson(Map<String, dynamic> json) {
    final rawIds = json['work_order_ids'];
    final ids = rawIds is List
        ? rawIds.map((e) => asJsonInt(e)).whereType<int>().toList()
        : <int>[];
    return BatchConvertResult(
      workOrderIds: ids,
      message: asJsonString(json['message']),
    );
  }

  @override
  List<Object?> get props => [workOrderIds, message];
}
