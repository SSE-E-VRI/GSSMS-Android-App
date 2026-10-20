import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:gssms_mobile/core/data/lookup_options_service.dart';
import 'package:gssms_mobile/core/data/org_scope_options_service.dart';
import 'package:gssms_mobile/core/domain/lookup_option.dart';
import 'package:gssms_mobile/core/domain/org_option.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_controller.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';

const _infraTypes = [
  InfraFilterType.station,
  InfraFilterType.lcGate,
  InfraFilterType.serviceBuilding,
  InfraFilterType.staffQuarter,
];

/// Report New Breakdown — mirrors web `Report New Breakdown`
/// (gssms.share.zrok.io/complaints/new) field-for-field: Depot, Department
/// Reporting, Title/Subject, a Location & Asset Details group (Infrastructure
/// Type, Location Name, Asset Category, Specific Asset), then Description,
/// with Cancel / Submit Breakdown footer.
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
  static const int _maxPhotos = 5;
  static const int _maxPhotoBytes = 15 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _complainantController = TextEditingController();
  final _generalAssetController = TextEditingController();

  DateTime? _failureDate;
  TimeOfDay? _failureTime;
  String? _failureDateError;
  String? _failureTimeError;

  final List<XFile> _stagedPhotos = [];

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
  int _loadSeq = 0;
  List<String> _categories = const [];
  String? _selectedCategory;
  int? _selectedAssetId;

  /// Header band + submit button: a solid/on-solid pair so the text stays
  /// readable in both themes (the band is red, as on the Web form).
  Color get _band => context.gssms.danger.solid;
  Color get _onBand => context.gssms.danger.onSolid;
  Color get _webLightBg => context.gssms.surfaceInset;
  Color get _border => context.gssms.border;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _complainantController.dispose();
    _generalAssetController.dispose();
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
    final session = sessionFromAuth(ref.read(authControllerProvider));
    if (!sessionAllows(session, 'complaints.create')) {
      if (mounted) setState(() => _bootstrapped = true);
      return;
    }
    final scope = session?.scope ?? const OrgScope();

    setState(() {
      _canSelectDepot = session != null &&
          scope.level != OrgScopeLevel.depot &&
          scope.level != OrgScopeLevel.self;
      _selectedDepotId = session?.depotId;
      // For depot-scoped users the dropdown is disabled — seed it with their
      // own depot so the field still shows the resolved depot name rather
      // than a blank "-- Select Depot --" hint (same as inspection form).
      if (!_canSelectDepot && _selectedDepotId != null) {
        _depots = [
          OrgOption(
              id: _selectedDepotId!,
              name: session?.depotName ?? 'Depot #$_selectedDepotId')
        ];
      }
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
    if (!mounted) return;
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
    if (!mounted) return;
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
    if (!mounted) return;
    final seq = ++_loadSeq;
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
      if (!mounted || seq != _loadSeq) return;
      setState(() => _locations = options);
    } catch (_) {
      if (!mounted || seq != _loadSeq) return;
      setState(() => _locations = const []);
    } finally {
      if (mounted && seq == _loadSeq) setState(() => _loadingLocations = false);
    }
  }

  Future<void> _loadAssetsForLocation() async {
    if (!mounted) return;
    final seq = ++_loadSeq;
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
      if (!mounted || seq != _loadSeq) return;
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
      if (!mounted || seq != _loadSeq) return;
      setState(() => _assets = const []);
    } finally {
      if (mounted && seq == _loadSeq) setState(() => _loadingAssets = false);
    }
  }

  List<Asset> get _filteredAssets {
    if (_selectedCategory == null) return _assets;
    return _assets
        .where((a) => a.assetCategoryName == _selectedCategory)
        .toList();
  }

  Future<void> _submitComplaint() async {
    if (!sessionAllows(
        sessionFromAuth(ref.read(authControllerProvider)), 'complaints.create')) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedDepartment == null) {
      setState(() => _departmentError = 'Please select a department');
      return;
    }
    var valid = true;
    if (_failureDate == null) {
      setState(() => _failureDateError = 'Please select the failure date');
      valid = false;
    } else {
      setState(() => _failureDateError = null);
    }
    if (_failureTime == null) {
      setState(() => _failureTimeError = 'Please select the failure time');
      valid = false;
    } else {
      setState(() => _failureTimeError = null);
    }
    if (!valid) return;
    if (_canSelectDepot && _selectedDepotId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: const Text('Please select a Depot'),
            backgroundColor: context.gssms.danger.solid),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final failureDate =
          DateFormat('yyyy-MM-dd').format(_failureDate ?? DateTime.now());
      final failureTime =
          '${_failureTime!.hour.toString().padLeft(2, '0')}:${_failureTime!.minute.toString().padLeft(2, '0')}';
      final generalAsset = _generalAssetController.text.trim();
      final created =
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
                assetId: generalAsset.isNotEmpty
                    ? null
                    : (_selectedAssetId ?? widget.initialAssetId),
                generalAssetDescription:
                    generalAsset.isNotEmpty ? generalAsset : null,
                failureDate: failureDate,
                failureTime: failureTime,
                complainantName: _complainantController.text.trim(),
              );

      // Staged evidence uploads after the breakdown exists (it needs the id
      // first) — a failure here warns but keeps the created breakdown, same
      // as web's photoWarning path.
      var photoErrors = 0;
      for (final photo in _stagedPhotos) {
        try {
          await ref.read(complaintRepositoryProvider).uploadPhoto(
                complaintId: created.id,
                file: await _photoFile(photo),
              );
        } catch (_) {
          photoErrors++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(photoErrors > 0
                ? 'Breakdown reported successfully! ($photoErrors photo(s) could not be uploaded.)'
                : 'Breakdown reported successfully!'),
            backgroundColor: context.gssms.success.solid,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Failed to report breakdown: ${workOrderReadableError(e)}'),
            backgroundColor: context.gssms.danger.solid,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// JPEG-only, ≤15MB multipart file for a staged photo (mirrors web's
  /// client-side gate; the server re-validates and normalizes).
  Future<MultipartFile> _photoFile(XFile photo) async {
    final file = File(photo.path);
    if (!await file.exists()) {
      throw ArgumentError('Photo not found');
    }
    final lower = photo.path.toLowerCase();
    if (!lower.endsWith('.jpg') && !lower.endsWith('.jpeg')) {
      throw ArgumentError('Only JPEG photos are allowed');
    }
    if (await file.length() > _maxPhotoBytes) {
      throw ArgumentError('Photo exceeds the 15 MB limit');
    }
    final filename = photo.path.split(Platform.pathSeparator).last;
    return MultipartFile.fromFile(
      photo.path,
      filename: filename.isNotEmpty ? filename : 'evidence.jpg',
      contentType: DioMediaType('image', 'jpeg'),
    );
  }

  Future<void> _pickPhotos() async {
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
      if (!mounted) return;
      setState(() {
        for (final p in picked) {
          if (_stagedPhotos.length >= _maxPhotos) break;
          final lower = p.path.toLowerCase();
          if (!lower.endsWith('.jpg') && !lower.endsWith('.jpeg')) {
            continue;
          }
          _stagedPhotos.add(p);
        }
      });
    } catch (_) {
      // Picker dismissal / denial — stay on the form.
    }
  }

  Future<void> _pickFailureDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _failureDate ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Select failure date',
    );
    if (picked != null && mounted) {
      setState(() {
        _failureDate = picked;
        _failureDateError = null;
      });
    }
  }

  Future<void> _pickFailureTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _failureTime ?? TimeOfDay.now(),
      helpText: 'Select failure time',
    );
    if (picked != null && mounted) {
      setState(() {
        _failureTime = picked;
        _failureTimeError = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionAllows(sessionOf(ref), 'complaints.create')) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Report New Breakdown'),
        ),
        body: const PermissionDeniedView(),
      );
    }

    return Scaffold(
      // No title here — the colored header below already carries it (as an
      // accessible `Semantics(header: true)` region), so the AppBar isn't
      // duplicating it back-to-back. Only the back button lives up top.
      appBar: AppBar(),
      backgroundColor: _webLightBg,
      body: !_bootstrapped
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Form(
                key: _formKey,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Red header — mirrors web's "Report New Breakdown" bar.
                      // This is the screen's only title (the AppBar carries
                      // no text of its own — see build() above), so it's
                      // marked as an accessible header region rather than
                      // decorative content screen readers would otherwise
                      // skip.
                      Semantics(
                        header: true,
                        label: 'Report New Breakdown',
                        // The Row's own Icon/Text would otherwise each add
                        // their own semantics on top of this label.
                        excludeSemantics: true,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _band,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12)),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(Icons.campaign_outlined,
                                  color: _onBand, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Report New Breakdown',
                                style: TextStyle(
                                    color: _onBand,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.initialAssetName != null) ...[
                              _targetAssetBanner(),
                              const SizedBox(height: 14),
                            ],
                            _depotField(),
                            const SizedBox(height: 14),
                            _departmentField(),
                            const SizedBox(height: 14),
                            _titleField(),
                            const SizedBox(height: 14),
                            _failureFields(),
                            const SizedBox(height: 14),
                            _complainantField(),
                            const SizedBox(height: 16),
                            _locationAndAssetSection(),
                            const SizedBox(height: 14),
                            _descriptionField(),
                            const SizedBox(height: 16),
                            _photosSection(),
                            const SizedBox(height: 16),
                            Divider(height: 1, color: _border),
                            const SizedBox(height: 16),
                            _actionRow(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _labelWithInfo(String label, {bool required = false, required String tooltip}) {
    // Flexible text so long labels (e.g. "Specific Asset (Optional)") wrap
    // instead of overflowing their half-width column at 360dp.
    return Row(
      children: [
        Flexible(
          child: Text.rich(
            TextSpan(
              text: label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.gssms.textPrimary),
              children: [
                if (required)
                  TextSpan(
                      text: ' *',
                      style: TextStyle(
                          color: context.gssms.danger.foreground,
                          fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Was purely decorative — visually promised "tap for help" but had no
        // handler. Tooltip makes it a real tap/long-press affordance, and its
        // `message` doubles as the icon's accessible label instead of a
        // silent, unlabeled glyph.
        Tooltip(
          message: tooltip,
          triggerMode: TooltipTriggerMode.tap,
          child: Icon(Icons.info_outline,
              size: 14, color: context.gssms.textSecondary),
        ),
      ],
    );
  }

  InputDecoration _webInput({
    String? hint,
    Widget? suffixIcon,
    String? errorText,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          TextStyle(color: context.gssms.textSecondary, fontSize: 14),
      filled: true,
      fillColor: Theme.of(context).inputDecorationTheme.fillColor,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _border)),
      errorText: errorText,
      suffixIcon: suffixIcon,
    );
  }

  Widget _targetAssetBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.gssms.info.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.gssms.info.border),
      ),
      child: Row(
        children: [
          Icon(Icons.build_circle_outlined,
              color: context.gssms.link, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Target Asset: ${widget.initialAssetName}',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: context.gssms.link,
                  fontSize: 13),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Depot',
            tooltip:
                'The depot this breakdown is scoped to. Locked to your own depot unless you have multi-depot access.'),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          key: const Key('complaint_depot_dropdown'),
          isExpanded: true,
          value: safeValue,
          decoration: _webInput(
            hint: '-- Select Depot --',
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
          items: _depots
              .map((d) => DropdownMenuItem(
                  value: d.id,
                  child: Text(d.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14))))
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
        ),
      ],
    );
  }

  Widget _departmentField() {
    final safeValue = _departments.any((d) => d.key == _selectedDepartment)
        ? _selectedDepartment
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Department Reporting',
            required: true,
            tooltip: 'The department responsible for handling this breakdown.'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: const Key('complaint_department_dropdown'),
          isExpanded: true,
          value: safeValue,
          decoration: _webInput(
            hint: '-- Select Department --',
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
          items: _departments
              .map((d) => DropdownMenuItem(
                  value: d.key,
                  child: Text(d.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14))))
              .toList(),
          onChanged: _loadingDepartments
              ? null
              : (key) => setState(() {
                    _selectedDepartment = key;
                    _departmentError = null;
                  }),
        ),
      ],
    );
  }

  Widget _titleField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Title / Subject',
            required: true,
            tooltip: 'A short summary of the issue, shown in lists and notifications.'),
        const SizedBox(height: 6),
        TextFormField(
          key: const Key('complaint_title_field'),
          controller: _titleController,
          decoration: _webInput(hint: 'e.g. Fan not working in Waiting Hall'),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter a breakdown title';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _failureFields() {
    final dateText = _failureDate == null
        ? '-- Select date --'
        : DateFormat('dd-MM-yyyy').format(_failureDate!);
    final timeText = _failureTime == null
        ? '-- Select time --'
        : _failureTime!.format(context);
    InputDecoration box(String? error) => _webInput().copyWith(
          errorText: error,
          suffixIcon: Icon(Icons.calendar_today_outlined,
              size: 18, color: context.gssms.textSecondary),
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 420;
        final dateField = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _labelWithInfo('Failure Date',
                required: true,
                tooltip: 'When the failure happened. Cannot be in the future.'),
            const SizedBox(height: 6),
            InkWell(
              key: const Key('complaint_failure_date_field'),
              onTap: _pickFailureDate,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: box(_failureDateError),
                child: Text(dateText,
                    style: TextStyle(
                        fontSize: 14, color: context.gssms.textPrimary)),
              ),
            ),
          ],
        );
        final timeField = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _labelWithInfo('Failure Time',
                required: true,
                tooltip: 'The time the failure was observed.'),
            const SizedBox(height: 6),
            InkWell(
              key: const Key('complaint_failure_time_field'),
              onTap: _pickFailureTime,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration:
                    box(_failureTimeError).copyWith(suffixIcon: null),
                child: Text(timeText,
                    style: TextStyle(
                        fontSize: 14, color: context.gssms.textPrimary)),
              ),
            ),
          ],
        );
        if (narrow) {
          return Column(
            children: [
              dateField,
              const SizedBox(height: 12),
              timeField,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: dateField),
            const SizedBox(width: 12),
            Expanded(child: timeField),
          ],
        );
      },
    );
  }

  Widget _complainantField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Complainant Name',
            required: true,
            tooltip: 'Name of the person who reported this breakdown.'),
        const SizedBox(height: 6),
        TextFormField(
          key: const Key('complaint_complainant_field'),
          controller: _complainantController,
          decoration: _webInput(hint: 'Who reported this?'),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter the complainant name';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _generalAssetField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('General / Non-Registered Asset (Optional)',
            tooltip:
                'Describe the affected item when there is no registered asset for it. Clears the Specific Asset selection above.'),
        const SizedBox(height: 6),
        TextFormField(
          key: const Key('complaint_general_asset_field'),
          controller: _generalAssetController,
          decoration: _webInput(hint: 'e.g. Platform bench near Gate 2'),
          onChanged: (v) {
            if (v.trim().isNotEmpty && _selectedAssetId != null) {
              setState(() => _selectedAssetId = null);
            }
          },
        ),
      ],
    );
  }

  Widget _photosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Evidence Photos (Optional)',
            tooltip:
                'JPEG only, up to 5. Uploaded after the breakdown is reported; a failure warns but keeps the breakdown.'),
        const SizedBox(height: 6),
        if (_stagedPhotos.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _stagedPhotos.length; i++)
                Chip(
                  key: Key('complaint_staged_photo_$i'),
                  label: Text(
                    _stagedPhotos[i].path.split(Platform.pathSeparator).last,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => setState(() => _stagedPhotos.removeAt(i)),
                ),
            ],
          ),
        if (_stagedPhotos.isNotEmpty) const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('complaint_add_photos_button'),
          onPressed:
              _stagedPhotos.length >= _maxPhotos ? null : _pickPhotos,
          icon: const Icon(Icons.photo_camera_outlined, size: 16),
          label: Text(
              'Add Photos (${_stagedPhotos.length}/$_maxPhotos)',
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _descriptionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Description',
            required: true,
            tooltip: "Full details of the issue — what's wrong, where, and any relevant context."),
        const SizedBox(height: 6),
        TextFormField(
          key: const Key('complaint_description_field'),
          controller: _descriptionController,
          decoration:
              _webInput(hint: 'Describe the issue in detail...'),
          maxLines: 5,
          minLines: 4,
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter detailed description';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _locationAndAssetSection() {
    // Neutral styling (not the errorLight/errorBorder red tint this used to
    // carry): every field in this section is optional — no validator is
    // attached to any of _infraTypeField/_locationField/_categoryField/
    // _assetField — so a red-tinted card next to the genuinely required
    // fields above it misread as "needs attention". "(Optional)" is spelled
    // out in the header too, matching InspectionCreateScreen's equivalent
    // card, so the user isn't left guessing whether this section is required.
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, color: context.gssms.link, size: 16),
              const SizedBox(width: 6),
              Text(
                'Location & Asset Details (Optional)',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.gssms.link,
                    fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Row 1: Infrastructure Type + Location Name (mirrors web 2-col).
          // Wrap-friendly: on narrow phones the two fields stack instead of
          // overflowing — the previous fixed Row could push the Location
          // dropdown off-screen at 360dp.
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 420;
              if (narrow) {
                return Column(
                  children: [
                    _infraTypeField(),
                    const SizedBox(height: 12),
                    _locationField(),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _infraTypeField()),
                  const SizedBox(width: 12),
                  Expanded(child: _locationField()),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          // Row 2: Asset Category + Specific Asset.
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 420;
              if (narrow) {
                return Column(
                  children: [
                    _categoryField(),
                    const SizedBox(height: 12),
                    _assetField(),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _categoryField()),
                  const SizedBox(width: 12),
                  Expanded(child: _assetField()),
                ],
              );
            },
          ),
          if (_resolvedStationId != null && !_loadingAssets && _assets.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No registered assets found for this location. You can still report a generic breakdown.',
                style: TextStyle(fontSize: 12, color: context.gssms.textSecondary),
              ),
            ),
          const SizedBox(height: 12),
          _generalAssetField(),
        ],
      ),
    );
  }

  Widget _infraTypeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Infrastructure Type',
            tooltip:
                'Narrows the Location Name list below to Stations, LC Gates, Service Buildings, or Staff Quarters.'),
        const SizedBox(height: 6),
        DropdownButtonFormField<InfraFilterType>(
          key: const Key('complaint_infra_type_dropdown'),
          isExpanded: true,
          value: _infraType,
          decoration: _webInput().copyWith(
            fillColor: context.gssms.surfaceInset,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          items: _infraTypes
              .map((t) => DropdownMenuItem(
                  value: t,
                  child: Text(t.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13))))
              .toList(),
          onChanged: (type) {
            if (type == null) return;
            setState(() => _infraType = type);
            unawaited(_loadLocations());
          },
        ),
      ],
    );
  }

  Widget _locationField() {
    final safeValue = _locations.any((l) => l.id == _selectedLocationId)
        ? _selectedLocationId
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Location Name',
            tooltip: 'The specific site this breakdown applies to.'),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          key: const Key('complaint_location_dropdown'),
          isExpanded: true,
          value: safeValue,
          decoration: _webInput(
            hint: '-- Select ${_infraType.label} --',
            suffixIcon: _loadingLocations
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ).copyWith(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          items: _locations
              .map((l) => DropdownMenuItem(
                  value: l.id,
                  child: Text(l.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13))))
              .toList(),
          onChanged: _loadingLocations
              ? null
              : (id) {
                  setState(() => _selectedLocationId = id);
                  unawaited(_loadAssetsForLocation());
                },
        ),
      ],
    );
  }

  Widget _categoryField() {
    final safeValue =
        _categories.contains(_selectedCategory) ? _selectedCategory : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Asset Category',
            tooltip: 'Filters the Specific Asset list below by category.'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: const Key('complaint_asset_category_dropdown'),
          isExpanded: true,
          value: safeValue,
          decoration: _webInput(hint: '-- All Categories --').copyWith(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          // "-- All Categories --" is a real, selectable item (value: null), not
          // just the unselected hint — otherwise there is no menu item that can
          // take a selection back to "all" once a real category is picked.
          items: [
            const DropdownMenuItem<String>(
                value: null, child: Text('-- All Categories --', style: TextStyle(fontSize: 13))),
            ..._categories.map((c) => DropdownMenuItem(
                value: c,
                child: Text(c,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)))),
          ],
          onChanged: (_selectedLocationId == null || _assets.isEmpty)
              ? null
              : (cat) => setState(() {
                    _selectedCategory = cat;
                    if (_selectedAssetId != null &&
                        !_filteredAssets
                            .any((a) => a.id == _selectedAssetId)) {
                      _selectedAssetId = null;
                    }
                  }),
        ),
      ],
    );
  }

  Widget _assetField() {
    final options = _filteredAssets;
    final safeValue =
        options.any((a) => a.id == _selectedAssetId) ? _selectedAssetId : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Specific Asset (Optional)',
            tooltip:
                'Link this breakdown to one exact asset, or leave blank for a general/location-level issue.'),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          key: const Key('complaint_asset_dropdown'),
          isExpanded: true,
          value: safeValue,
          decoration: _webInput(
            hint: '-- Generic / Location Issue --',
            suffixIcon: _loadingAssets
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ).copyWith(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          // Same reasoning as the category dropdown: a real null-valued item so
          // a generic (non-asset-specific) complaint can be reselected after
          // picking a specific asset.
          items: [
            const DropdownMenuItem<int>(
                value: null,
                child: Text('-- Generic / Location Issue --',
                    style: TextStyle(fontSize: 13))),
            ...options.map((a) => DropdownMenuItem(
                  value: a.id,
                  child: Text(
                    _selectedCategory == null
                        ? '${a.uniqueId} (${a.assetCategoryName ?? ''})'
                        : a.uniqueId,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                )),
          ],
          onChanged: _selectedLocationId == null
              ? null
              : (id) => setState(() {
                    _selectedAssetId = id;
                    // Registered asset and general item are mutually
                    // exclusive server-side — picking one clears the other.
                    if (id != null && _generalAssetController.text.isNotEmpty) {
                      _generalAssetController.clear();
                    }
                  }),
        ),
      ],
    );
  }

  Widget _actionRow() {
    // NOTE: do NOT use full-width / expanded buttons here — AppTheme's
    // elevatedButtonTheme sets minimumSize: Size.fromHeight(48) (infinite
    // width), which inside a Row produces BoxConstraints(w=Infinity) and a
    // blank screen (same crash fixed on InspectionCreateScreen). Explicit
    // finite minimumSize + shrinkWrap keeps both buttons content-sized.
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          key: const Key('cancel_complaint_button'),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.gssms.textSecondary,
            side: BorderSide(color: context.gssms.border),
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(0, 48),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.close, size: 16),
          label:
              const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          key: const Key('submit_complaint_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _band,
            foregroundColor: _onBand,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            elevation: 2,
            minimumSize: const Size(0, GssmsSize.touchTarget),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: _isSubmitting ? null : _submitComplaint,
          icon: _isSubmitting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: _onBand, strokeWidth: 2))
              : const Icon(Icons.send_outlined,
                  size: 16),
          label: Text(_isSubmitting ? 'Submitting...' : 'Submit Breakdown',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ),
      ],
    );
  }
}
