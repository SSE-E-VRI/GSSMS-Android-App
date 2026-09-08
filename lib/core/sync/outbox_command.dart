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

  static OutboxCommandType? fromCode(String code) {
    for (final t in OutboxCommandType.values) {
      if (t.code == code) return t;
    }
    return null;
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
    this.ownerUserId,
  });

  final String idempotencyKey;
  final OutboxCommandType type;
  final int entityId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final String? lastError;
  final OutboxCommandStatus status;

  /// JWT `user_id` of the session that queued this mutation. Commands without
  /// an owner, or owned by a different user, are never replayed.
  final int? ownerUserId;

  OutboxCommand copyWith({
    int? retryCount,
    String? lastError,
    OutboxCommandStatus? status,
    int? ownerUserId,
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
      ownerUserId: ownerUserId ?? this.ownerUserId,
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
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
    };
  }

  factory OutboxCommand.fromJson(Map<String, dynamic> json) {
    final typeCode = json['type']?.toString();
    final parsedType = typeCode != null ? OutboxCommandType.fromCode(typeCode) : null;
    if (parsedType == null) {
      throw FormatException('Unknown or missing outbox command type: ${json['type']}');
    }

    final rawCreatedAt = json['created_at'];
    final createdAt = rawCreatedAt is String
        ? (DateTime.tryParse(rawCreatedAt) ?? DateTime.now())
        : DateTime.now();

    final entityIdRaw = json['entity_id'];
    final entityId = entityIdRaw is int ? entityIdRaw : (int.tryParse('$entityIdRaw') ?? 0);

    final rawIdempotencyKey = json['idempotency_key']?.toString();
    final idempotencyKey = (rawIdempotencyKey == null || rawIdempotencyKey.isEmpty)
        // Legacy outbox command persisted before idempotencyKey existed —
        // synthesize a key unique to this command so it can't collide with
        // another legacy command's empty key on the server's dedup check.
        ? 'legacy_${typeCode}_${entityId}_${createdAt.millisecondsSinceEpoch}'
        : rawIdempotencyKey;

    final ownerRaw = json['owner_user_id'];
    final ownerUserId =
        ownerRaw is int ? ownerRaw : int.tryParse('$ownerRaw');

    return OutboxCommand(
      idempotencyKey: idempotencyKey,
      type: parsedType,
      entityId: entityId,
      payload: json['payload'] is Map ? Map<String, dynamic>.from(json['payload'] as Map) : {},
      createdAt: createdAt,
      retryCount: json['retry_count'] is int ? json['retry_count'] as int : (int.tryParse('${json['retry_count']}') ?? 0),
      lastError: json['last_error']?.toString(),
      status: OutboxCommandStatus.fromCode(json['status']?.toString() ?? 'PENDING'),
      ownerUserId: ownerUserId,
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
        ownerUserId,
      ];
}
