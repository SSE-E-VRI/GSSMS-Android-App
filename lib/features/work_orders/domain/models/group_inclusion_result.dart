import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// Response of `POST /maintenance/records/{id}/group-inclusion/`.
class GroupInclusionResult extends Equatable {
  const GroupInclusionResult({
    this.included = false,
    this.checkedOut = false,
    this.excluded = false,
    this.exclusionReason,
    this.applicability,
    this.checkoutSource = '',
    this.returnedToTechnician = false,
  });

  final bool included;
  final bool checkedOut;
  final bool excluded;
  final String? exclusionReason;
  final String? applicability;

  /// `SUPERVISOR`, `TECHNICIAN` or empty.
  final String checkoutSource;

  /// True when un-checking at TECH_COMPLETED moved the Job Work to
  /// REWORK_REQUIRED.
  final bool returnedToTechnician;

  factory GroupInclusionResult.fromJson(Map<String, dynamic> json) {
    return GroupInclusionResult(
      included: asJsonBool(json['included']) ?? false,
      checkedOut: asJsonBool(json['checked_out']) ?? false,
      excluded: asJsonBool(json['excluded']) ?? false,
      exclusionReason: asJsonString(json['exclusion_reason']),
      applicability: asJsonString(json['applicability']),
      checkoutSource: asJsonString(json['checkout_source']) ?? '',
      returnedToTechnician:
          asJsonBool(json['returned_to_technician']) ?? false,
    );
  }

  @override
  List<Object?> get props => [
        included,
        checkedOut,
        excluded,
        exclusionReason,
        applicability,
        checkoutSource,
        returnedToTechnician,
      ];
}
