import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/features/notifications/domain/models/inbox_event.dart';

/// Proposed backend contract. Do not activate until endpoints are verified.
final inboxApiProvider = Provider<InboxApi>((ref) {
  return InboxApi(ref.watch(authenticatedDioProvider));
});

class InboxApi {
  const InboxApi(this._dio);
  final Dio _dio;

  Future<InboxPage> list({String? cursor}) async {
    final response = await _dio.get<Object?>(
      'notifications/',
      queryParameters: cursor == null ? null : {'cursor': cursor},
    );
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid notification API response');
    }
    return InboxPage.fromJson(data);
  }

  Future<int> unreadCount() async {
    final response = await _dio.get<Object?>('notifications/unread-count/');
    final data = response.data;
    if (data is! Map<String, dynamic> || data['count'] is! int ||
        (data['count'] as int) < 0) {
      throw const FormatException('Invalid notification count');
    }
    return data['count'] as int;
  }

  Future<void> markRead(String id) async {
    if (id.isEmpty) throw const FormatException('Missing event id');
    await _dio.post<void>('notifications/${Uri.encodeComponent(id)}/read/');
  }

  Future<void> markAllRead() async {
    await _dio.post<void>('notifications/read-all/');
  }
}
