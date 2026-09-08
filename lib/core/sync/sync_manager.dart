import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
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
    this.lastSyncTime,
    this.lastError,
  });

  final SyncConnectivityMode mode;
  final int pendingCount;
  final DateTime? lastSyncTime;
  final String? lastError;

  SyncState copyWith({
    SyncConnectivityMode? mode,
    int? pendingCount,
    DateTime? lastSyncTime,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncState(
      mode: mode ?? this.mode,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => [mode, pendingCount, lastSyncTime, lastError];
}

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

  Future<int?> _cacheOwnerUserId() => _cacheService.getCacheOwnerUserId();

  /// Bump the session generation so an in-flight drain cannot persist the
  /// previous user's outbox after logout or an identity change.
  void invalidateSessionBoundWork() {
    _sessionEpoch++;
  }

  Future<void> refreshPendingCount() async {
    final commands = await _cacheService.getOutboxCommands();
    final pending = commands.where((c) => c.status != OutboxCommandStatus.synced).length;
    state = state.copyWith(pendingCount: pending);
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
            pendingCount: scopedCommands
                .where((c) => c.status != OutboxCommandStatus.synced)
                .length,
            lastSyncTime: DateTime.now(),
          );
          return;
        }

        final remainingCommands = <OutboxCommand>[];

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

          try {
            await _executeCommand(cmd);
            // Synced successfully - omit from remaining outbox
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
        final activePending = remainingCommands.where((c) => c.status == OutboxCommandStatus.pending).length;

        state = state.copyWith(
          mode: activePending == 0 ? SyncConnectivityMode.online : SyncConnectivityMode.offline,
          pendingCount: remainingCommands.length,
          lastSyncTime: DateTime.now(),
        );
      } finally {
        _isDraining = false;
      }
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
        await _apiService.uploadRecordEvidence(
          cmd.entityId,
          proofJpegPath: cmd.payload['proof_path'] as String?,
          remarks: cmd.payload['remarks'] as String?,
          otherStaff: cmd.payload['other_staff'] as String?,
          idempotencyKey: cmd.idempotencyKey,
        );
        break;
    }
  }
}
