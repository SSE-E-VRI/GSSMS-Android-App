import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/verification_workspace_state.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';

final verificationWorkspaceControllerProvider = NotifierProvider.family<
    VerificationWorkspaceController, VerificationWorkspaceState, int>(() {
  return VerificationWorkspaceController();
});

class VerificationWorkspaceController
    extends FamilyNotifier<VerificationWorkspaceState, int> {
  @override
  VerificationWorkspaceState build(int arg) {
    return const VerificationWorkspaceLoading();
  }

  IWorkOrderRepository get _repository => ref.read(workOrderRepositoryProvider);

  Future<void> load() async {
    state = const VerificationWorkspaceLoading();
    try {
      final workspace = await _repository.fetchVerificationWorkspace(arg);
      state = VerificationWorkspaceLoaded(workspace: workspace);
    } catch (e) {
      state = VerificationWorkspaceError(
        'Failed to load verification workspace: ${workOrderReadableError(e)}',
      );
    }
  }
}
