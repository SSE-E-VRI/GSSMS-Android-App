import 'package:equatable/equatable.dart';

enum OutboxCommandType {
  submitLine('SUBMIT_LINE'),
  transitionStatus('TRANSITION_STATUS'),
  startExecution('START_EXECUTION'),
  completeRecord('COMPLETE_RECORD'),

  /// Proof-of-execution photo upload. Its payload carries the path of a file
  /// copied into the app's documents directory, so the queued upload still has
  /// its image after the OS clears picker caches.
  uploadEvidence('UPLOAD_EVIDENCE');

  const OutboxCommandType(this.code);
  final String code;

  static OutboxCommandType fromCode(String code) {
    for (final t in OutboxCommandType.values) {
      if (t.code == code) return t;
    }
    return OutboxCommandType.submitLine;
  }
}

enum OutboxCommandStatus {
  draft('DRAFT'),
  pending('PENDING'),
  syncing('SYNCING'),
  failed('FAILED'),
  conflict('CONFLICT'),
  synced('SYNCED');

  const OutboxCommandStatus(this.code);
  final String code;

  static OutboxCommandStatus fromCode(String code) {
    for (final s in OutboxCommandStatus.values) {
      if (s.code == code) return s;
    }
    return OutboxCommandStatus.pending;
  }
}

class OutboxCommand extends Equatable {
  const OutboxCommand({
    required this.idempotencyKey,
    required this.type,
    required this.entityId,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.lastError,
    this.status = OutboxCommandStatus.pending,
  });

  final String idempotencyKey;
  final OutboxCommandType type;
  final int entityId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final String? lastError;
  final OutboxCommandStatus status;

  OutboxCommand copyWith({
    int? retryCount,
    String? lastError,
    OutboxCommandStatus? status,
  }) {
    return OutboxCommand(
      idempotencyKey: idempotencyKey,
      type: type,
      entityId: entityId,
      payload: payload,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idempotency_key': idempotencyKey,
      'type': type.code,
      'entity_id': entityId,
      'payload': payload,
      'created_at': createdAt.toIso8601String(),
      'retry_count': retryCount,
      'last_error': lastError,
      'status': status.code,
    };
  }

  factory OutboxCommand.fromJson(Map<String, dynamic> json) {
    return OutboxCommand(
      idempotencyKey: json['idempotency_key'] as String,
      type: OutboxCommandType.fromCode(json['type'] as String),
      entityId: json['entity_id'] as int,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      createdAt: DateTime.parse(json['created_at'] as String),
      retryCount: json['retry_count'] as int? ?? 0,
      lastError: json['last_error'] as String?,
      status: OutboxCommandStatus.fromCode(json['status'] as String? ?? 'PENDING'),
    );
  }

  @override
  List<Object?> get props => [
        idempotencyKey,
        type,
        entityId,
        payload,
        createdAt,
        retryCount,
        lastError,
        status,
      ];
}
