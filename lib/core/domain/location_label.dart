/// Human-readable location for a Complaint/Inspection, built exactly like the
/// Web registers' `getInfraName`: the station if there is one, otherwise the
/// linked infrastructure by type (LC gate, service building, staff quarter).
/// Returns null when nothing is linked so callers choose their own fallback.
String? infrastructureLocationLabel({
  String? stationName,
  String? lcGateNumber,
  String? serviceBuildingName,
  String? staffQuarterName,
  String? infrastructureName,
}) {
  bool has(String? v) => v != null && v.trim().isNotEmpty;
  if (has(stationName)) return '${stationName!.trim()} (Station)';
  if (has(lcGateNumber)) return 'Gate ${lcGateNumber!.trim()} (LC Gate)';
  if (has(serviceBuildingName)) return '${serviceBuildingName!.trim()} (Building)';
  if (has(staffQuarterName)) return '${staffQuarterName!.trim()} (Quarter)';
  if (has(infrastructureName)) return infrastructureName!.trim();
  return null;
}
