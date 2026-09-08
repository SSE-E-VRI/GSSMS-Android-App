import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/data/org_scope_options_service.dart';
import 'package:gssms_mobile/core/domain/org_option.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';

/// The zone/division/depot/station selection this bar reports back.
class OrgScopeSelection extends Equatable {
  const OrgScopeSelection({this.zoneId, this.divisionId, this.depotId, this.stationId});

  final int? zoneId;
  final int? divisionId;
  final int? depotId;
  final int? stationId;

  static const empty = OrgScopeSelection();

  @override
  List<Object?> get props => [zoneId, divisionId, depotId, stationId];
}

/// Cascading Zone → Division → Depot → Station filter row.
///
/// Mirrors the web's `SectionScopeFilter` gating exactly: a level is only
/// shown as an editable dropdown when the signed-in user's own scope
/// ([scope]) is broad enough to need it — GLOBAL sees Zone→Division→Depot,
/// ZONE sees Division→Depot (their own zone is already fixed), DIVISION sees
/// Depot only, DEPOT/SELF sees none of the three (already one depot).
///
/// Not every backend list endpoint accepts every level, so a caller whose
/// endpoint can't filter by them must say so rather than let this bar offer
/// a control that silently filters nothing:
/// - [enableZoneDivision] — false for an endpoint with no `zone`/`division`
///   query param (e.g. the maintenance register), which forces Depot-only
///   regardless of the viewer's own scope.
/// - [enableStation] — false for an endpoint with no station filter at all
///   (e.g. Complaints/Inspections today). When true, Station appears once a
///   depot is resolved — either picked here, or the user's own fixed depot —
///   since narrowing to one station is useful even for a depot-scoped user
///   with several stations under them.
class OrgScopeFilterBar extends ConsumerStatefulWidget {
  const OrgScopeFilterBar({
    super.key,
    required this.scope,
    required this.selection,
    required this.onChanged,
    this.enableZoneDivision = true,
    this.enableStation = true,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 8),
  });

  final OrgScope scope;
  final OrgScopeSelection selection;
  final void Function(OrgScopeSelection selection) onChanged;
  final bool enableZoneDivision;
  final bool enableStation;
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<OrgScopeFilterBar> createState() => _OrgScopeFilterBarState();
}

class _OrgScopeFilterBarState extends ConsumerState<OrgScopeFilterBar> {
  // Mirrors widget.selection, but updated synchronously the moment the user
  // picks something — widget.selection only catches up once the parent's own
  // (async) onChanged round-trip rebuilds this widget. Cascading fetches
  // (e.g. divisions for a just-picked zone) must use the value just picked,
  // not the stale prop, so every read in this State goes through this local
  // copy rather than widget.selection directly.
  late OrgScopeSelection _selection;

  List<OrgOption> _zones = const [];
  List<OrgOption> _divisions = const [];
  List<OrgOption> _depots = const [];
  List<OrgOption> _stations = const [];

  bool _loadingDivisions = false;
  bool _loadingDepots = false;
  bool _loadingStations = false;

  bool get _showZone =>
      widget.enableZoneDivision && widget.scope.level == OrgScopeLevel.global;
  bool get _showDivision =>
      widget.enableZoneDivision &&
      (widget.scope.level == OrgScopeLevel.global || widget.scope.level == OrgScopeLevel.zone);
  bool get _showDepot =>
      widget.enableZoneDivision
          ? (widget.scope.level == OrgScopeLevel.global ||
              widget.scope.level == OrgScopeLevel.zone ||
              widget.scope.level == OrgScopeLevel.division)
          // enableZoneDivision: false (e.g. Reports) forces Depot as the only
          // level offered — except for a viewer already fixed to one depot
          // (DEPOT/SELF), where an editable "pick a depot" control would
          // only ever have their own single depot in it (every one of these
          // endpoints scopes its results via ScopeService regardless of the
          // param sent, so it couldn't show another depot's data even if
          // selected — this is purely about not showing a pointless control).
          : widget.scope.level != OrgScopeLevel.depot && widget.scope.level != OrgScopeLevel.self;

  /// The zone/division/depot id in effect for cascading fetches: the user's
  /// own fixed unit when their scope already pins it, otherwise the current
  /// local selection.
  int? get _effectiveZoneId => _showZone ? _selection.zoneId : widget.scope.zone?.id;
  int? get _effectiveDivisionId =>
      _showDivision ? _selection.divisionId : widget.scope.division?.id;
  int? get _effectiveDepotId => _showDepot ? _selection.depotId : widget.scope.depot?.id;

  OrgScopeOptionsService get _service => ref.read(orgScopeOptionsServiceProvider);

  @override
  void initState() {
    super.initState();
    _selection = widget.selection;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void didUpdateWidget(covariant OrgScopeFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Resync when the parent hands back a selection this widget didn't just
    // emit itself (e.g. a "clear filters" reset elsewhere) — an update that
    // matches what we already emitted is the normal round-trip and would
    // otherwise re-run every cascading fetch a second time for nothing.
    if (widget.selection != _selection && widget.selection != oldWidget.selection) {
      setState(() => _selection = widget.selection);
    }
  }

  Future<void> _bootstrap() async {
    if (_showZone) await _loadZones();
    if (_showDivision) await _loadDivisions();
    if (_showDepot) await _loadDepots();
    await _loadStations();
  }

  Future<void> _loadZones() async {
    try {
      final zones = await _service.fetchZones();
      if (mounted) setState(() => _zones = zones);
    } catch (_) {
      // Options are an enrichment of the filter row, not the list itself —
      // a failed fetch just leaves this dropdown showing "All", it must not
      // crash or block the screen the bar sits on.
    }
  }

  Future<void> _loadDivisions() async {
    if (!mounted) return;
    setState(() => _loadingDivisions = true);
    try {
      final divisions = await _service.fetchDivisions(zoneId: _effectiveZoneId);
      if (mounted) setState(() => _divisions = divisions);
    } catch (_) {
      if (mounted) setState(() => _divisions = const []);
    } finally {
      if (mounted) setState(() => _loadingDivisions = false);
    }
  }

  Future<void> _loadDepots() async {
    if (!mounted) return;
    setState(() => _loadingDepots = true);
    try {
      final depots = await _service.fetchDepots(
        zoneId: _effectiveZoneId,
        divisionId: _effectiveDivisionId,
      );
      if (mounted) setState(() => _depots = depots);
    } catch (_) {
      if (mounted) setState(() => _depots = const []);
    } finally {
      if (mounted) setState(() => _loadingDepots = false);
    }
  }

  Future<void> _loadStations() async {
    final depotId = _effectiveDepotId;
    if (!widget.enableStation || depotId == null) {
      if (mounted) setState(() => _stations = const []);
      return;
    }
    if (!mounted) return;
    setState(() => _loadingStations = true);
    try {
      final stations = await _service.fetchStations(depotId: depotId);
      if (mounted) setState(() => _stations = stations);
    } catch (_) {
      if (mounted) setState(() => _stations = const []);
    } finally {
      if (mounted) setState(() => _loadingStations = false);
    }
  }

  void _onZoneChanged(int? zoneId) {
    setState(() {
      _selection = OrgScopeSelection(zoneId: zoneId);
      _divisions = const [];
      _depots = const [];
      _stations = const [];
    });
    widget.onChanged(_selection);
    unawaited(_loadDivisions());
  }

  void _onDivisionChanged(int? divisionId) {
    setState(() {
      _selection = OrgScopeSelection(zoneId: _selection.zoneId, divisionId: divisionId);
      _depots = const [];
      _stations = const [];
    });
    widget.onChanged(_selection);
    unawaited(_loadDepots());
  }

  void _onDepotChanged(int? depotId) {
    setState(() {
      _selection = OrgScopeSelection(
        zoneId: _selection.zoneId,
        divisionId: _selection.divisionId,
        depotId: depotId,
      );
      _stations = const [];
    });
    widget.onChanged(_selection);
    unawaited(_loadStations());
  }

  void _onStationChanged(int? stationId) {
    setState(() {
      _selection = OrgScopeSelection(
        zoneId: _selection.zoneId,
        divisionId: _selection.divisionId,
        depotId: _selection.depotId,
        stationId: stationId,
      );
    });
    widget.onChanged(_selection);
  }

  @override
  Widget build(BuildContext context) {
    final showStation = widget.enableStation && _effectiveDepotId != null;
    final fields = <Widget>[
      if (_showZone)
        _scopeDropdown(
          keyName: 'org_scope_zone',
          label: 'Zone',
          value: _selection.zoneId,
          options: _zones,
          onChanged: _onZoneChanged,
        ),
      if (_showDivision)
        _scopeDropdown(
          keyName: 'org_scope_division',
          label: 'Division',
          value: _selection.divisionId,
          options: _divisions,
          loading: _loadingDivisions,
          onChanged: _onDivisionChanged,
        ),
      if (_showDepot)
        _scopeDropdown(
          keyName: 'org_scope_depot',
          label: 'Depot',
          value: _selection.depotId,
          options: _depots,
          loading: _loadingDepots,
          onChanged: _onDepotChanged,
        ),
      if (showStation)
        _scopeDropdown(
          keyName: 'org_scope_station',
          label: 'Station',
          value: _selection.stationId,
          options: _stations,
          loading: _loadingStations,
          onChanged: _onStationChanged,
        ),
    ];

    if (fields.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: widget.padding,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: fields.map((f) => SizedBox(width: 160, child: f)).toList(),
      ),
    );
  }

  Widget _scopeDropdown({
    required String keyName,
    required String label,
    required int? value,
    required List<OrgOption> options,
    required void Function(int?) onChanged,
    bool loading = false,
  }) {
    // The current value may not be in the just-fetched options list while a
    // cascading reload is in flight — DropdownButtonFormField throws if
    // `value` isn't among `items`, so fall back to unselected until it is.
    final safeValue = options.any((o) => o.id == value) ? value : null;

    return DropdownButtonFormField<int>(
      key: Key(keyName),
      isExpanded: true,
      isDense: true,
      value: safeValue,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        suffixIcon: loading
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.railwayBlue),
                ),
              )
            : null,
      ),
      // "All" is a real, selectable menu item (value: null) rather than just
      // the unselected hint — otherwise, once a real option is picked, there
      // was no item in the list that could take the selection back to null
      // and clear the filter. The hint stays as a fallback for the moment a
      // cascading reload leaves `value` null with no items loaded yet.
      hint: const Text('All', overflow: TextOverflow.ellipsis),
      items: [
        const DropdownMenuItem<int>(value: null, child: Text('All')),
        ...options.map(
          (o) => DropdownMenuItem(value: o.id, child: Text(o.name, overflow: TextOverflow.ellipsis)),
        ),
      ],
      onChanged: loading ? null : onChanged,
    );
  }
}
