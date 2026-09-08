import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/reports/data/infrastructure_options_service.dart';
import 'package:gssms_mobile/features/reports/data/reports_api_service.dart';
import 'package:gssms_mobile/features/reports/data/reports_repository.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_state.dart';

final reportsApiServiceProvider = Provider<ReportsApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return ReportsApiService(dio);
});

final reportsRepositoryProvider = Provider<IReportsRepository>((ref) {
  final api = ref.watch(reportsApiServiceProvider);
  return ReportsRepository(api);
});

final infrastructureOptionsServiceProvider =
    Provider<InfrastructureOptionsService>((ref) {
  return InfrastructureOptionsService(ref.watch(authenticatedDioProvider));
});

final reportsControllerProvider =
    NotifierProvider<ReportsController, ReportsState>(() {
  return ReportsController();
});

class ReportsController extends Notifier<ReportsState> {
  @override
  ReportsState build() {
    return const ReportsLoading();
  }

  IReportsRepository get _repository => ref.read(reportsRepositoryProvider);
  InfrastructureOptionsService get _options =>
      ref.read(infrastructureOptionsServiceProvider);

  Future<void> loadRegister({
    DateTime? startDate,
    DateTime? endDate,
    InfraFilterType? infraType,
    int? infraId,
    bool clearInfraId = false,
    OrgScopeSelection? orgScope,
  }) async {
    final currentState = state;
    final previous = currentState is ReportsLoaded
        ? currentState
        : (currentState is ReportsError ? currentState.previousLoaded : null);
    final now = DateTime.now();
    final end = endDate ?? previous?.endDate ?? now;
    final start = startDate ?? previous?.startDate ?? now.subtract(const Duration(days: 30));
    final type = infraType ?? previous?.infraType ?? InfraFilterType.all;
    final typeChanged = infraType != null && infraType != previous?.infraType;
    final id = (typeChanged || clearInfraId) ? null : (infraId ?? previous?.infraId);
    final scope = orgScope ?? previous?.orgScope ?? OrgScopeSelection.empty;

    state = const ReportsLoading();

    final df = DateFormat('yyyy-MM-dd');
    try {
      var options = previous?.infraOptions ?? const [];
      if (type != previous?.infraType) {
        // The item dropdown's options are an enrichment of the register, not
        // the register itself — a role without infrastructure.view (or a
        // network hiccup) here must not turn an otherwise-successful load
        // into a full-screen error and lose the already-loaded entries.
        // Same reasoning as WorkOrderDetailController.loadActionsAndAudit.
        // An explicit try/catch (not `.catchError` on the Future) so this is
        // robust regardless of whether the failure surfaces as a rejected
        // Future or a synchronous throw from the service call itself.
        if (type == InfraFilterType.all) {
          options = const [];
        } else {
          try {
            options = await _options.fetchOptions(type);
          } catch (_) {
            options = const [];
          }
        }
      }

      final entries = await _repository.fetchMaintenanceRegister(
        startDate: df.format(start),
        endDate: df.format(end),
        depotId: scope.depotId,
        infraType: type,
        infraId: id,
      );

      state = ReportsLoaded(
        entries: entries,
        startDate: start,
        endDate: end,
        infraType: type,
        infraId: id,
        infraOptions: options,
        orgScope: scope,
      );
    } catch (e) {
      state = ReportsError('Failed to load register report: $e', previousLoaded: previous);
    }
  }

  Future<void> setInfraType(InfraFilterType type) {
    return loadRegister(infraType: type, clearInfraId: true);
  }

  Future<void> setInfraId(int? id) {
    return loadRegister(infraId: id, clearInfraId: id == null);
  }

  /// Depot filter, same server-side reasoning as the date range and infra
  /// type/id filters. Used with `enableZoneDivision: false` (register_report
  /// has no zone/division param) and `enableStation: false` — station-level
  /// narrowing is already covered by the Infrastructure Type/Item filter
  /// above (Type=Station + item), so the org-scope bar here only offers Depot.
  Future<void> setOrgScope(OrgScopeSelection scope) {
    return loadRegister(orgScope: scope);
  }
}
