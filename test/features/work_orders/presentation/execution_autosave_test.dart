import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/execution_autosave.dart';

const _delay = Duration(milliseconds: 20);
Future<void> _wait([int ms = 80]) => Future.delayed(Duration(milliseconds: ms));

void main() {
  group('ExecutionAutosaveController', () {
    test('flush waits for edits made while its save is in flight', () async {
      var saves = 0;
      final first = Completer<void>();
      final second = Completer<void>();
      final c = ExecutionAutosaveController(
        delay: const Duration(seconds: 5),
        save: () async {
          saves++;
          await (saves == 1 ? first.future : second.future);
        },
      );
      c.markEdited();
      var finished = false;
      final flush = c.flush().then((ok) {
        finished = true;
        return ok;
      });
      c.markEdited();
      first.complete();
      await _wait(20);
      expect(saves, 2);
      expect(finished, isFalse);
      second.complete();
      expect(await flush, isTrue);
      expect(c.isDirty, isFalse);
      c.dispose();
    });

    test('several edits within the delay produce one save', () async {
      var saves = 0;
      final c = ExecutionAutosaveController(
        delay: _delay,
        save: () async => saves++,
      );
      c.markEdited();
      c.markEdited();
      c.markEdited();
      await _wait();
      expect(saves, 1);
      expect(c.isDirty, isFalse);
      expect(c.status, AutosaveStatus.saved);
      c.dispose();
      expect(saves, 1);
    });

    test('an edit during an in-flight save produces exactly two saves',
        () async {
      var saves = 0;
      final gate = Completer<void>();
      final c = ExecutionAutosaveController(
        delay: _delay,
        save: () async {
          saves++;
          if (saves == 1) await gate.future;
        },
      );
      c.markEdited();
      await _wait(40); // first save now in flight
      expect(c.isSaving, isTrue);
      c.markEdited();
      await _wait(40); // timer fired while in flight: must not start another
      expect(saves, 1);
      gate.complete();
      await _wait(100);
      expect(saves, 2);
      expect(c.isDirty, isFalse);
      c.dispose();
    });

    test('a failed save keeps the form dirty and flush returns false',
        () async {
      final c = ExecutionAutosaveController(
        delay: _delay,
        save: () async => throw Exception('boom'),
      );
      c.markEdited();
      await _wait();
      expect(c.status, AutosaveStatus.error);
      expect(c.isDirty, isTrue);
      expect(await c.flush(), isFalse);
      c.markSubmitted();
      c.dispose();
    });

    test('after markSubmitted no save happens', () async {
      var saves = 0;
      final c = ExecutionAutosaveController(
        delay: _delay,
        save: () async => saves++,
      );
      c.markEdited();
      c.markSubmitted();
      await _wait();
      expect(await c.flush(manual: true), isTrue);
      c.dispose();
      expect(saves, 0);
    });

    test('dispose while dirty calls save once', () async {
      var saves = 0;
      final c = ExecutionAutosaveController(
        delay: const Duration(seconds: 5),
        save: () async => saves++,
      );
      c.markEdited();
      c.dispose();
      await _wait(20);
      expect(saves, 1);
    });
  });
}
