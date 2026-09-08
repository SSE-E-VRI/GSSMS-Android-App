import 'package:gssms_mobile/features/inspections/data/inspection_api_service.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';

abstract class IInspectionRepository {
  Future<List<Inspection>> fetchInspections({
    String? status,
    String? priority,
    int? zoneId,
    int? divisionId,
    int? depotId,
    String? dateFrom,
    String? dateTo,
  });
  Future<Inspection> fetchInspectionById(int id);
  Future<Inspection> createInspection({
    required String title,
    required String description,
    String priority = 'MEDIUM',
    int? assetId,
    int? stationId,
    int? infrastructureId,
    int? depotId,
    String? scheduledDate,
    List<String>? inspectionPoints,
  });
  Future<Map<String, dynamic>> convertToWorkOrder(int inspectionId);
}

class InspectionRepository implements IInspectionRepository {
  InspectionRepository(this._apiService);
  final InspectionApiService _apiService;

  @override
  Future<List<Inspection>> fetchInspections({
    String? status,
    String? priority,
    int? zoneId,
    int? divisionId,
    int? depotId,
    String? dateFrom,
    String? dateTo,
  }) {
    return _apiService.getInspections(
      status: status,
      priority: priority,
      zoneId: zoneId,
      divisionId: divisionId,
      depotId: depotId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
  }

  @override
  Future<Inspection> fetchInspectionById(int id) => _apiService.getInspection(id);

  @override
  Future<Inspection> createInspection({
    required String title,
    required String description,
    String priority = 'MEDIUM',
    int? assetId,
    int? stationId,
    int? infrastructureId,
    int? depotId,
    String? scheduledDate,
    List<String>? inspectionPoints,
  }) async {
    final payload = <String, dynamic>{
      'title': title,
      'description': description,
      'priority': priority,
      'source': 'MOBILE',
      if (assetId != null) 'asset': assetId,
      if (stationId != null) 'station': stationId,
      if (infrastructureId != null) 'infrastructure': infrastructureId,
      if (depotId != null) 'depot': depotId,
      if (scheduledDate != null) 'scheduled_date': scheduledDate,
      if (inspectionPoints != null && inspectionPoints.isNotEmpty) 'inspection_points': inspectionPoints,
    };
    return _apiService.createInspection(payload);
  }

  @override
  Future<Map<String, dynamic>> convertToWorkOrder(int inspectionId) =>
      _apiService.convertToWorkOrder(inspectionId);
}
