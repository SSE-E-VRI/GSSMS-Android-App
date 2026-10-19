import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// Visual evidence on an inspection or point (Slice I6).
/// Mirrors `InspectionEvidencePhotoSerializer`.
class InspectionEvidencePhoto extends Equatable {
  const InspectionEvidencePhoto({
    required this.id,
    this.inspectionId,
    this.inspectionPointId,
    this.caption,
    this.imageUrl,
    this.uploadedByName,
    this.uploadedAt,
    this.isLocked = false,
    this.lockedAt,
    this.lockedByName,
  });

  final int id;
  final int? inspectionId;
  final int? inspectionPointId;
  final String? caption;
  final String? imageUrl;
  final String? uploadedByName;
  final DateTime? uploadedAt;
  final bool isLocked;
  final DateTime? lockedAt;
  final String? lockedByName;

  static int? _fkId(dynamic v) =>
      v is Map ? asJsonInt(v['id']) : asJsonInt(v);

  factory InspectionEvidencePhoto.fromJson(Map<String, dynamic> json) {
    // DRF ImageField serializes to URL string; keep raw and let Dio/auth
    // image loading resolve it (same as work-order proof handling).
    final rawImage = json['image'];
    return InspectionEvidencePhoto(
      id: asJsonInt(json['id']) ?? 0,
      inspectionId: _fkId(json['inspection']),
      inspectionPointId: _fkId(json['inspection_point']),
      caption: asJsonString(json['caption']),
      imageUrl: rawImage == null ? null : rawImage.toString(),
      uploadedByName: asJsonString(json['uploaded_by_name']) ??
          asJsonString(json['uploaded_by']),
      uploadedAt: asJsonDateTime(json['uploaded_at']),
      isLocked: asJsonBool(json['is_locked']) ?? false,
      lockedAt: asJsonDateTime(json['locked_at']),
      lockedByName: asJsonString(json['locked_by_name']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        inspectionId,
        inspectionPointId,
        caption,
        imageUrl,
        uploadedByName,
        uploadedAt,
        isLocked,
        lockedAt,
        lockedByName,
      ];
}
