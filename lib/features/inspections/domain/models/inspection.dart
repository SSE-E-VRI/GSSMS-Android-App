import 'package:equatable/equatable.dart';

enum InspectionStatus {
  pending('PENDING', 'Pending'),
  inProgress('IN_PROGRESS', 'In Progress'),
  completed('COMPLETED', 'Completed'),
  converted('CONVERTED', 'Converted to Work Order'),
  cancelled('CANCELLED', 'Cancelled'),
  unknown('UNKNOWN', 'Unknown');

  const InspectionStatus(this.code, this.displayName);
  final String code;
  final String displayName;

  static InspectionStatus fromString(String? code) {
    if (code == null) return InspectionStatus.unknown;
    final upper = code.toUpperCase().trim();
    for (final s in InspectionStatus.values) {
      if (s.code == upper) return s;
    }
    return InspectionStatus.unknown;
  }
}

enum InspectionPriority {
  critical('CRITICAL', 'Critical'),
  high('HIGH', 'High'),
  medium('MEDIUM', 'Medium'),
  low('LOW', 'Low');

  const InspectionPriority(this.code, this.displayName);
  final String code;
  final String displayName;

  static InspectionPriority fromString(String? code) {
    if (code == null) return InspectionPriority.medium;
    final upper = code.toUpperCase().trim();
    for (final p in InspectionPriority.values) {
      if (p.code == upper) return p;
    }
    return InspectionPriority.medium;
  }
}

class Inspection extends Equatable {
  const Inspection({
    required this.id,
    required this.inspectionNumber,
    required this.title,
    this.description,
    this.status = InspectionStatus.pending,
    this.priority = InspectionPriority.medium,
    this.stationId,
    this.stationName,
    this.depotId,
    this.depotName,
    this.assetId,
    this.assetName,
    this.scheduledDate,
    this.completedDate,
    this.createdAt,
    this.reportedByName,
  });

  final int id;
  final String inspectionNumber;
  final String title;
  final String? description;
  final InspectionStatus status;
  final InspectionPriority priority;
  final int? stationId;
  final String? stationName;
  final int? depotId;
  final String? depotName;
  final int? assetId;
  final String? assetName;
  final DateTime? scheduledDate;
  final DateTime? completedDate;
  final DateTime? createdAt;
  final String? reportedByName;

  factory Inspection.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic d) {
      if (d == null || d == '') return null;
      return DateTime.tryParse(d.toString());
    }

    return Inspection(
      id: json['id'] as int? ?? 0,
      inspectionNumber: json['inspection_number'] as String? ??
          json['ticket_number'] as String? ??
          'INSP-${json['id']}',
      title: json['title'] as String? ?? 'Untitled Inspection',
      description: json['description'] as String?,
      status: InspectionStatus.fromString(json['status'] as String?),
      priority: InspectionPriority.fromString(json['priority'] as String? ?? json['severity'] as String?),
      stationId: json['station'] as int?,
      stationName: json['station_name'] as String?,
      depotId: json['depot'] as int?,
      depotName: json['depot_name'] as String?,
      assetId: json['asset'] as int?,
      assetName: json['asset_name'] as String?,
      scheduledDate: parseDate(json['scheduled_date']),
      completedDate: parseDate(json['completed_date'] ?? json['resolved_at']),
      createdAt: parseDate(json['created_at']),
      reportedByName: json['reported_by_name'] as String? ?? json['created_by_name'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        inspectionNumber,
        title,
        description,
        status,
        priority,
        stationId,
        stationName,
        depotId,
        depotName,
        assetId,
        assetName,
        scheduledDate,
        completedDate,
        createdAt,
        reportedByName,
      ];
}
