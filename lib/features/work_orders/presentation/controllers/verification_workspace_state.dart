import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/verification_workspace.dart';

sealed class VerificationWorkspaceState extends Equatable {
  const VerificationWorkspaceState();

  @override
  List<Object?> get props => [];
}

class VerificationWorkspaceLoading extends VerificationWorkspaceState {
  const VerificationWorkspaceLoading();
}

class VerificationWorkspaceLoaded extends VerificationWorkspaceState {
  const VerificationWorkspaceLoaded({
    required this.workspace,
    this.isSubmitting = false,
  });

  final VerificationWorkspace workspace;
  final bool isSubmitting;

  VerificationWorkspaceLoaded copyWith({
    VerificationWorkspace? workspace,
    bool? isSubmitting,
  }) {
    return VerificationWorkspaceLoaded(
      workspace: workspace ?? this.workspace,
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }

  @override
  List<Object?> get props => [workspace, isSubmitting];
}

class VerificationWorkspaceError extends VerificationWorkspaceState {
  const VerificationWorkspaceError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
