import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/data/pending_execution_photo_store.dart';
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

  // M6: backoff for automatic (resume-triggered) drains. Every failed
  // offline drain pushes connectivity re-checks further out so a device
  // leaving coverage cannot burn the auto-retry cap with app resumes.
  DateTime _offlineBackoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int _offlineStrikes = 0;

  @override
  SyncState build() {
    // Initial sync count check — guarded so a startup storage error
    // never surfaces as an unhandled async exception.
    Future.microtask(() async {
      try {
        await refreshPendingCount();
      } catch (_) {}
    });
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
  /// HTTP statuses that mean "try again later", not "this command is bad".
  static bool _isTransientHttp(int? status) =>
      status == 408 ||
      status == 429 ||
      status == 502 ||
      status == 503 ||
      status == 504;

  /// Numeric `Retry-After` (seconds) on 429/503, capped at 480s.
  static int? _retryAfterSeconds(DioException e) {
    final status = e.response?.statusCode;
    if (status != 429 && status != 503) return null;
    final raw = e.response?.headers.value('retry-after');
    final secs = int.tryParse(raw?.trim() ?? '');
    if (secs == null || secs < 0) return null;
    return secs > 480 ? 480 : secs;
  }

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

    // A record must not close server-side while its line observations or a
    // line attachment are still queued/unsynced — the observations that
    // justify the completion could later FAIL, and a completed record may
    // reject them (M8 audit fix). Terminal status transitions get the same
    // rule so a closure can never overtake pending line work for the
    // same/linked entity.
    final transitionStatus = asJsonString(cmd.payload['status'])?.toUpperCase();
    final isTerminalTransition =
        cmd.type == OutboxCommandType.transitionStatus &&
            (transitionStatus == 'TECH_COMPLETED' ||
                transitionStatus == 'VERIFIED' ||
                transitionStatus == 'CLOSED');
    if (cmd.type == OutboxCommandType.completeRecord || isTerminalTransition) {
      final hasUnsyncedLineWork = scopedCommands.any((c) =>
          (c.type == OutboxCommandType.submitLine ||
              c.type == OutboxCommandType.uploadLineAttachment) &&
          c.entityId == cmd.entityId &&
          !syncedKeys.contains(c.idempotencyKey));
      if (hasUnsyncedLineWork) return true;
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

    unawaited(previous.then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    }, onError: (_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    }));

    return completer.future;
  }

  Future<void> enqueueCommand(OutboxCommand command,
      {bool autoDrain = true}) async {
    await _synchronized(() async {
      final ownerId = command.ownerUserId ?? await _cacheOwnerUserId();
      final stamped =
          ownerId == null ? command : command.copyWith(ownerUserId: ownerId);
      final commands = [...await _cacheService.getOutboxCommands()];
      commands.add(stamped);
      await _cacheService.saveOutboxCommands(commands);
      await refreshPendingCount();
    });

    // Trigger sync attempt immediately
    if (autoDrain) {
      await drainOutbox();
    }
  }

  /// Atomically enqueues [command], replacing pending line assignments with
  /// their latest value and deduplicating other pending commands.
  ///
  /// The dedup read, check and save all run inside `_synchronized`, closing
  /// the check-then-act race in which two near-simultaneous calls both read
  /// the outbox before either save lands and both enqueue the same logical
  /// write under different idempotency keys (double-tap offline).
  ///
  /// Returns true when persisted (including replacement), false on dedup-hit.
  Future<bool> enqueueDeduped(
    OutboxCommand command, {
    required bool Function(OutboxCommand existing) isDuplicate,
    bool autoDrain = true,
  }) {
    return _synchronized(() async {
      final ownerId = command.ownerUserId ?? await _cacheOwnerUserId();
      final stamped =
          ownerId == null ? command : command.copyWith(ownerUserId: ownerId);
      final commands = [...await _cacheService.getOutboxCommands()];
      // Line autosaves are assignments: keep the latest payload, not the
      // first character typed. Use the new operation's key, never associate
      // a changed payload with a key that may already have reached the server.
      // The drain holds this same lock through acknowledgment/persistence, so
      // an in-flight acknowledgment cannot remove this replacement.
      final matching = commands
          .where((c) =>
              c.ownerUserId == stamped.ownerUserId &&
              c.status == OutboxCommandStatus.pending &&
              isDuplicate(c))
          .toList();
      final isDup = matching.isNotEmpty;
      if (isDup && stamped.type == OutboxCommandType.submitLine) {
        if (matching.length == 1 &&
            mapEquals(matching.single.payload, stamped.payload)) {
          return false;
        }
        final index = commands.indexOf(matching.first);
        commands.removeWhere(matching.contains);
        commands.insert(index, stamped);
        await _cacheService.saveOutboxCommands(commands);
        await refreshPendingCount();
        return true;
      }
      if (isDup) return false;
      commands.add(stamped);
      await _cacheService.saveOutboxCommands(commands);
      await refreshPendingCount();
      return true;
    }).then((enqueued) async {
      if (autoDrain && enqueued) {
        await drainOutbox();
      }
      return enqueued;
    });
  }

  Future<void> drainOutbox() async {
    final auth = ref.read(authControllerProvider);
    if (auth is Authenticated && auth.session.isOffline) return;
    // Set the guard synchronously (no `await` before it) so a second call
    // arriving before this one's queued action even starts can't slip past
    // the check and queue a redundant drain behind it.
    if (_isDraining) return;
    _isDraining = true;

    await _synchronized(() async {
      final epoch = _sessionEpoch;
      state =
          state.copyWith(mode: SyncConnectivityMode.syncing, clearError: true);

      try {
        if (epoch != _sessionEpoch) {
          return;
        }

        final commands = await _cacheService.getOutboxCommands();
        final actorUserId = await _cacheOwnerUserId();
        final scopedCommands = actorUserId == null
            ? commands
            : commands.where((c) => c.ownerUserId == actorUserId).toList();
        // Never drop another user's queued commands: they stay untouched
        // while this session drains only its own scope.
        final unscopedCommands = actorUserId == null
            ? const <OutboxCommand>[]
            : commands.where((c) => c.ownerUserId != actorUserId).toList();
        Future<void> persistScoped(List<OutboxCommand> scoped) =>
            _cacheService.saveOutboxCommands([...unscopedCommands, ...scoped]);
        final pendingCommands = scopedCommands
            .where((c) => c.status == OutboxCommandStatus.pending)
            .toList();

        if (pendingCommands.isEmpty) {
          // Epoch changed (logout/identity switch): return without writing
          // so we never persist the previous user's outbox view.
          if (epoch != _sessionEpoch) return;
          // Low 7/8/10: no silent eviction on automatic drains; FAILED/CONFLICT
          // commands are only removed by explicit user discard. Counts come
          // from the full persisted list (this user's scope plus other
          // users' untouched commands), so the badge never reports
          // fully-synced while stuck work remains on disk.
          await persistScoped(scopedCommands);
          final fullPersisted = [...unscopedCommands, ...scopedCommands];
          state = state.copyWith(
            mode: SyncConnectivityMode.online,
            pendingCount: _countQueued(fullPersisted),
            attentionCount: _countNeedsAttention(fullPersisted),
            lastSyncTime: DateTime.now(),
          );
          return;
        }

        final remainingCommands = <OutboxCommand>[];
        final syncedKeys = <String>{};
        // True only when the loop stopped on a network failure or a transient
        // HTTP status (408/429/502/503/504).
        var hitConnectivity = false;

        for (var i = 0; i < scopedCommands.length; i++) {
          // Epoch changed mid-drain: abort without persisting anything.
          if (epoch != _sessionEpoch) return;
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
            // Update the owner-scoped offline read model before retiring the
            // acknowledged command. A cache-write failure leaves it in the
            // outbox for safe idempotent replay instead of showing stale data.
            if (cmd.type == OutboxCommandType.submitLine &&
                actorUserId != null && cmd.ownerUserId == actorUserId &&
                epoch == _sessionEpoch) {
              await _reconcileAcknowledgedLine(cmd);
            }
            // Synced successfully - track key and omit from remaining outbox
            syncedKeys.add(cmd.idempotencyKey);
          } on DioException catch (dioErr) {
            final errStr = dioErr.toString().toLowerCase();
            final isNetwork =
                dioErr.type == DioExceptionType.connectionTimeout ||
                    dioErr.type == DioExceptionType.connectionError ||
                    dioErr.type == DioExceptionType.receiveTimeout ||
                    dioErr.type == DioExceptionType.sendTimeout ||
                    (dioErr.type == DioExceptionType.unknown &&
                        dioErr.error is SocketException) ||
                    errStr.contains('socketexception') ||
                    errStr.contains('network is unreachable');

            final statusCode = dioErr.response?.statusCode;
            final isTransient = _isTransientHttp(statusCode);
            if (isNetwork || isTransient) {
              hitConnectivity = true;
              final reason = isNetwork ? 'Network offline.' : 'Server busy.';
              // Keep command in pending state and pause outbox draining.
              // Cap retries so an always-offline queue cannot grow its
              // retryCount unboundedly; after the cap it parks as FAILED
              // for the user to retry explicitly. The backoff in
              // [resumePendingSync] means the cap is only reached after
              // real spread-out attempts, not twenty consecutive app resumes.
              const maxAutoRetries = 25;
              if (cmd.retryCount >= maxAutoRetries) {
                remainingCommands.add(cmd.copyWith(
                  status: OutboxCommandStatus.failed,
                  lastError: '$reason Retry limit reached — tap retry.',
                ));
              } else {
                remainingCommands.add(cmd.copyWith(
                  retryCount: cmd.retryCount + 1,
                  lastError: '$reason Will retry automatically.',
                ));
              }
              remainingCommands.addAll(scopedCommands.sublist(i + 1));
              state = state.copyWith(
                mode: SyncConnectivityMode.offline,
                lastError: '$reason Queued for background sync.',
              );
              _offlineStrikes = (_offlineStrikes + 1).clamp(0, 4);
              final computed = 30 << _offlineStrikes;
              final backoffSeconds = _retryAfterSeconds(dioErr) ??
                  (computed > 480 ? 480 : computed);
              _offlineBackoffUntil = DateTime.now().add(
                Duration(seconds: backoffSeconds),
              );
              break;
            }

            // lastError is shown to the user (per-photo sync badge), so it
            // gets the same user-facing text as every other error — never the
            // raw response body, which can be an HTML proxy page.
            if (statusCode == 409) {
              remainingCommands.add(cmd.copyWith(
                status: OutboxCommandStatus.conflict,
                lastError: userFacingError(dioErr),
              ));
            } else {
              // Unrecoverable validation or server error
              remainingCommands.add(cmd.copyWith(
                status: OutboxCommandStatus.failed,
                lastError: userFacingError(dioErr),
              ));
            }
          } catch (e) {
            remainingCommands.add(cmd.copyWith(
              status: OutboxCommandStatus.failed,
              lastError: userFacingError(e),
            ));
          }
        }

        if (epoch != _sessionEpoch) {
          return;
        }
        final prunedRemaining = remainingCommands;
        // Persist first, discard evidence files only afterwards: a crash
        // between discard and persist must never leave a replay pointing
        // at a missing file (permanent FAILED).
        await persistScoped(prunedRemaining);
        if (epoch != _sessionEpoch) return;
        // Discard evidence for commands that just synced successfully.
        final syncedIds = syncedKeys;
        if (syncedIds.isNotEmpty) {
          final syncedFilePaths = <String>{};
          for (final cmd in scopedCommands) {
            if (!syncedIds.contains(cmd.idempotencyKey)) continue;
            final fp = cmd.payload['file_path']?.toString();
            if (fp != null && fp.isNotEmpty) syncedFilePaths.add(fp);
            final pp = cmd.payload['proof_path']?.toString();
            if (pp != null && pp.isNotEmpty) syncedFilePaths.add(pp);
          }
          for (final p in syncedFilePaths) {
            try {
              await _evidenceService.discard(p);
            } catch (_) {}
          }
        }
        // Retention sweep: delete expired local evidence, never files that
        // are still queued for upload. Compare canonical absolute paths so
        // a symlink/relative mismatch cannot delete a queued photo.
        final queuedPaths = <String>{};
        // Include other owners' queued commands too: their files must never be
        // swept by this session's retention pass.
        for (final cmd in [...prunedRemaining, ...unscopedCommands]) {
          final filePath = cmd.payload['file_path']?.toString();
          if (filePath != null && filePath.isNotEmpty) {
            queuedPaths.add(_canonicalPath(filePath));
          }
          final proofPath = cmd.payload['proof_path']?.toString();
          if (proofPath != null && proofPath.isNotEmpty) {
            queuedPaths.add(_canonicalPath(proofPath));
          }
        }
        try {
          // Breakdown photos waiting for Save Progress live outside the
          // outbox; sweeping them would silently lose unsaved evidence.
          for (final p in await PendingExecutionPhotoStore.allReferencedPaths()) {
            queuedPaths.add(_canonicalPath(p));
          }
          await _evidenceService.cleanupExpiredEvidence(
            excludePaths: queuedPaths,
          );
        } catch (_) {}
        final queued = _countQueued(prunedRemaining);
        if (queued == 0) {
          // A drain that ended with an empty queue proves connectivity.
          _offlineStrikes = 0;
          _offlineBackoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
        }

        // Low 8/10: badge counts from the full persisted list (this user's
        // scope plus other users' untouched commands) — isFullySynced cannot
        // pass while stuck work is still on disk.
        final persistedAll = [...unscopedCommands, ...prunedRemaining];
        state = state.copyWith(
          mode: hitConnectivity
              ? SyncConnectivityMode.offline
              : SyncConnectivityMode.online,
          pendingCount: _countQueued(persistedAll),
          attentionCount: _countNeedsAttention(persistedAll),
          lastSyncTime: DateTime.now(),
        );
      } finally {
        _isDraining = false;
        if (epoch != _sessionEpoch &&
            state.mode == SyncConnectivityMode.syncing) {
          state = state.copyWith(mode: SyncConnectivityMode.online);
        }
      }
    });
  }

  /// Opportunistic drain for app start, sign-in and resume-from-background.
  ///
  /// Without it, work queued before a restart (or while the phone was out of
  /// coverage) sat in the outbox until the user happened to create another
  /// mutation or tapped the sync strip. Only PENDING commands replay —
  /// FAILED/CONFLICT still wait for the user — and every command carries its
  /// idempotency key, so an extra drain cannot duplicate a server mutation.
  ///
  /// M6: while a connectivity failure has placed the manager in backoff,
  /// resume-triggered drains are skipped so repeated app resumes (commute,
  /// dead coverage) do not burn the 25-attempt auto-retry cap without any
  /// real network attempts in between. Explicit user action (`retryCommand`,
  /// `retryAllFailed`, badge tap) still drains immediately.
  Future<void> resumePendingSync({bool skipBackoffGate = false}) async {
    try {
      await refreshPendingCount();
      if (state.pendingCount == 0) return;
      if (!skipBackoffGate && DateTime.now().isBefore(_offlineBackoffUntil)) {
        return;
      }
      await drainOutbox();
    } catch (_) {
      // Storage unavailable (tests, early start-up): the next trigger retries.
    }
  }

  /// Retries a previously failed or conflicting command by resetting it to pending.
  Future<void> retryCommand(String idempotencyKey) async {
    await _synchronized(() async {
      final commands = await _cacheService.getOutboxCommands();
      final updated = commands.map((c) {
        if (c.idempotencyKey == idempotencyKey) {
          return c.copyWith(
            status: OutboxCommandStatus.pending,
            // M7: an explicit user retry must get a fresh auto-retry budget —
            // a capped command otherwise re-fails after a single attempt.
            retryCount: 0,
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
                  // M7: fresh auto-retry budget on an explicit retry-all too.
                  retryCount: 0,
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
      final commands = [...await _cacheService.getOutboxCommands()];
      commands.removeWhere((c) => c.idempotencyKey == idempotencyKey);
      await _cacheService.saveOutboxCommands(commands);
      await refreshPendingCount();
    });
  }

  String _canonicalPath(String path) {
    try {
      return File(path).absolute.path;
    } catch (_) {
      return path;
    }
  }

  /// Mirrors an acknowledged line assignment into the saved offline record.
  /// The same serialized drain lock protects the queue and cache update.
  Future<void> _reconcileAcknowledgedLine(OutboxCommand cmd) async {
    final cached = await _cacheService.getCachedMaintenanceRecord(cmd.entityId);
    if (cached == null) return;
    final lineId = asJsonInt(cmd.payload['line_id']);
    if (lineId == null || !cached.lines.any((line) => line.id == lineId)) return;
    final updated = cached.lines.map((line) {
      if (line.id != lineId) return line;
      return line.copyWith(
        recordedValue: cmd.payload['value'],
        status: asJsonString(cmd.payload['status']) ?? line.status,
        statusOptionId: asJsonInt(cmd.payload['status_option']),
        actionOptionId: asJsonInt(cmd.payload['action_option']),
        isSaved: true,
        localSyncStatus: null,
      );
    }).toList();
    await _cacheService.cacheMaintenanceRecord(cached.copyWith(lines: updated));
  }

  Future<void> _executeCommand(OutboxCommand cmd) async {
    // NOTE: evidence files are discarded by drainOutbox *after* the outbox
    // persist, never here — see drainOutbox. Discarding here would leave a
    // replay pointing at a missing file if the app crashed before saving.
    switch (cmd.type) {
      case OutboxCommandType.submitLine:
        await _apiService.submitLine(
          cmd.entityId,
          cmd.payload,
          idempotencyKey: cmd.idempotencyKey,
        );
        break;
      case OutboxCommandType.transitionStatus:
        final status = asJsonString(cmd.payload['status']);
        if (status == null || status.isEmpty) {
          throw const FormatException(
              'Missing status in transitionStatus payload');
        }
        final rawChecklist = cmd.payload['checklist'];
        final checklist = rawChecklist is Map
            ? Map<String, dynamic>.from(rawChecklist)
            : null;
        final rawEvidence = cmd.payload['evidence'];
        final evidence = rawEvidence is List
            ? rawEvidence.map((e) => asJsonInt(e)).whereType<int>().toList()
            : null;
        await _apiService.changeStatus(
          cmd.entityId,
          status: status,
          remarks: asJsonString(cmd.payload['remarks']),
          checklist: checklist,
          evidence: evidence,
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
          technicianName: asJsonString(cmd.payload['technician_name']) ?? '',
          remarks: asJsonString(cmd.payload['remarks']) ?? '',
          supervisorName: asJsonString(cmd.payload['supervisor_name']),
          idempotencyKey: cmd.idempotencyKey,
        );
        break;
      case OutboxCommandType.uploadEvidence:
        final proofPath = asJsonString(cmd.payload['proof_path']);
        await _apiService.uploadRecordEvidence(
          cmd.entityId,
          proofJpegPath: proofPath,
          remarks: asJsonString(cmd.payload['remarks']),
          otherStaff: asJsonString(cmd.payload['other_staff']),
          idempotencyKey: cmd.idempotencyKey,
        );
        break;
      case OutboxCommandType.uploadLineAttachment:
        final filePath = asJsonString(cmd.payload['file_path']);
        if (filePath == null || filePath.isEmpty) {
          throw const FormatException(
              'Missing file_path in line attachment payload');
        }
        final lineId = asJsonInt(cmd.payload['line_id']);
        if (lineId == null) {
          throw const FormatException(
              'Missing line_id in line attachment payload');
        }
        final kind = asJsonString(cmd.payload['kind']);
        if (kind == null || kind.isEmpty) {
          throw const FormatException(
              'Missing kind in line attachment payload');
        }
        final capturedAtStr = asJsonString(cmd.payload['captured_at']);
        final capturedAt =
            capturedAtStr != null ? DateTime.tryParse(capturedAtStr) : null;
        // ME-02/ME-04: provenance was frozen when the command was enqueued —
        // replay it verbatim. Never re-derive `captured_at` or take a fresh
        // GPS fix during sync; sync-time location would be a substitution.
        final source =
            asJsonString(cmd.payload['source'])?.toUpperCase() ?? 'UNKNOWN';
        final latitude = asJsonDouble(cmd.payload['latitude']);
        final longitude = asJsonDouble(cmd.payload['longitude']);
        final accuracyM = asJsonDouble(cmd.payload['location_accuracy_m']);
        final recordedStr = asJsonString(cmd.payload['location_recorded_at']);
        final recordedAt =
            recordedStr != null ? DateTime.tryParse(recordedStr) : null;
        await _apiService.uploadLineAttachment(
          cmd.entityId,
          lineId: lineId,
          kind: kind,
          imagePath: filePath,
          capturedAt: capturedAt,
          source: source,
          latitude: latitude,
          longitude: longitude,
          locationAccuracyM: accuracyM,
          locationRecordedAt: recordedAt,
          idempotencyKey: cmd.idempotencyKey,
        );
        break;
    }
  }
}
