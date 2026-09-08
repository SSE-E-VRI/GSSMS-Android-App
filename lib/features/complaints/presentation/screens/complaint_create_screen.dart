import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/data/lookup_options_service.dart';
import 'package:gssms_mobile/core/data/org_scope_options_service.dart';
import 'package:gssms_mobile/core/domain/lookup_option.dart';
import 'package:gssms_mobile/core/domain/org_option.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_controller.dart';

const _infraTypes = [
  InfraFilterType.station,
  InfraFilterType.lcGate,
  InfraFilterType.serviceBuilding,
  InfraFilterType.staffQuarter,
];

/// Log New Complaint — mirrors the web ComplaintForm field-for-field
/// (GSSMS/frontend/src/views/ComplaintForm.jsx): Depot, Department Reporting,
/// Title/Subject, a Location & Asset Details group (Infrastructure Type,
/// Location Name, Asset Category, Specific Asset), then Description. The
/// mobile form previously only asked for a title, a severity dropdown the
/// server has no column for at all, and a description.
class ComplaintCreateScreen extends ConsumerStatefulWidget {
  const ComplaintCreateScreen(
      {super.key, this.initialAssetId, this.initialAssetName});

  final int? initialAssetId;
  final String? initialAssetName;

  @override
  ConsumerState<ComplaintCreateScreen> createState() =>
      _ComplaintCreateScreenState();
}

class _ComplaintCreateScreenState extends ConsumerState<ComplaintCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isSubmitting = false;
  bool _bootstrapped = false;

  List<LookupOption> _departments = const [];
  bool _loadingDepartments = false;
  String? _selectedDepartment;
  String? _departmentError;

  bool _canSelectDepot = false;
  List<OrgOption> _depots = const [];
  bool _loadingDepots = false;
  int? _selectedDepotId;

  InfraFilterType _infraType = InfraFilterType.station;
  List<InfrastructureOption> _locations = const [];
  bool _loadingLocations = false;
  int? _selectedLocationId;

  List<Asset> _assets = const [];
  bool _loadingAssets = false;
  List<String> _categories = const [];
  String? _selectedCategory;
  int? _selectedAssetId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// The station this complaint's location resolves to, whatever
  /// Infrastructure Type is selected — a Station row's own id, or the
  /// selected LC Gate/Service Building/Staff Quarter's parent station.
  int? get _resolvedStationId {
    if (_selectedLocationId == null) return null;
    if (_infraType == InfraFilterType.station) return _selectedLocationId;
    final match = _locations.where((l) => l.id == _selectedLocationId);
    return match.isEmpty ? null : match.first.stationId;
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final authState = ref.read(authControllerProvider);
    final session = authState is Authenticated ? authState.session : null;
    final scope = session?.scope ?? const OrgScope();

    setState(() {
      _canSelectDepot = scope.level != OrgScopeLevel.depot &&
          scope.level != OrgScopeLevel.self;
      _selectedDepotId = session?.depotId;
      _bootstrapped = true;
    });

    unawaited(_loadDepartments());
    if (_canSelectDepot) {
      unawaited(
          _loadDepots(zoneId: scope.zone?.id, divisionId: scope.division?.id));
    }
    unawaited(_loadLocations());
  }

  Future<void> _loadDepartments() async {
    setState(() => _loadingDepartments = true);
    try {
      final options = await ref
          .read(lookupOptionsServiceProvider)
          .fetchOptions('complaint_department');
      if (mounted) setState(() => _departments = options);
    } catch (_) {
      if (mounted) {
        setState(() => _departmentError = 'Failed to load departments');
      }
    } finally {
      if (mounted) setState(() => _loadingDepartments = false);
    }
  }

  Future<void> _loadDepots({int? zoneId, int? divisionId}) async {
    setState(() => _loadingDepots = true);
    try {
      final depots = await ref
          .read(orgScopeOptionsServiceProvider)
          .fetchDepots(zoneId: zoneId, divisionId: divisionId);
      if (mounted) setState(() => _depots = depots);
    } catch (_) {
      if (mounted) setState(() => _depots = const []);
    } finally {
      if (mounted) setState(() => _loadingDepots = false);
    }
  }

  Future<void> _loadLocations() async {
    setState(() {
      _loadingLocations = true;
      _selectedLocationId = null;
      _locations = const [];
      _assets = const [];
      _categories = const [];
      _selectedCategory = null;
      _selectedAssetId = null;
    });
    try {
      final options = await ref
          .read(infrastructureOptionsServiceProvider)
          .fetchOptions(_infraType, depotId: _selectedDepotId);
      if (mounted) setState(() => _locations = options);
    } catch (_) {
      if (mounted) setState(() => _locations = const []);
    } finally {
      if (mounted) setState(() => _loadingLocations = false);
    }
  }

  Future<void> _loadAssetsForLocation() async {
    final stationId = _resolvedStationId;
    setState(() {
      _assets = const [];
      _categories = const [];
      _selectedCategory = null;
      _selectedAssetId = null;
    });
    if (stationId == null) return;

    setState(() => _loadingAssets = true);
    try {
      final page = await ref
          .read(assetApiServiceProvider)
          .getAssets(stationId: stationId);
      if (!mounted) return;
      final categories = <String>{
        for (final a in page.assets)
          if ((a.assetCategoryName ?? '').trim().isNotEmpty)
            a.assetCategoryName!.trim(),
      }.toList()
        ..sort();
      setState(() {
        _assets = page.assets;
        _categories = categories;
      });
    } catch (_) {
      if (mounted) setState(() => _assets = const []);
    } finally {
      if (mounted) setState(() => _loadingAssets = false);
    }
  }

  List<Asset> get _filteredAssets {
    if (_selectedCategory == null) return _assets;
    return _assets
        .where((a) => a.assetCategoryName == _selectedCategory)
        .toList();
  }

  Future<void> _submitComplaint() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDepartment == null) {
      setState(() => _departmentError = 'Please select a department');
      return;
    }
    if (_canSelectDepot && _selectedDepotId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a Depot'),
            backgroundColor: AppTheme.errorRed),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(complaintRepositoryProvider).createComplaint(
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            department: _selectedDepartment!,
            depotId: _selectedDepotId,
            stationId: _infraType == InfraFilterType.station
                ? _selectedLocationId
                : null,
            infrastructureId: _infraType == InfraFilterType.station
                ? null
                : _selectedLocationId,
            assetId: _selectedAssetId ?? widget.initialAssetId,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complaint logged successfully!'),
            backgroundColor: AppTheme.railwayGreen,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to log complaint: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log Field Complaint')),
      body: !_bootstrapped
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.initialAssetName != null) ...[
                      _targetAssetBanner(),
                      const SizedBox(height: 16),
                    ],
                    _depotField(),
                    const SizedBox(height: 16),
                    _departmentField(),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('complaint_title_field'),
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title / Subject *',
                        hintText: 'e.g. Fan not working in Waiting Hall',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter a complaint title';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _locationAndAssetSection(),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('complaint_description_field'),
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description *',
                        hintText: 'Describe the issue in detail...',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 5,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter detailed description';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        key: const Key('submit_complaint_button'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _isSubmitting ? null : _submitComplaint,
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Text(
                                'Submit Complaint',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _targetAssetBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.railwayBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.railwayBlue.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.build_circle_outlined, color: AppTheme.railwayBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Target Asset: ${widget.initialAssetName}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: AppTheme.railwayBlue),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _depotField() {
    final safeValue =
        _depots.any((d) => d.id == _selectedDepotId) ? _selectedDepotId : null;
    return DropdownButtonFormField<int>(
      key: const Key('complaint_depot_dropdown'),
      isExpanded: true,
      value: safeValue,
      decoration: InputDecoration(
        labelText: 'Depot',
        border: const OutlineInputBorder(),
        suffixIcon: _loadingDepots
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      hint: const Text('-- Select Depot --'),
      items: _depots
          .map((d) => DropdownMenuItem(
              value: d.id,
              child: Text(d.name, overflow: TextOverflow.ellipsis)))
          .toList(),
      // Disabled once the user's own scope already fixes one depot — same as
      // web's `disabled={!canSelectDepot}`; the server forces this depot
      // regardless of what's sent for such a user, so an editable control
      // here would just be misleading.
      onChanged: !_canSelectDepot || _loadingDepots
          ? null
          : (id) {
              setState(() => _selectedDepotId = id);
              unawaited(_loadLocations());
            },
    );
  }

  Widget _departmentField() {
    final safeValue = _departments.any((d) => d.key == _selectedDepartment)
        ? _selectedDepartment
        : null;
    return DropdownButtonFormField<String>(
      key: const Key('complaint_department_dropdown'),
      isExpanded: true,
      value: safeValue,
      decoration: InputDecoration(
        labelText: 'Department Reporting *',
        border: const OutlineInputBorder(),
        errorText: _departmentError,
        suffixIcon: _loadingDepartments
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      hint: const Text('-- Select Department --'),
      items: _departments
          .map((d) => DropdownMenuItem(
              value: d.key,
              child: Text(d.label, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: _loadingDepartments
          ? null
          : (key) => setState(() {
                _selectedDepartment = key;
                _departmentError = null;
              }),
    );
  }

  Widget _locationAndAssetSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.errorRed.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.errorRed.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.location_on, color: AppTheme.errorRed, size: 18),
              SizedBox(width: 6),
              Text(
                'Location & Asset Details',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppTheme.errorRed),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<InfraFilterType>(
            key: const Key('complaint_infra_type_dropdown'),
            isExpanded: true,
            value: _infraType,
            decoration: const InputDecoration(
                labelText: 'Infrastructure Type', border: OutlineInputBorder()),
            items: _infraTypes
                .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                .toList(),
            onChanged: (type) {
              if (type == null) return;
              setState(() => _infraType = type);
              unawaited(_loadLocations());
            },
          ),
          const SizedBox(height: 12),
          _locationField(),
          const SizedBox(height: 12),
          _categoryField(),
          const SizedBox(height: 12),
          _assetField(),
          if (_resolvedStationId != null && !_loadingAssets && _assets.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'No registered assets found for this location. You can still log a generic complaint.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _locationField() {
    final safeValue = _locations.any((l) => l.id == _selectedLocationId)
        ? _selectedLocationId
        : null;
    return DropdownButtonFormField<int>(
      key: const Key('complaint_location_dropdown'),
      isExpanded: true,
      value: safeValue,
      decoration: InputDecoration(
        labelText: 'Location Name',
        border: const OutlineInputBorder(),
        suffixIcon: _loadingLocations
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : null,
      ),
      hint: Text('-- Select ${_infraType.label} --'),
      items: _locations
          .map((l) => DropdownMenuItem(
              value: l.id,
              child: Text(l.name, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: _loadingLocations
          ? null
          : (id) {
              setState(() => _selectedLocationId = id);
              unawaited(_loadAssetsForLocation());
            },
    );
  }

  Widget _categoryField() {
    final safeValue =
        _categories.contains(_selectedCategory) ? _selectedCategory : null;
    return DropdownButtonFormField<String>(
      key: const Key('complaint_asset_category_dropdown'),
      isExpanded: true,
      value: safeValue,
      decoration: const InputDecoration(
          labelText: 'Asset Category', border: OutlineInputBorder()),
      hint: const Text('-- All Categories --'),
      // "-- All Categories --" is a real, selectable item (value: null), not
      // just the unselected hint — otherwise there is no menu item that can
      // take a selection back to "all" once a real category is picked.
      items: [
        const DropdownMenuItem<String>(
            value: null, child: Text('-- All Categories --')),
        ..._categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
      ],
      onChanged: (_selectedLocationId == null || _assets.isEmpty)
          ? null
          : (cat) => setState(() {
                _selectedCategory = cat;
                if (_selectedAssetId != null &&
                    !_filteredAssets.any((a) => a.id == _selectedAssetId)) {
                  _selectedAssetId = null;
                }
              }),
    );
  }

  Widget _assetField() {
    final options = _filteredAssets;
    final safeValue =
        options.any((a) => a.id == _selectedAssetId) ? _selectedAssetId : null;
    return DropdownButtonFormField<int>(
      key: const Key('complaint_asset_dropdown'),
      isExpanded: true,
      value: safeValue,
      decoration: InputDecoration(
        labelText: 'Specific Asset (Optional)',
        border: const OutlineInputBorder(),
        suffixIcon: _loadingAssets
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : null,
      ),
      hint: const Text('-- Generic / Location Issue --'),
      // Same reasoning as the category dropdown: a real null-valued item so
      // a generic (non-asset-specific) complaint can be reselected after
      // picking a specific asset.
      items: [
        const DropdownMenuItem<int>(
            value: null, child: Text('-- Generic / Location Issue --')),
        ...options.map((a) => DropdownMenuItem(
              value: a.id,
              child: Text(
                _selectedCategory == null
                    ? '${a.uniqueId} (${a.assetCategoryName ?? ''})'
                    : a.uniqueId,
                overflow: TextOverflow.ellipsis,
              ),
            )),
      ],
      onChanged: _selectedLocationId == null
          ? null
          : (id) => setState(() => _selectedAssetId = id),
    );
  }
}
