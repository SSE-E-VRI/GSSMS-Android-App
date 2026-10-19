import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/deficiency_severity_option.dart';
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
    this.severities = const [],
    this.isMutating = false,
  });

  final VerificationWorkspace workspace;
  final bool isSubmitting;

  /// Active deficiency severities for the triage dropdown / flag dialog.
  final List<DeficiencySeverityOption> severities;

  /// True while a severity / flag / un-check request is in flight.
  final bool isMutating;

  VerificationWorkspaceLoaded copyWith({
    VerificationWorkspace? workspace,
    bool? isSubmitting,
    List<DeficiencySeverityOption>? severities,
    bool? isMutating,
  }) {
    return VerificationWorkspaceLoaded(
      workspace: workspace ?? this.workspace,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      severities: severities ?? this.severities,
      isMutating: isMutating ?? this.isMutating,
    );
  }

  @override
  List<Object?> get props => [workspace, isSubmitting, severities, isMutating];
}

class VerificationWorkspaceError extends VerificationWorkspaceState {
  const VerificationWorkspaceError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
