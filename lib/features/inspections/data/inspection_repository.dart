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

  /// Builds the canonical Inspection creation payload — per SSOT §11.1/§11.3
  /// the backend Inspection model has exactly: title, notes, inspection_date,
  /// station, infrastructure, depot (plus server-owned fields). It has no
  /// description/priority/source/asset/scheduled_date/inspection_points.
  Future<Inspection> createInspection({
    required String title,
    required String notes,
    required String inspectionDate,
    int? stationId,
    int? infrastructureId,
    int? depotId,
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
    required String notes,
    required String inspectionDate,
    int? stationId,
    int? infrastructureId,
    int? depotId,
  }) async {
    final payload = <String, dynamic>{
      'title': title,
      'notes': notes,
      'inspection_date': inspectionDate,
      if (depotId != null) 'depot': depotId,
      if (stationId != null) 'station': stationId,
      if (infrastructureId != null) 'infrastructure': infrastructureId,
    };
    return _apiService.createInspection(payload);
  }

  @override
  Future<Map<String, dynamic>> convertToWorkOrder(int inspectionId) =>
      _apiService.convertToWorkOrder(inspectionId);
}
