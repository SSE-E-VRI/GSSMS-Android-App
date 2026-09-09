import 'package:flutter/material.dart';
import '../../features/auth/domain/models/org_scope.dart';
import '../theme/app_theme.dart';
import 'org_scope_filter_bar.dart';

/// An app-bar action that provides organisation/depot scope filtering.
///
/// Replaces the fixed 90px in-body floating filter row on list screens:
/// - When scope is at its default, renders a plain filter icon with no chip.
/// - When a filter is active, renders an app-bar chip labelled with the active value ("Depot: All ▾" or active name).
/// - For a viewer whose scope has no filterable options (e.g. depot-scoped user with enableStation: false),
///   collapses to `SizedBox.shrink()` preserving existing gating logic.
/// - Tapping opens a modal bottom sheet hosting [OrgScopeFilterBar].
class OrgScopeAppBarFilter extends StatelessWidget {
  const OrgScopeAppBarFilter({
    super.key,
    required this.scope,
    required this.selection,
    required this.onChanged,
    this.enableZoneDivision = true,
    this.enableStation = true,
    this.depotLabel,
  });

  final OrgScope scope;
  final OrgScopeSelection selection;
  final void Function(OrgScopeSelection selection) onChanged;
  final bool enableZoneDivision;
  final bool enableStation;
  final String? depotLabel;

  bool get _hasFilterableOptions => OrgScopeFilterBar.hasFilterableOptions(
        scope: scope,
        selection: selection,
        enableZoneDivision: enableZoneDivision,
        enableStation: enableStation,
      );

  bool get _isDefault {
    return selection.zoneId == null &&
        selection.divisionId == null &&
        selection.depotId == null &&
        selection.stationId == null;
  }

  /// Display name of the viewer's own unit when the selection pins it, so the
  /// chip reads "Depot: Vriddhachalam ▾" instead of "Depot: #7 ▾".
  String? _ownUnitName(OrgUnitInfo? unit, int? selectedId) {
    final name = unit?.name;
    if (unit?.id != null && unit?.id == selectedId && name != null && name.isNotEmpty) {
      return name;
    }
    return null;
  }

  String get _activeLabel {
    if (selection.stationId != null) {
      return 'Station: #${selection.stationId} ▾';
    }
    if (selection.depotId != null) {
      final own = _ownUnitName(scope.depot, selection.depotId);
      if (own != null) return 'Depot: $own ▾';
      return depotLabel != null
          ? 'Depot: $depotLabel ▾'
          : 'Depot: #${selection.depotId} ▾';
    }
    if (selection.divisionId != null) {
      final own = _ownUnitName(scope.division, selection.divisionId);
      if (own != null) return 'Division: $own ▾';
      return 'Division: #${selection.divisionId} ▾';
    }
    if (selection.zoneId != null) {
      final own = _ownUnitName(scope.zone, selection.zoneId);
      if (own != null) return 'Zone: $own ▾';
      return 'Zone: #${selection.zoneId} ▾';
    }
    return 'Depot: All ▾';
  }

  void _openFilterSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          key: const Key('org_scope_bottom_sheet'),
          decoration: const BoxDecoration(
            color: AppTheme.surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.borderGrey,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filter by Location',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        Row(
                          children: [
                            if (!_isDefault)
                              TextButton(
                                key: const Key('org_scope_clear_button'),
                                onPressed: () {
                                  onChanged(OrgScopeSelection.empty);
                                  Navigator.of(sheetContext).pop();
                                },
                                child: const Text('Reset'),
                              ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: 'Close',
                              onPressed: () => Navigator.of(sheetContext).pop(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppTheme.borderGrey),
                  const SizedBox(height: 12),

                  // Cascading filter bar
                  OrgScopeFilterBar(
                    scope: scope,
                    selection: selection,
                    enableZoneDivision: enableZoneDivision,
                    enableStation: enableStation,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    onChanged: (newSelection) {
                      onChanged(newSelection);
                    },
                  ),
                  const SizedBox(height: 20),

                  // Done button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: ElevatedButton(
                      key: const Key('org_scope_done_button'),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('Apply Filter'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasFilterableOptions) {
      return const SizedBox.shrink();
    }

    if (_isDefault) {
      return IconButton(
        key: const Key('org_scope_filter_icon'),
        icon: const Icon(Icons.filter_list_rounded),
        tooltip: 'Filter by Scope',
        onPressed: () => _openFilterSheet(context),
      );
    }

    // Active chip
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Material(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: const Key('org_scope_active_chip'),
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openFilterSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.filter_list_rounded,
                    size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  _activeLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
