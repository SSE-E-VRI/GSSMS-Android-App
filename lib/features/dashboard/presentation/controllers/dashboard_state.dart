import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/features/dashboard/domain/models/dashboard_models.dart';

sealed class DashboardState extends Equatable {
  const DashboardState();

  @override
  List<Object?> get props => [];
}

class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

class DashboardLoaded extends DashboardState {
  const DashboardLoaded({
    required this.attention,
    required this.summary,
  });

  final AttentionSummary attention;
  final DashboardSummary summary;

  DashboardLoaded copyWith({
    AttentionSummary? attention,
    DashboardSummary? summary,
  }) {
    return DashboardLoaded(
      attention: attention ?? this.attention,
      summary: summary ?? this.summary,
    );
  }

  @override
  List<Object?> get props => [attention, summary];
}

class DashboardError extends DashboardState {
  const DashboardError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
