import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:intl/intl.dart';

// ---------------------------------------------------------------------------
// Job Work report models (technician "Report Preview").
//
// Pure-Dart view models parsed from the raw JSON of the four report sources
// (checklist record, Breakdown / Inspection / Rectification execution). They
// intentionally do NOT reuse the execution-form models: those are thin and
// shaped for editing, while a report needs submission history, organization,
// verification and frozen labels. Ports of the web FormPreview,
// ComplaintExecutionPrintPreview, InspectionReportPreview and
// RectificationReportPreview data shaping.
// ---------------------------------------------------------------------------

/// `dd MMM yyyy`, or [fallback] when [value] is null.
String formatReportDate(DateTime? value, {String fallback = 'N/A'}) =>
    value == null ? fallback : DateFormat('dd MMM yyyy').format(value);

/// `dd MMM yyyy, HH:mm`, or [fallback] when [value] is null.
String formatReportDateTime(DateTime? value, {String fallback = 'N/A'}) =>
    value == null ? fallback : DateFormat('dd MMM yyyy, HH:mm').format(value);

/// Printed PM status text: the configured option label, never a raw DB code.
/// Mirrors web `reportStatusLabel` / backend `_report_status_label`.
String reportStatusLabel({
  String? snapshot,
  String? status,
  required bool addressed,
}) {
  if (snapshot != null && snapshot.isNotEmpty) return snapshot;
  if (addressed && status == 'NA') return 'Not applicable';
  return 'Not recorded';
}

/// Ports web `formatRecordedValue`: a JSON object string (or a decoded map)
/// becomes `k: v, k2: v2` skipping null / empty values; anything else is
/// stringified. Returns '' for null / empty input.
String formatRecordedValue(dynamic value) {
  if (value == null) return '';
  dynamic parsed = value;
  if (value is String) {
    if (value.isEmpty) return '';
    if (value.startsWith('{') || value.startsWith('[')) {
      try {
        parsed = jsonDecode(value);
      } catch (_) {
        return value;
      }
    }
  }
  if (parsed is Map) {
    return parsed.entries
        .where((e) => e.value != null && e.value.toString().isNotEmpty)
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');
  }
  if (parsed is List) {
    return parsed
        .where((e) => e != null && e.toString().isNotEmpty)
        .map((e) => e.toString())
        .join(', ');
  }
  return parsed.toString();
}

Map<String, dynamic>? _map(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

List<Map<String, dynamic>> _maps(dynamic v) {
  if (v is! List) return const [];
  return [
    for (final e in v)
      if (_map(e) != null) _map(e)!,
  ];
}

String _str(dynamic v) => (asJsonString(v) ?? '').trim();

/// First non-blank string among [values], else [fallback].
String _firstText(Iterable<dynamic> values, [String fallback = '']) {
  for (final v in values) {
    final t = _str(v);
    if (t.isNotEmpty) return t;
  }
  return fallback;
}

// ---------------------------------------------------------------------------
// Shared types
// ---------------------------------------------------------------------------

class ReportOrganization extends Equatable {
  const ReportOrganization({
    this.railwayName = 'RAILWAY',
    this.divisionName = 'Division',
    this.depotName = 'Depot',
  });

  /// Already upper-cased.
  final String railwayName;
  final String divisionName;
  final String depotName;

  factory ReportOrganization.fromJson(Map<dynamic, dynamic>? json) {
    final m = _map(json);
    if (m == null) return const ReportOrganization();
    return ReportOrganization(
      railwayName: _firstText([m['railway_name']], 'Railway').toUpperCase(),
      divisionName: _firstText([m['division_name']], 'Division'),
      depotName:
          _firstText([m['depot_name'], m['register_title']], 'Depot'),
    );
  }

  @override
  List<Object?> get props => [railwayName, divisionName, depotName];
}

class ReportVerification extends Equatable {
  const ReportVerification({
    required this.verifiedByName,
    this.verifiedAt,
    this.remarks = '',
  });

  final String verifiedByName;
  final DateTime? verifiedAt;
  final String remarks;

  /// Null when `verified_by_name` is empty (Job Work not yet verified).
  static ReportVerification? fromJson(Map<dynamic, dynamic>? json) {
    final m = _map(json);
    if (m == null) return null;
    final name = _str(m['verified_by_name']);
    if (name.isEmpty) return null;
    return ReportVerification(
      verifiedByName: name,
      verifiedAt: asJsonDateTime(m['verified_at']),
      remarks: _str(m['remarks']),
    );
  }

  @override
  List<Object?> get props => [verifiedByName, verifiedAt, remarks];
}

class ReportPhoto extends Equatable {
  const ReportPhoto({
    required this.key,
    required this.url,
    this.kind = '',
    this.caption = '',
  });

  /// The photo URL, used as the key into `LoadedJobWorkReport.photos`.
  final String key;
  final String url;

  /// BEFORE / DURING / AFTER (or '' when unknown).
  final String kind;
  final String caption;

  factory ReportPhoto.fromJson(Map<dynamic, dynamic> json) {
    final m = _map(json) ?? const <String, dynamic>{};
    final url = _firstText([m['image'], m['url']]);
    return ReportPhoto(
      key: url,
      url: url,
      kind: _firstText([m['kind'], m['photo_type']]).toUpperCase(),
      caption: _str(m['caption']),
    );
  }

  /// Parses a JSON list of photo objects, dropping entries without a URL.
  static List<ReportPhoto> listOf(dynamic json) {
    final out = <ReportPhoto>[];
    for (final m in _maps(json)) {
      final photo = ReportPhoto.fromJson(m);
      if (photo.url.isNotEmpty) out.add(photo);
    }
    return out;
  }

  @override
  List<Object?> get props => [key, url, kind, caption];
}

class ReportParameter extends Equatable {
  const ReportParameter({
    required this.parameter,
    required this.value,
    this.unit = '',
  });

  final String parameter;
  final String value;
  final String unit;

  static List<ReportParameter> listOf(dynamic json) => [
        for (final m in _maps(json))
          ReportParameter(
            parameter: _str(m['parameter']),
            value: _str(m['value']),
            unit: _str(m['unit']),
          ),
      ];

  @override
  List<Object?> get props => [parameter, value, unit];
}

class ReportSubmission extends Equatable {
  const ReportSubmission({
    required this.number,
    this.timestamp,
    this.submittedByName = '',
  });

  /// Submission number as text (`submission_no`).
  final String number;
  final DateTime? timestamp;
  final String submittedByName;

  @override
  List<Object?> get props => [number, timestamp, submittedByName];
}

/// A report plus the downscaled bytes of its photos (null = fetch failed).
class LoadedJobWorkReport {
  const LoadedJobWorkReport({required this.report, required this.photos});

  final JobWorkReport report;

  /// Keyed by [ReportPhoto.key].
  final Map<String, Uint8List?> photos;
}

sealed class JobWorkReport extends Equatable {
  const JobWorkReport();

  /// Job Work ticket number (falls back to the Job Work reference).
  String get ticket;
  ReportOrganization get org;

  /// Every photo that appears in the rendered report (de-duplicated by key,
  /// in render order). Drives photo preloading.
  List<ReportPhoto> get allPhotos;

  /// Report title as printed (e.g. "Breakdown Job Work Report").
  String get title;

  /// Location line (station / depot).
  String get location;

  /// Pre-formatted date line.
  String get dateLabel;

  ReportVerification? get verification;
}

List<ReportPhoto> _dedupe(Iterable<ReportPhoto> photos) {
  final seen = <String>{};
  return [
    for (final p in photos)
      if (p.url.isNotEmpty && seen.add(p.key)) p,
  ];
}

// ---------------------------------------------------------------------------
// Checklist (Preventive Maintenance)
// ---------------------------------------------------------------------------

class ChecklistReportRow extends Equatable {
  const ChecklistReportRow({
    required this.itemName,
    required this.checkpoint,
    required this.isRecordParameter,
    required this.statusLabel,
    required this.actionLabel,
    required this.formattedValue,
    required this.unit,
    required this.attachments,
    this.itemSpanLen = 1,
    this.paramSpanLen = 0,
  });

  final String itemName;
  final String checkpoint;
  final bool isRecordParameter;
  final String statusLabel;

  /// Frozen action label; '' when none (render as '-').
  final String actionLabel;

  /// Formatted recorded value; '' when none (render as '——' / '--').
  final String formattedValue;
  final String unit;
  final List<ReportPhoto> attachments;

  /// >0 on the first row of a run of the same `item_name` (row span of the
  /// Asset/Equipment cell); 0 on the continuation rows.
  final int itemSpanLen;

  /// >0 on the first row of a run of consecutive RECORD_PARAMETER rows (row
  /// span of the merged "Record Parameters" cell); 0 elsewhere.
  final int paramSpanLen;

  bool get itemSpanStart => itemSpanLen > 0;
  bool get paramSpanStart => paramSpanLen > 0;

  /// '-' when no action label.
  String get actionDisplay => actionLabel.isEmpty ? '-' : actionLabel;

  /// True when there is a real recorded value to show.
  bool get hasValue => formattedValue.isNotEmpty && formattedValue != '-';

  ChecklistReportRow _withSpans(int item, int param) => ChecklistReportRow(
        itemName: itemName,
        checkpoint: checkpoint,
        isRecordParameter: isRecordParameter,
        statusLabel: statusLabel,
        actionLabel: actionLabel,
        formattedValue: formattedValue,
        unit: unit,
        attachments: attachments,
        itemSpanLen: item,
        paramSpanLen: param,
      );

  @override
  List<Object?> get props => [
        itemName,
        checkpoint,
        isRecordParameter,
        statusLabel,
        actionLabel,
        formattedValue,
        unit,
        attachments,
        itemSpanLen,
        paramSpanLen,
      ];
}

class ChecklistReportGroup extends Equatable {
  const ChecklistReportGroup({required this.name, required this.rows});

  final String name;
  final List<ChecklistReportRow> rows;

  @override
  List<Object?> get props => [name, rows];
}

class ChecklistDeficiencyRow extends Equatable {
  const ChecklistDeficiencyRow({
    required this.asset,
    required this.checkpoint,
    required this.finding,
    required this.action,
    required this.severity,
  });

  final String asset;
  final String checkpoint;
  final String finding;
  final String action;
  final String severity;

  @override
  List<Object?> get props => [asset, checkpoint, finding, action, severity];
}

class ChecklistJobWorkReport extends JobWorkReport {
  const ChecklistJobWorkReport({
    required this.ticket,
    required this.org,
    required this.station,
    required this.date,
    required this.schedule,
    required this.technician,
    required this.verification,
    required this.remarks,
    required this.otherStaff,
    required this.groups,
    required this.deficiencies,
  });

  /// Report for a Job Work with no checklist record ("No details available").
  factory ChecklistJobWorkReport.empty(WorkOrder wo) => ChecklistJobWorkReport(
        ticket: wo.displayReference,
        org: const ReportOrganization(),
        station: _firstText([wo.stationName, wo.depotName], 'Unknown'),
        date: wo.reportCompletedAt ?? wo.createdAt,
        schedule: wo.displayTitle,
        technician: _firstText([wo.assignedToName], 'Unknown'),
        verification: null,
        remarks: '',
        otherStaff: '',
        groups: const [],
        deficiencies: const [],
      );

  /// Ports web `viewJobWork` (checklist branch) + `FormPreview` shaping.
  factory ChecklistJobWorkReport.fromRecordJson(
    Map<dynamic, dynamic> record,
    WorkOrder wo,
  ) {
    final rec = _map(record) ?? const <String, dynamic>{};
    final lines = _maps(rec['lines']);

    // Same gate as ReportsView: unchecked / supervisor-excluded lines were
    // never executed and must not appear in the report.
    bool skipped(Map<String, dynamic> l) =>
        asJsonBool(l['checked_out']) == false ||
        asJsonBool(l['excluded']) == true;

    final grouped = <String, List<ChecklistReportRow>>{};
    for (final line in lines) {
      if (skipped(line)) continue;
      final key = _firstText(
          [line['asset_unique_id'], line['asset_category']], 'General Items');
      final snapshot = _str(line['status_label_snapshot']);
      final status = _str(line['status']);
      final recorded = line['recorded_value'];
      final addressed = snapshot.isNotEmpty ||
          _str(line['observation_action']).isNotEmpty ||
          (recorded != null && recorded.toString().isNotEmpty) ||
          (status.isNotEmpty && status != 'OK');
      (grouped[key] ??= []).add(ChecklistReportRow(
        itemName: _str(line['item_name']),
        checkpoint: _str(line['inspection_point']),
        isRecordParameter: _str(line['item_kind']) == 'RECORD_PARAMETER',
        statusLabel: reportStatusLabel(
          snapshot: snapshot,
          status: status.isEmpty ? null : status,
          addressed: addressed,
        ),
        actionLabel: _str(line['action_label_snapshot']),
        formattedValue: formatRecordedValue(recorded),
        unit: _str(line['unit_snapshot']),
        attachments: ReportPhoto.listOf(line['attachments']),
      ));
    }

    final groups = <ChecklistReportGroup>[
      for (final e in grouped.entries)
        ChecklistReportGroup(name: e.key, rows: _withSpans(e.value)),
    ];

    final deficiencies = <ChecklistDeficiencyRow>[];
    for (final line in lines) {
      if (skipped(line)) continue;
      final statusOpt = _maps(line['status_options']).where(
          (o) => _str(o['id']) == _str(line['status_option']));
      final selectedStatus = statusOpt.isEmpty ? null : statusOpt.first;
      Map<String, dynamic>? selectedAction;
      if (selectedStatus != null) {
        final acts = _maps(selectedStatus['action_options']).where(
            (o) => _str(o['id']) == _str(line['action_option']));
        selectedAction = acts.isEmpty ? null : acts.first;
      }
      final flagged = asJsonBool(selectedStatus?['is_deficiency']) == true ||
          asJsonBool(selectedAction?['is_deficiency']) == true;
      if (!flagged) continue;
      deficiencies.add(ChecklistDeficiencyRow(
        asset: _firstText([
          line['asset_unique_id'],
          line['item_name'],
          line['asset_category'],
        ], 'General'),
        checkpoint: _str(line['inspection_point']),
        finding: _firstText(
            [selectedStatus?['label'], line['status_label_snapshot']], '-'),
        action: _firstText(
            [selectedAction?['label'], line['action_label_snapshot']], '-'),
        severity: _firstText(
            [line['deficiency_severity_label']], 'Pending review'),
      ));
    }

    final sched = _map(rec['schedule_details']);
    return ChecklistJobWorkReport(
      ticket: wo.displayReference,
      org: ReportOrganization.fromJson(_map(sched?['organization'])),
      station: _firstText(
          [sched?['station_name'], wo.stationName, wo.depotName], 'Unknown'),
      date: asJsonDateTime(rec['date_of_maintenance']) ??
          wo.reportCompletedAt ??
          wo.createdAt,
      schedule: sched != null
          ? _firstText([sched['template_name']], 'Scheduled Maintenance')
          : wo.displayTitle,
      technician:
          _firstText([rec['technician_name'], wo.assignedToName], 'Unknown'),
      verification: ReportVerification.fromJson(_map(rec['verification'])),
      remarks: _str(rec['remarks']),
      otherStaff: _str(rec['other_staff']),
      groups: groups,
      deficiencies: deficiencies,
    );
  }

  static List<ChecklistReportRow> _withSpans(List<ChecklistReportRow> rows) {
    final itemLen = List<int>.filled(rows.length, 0);
    final paramLen = List<int>.filled(rows.length, 0);
    String? currentItem;
    int itemStart = -1;
    int paramStart = -1;
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (itemStart < 0 || r.itemName != currentItem) {
        currentItem = r.itemName;
        itemStart = i;
        itemLen[i] = 1;
      } else {
        itemLen[itemStart]++;
      }
      if (r.isRecordParameter) {
        if (paramStart < 0) {
          paramStart = i;
          paramLen[i] = 1;
        } else {
          paramLen[paramStart]++;
        }
      } else {
        paramStart = -1;
      }
    }
    return [
      for (var i = 0; i < rows.length; i++)
        rows[i]._withSpans(itemLen[i], paramLen[i]),
    ];
  }

  @override
  final String ticket;
  @override
  final ReportOrganization org;
  final String station;
  final DateTime? date;
  final String schedule;
  final String technician;
  @override
  final ReportVerification? verification;
  final String remarks;
  final String otherStaff;
  final List<ChecklistReportGroup> groups;
  final List<ChecklistDeficiencyRow> deficiencies;

  /// True when there is nothing to show ("No details available.").
  bool get isEmpty => groups.isEmpty;

  @override
  String get title => 'Preventive Maintenance Report';
  @override
  String get location => station;
  @override
  String get dateLabel => formatReportDate(date);

  @override
  List<ReportPhoto> get allPhotos => _dedupe([
        for (final g in groups)
          for (final r in g.rows) ...r.attachments,
      ]);

  @override
  List<Object?> get props => [
        ticket,
        org,
        station,
        date,
        schedule,
        technician,
        verification,
        remarks,
        otherStaff,
        groups,
        deficiencies,
      ];
}

// ---------------------------------------------------------------------------
// Breakdown (complaint)
// ---------------------------------------------------------------------------

enum ComplaintSection1Kind { deficiency, complaint, jobWork }

class ReportDeficiencyDetails extends Equatable {
  const ReportDeficiencyDetails({
    required this.sourceTicket,
    required this.severity,
    required this.targetDate,
    required this.equipment,
    required this.checkpoint,
    required this.finding,
  });

  /// Each field is 'N/A' when blank, except [finding] ('' when blank).
  final String sourceTicket;
  final String severity;
  final String targetDate;
  final String equipment;
  final String checkpoint;
  final String finding;

  @override
  List<Object?> get props =>
      [sourceTicket, severity, targetDate, equipment, checkpoint, finding];
}

class ReportComplaintDetails extends Equatable {
  const ReportComplaintDetails({
    required this.complaintNumber,
    required this.failureDateTime,
    required this.complainant,
    required this.reportedAsset,
    required this.description,
  });

  /// 'N/A' when blank.
  final String complaintNumber;

  /// Pre-formatted failure date (+ time); 'N/A' when unknown.
  final String failureDateTime;
  final String complainant;
  final String reportedAsset;

  /// '' when blank.
  final String description;

  @override
  List<Object?> get props => [
        complaintNumber,
        failureDateTime,
        complainant,
        reportedAsset,
        description
      ];
}

String _naIfBlank(dynamic v) => _firstText([v], 'N/A');

/// `dd MMM yyyy[, HH:mm]` from a date value and an optional `HH:mm[:ss]`.
String _dateWithTime(dynamic date, dynamic time) {
  final d = asJsonDateTime(date);
  if (d == null) return 'N/A';
  final t = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(_str(time));
  final text = formatReportDate(d);
  // A date-only value is local midnight; only append an explicit clock time.
  if (t != null && _str(date).length <= 10) {
    return '$text, ${t.group(1)!.padLeft(2, '0')}:${t.group(2)}';
  }
  return _str(date).length > 10 ? formatReportDateTime(d) : text;
}

class ComplaintJobWorkReport extends JobWorkReport {
  const ComplaintJobWorkReport({
    required this.ticket,
    required this.org,
    required this.station,
    required this.reportDate,
    required this.submitter,
    required this.submission,
    required this.verification,
    required this.initialFindings,
    required this.actionTaken,
    required this.finalRemarks,
    required this.parameters,
    required this.beforePhotos,
    required this.afterPhotos,
    required this.section1Kind,
    required this.deficiencyDetails,
    required this.complaintDetails,
    required this.assetName,
    required this.workTitle,
    required this.workDescription,
  });

  /// Ports `ComplaintExecutionPrintPreview` shaping. [exec] is the
  /// `complaint-execution/` GET body; [woJson] the Job Work detail body
  /// (carries `original_complaint_details` / `original_deficiency_details`).
  factory ComplaintJobWorkReport.fromJson(
    Map<dynamic, dynamic> exec,
    Map<dynamic, dynamic> woJson, {
    String? fallbackTicket,
  }) {
    final e = _map(exec) ?? const <String, dynamic>{};
    final w = _map(woJson) ?? const <String, dynamic>{};
    final history = _maps(e['submission_history']);
    final src = history.isNotEmpty ? history.last : e;
    final photos = ReportPhoto.listOf(src['photos']);

    final defRaw = _map(w['original_deficiency_details']);
    final compRaw = _map(w['original_complaint_details']);

    final station = _firstText(
        [w['station_name'], w['depot_name']], 'N/A');

    ReportDeficiencyDetails? defDetails;
    if (defRaw != null && defRaw.isNotEmpty) {
      defDetails = ReportDeficiencyDetails(
        sourceTicket: _naIfBlank(defRaw['source_ticket']),
        severity: _naIfBlank(defRaw['severity']),
        targetDate: _naIfBlank(defRaw['target_date']),
        equipment: _naIfBlank(defRaw['equipment']),
        checkpoint: _naIfBlank(defRaw['checkpoint']),
        finding: _str(defRaw['finding']),
      );
    }
    ReportComplaintDetails? compDetails;
    if (compRaw != null && compRaw.isNotEmpty) {
      compDetails = ReportComplaintDetails(
        complaintNumber: _naIfBlank(compRaw['complaint_number']),
        failureDateTime: _str(compRaw['failure_date']).isEmpty
            ? 'N/A'
            : _dateWithTime(compRaw['failure_date'], compRaw['failure_time']),
        complainant: _naIfBlank(compRaw['complainant_name']),
        reportedAsset: _firstText([
          compRaw['asset_name'],
          compRaw['general_asset_description'],
          w['asset_name'],
        ], 'Location Issue'),
        description:
            _firstText([compRaw['description'], w['description']]),
      );
    }

    final submissionNo = _str(src['submission_no']);
    return ComplaintJobWorkReport(
      ticket: _firstText([w['ticket_number']], fallbackTicket ?? ''),
      org: ReportOrganization.fromJson(_map(e['organization'])),
      station: station,
      reportDate: asJsonDateTime(src['timestamp']) ??
          asJsonDateTime(src['updated_at']) ??
          asJsonDateTime(w['updated_at']),
      submitter: _firstText([
        src['submitted_by_name'],
        src['submitted_by'],
        e['updated_by_name'],
        w['assigned_to_name'],
      ], 'N/A'),
      submission: submissionNo.isEmpty
          ? null
          : ReportSubmission(
              number: submissionNo,
              timestamp: asJsonDateTime(src['timestamp']),
            ),
      verification: ReportVerification.fromJson(_map(e['verification'])),
      initialFindings: _str(src['initial_findings']),
      actionTaken: _str(src['action_taken']),
      finalRemarks: _str(src['final_remarks']),
      parameters: ReportParameter.listOf(src['parameters']),
      beforePhotos: [for (final p in photos) if (p.kind == 'BEFORE') p],
      afterPhotos: [for (final p in photos) if (p.kind == 'AFTER') p],
      section1Kind: defDetails != null
          ? ComplaintSection1Kind.deficiency
          : compDetails != null
              ? ComplaintSection1Kind.complaint
              : ComplaintSection1Kind.jobWork,
      deficiencyDetails: defDetails,
      complaintDetails: compDetails,
      assetName: _firstText([w['asset_name']], 'General'),
      workTitle: _str(w['title']),
      workDescription: _str(w['description']),
    );
  }

  @override
  final String ticket;
  @override
  final ReportOrganization org;
  final String station;
  final DateTime? reportDate;
  final String submitter;
  final ReportSubmission? submission;
  @override
  final ReportVerification? verification;
  final String initialFindings;
  final String actionTaken;
  final String finalRemarks;
  final List<ReportParameter> parameters;
  final List<ReportPhoto> beforePhotos;
  final List<ReportPhoto> afterPhotos;
  final ComplaintSection1Kind section1Kind;
  final ReportDeficiencyDetails? deficiencyDetails;
  final ReportComplaintDetails? complaintDetails;

  /// Job Work asset ('General' when blank) for the "Job Work Details" block.
  final String assetName;
  final String workTitle;
  final String workDescription;

  /// "Work to be done" text for the "Job Work Details" block.
  String get workToBeDone =>
      [workTitle, workDescription].where((s) => s.isNotEmpty).join(' - ');

  @override
  String get title => 'Breakdown Job Work Report';
  @override
  String get location => station;
  @override
  String get dateLabel => formatReportDate(reportDate);

  @override
  List<ReportPhoto> get allPhotos =>
      _dedupe([...beforePhotos, ...afterPhotos]);

  @override
  List<Object?> get props => [
        ticket,
        org,
        station,
        reportDate,
        submitter,
        submission,
        verification,
        initialFindings,
        actionTaken,
        finalRemarks,
        parameters,
        beforePhotos,
        afterPhotos,
        section1Kind,
        deficiencyDetails,
        complaintDetails,
        assetName,
        workTitle,
        workDescription,
      ];
}

// ---------------------------------------------------------------------------
// Inspection
// ---------------------------------------------------------------------------

class InspectionReportPoint extends Equatable {
  const InspectionReportPoint({
    this.pointNumber,
    this.observation = '',
    this.assetName = '',
    this.priority = '',
    this.initialFindings = '',
    this.actionTaken = '',
    this.finalRemarks = '',
    this.correctiveActionPerformed,
    this.technicalParameters = const [],
    this.beforePhotos = const [],
    this.afterPhotos = const [],
    this.inspectionEvidencePhotos = const [],
  });

  /// Null for the legacy single-execution row.
  final int? pointNumber;
  final String observation;
  final String assetName;
  final String priority;
  final String initialFindings;
  final String actionTaken;
  final String finalRemarks;

  /// `false` = observation only, no corrective action (After photos N/A).
  final bool? correctiveActionPerformed;
  final List<ReportParameter> technicalParameters;
  final List<ReportPhoto> beforePhotos;
  final List<ReportPhoto> afterPhotos;
  final List<ReportPhoto> inspectionEvidencePhotos;

  bool get isLegacy => pointNumber == null;

  @override
  List<Object?> get props => [
        pointNumber,
        observation,
        assetName,
        priority,
        initialFindings,
        actionTaken,
        finalRemarks,
        correctiveActionPerformed,
        technicalParameters,
        beforePhotos,
        afterPhotos,
        inspectionEvidencePhotos,
      ];
}

/// One line of the legacy "Inspection Points Covered" list.
class InspectionCoveredPoint extends Equatable {
  const InspectionCoveredPoint({
    required this.number,
    required this.text,
    this.priority = '',
  });

  final int number;
  final String text;
  final String priority;

  @override
  List<Object?> get props => [number, text, priority];
}

class InspectionJobWorkReport extends JobWorkReport {
  const InspectionJobWorkReport({
    required this.ticket,
    required this.org,
    required this.station,
    required this.inspectionDate,
    required this.inspectionTime,
    required this.inspectionTitle,
    required this.inspectionNumber,
    required this.inspector,
    required this.inspectionRemarks,
    required this.generalEvidencePhotos,
    required this.coveredPoints,
    required this.points,
    required this.submission,
    required this.technician,
    required this.verification,
  });

  /// Ports `toInspectionReport` (default: latest submission).
  factory InspectionJobWorkReport.fromJson(
    Map<dynamic, dynamic> payload, {
    String fallbackTicket = '',
  }) {
    final p = _map(payload) ?? const <String, dynamic>{};
    final history = _maps(p['submission_history']);
    final sub = history.isNotEmpty ? history.last : null;
    final details = _map(p['inspection_details']) ?? const <String, dynamic>{};

    InspectionReportPoint legacy(Map<String, dynamic> src, dynamic photos) {
      final list = ReportPhoto.listOf(photos);
      return InspectionReportPoint(
        initialFindings:
            _firstText([src['initial_findings'], src['findings_summary']]),
        actionTaken: _str(src['action_taken']),
        finalRemarks:
            _firstText([src['final_remarks'], src['technician_remarks']]),
        correctiveActionPerformed:
            asJsonBool(src['corrective_action_performed']),
        technicalParameters: ReportParameter.listOf(
            src['technical_parameters'] ?? src['parameters']),
        beforePhotos: [for (final x in list) if (x.kind == 'BEFORE') x],
        afterPhotos: [for (final x in list) if (x.kind == 'AFTER') x],
      );
    }

    final List<InspectionReportPoint> points;
    if (sub != null) {
      final snaps = _maps(sub['point_snapshots']);
      points = snaps.isNotEmpty
          ? [
              for (var i = 0; i < snaps.length; i++)
                _pointFrom(snaps[i], i, snaps[i], snapshot: true),
            ]
          : [legacy(sub, sub['photos'])];
    } else if (asJsonBool(p['is_pointwise']) == true) {
      final pts = _maps(p['points']);
      points = [
        for (var i = 0; i < pts.length; i++)
          _pointFrom(
              pts[i], i, _map(pts[i]['execution']) ?? const <String, dynamic>{}),
      ];
    } else {
      points = [legacy(p, p['photos'])];
    }

    final covered = _maps(details['points']);
    return InspectionJobWorkReport(
      ticket: _firstText([p['ticket_number']], fallbackTicket),
      org: ReportOrganization.fromJson(_map(details['organization'])),
      station: _firstText(
          [details['station_name'], details['location']], '-'),
      inspectionDate: asJsonDateTime(details['inspection_date']),
      inspectionTime: _str(details['inspection_time']),
      inspectionTitle: _str(details['inspection_title']),
      inspectionNumber: _naIfBlank(details['inspection_number']),
      inspector: _naIfBlank(details['inspector_name']),
      inspectionRemarks: _firstText(
          [details['inspection_remarks'], details['original_observation']]),
      generalEvidencePhotos:
          ReportPhoto.listOf(details['general_evidence_photos']),
      coveredPoints: [
        for (var i = 0; i < covered.length; i++)
          InspectionCoveredPoint(
            number: asJsonInt(covered[i]['point_number']) ?? i + 1,
            text: _firstText(
                [covered[i]['observation'], covered[i]['description']]),
            priority: _str(covered[i]['priority']),
          ),
      ],
      points: points,
      submission: sub == null
          ? null
          : ReportSubmission(
              number: _str(sub['submission_no']),
              timestamp: asJsonDateTime(sub['timestamp']),
              submittedByName:
                  _firstText([sub['submitted_by_name'], sub['submitted_by']]),
            ),
      technician: sub == null
          ? ''
          : _firstText([sub['submitted_by_name'], sub['submitted_by']]),
      verification: ReportVerification.fromJson(_map(p['verification'])),
    );
  }

  /// A pointwise row. [meta] carries point_number / observation / ...;
  /// [exec] carries the execution fields (for submission snapshots both are
  /// the same map).
  static InspectionReportPoint _pointFrom(
    Map<String, dynamic> meta,
    int index,
    Map<String, dynamic> exec, {
    bool snapshot = false,
  }) {
    String pick(String k) => _str(exec[k]);
    final photos = ReportPhoto.listOf(exec['photos']);
    return InspectionReportPoint(
      pointNumber: asJsonInt(meta['point_number']) ?? index + 1,
      observation: _firstText([meta['observation'], meta['description']]),
      assetName: _str(meta['asset_name']),
      priority: _str(meta['priority']),
      initialFindings: pick('initial_findings'),
      actionTaken: pick('action_taken'),
      finalRemarks: pick('final_remarks'),
      correctiveActionPerformed:
          asJsonBool(exec['corrective_action_performed']),
      technicalParameters: ReportParameter.listOf(exec['technical_parameters']),
      beforePhotos: snapshot
          ? ReportPhoto.listOf(exec['before_photos'])
          : [for (final x in photos) if (x.kind == 'BEFORE') x],
      afterPhotos: snapshot
          ? ReportPhoto.listOf(exec['after_photos'])
          : [for (final x in photos) if (x.kind == 'AFTER') x],
      inspectionEvidencePhotos:
          ReportPhoto.listOf(exec['inspection_evidence_photos']),
    );
  }

  @override
  final String ticket;
  @override
  final ReportOrganization org;
  final String station;
  final DateTime? inspectionDate;

  /// Raw `HH:mm[:ss]` text ('' when none).
  final String inspectionTime;
  final String inspectionTitle;

  /// 'N/A' when blank.
  final String inspectionNumber;

  /// 'N/A' when blank.
  final String inspector;
  final String inspectionRemarks;
  final List<ReportPhoto> generalEvidencePhotos;

  /// Legacy "Inspection Points Covered" list.
  final List<InspectionCoveredPoint> coveredPoints;
  final List<InspectionReportPoint> points;
  final ReportSubmission? submission;

  /// Submitting technician ('' when no submission yet).
  final String technician;
  @override
  final ReportVerification? verification;

  @override
  String get title => 'Inspection Job Work Report';
  @override
  String get location => station;
  @override
  String get dateLabel =>
      _dateWithTime(inspectionDate?.toIso8601String().substring(0, 10),
          inspectionTime);

  @override
  List<ReportPhoto> get allPhotos => _dedupe([
        ...generalEvidencePhotos,
        for (final pt in points) ...[
          ...pt.inspectionEvidencePhotos,
          ...pt.beforePhotos,
          ...pt.afterPhotos,
        ],
      ]);

  @override
  List<Object?> get props => [
        ticket,
        org,
        station,
        inspectionDate,
        inspectionTime,
        inspectionTitle,
        inspectionNumber,
        inspector,
        inspectionRemarks,
        generalEvidencePhotos,
        coveredPoints,
        points,
        submission,
        technician,
        verification,
      ];
}

// ---------------------------------------------------------------------------
// Rectification
// ---------------------------------------------------------------------------

enum RectificationOutcome { rectified, notRectified, pending }

class RectificationReportItem extends Equatable {
  const RectificationReportItem({
    required this.asset,
    required this.checkpoint,
    required this.severity,
    required this.sourceTicket,
    required this.detectedAt,
    required this.finding,
    required this.actionTaken,
    required this.outcome,
    required this.reason,
    required this.beforePhotos,
    required this.afterPhotos,
  });

  final String asset;
  final String checkpoint;

  /// 'N/A' when blank.
  final String severity;

  /// 'N/A' when blank.
  final String sourceTicket;
  final DateTime? detectedAt;
  final String finding;
  final String actionTaken;
  final RectificationOutcome outcome;
  final String reason;
  final List<ReportPhoto> beforePhotos;
  final List<ReportPhoto> afterPhotos;

  /// `source_ticket | detected date` as the web prints it.
  String get sourceLabel => detectedAt == null
      ? sourceTicket
      : '$sourceTicket | ${formatReportDate(detectedAt)}';

  @override
  List<Object?> get props => [
        asset,
        checkpoint,
        severity,
        sourceTicket,
        detectedAt,
        finding,
        actionTaken,
        outcome,
        reason,
        beforePhotos,
        afterPhotos,
      ];
}

class RectificationJobWorkReport extends JobWorkReport {
  const RectificationJobWorkReport({
    required this.ticket,
    required this.org,
    required this.station,
    required this.reportDate,
    required this.finalRemarks,
    required this.technician,
    required this.otherStaff,
    required this.verification,
    required this.items,
  });

  factory RectificationJobWorkReport.fromJson(
    Map<dynamic, dynamic> payload, {
    String fallbackTicket = '',
    String? fallbackStation,
  }) {
    final p = _map(payload) ?? const <String, dynamic>{};
    final verifiedBy = _str(p['verified_by']);
    return RectificationJobWorkReport(
      ticket: _firstText([p['ticket_number']], fallbackTicket),
      org: ReportOrganization.fromJson(_map(p['organization'])),
      station: _firstText([p['station_name'], fallbackStation], '-'),
      reportDate: asJsonDateTime(p['report_date']),
      finalRemarks: _str(p['final_remarks']),
      technician: _str(p['technician']),
      otherStaff: _str(p['other_staff']),
      verification: verifiedBy.isEmpty
          ? null
          : ReportVerification(
              verifiedByName: verifiedBy,
              verifiedAt: asJsonDateTime(p['verified_at']),
              remarks: _str(p['verified_remarks']),
            ),
      items: [
        for (final i in _maps(p['items']))
          () {
            final photos = ReportPhoto.listOf(i['photos']);
            return RectificationReportItem(
              asset: _str(i['asset']),
              checkpoint: _str(i['checkpoint']),
              severity: _naIfBlank(i['severity']),
              sourceTicket: _naIfBlank(i['source_ticket']),
              detectedAt: asJsonDateTime(i['detected_at']),
              finding: _str(i['finding']),
              actionTaken: _str(i['action_taken']),
              outcome: switch (_str(i['outcome'])) {
                'RECTIFIED' => RectificationOutcome.rectified,
                'NOT_RECTIFIED' => RectificationOutcome.notRectified,
                _ => RectificationOutcome.pending,
              },
              reason: _str(i['reason']),
              beforePhotos: [
                for (final x in photos) if (x.kind == 'BEFORE') x
              ],
              afterPhotos: [
                for (final x in photos) if (x.kind == 'AFTER') x
              ],
            );
          }(),
      ],
    );
  }

  @override
  final String ticket;
  @override
  final ReportOrganization org;
  final String station;
  final DateTime? reportDate;
  final String finalRemarks;
  final String technician;
  final String otherStaff;
  @override
  final ReportVerification? verification;
  final List<RectificationReportItem> items;

  int get totalCount => items.length;
  int get rectifiedCount =>
      items.where((i) => i.outcome == RectificationOutcome.rectified).length;
  int get notRectifiedCount => items
      .where((i) => i.outcome == RectificationOutcome.notRectified)
      .length;

  /// `N items | x rectified | y not rectified`.
  String get summaryLine =>
      '$totalCount item${totalCount == 1 ? '' : 's'} | $rectifiedCount '
      'rectified | $notRectifiedCount not rectified';

  @override
  String get title => 'Deficiency Rectification Report';
  @override
  String get location => station;
  @override
  String get dateLabel => formatReportDate(reportDate);

  @override
  List<ReportPhoto> get allPhotos => _dedupe([
        for (final i in items) ...i.beforePhotos,
        for (final i in items) ...i.afterPhotos,
      ]);

  @override
  List<Object?> get props => [
        ticket,
        org,
        station,
        reportDate,
        finalRemarks,
        technician,
        otherStaff,
        verification,
        items,
      ];
}
