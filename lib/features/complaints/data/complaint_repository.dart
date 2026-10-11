import 'package:dio/dio.dart';
import 'package:gssms_mobile/features/complaints/data/complaint_api_service.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';

abstract class IComplaintRepository {
  // Note: no `severity` filter — per SSOT §10.6 the backend Complaint API
  // has no severity field/filter to send.
  Future<List<Complaint>> fetchComplaints({
    String? status,
    String? excludeStatus,
    int? zoneId,
    int? divisionId,
    int? depotId,
    String? dateFrom,
    String? dateTo,
  });

  Future<Complaint> fetchComplaintById(int id);
  Future<Complaint> createComplaint({
    required String title,
    required String description,
    required String department,
    int? depotId,
    int? stationId,
    int? infrastructureId,
    int? assetId,
    String? generalAssetDescription,
    String? failureDate,
    String? failureTime,
    String? complainantName,
  });

  Future<Map<String, dynamic>> convertToWorkOrder(int complaintId);
  Future<Complaint> closeComplaint(
    int complaintId, {
    required String closureReason,
    required String closureRemarks,
  });
  Future<ComplaintPhoto> uploadPhoto({
    required int complaintId,
    required MultipartFile file,
  });
}

class ComplaintRepository implements IComplaintRepository {
  ComplaintRepository(this._apiService);

  final ComplaintApiService _apiService;

  @override
  Future<List<Complaint>> fetchComplaints({
    String? status,
    String? excludeStatus,
    int? zoneId,
    int? divisionId,
    int? depotId,
    String? dateFrom,
    String? dateTo,
  }) async {
    return _apiService.getComplaints(
      status: status,
      excludeStatus: excludeStatus,
      zoneId: zoneId,
      divisionId: divisionId,
      depotId: depotId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
  }

  @override
  Future<Complaint> fetchComplaintById(int id) async {
    return _apiService.getComplaint(id);
  }

  @override
  Future<Complaint> createComplaint({
    required String title,
    required String description,
    required String department,
    int? depotId,
    int? stationId,
    int? infrastructureId,
    int? assetId,
    String? generalAssetDescription,
    String? failureDate,
    String? failureTime,
    String? complainantName,
  }) async {
    final payload = {
      'title': title,
      'description': description,
      'department': department,
      if (depotId != null) 'depot': depotId,
      if (stationId != null) 'station': stationId,
      if (infrastructureId != null) 'infrastructure': infrastructureId,
      if (assetId != null) 'asset': assetId,
      if (generalAssetDescription != null &&
          generalAssetDescription.trim().isNotEmpty)
        'general_asset_description': generalAssetDescription.trim(),
      if (failureDate != null && failureDate.isNotEmpty)
        'failure_date': failureDate,
      if (failureTime != null && failureTime.isNotEmpty)
        'failure_time': failureTime,
      if (complainantName != null && complainantName.trim().isNotEmpty)
        'complainant_name': complainantName.trim(),
    };
    return _apiService.createComplaint(payload);
  }

  @override
  Future<Map<String, dynamic>> convertToWorkOrder(int complaintId) =>
      _apiService.convertToWorkOrder(complaintId);

  @override
  Future<Complaint> closeComplaint(
    int complaintId, {
    required String closureReason,
    required String closureRemarks,
  }) =>
      _apiService.closeComplaint(
        complaintId,
        closureReason: closureReason,
        closureRemarks: closureRemarks,
      );

  @override
  Future<ComplaintPhoto> uploadPhoto({
    required int complaintId,
    required MultipartFile file,
  }) =>
      _apiService.uploadPhoto(complaintId: complaintId, file: file);
}
