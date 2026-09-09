import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';

enum SyncConnectivityMode {
  online('Online'),
  offline('Offline'),
  syncing('Syncing');

  const SyncConnectivityMode(this.label);
  final String label;
}

class SyncState extends Equatable {
  const SyncState({
    this.mode = SyncConnectivityMode.online,
    this.pendingCount = 0,
    this.attentionCount = 0,
    this.lastSyncTime,
    this.lastError,
  });

  final SyncConnectivityMode mode;

  /// Commands that will still sync on their own: status PENDING or SYNCING.
  ///
  /// Deliberately excludes FAILED and CONFLICT. Those never drain without the
  /// user acting, so counting them here would leave the offline banner up
  /// forever on an online, idle app — see [attentionCount].
  final int pendingCount;

  /// Commands stuck in FAILED or CONFLICT that need the user to retry or
  /// discard them.
  final int attentionCount;

  final DateTime? lastSyncTime;
  final String? lastError;

  /// True when nothing is queued and nothing is stuck.
  bool get isFullySynced => pendingCount == 0 && attentionCount == 0;

  SyncState copyWith({
    SyncConnectivityMode? mode,
    int? pendingCount,
    int? attentionCount,
    DateTime? lastSyncTime,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncState(
      mode: mode ?? this.mode,
      pendingCount: pendingCount ?? this.pendingCount,
      attentionCount: attentionCount ?? this.attentionCount,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props =>
      [mode, pendingCount, attentionCount, lastSyncTime, lastError];
}

/// Counts commands that still drain on their own.
int _countQueued(Iterable<OutboxCommand> commands) => commands
    .where((c) =>
        c.status == OutboxCommandStatus.pending ||
        c.status == OutboxCommandStatus.syncing)
    .length;

/// Counts commands that cannot drain without the user acting.
int _countNeedsAttention(Iterable<OutboxCommand> commands) => commands
    .where((c) =>
        c.status == OutboxCommandStatus.failed ||
        c.status == OutboxCommandStatus.conflict)
    .length;

final localCacheServiceProvider = Provider<ILocalCacheService>((ref) {
  return LocalCacheService();
});

final syncManagerProvider = NotifierProvider<SyncManager, SyncState>(() {
  return SyncManager();
});

class SyncManager extends Notifier<SyncState> {
  bool _isDraining = false;
  Future<void> _lock = Future.value();
  int _sessionEpoch = 0;

  @override
  SyncState build() {
    // Initial sync count check
    Future.microtask(() => refreshPendingCount());
    return const SyncState();
  }

  ILocalCacheService get _cacheService => ref.read(localCacheServiceProvider);
  WorkOrderApiService get _apiService => ref.read(workOrderApiServiceProvider);
  EvidenceService get _evidenceService => ref.read(evidenceServiceProvider);

  Future<int?> _cacheOwnerUserId() => _cacheService.getCacheOwnerUserId();

  /// Checks whether [cmd] must wait for another command in this drain.
  ///
  /// There is exactly one ordering rule, stated explicitly rather than through
  /// a general dependency field: a line attachment must never replay before
  /// `submitLine` for the same record and line has succeeded.
  ///
  /// A general `dependsOn` field used to exist here but nothing ever populated
  /// it, so it read as a safety mechanism while enforcing nothing. If another
  /// command type ever needs ordering, add its rule below — and a test — so
  /// the guarantee stays visible in one place.
  bool _hasUnsyncedDependency(
    OutboxCommand cmd,
    List<OutboxCommand> scopedCommands,
    Set<String> syncedKeys,
  ) {
    if (cmd.type == OutboxCommandType.uploadLineAttachment) {
      final lineId = cmd.payload['line_id'];
      if (lineId != null) {
        final hasUnsyncedSubmitLine = scopedCommands.any((c) =>
            c.type == OutboxCommandType.submitLine &&
            c.entityId == cmd.entityId &&
            c.payload['line_id'] == lineId &&
            !syncedKeys.contains(c.idempotencyKey));
        if (hasUnsyncedSubmitLine) return true;
      }
    }

    return false;
  }

  /// Bump the session generation so an in-flight drain cannot persist the
  /// previous user's outbox after logout or an identity change.
  void invalidateSessionBoundWork() {
    _sessionEpoch++;
  }

  Future<void> refreshPendingCount() async {
    final commands = await _cacheService.getOutboxCommands();
    state = state.copyWith(
      pendingCount: _countQueued(commands),
      attentionCount: _countNeedsAttention(commands),
    );
  }

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final previous = _lock;
    final completer = Completer<T>();
    _lock = completer.future.then((_) => null, onError: (_) => null);

    previous.whenComplete(() async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });

    return completer.future;
  }

  Future<void> enqueueCommand(OutboxCommand command, {bool autoDrain = true}) async {
    await _synchronized(() async {
      final ownerId = command.ownerUserId ?? await _cacheOwnerUserId();
      final stamped =
          ownerId == null ? command : command.copyWith(ownerUserId: ownerId);
      final commands = await _cacheService.getOutboxCommands();
      commands.add(stamped);
      await _cacheService.saveOutboxCommands(commands);
      await refreshPendingCount();
    });

    // Trigger sync attempt immediately
    if (autoDrain) {
      await drainOutbox();
    }
  }

  Future<void> drainOutbox() async {
    // Set the guard synchronously (no `await` before it) so a second call
    // arriving before this one's queued action even starts can't slip past
    // the check and queue a redundant drain behind it.
    if (_isDraining) return;
    _isDraining = true;

    await _synchronized(() async {
      final epoch = _sessionEpoch;
      state = state.copyWith(mode: SyncConnectivityMode.syncing, clearError: true);

      try {
        if (epoch != _sessionEpoch) {
          return;
        }

        final commands = await _cacheService.getOutboxCommands();
        final actorUserId = await _cacheOwnerUserId();
        final scopedCommands = actorUserId == null
            ? commands
            : commands.where((c) => c.ownerUserId == actorUserId).toList();
        final pendingCommands =
            scopedCommands.where((c) => c.status == OutboxCommandStatus.pending).toList();

        if (pendingCommands.isEmpty) {
          if (epoch != _sessionEpoch) return;
          await _cacheService.saveOutboxCommands(scopedCommands);
          if (epoch != _sessionEpoch) {
            await _cacheService.saveOutboxCommands(const []);
            return;
          }
          state = state.copyWith(
            mode: SyncConnectivityMode.online,
            pendingCount: _countQueued(scopedCommands),
            attentionCount: _countNeedsAttention(scopedCommands),
            lastSyncTime: DateTime.now(),
          );
          return;
        }

        final remainingCommands = <OutboxCommand>[];
        final syncedKeys = <String>{};

        for (var i = 0; i < scopedCommands.length; i++) {
          if (epoch != _sessionEpoch) {
            remainingCommands.clear();
            break;
          }
          final cmd = scopedCommands[i];
          if (cmd.status != OutboxCommandStatus.pending) {
            remainingCommands.add(cmd);
            continue;
          }

          if (_hasUnsyncedDependency(cmd, scopedCommands, syncedKeys)) {
            remainingCommands.add(cmd);
            continue;
          }

          try {
            await _executeCommand(cmd);
            // Synced successfully - track key and omit from remaining outbox
            syncedKeys.add(cmd.idempotencyKey);
          } on DioException catch (dioErr) {
            final errStr = dioErr.toString().toLowerCase();
            final isNetwork = dioErr.type == DioExceptionType.connectionTimeout ||
                dioErr.type == DioExceptionType.connectionError ||
                dioErr.type == DioExceptionType.receiveTimeout ||
                dioErr.type == DioExceptionType.sendTimeout ||
                (dioErr.type == DioExceptionType.unknown && dioErr.error is SocketException) ||
                errStr.contains('socketexception') ||
                errStr.contains('network is unreachable');

            if (isNetwork) {
              // Keep command in pending state and pause outbox draining
              remainingCommands.add(cmd.copyWith(
                retryCount: cmd.retryCount + 1,
                lastError: 'Network offline. Will retry automatically.',
              ));
              remainingCommands.addAll(scopedCommands.sublist(i + 1));
              state = state.copyWith(
                mode: SyncConnectivityMode.offline,
                lastError: 'Network offline. Queued for background sync.',
              );
              break;
            }

            final statusCode = dioErr.response?.statusCode;
            if (statusCode == 409) {
              // Conflict
              remainingCommands.add(cmd.copyWith(
                status: OutboxCommandStatus.conflict,
                lastError: 'Conflict: ${dioErr.response?.data}',
              ));
            } else {
              // Unrecoverable validation or server error
              remainingCommands.add(cmd.copyWith(
                status: OutboxCommandStatus.failed,
                lastError: 'Failed (${dioErr.response?.statusCode}): ${dioErr.response?.data}',
              ));
            }
          } catch (e) {
            remainingCommands.add(cmd.copyWith(
              status: OutboxCommandStatus.failed,
              lastError: e.toString(),
            ));
          }
        }

        if (epoch != _sessionEpoch) {
          return;
        }
        await _cacheService.saveOutboxCommands(remainingCommands);
        if (epoch != _sessionEpoch) {
          await _cacheService.saveOutboxCommands(const []);
          return;
        }
        // Retention sweep: delete expired local evidence, never files that
        // are still queued for upload.
        final queuedPaths = <String>{};
        for (final cmd in remainingCommands) {
          final filePath = cmd.payload['file_path']?.toString();
          if (filePath != null && filePath.isNotEmpty) {
            queuedPaths.add(filePath);
          }
          final proofPath = cmd.payload['proof_path']?.toString();
          if (proofPath != null && proofPath.isNotEmpty) {
            queuedPaths.add(proofPath);
          }
        }
        try {
          await _evidenceService.cleanupExpiredEvidence(
            excludePaths: queuedPaths,
          );
        } catch (_) {}
        final queued = _countQueued(remainingCommands);

        state = state.copyWith(
          mode: queued == 0
              ? SyncConnectivityMode.online
              : SyncConnectivityMode.offline,
          pendingCount: queued,
          attentionCount: _countNeedsAttention(remainingCommands),
          lastSyncTime: DateTime.now(),
        );
      } finally {
        _isDraining = false;
      }
    });
  }

  /// Retries a previously failed or conflicting command by resetting it to pending.
  Future<void> retryCommand(String idempotencyKey) async {
    await _synchronized(() async {
      final commands = await _cacheService.getOutboxCommands();
      final updated = commands.map((c) {
        if (c.idempotencyKey == idempotencyKey) {
          return c.copyWith(
            status: OutboxCommandStatus.pending,
            clearError: true,
          );
        }
        return c;
      }).toList();
      await _cacheService.saveOutboxCommands(updated);
      await refreshPendingCount();
    });
    await drainOutbox();
  }

  /// Resets every FAILED or CONFLICT command back to pending and drains.
  ///
  /// This is the only route out of [SyncState.attentionCount] for command
  /// types with no per-item retry affordance of their own (submitLine,
  /// uploadEvidence); without it a single rejected line would leave the
  /// status banner up permanently.
  Future<void> retryAllFailed() async {
    await _synchronized(() async {
      final commands = await _cacheService.getOutboxCommands();
      final updated = commands
          .map((c) => c.status == OutboxCommandStatus.failed ||
                  c.status == OutboxCommandStatus.conflict
              ? c.copyWith(
                  status: OutboxCommandStatus.pending,
                  clearError: true,
                )
              : c)
          .toList();
      await _cacheService.saveOutboxCommands(updated);
      await refreshPendingCount();
    });
    await drainOutbox();
  }

  /// Removes a command permanently from the outbox cache (e.g. user dismissed or deleted it).
  Future<void> removeCommand(String idempotencyKey) async {
    await _synchronized(() async {
      final commands = await _cacheService.getOutboxCommands();
      commands.removeWhere((c) => c.idempotencyKey == idempotencyKey);
      await _cacheService.saveOutboxCommands(commands);
      await refreshPendingCount();
    });
  }

  Future<void> _executeCommand(OutboxCommand cmd) async {
    switch (cmd.type) {
      case OutboxCommandType.submitLine:
        await _apiService.submitLine(
          cmd.entityId,
          cmd.payload,
          idempotencyKey: cmd.idempotencyKey,
        );
        break;
      case OutboxCommandType.transitionStatus:
        await _apiService.changeStatus(
          cmd.entityId,
          status: cmd.payload['status'] as String,
          remarks: cmd.payload['remarks'] as String?,
          checklist: cmd.payload['checklist'] as Map<String, dynamic>?,
          evidence: (cmd.payload['evidence'] as List<dynamic>?)?.map((e) => e as int).toList(),
          idempotencyKey: cmd.idempotencyKey,
        );
        break;
      case OutboxCommandType.startExecution:
        await _apiService.startExecution(
          cmd.entityId,
          idempotencyKey: cmd.idempotencyKey,
        );
        break;
      case OutboxCommandType.completeRecord:
        await _apiService.completeRecord(
          cmd.entityId,
          technicianName: cmd.payload['technician_name'] as String? ?? '',
          remarks: cmd.payload['remarks'] as String? ?? '',
          supervisorName: cmd.payload['supervisor_name'] as String?,
          idempotencyKey: cmd.idempotencyKey,
        );
        break;
      case OutboxCommandType.uploadEvidence:
        final proofPath = cmd.payload['proof_path'] as String?;
        await _apiService.uploadRecordEvidence(
          cmd.entityId,
          proofJpegPath: proofPath,
          remarks: cmd.payload['remarks'] as String?,
          otherStaff: cmd.payload['other_staff'] as String?,
          idempotencyKey: cmd.idempotencyKey,
        );
        if (proofPath != null) {
          try {
            await _evidenceService.discard(proofPath);
          } catch (_) {}
        }
        break;
      case OutboxCommandType.uploadLineAttachment:
        final filePath = cmd.payload['file_path'] as String;
        final capturedAtStr = cmd.payload['captured_at'] as String?;
        final capturedAt = capturedAtStr != null ? DateTime.tryParse(capturedAtStr) : null;
        await _apiService.uploadLineAttachment(
          cmd.entityId,
          lineId: cmd.payload['line_id'] as int,
          kind: cmd.payload['kind'] as String,
          imagePath: filePath,
          capturedAt: capturedAt,
          idempotencyKey: cmd.idempotencyKey,
        );
        try {
          await _evidenceService.discard(filePath);
        } catch (_) {}
        break;
    }
  }
}
