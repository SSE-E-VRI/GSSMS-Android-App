import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/notifications/data/inbox_api.dart';

void main() {
  test('invalid event response is rejected', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, data: {'results': 'invalid'}));
    }));
    await expectLater(InboxApi(dio).list(), throwsFormatException);
  });

  test('read acknowledgement uses encoded event id', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/'));
    String? path;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      path = options.path;
      handler.resolve(Response(requestOptions: options, data: null));
    }));
    await InboxApi(dio).markRead('event/one');
    expect(path, 'notifications/event%2Fone/read/');
  });

  test('unread count is validated', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, data: {'count': -1}));
    }));
    await expectLater(InboxApi(dio).unreadCount(), throwsFormatException);
  });
}
