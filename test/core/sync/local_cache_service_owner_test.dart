import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Regression tests for the C1 audit finding: the real LocalCacheService's
  // static _lastGoodOutbox snapshot must never resurrect a wiped (or another
  // user's) outbox after sign-out on a shared device.
  group('LocalCacheService clearAllCache + outbox resurrection', () {
    test('clearAllCache resets the in-memory last-good outbox', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = LocalCacheService(prefs);

      final cmd = OutboxCommand(
        idempotencyKey: 'user_a_key',
        type: OutboxCommandType.submitLine,
        entityId: 1,
        payload: const {'line_id': 1},
        createdAt: DateTime.now(),
        ownerUserId: 7,
      );
      await service.saveOutboxCommands([cmd]);
      expect(await service.getOutboxCommands(), hasLength(1));
      await service.setCacheOwnerUserId(7);

      // Sign-out wipe.
      await service.clearAllCache();

      expect(await service.getCacheOwnerUserId(), isNull);
      // Persisted outbox is gone; the memory snapshot must not resurrect it.
      expect(await service.getOutboxCommands(), isEmpty);

      // Now a new-user login re-persists an empty/absent outbox: still empty.
      final secondService = LocalCacheService(prefs);
      expect(await secondService.getOutboxCommands(), isEmpty);
    });

    test('last-good fallback is withheld when it belongs to another owner',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = LocalCacheService(prefs);

      final cmd = OutboxCommand(
        idempotencyKey: 'user_a_key',
        type: OutboxCommandType.submitLine,
        entityId: 1,
        payload: const {'line_id': 1},
        createdAt: DateTime.now(),
        ownerUserId: 7,
      );
      await service.saveOutboxCommands([cmd]);
      // Owner stamped after login of user A: memory now holds user A's outbox.
      await service.setCacheOwnerUserId(7);

      // Simulate user B's session wiping the persisted store directly
      // (corrupt top-level / cleared by another path) and re-stamping the
      // owner to user B, without clearAllCache resetting memory.
      await prefs.remove('gssms_cache_outbox_commands');
      await prefs.remove('gssms_cache_outbox_commands_bak');
      await prefs.setInt('gssms_cache_owner_user_id', 42);
      final foreign = await service.getOutboxCommands();
      expect(foreign, isEmpty,
          reason: 'user A outbox must not leak into user B\'s session');

      // Same-owner reads still get the memory fallback (corrupt recovery).
      final own = LocalCacheService(prefs);
      final freshCmd = OutboxCommand(
        idempotencyKey: 'user_b_key',
        type: OutboxCommandType.submitLine,
        entityId: 2,
        payload: const {'line_id': 2},
        createdAt: DateTime.now(),
        ownerUserId: 42,
      );
      await own.saveOutboxCommands([freshCmd]);
      expect(await own.getOutboxCommands(), hasLength(1));
    });

    test('persisted owner=none with ownerless memory commands is withheld',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = LocalCacheService(prefs);

      final cmd = OutboxCommand(
        idempotencyKey: 'legacy_key',
        type: OutboxCommandType.submitLine,
        entityId: 3,
        payload: const {'line_id': 3},
        createdAt: DateTime.now(),
        // ownerUserId deliberately null (legacy command).
      );
      await service.saveOutboxCommands([cmd]);

      // Owner never stamped (pre-login state): do not drain stale commands.
      await prefs.remove('gssms_cache_outbox_commands');
      expect(await service.getOutboxCommands(), isEmpty);
    });
  });
}
