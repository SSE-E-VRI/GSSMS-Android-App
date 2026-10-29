import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/notifications/domain/models/inbox_event.dart';

void main() {
  final valid = <String, dynamic>{
    'id': 'evt-101', 'type': 'ASSIGNMENT', 'title': 'Assigned',
    'message': 'A job was assigned', 'created_at': '2026-10-27T00:00:00Z',
    'work_order_id': 101, 'read_at': null,
  };

  test('parses an unread event', () {
    final event = InboxEvent.fromJson(valid);
    expect(event.id, 'evt-101');
    expect(event.isRead, isFalse);
    expect(event.workOrderId, 101);
  });

  test('rejects malformed event and invalid read timestamp', () {
    expect(() => InboxEvent.fromJson({...valid, 'id': ''}), throwsFormatException);
    expect(() => InboxEvent.fromJson({...valid, 'read_at': 'invalid'}), throwsFormatException);
    expect(() => InboxEvent.fromJson({...valid, 'work_order_id': -1}), throwsFormatException);
  });

  test('parses page with opaque cursor', () {
    final page = InboxPage.fromJson({'results': [valid], 'next_cursor': 'opaque-2'});
    expect(page.events, hasLength(1));
    expect(page.nextCursor, 'opaque-2');
  });

  test('rejects malformed page', () {
    expect(() => InboxPage.fromJson({'results': 'wrong'}), throwsFormatException);
  });
}
