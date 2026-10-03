import 'package:dio/dio.dart';
import 'package:gssms_mobile/features/inspections/data/inspection_api_service.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection_evidence_photo.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection_point.dart';

/// Structured point input for creation (web `InspectionForm` contract).
class InspectionPointInput {
  const InspectionPointInput({
    required this.observation,
    this.priority = 'MEDIUM',
    this.assetId,
    this.itemReference = '',
  });

  final String observation;
  final String priority;
  final int? assetId;
  final String itemReference;

  Map<String, dynamic> toJson() => {
        'observation': observation.trim(),
        'priority': priority.trim().isEmpty ? 'MEDIUM' : priority.trim(),
        if (assetId != null) 'asset': assetId,
        'item_reference': itemReference.trim(),
      };
}

abstract class IInspectionRepository {
  Future<List<Inspection>> fetchInspections({
    String? status,
    int? zoneId,
    int? divisionId,
    int? depotId,
    String? dateFrom,
    String? dateTo,
    bool? pendingConversion,
    String? search,
    String? inspectionNumber,
    int? assetId,
    String? excludeStatus,
  });
  Future<Inspection> fetchInspectionById(int id);
  Future<List<InspectionPoint>> fetchPointsByInspection(int inspectionId);

  /// Canonical creation payload (web `InspectionForm.submitInspection`):
  /// title, inspection_date, depot, station, infrastructure, notes (header
  /// only), points[] with observation/priority/asset/item_reference.
  Future<Inspection> createInspection({
    required String title,
    required String notes,
    required String inspectionDate,
    int? stationId,
    int? infrastructureId,
    int? depotId,
    int? assetId,
    String? generalAssetDescription,
    List<InspectionPointInput> points = const [],
  });

  Future<Map<String, dynamic>> convertToWorkOrder(int inspectionId);
  Future<Map<String, dynamic>> createJobWork({
    required int inspectionId,
    required List<int> pointIds,
    required String priority,
    int? assignedTo,
    String? scheduledDate,
    String? title,
    String? description,
  });
  Future<Inspection> closeInspection(int inspectionId);
  Future<void> deleteInspection(int inspectionId);

  Future<InspectionPoint> resolvePoint(int pointId, {required String remarks});
  Future<InspectionPoint> disposePoint(int pointId,
      {required String reason, required String remarks});
  Future<InspectionPoint> markUnresolved(int pointId,
      {required String reason, required String remarks});
  Future<InspectionPoint> approveJw2(int pointId, {String remarks = ''});
  Future<Map<String, dynamic>> escalatePoint(
    int pointId, {
    String type = 'BREAKDOWN',
    String? priority,
    String? title,
    String? description,
    String? reason,
    String? remarks,
    String? breakdownTime,
    int? assignedTo,
  });

  Future<InspectionEvidencePhoto> uploadGeneralPhoto({
    required int inspectionId,
    required MultipartFile file,
    String caption = '',
  });
  Future<InspectionEvidencePhoto> uploadPointPhoto({
    required int pointId,
    required MultipartFile file,
    String caption = '',
  });
  Future<InspectionEvidencePhoto> updatePhotoCaption({
    required int photoId,
    required String caption,
  });
  Future<void> deletePhoto(int photoId);
}

class InspectionRepository implements IInspectionRepository {
  InspectionRepository(this._apiService);
  final InspectionApiService _apiService;

  @override
  Future<List<Inspection>> fetchInspections({
    String? status,
    int? zoneId,
    int? divisionId,
    int? depotId,
    String? dateFrom,
    String? dateTo,
    bool? pendingConversion,
    String? search,
    String? inspectionNumber,
    int? assetId,
    String? excludeStatus,
  }) {
    return _apiService.getInspections(
      status: status,
      zoneId: zoneId,
      divisionId: divisionId,
      depotId: depotId,
      dateFrom: dateFrom,
      dateTo: dateTo,
      pendingConversion: pendingConversion,
      search: search,
      inspectionNumber: inspectionNumber,
      assetId: assetId,
      excludeStatus: excludeStatus,
    );
  }

  @override
  Future<Inspection> fetchInspectionById(int id) =>
      _apiService.getInspection(id);

  @override
  Future<List<InspectionPoint>> fetchPointsByInspection(int inspectionId) =>
      _apiService.getInspectionPoints(inspectionId: inspectionId);

  @override
  Future<Inspection> createInspection({
    required String title,
    required String notes,
    required String inspectionDate,
    int? stationId,
    int? infrastructureId,
    int? depotId,
    int? assetId,
    String? generalAssetDescription,
    List<InspectionPointInput> points = const [],
  }) async {
    final payload = <String, dynamic>{
      'title': title,
      'notes': notes,
      'inspection_date': inspectionDate,
      if (depotId != null) 'depot': depotId,
      if (stationId != null) 'station': stationId,
      if (infrastructureId != null) 'infrastructure': infrastructureId,
      if (assetId != null) 'asset': assetId,
      if (generalAssetDescription != null &&
          generalAssetDescription.trim().isNotEmpty)
        'general_asset_description': generalAssetDescription.trim(),
      if (points.isNotEmpty)
        'points': points.map((p) => p.toJson()).toList(),
    };
    return _apiService.createInspection(payload);
  }

  @override
  Future<Map<String, dynamic>> convertToWorkOrder(int inspectionId) =>
      _apiService.convertToWorkOrder(inspectionId);

  @override
  Future<Map<String, dynamic>> createJobWork({
    required int inspectionId,
    required List<int> pointIds,
    required String priority,
    int? assignedTo,
    String? scheduledDate,
    String? title,
    String? description,
  }) =>
      _apiService.createInspectionJobWork(
        inspectionId,
        pointIds: pointIds,
        priority: priority,
        assignedTo: assignedTo,
        scheduledDate: scheduledDate,
        title: title,
        description: description,
      );

  @override
  Future<Inspection> closeInspection(int inspectionId) =>
      _apiService.closeInspection(inspectionId);

  @override
  Future<void> deleteInspection(int inspectionId) =>
      _apiService.deleteInspection(inspectionId);

  @override
  Future<InspectionPoint> resolvePoint(int pointId,
          {required String remarks}) =>
      _apiService.resolveInspectionPoint(pointId, remarks: remarks);

  @override
  Future<InspectionPoint> disposePoint(int pointId,
          {required String reason, required String remarks}) =>
      _apiService.disposeInspectionPoint(pointId,
          reason: reason, remarks: remarks);

  @override
  Future<InspectionPoint> markUnresolved(int pointId,
          {required String reason, required String remarks}) =>
      _apiService.markUnresolvedInspectionPoint(pointId,
          reason: reason, remarks: remarks);

  @override
  Future<InspectionPoint> approveJw2(int pointId, {String remarks = ''}) =>
      _apiService.approveJw2InspectionPoint(pointId, remarks: remarks);

  @override
  Future<Map<String, dynamic>> escalatePoint(
    int pointId, {
    String type = 'BREAKDOWN',
    String? priority,
    String? title,
    String? description,
    String? reason,
    String? remarks,
    String? breakdownTime,
    int? assignedTo,
  }) =>
      _apiService.escalateInspectionPoint(
        pointId,
        type: type,
        priority: priority,
        title: title,
        description: description,
        reason: reason,
        remarks: remarks,
        breakdownTime: breakdownTime,
        assignedTo: assignedTo,
      );

  @override
  Future<InspectionEvidencePhoto> uploadGeneralPhoto({
    required int inspectionId,
    required MultipartFile file,
    String caption = '',
  }) =>
      _apiService.uploadGeneralPhoto(
          inspectionId: inspectionId, file: file, caption: caption);

  @override
  Future<InspectionEvidencePhoto> uploadPointPhoto({
    required int pointId,
    required MultipartFile file,
    String caption = '',
  }) =>
      _apiService.uploadPointPhoto(
          pointId: pointId, file: file, caption: caption);

  @override
  Future<InspectionEvidencePhoto> updatePhotoCaption({
    required int photoId,
    required String caption,
  }) =>
      _apiService.updatePhotoCaption(photoId: photoId, caption: caption);

  @override
  Future<void> deletePhoto(int photoId) => _apiService.deletePhoto(photoId);
}
