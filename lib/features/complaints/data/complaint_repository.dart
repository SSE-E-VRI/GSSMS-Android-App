import 'package:gssms_mobile/features/complaints/data/complaint_api_service.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';

abstract class IComplaintRepository {
  Future<List<Complaint>> fetchComplaints({
    String? status,
    String? severity,
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
    required String severity,
    int? assetId,
    int? stationId,
    int? depotId,
  });
}

class ComplaintRepository implements IComplaintRepository {
  ComplaintRepository(this._apiService);

  final ComplaintApiService _apiService;

  @override
  Future<List<Complaint>> fetchComplaints({
    String? status,
    String? severity,
    int? zoneId,
    int? divisionId,
    int? depotId,
    String? dateFrom,
    String? dateTo,
  }) async {
    return _apiService.getComplaints(
      status: status,
      severity: severity,
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
    required String severity,
    int? assetId,
    int? stationId,
    int? depotId,
  }) async {
    final payload = {
      'title': title,
      'description': description,
      'severity': severity,
      'source': 'MOBILE',
      if (assetId != null) 'asset': assetId,
      if (stationId != null) 'station': stationId,
      if (depotId != null) 'depot': depotId,
    };
    return _apiService.createComplaint(payload);
  }
}
