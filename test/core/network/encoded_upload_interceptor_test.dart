import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/config/app_config.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/core/network/encoded_upload_interceptor.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_api_service.dart';

final _encodingHeader = kBodyEncodingHeader.toLowerCase();

/// A JPEG quantization-table marker: the bytes the production edge blocks.
final _jpeg = Uint8List.fromList(
    [0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x43, 0x00, 0x06, 0x04, 0xFF, 0xD9]);

class _Sent {
  _Sent(this.headers, this.body);
  final Map<String, dynamic> headers;
  final List<int> body;
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.status);

  final int Function(RequestOptions options) status;
  final sent = <_Sent>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final bytes = requestStream == null
        ? <int>[]
        : await requestStream.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    sent.add(_Sent(
        options.headers.map((k, v) => MapEntry(k.toLowerCase(), v)), bytes));
    return ResponseBody.fromString(
      jsonEncode({'id': 9, 'url': 'https://x/evidence.jpg'}),
      status(options),
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

int _indexOf(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

void main() {
  late Directory tmp;
  late String photoPath;
  String? token;

  Dio client(_RecordingAdapter adapter) {
    final dio = DioClient.create(
      config: const AppConfig(
          baseUrl: 'http://127.0.0.1:8765', environment: AppEnvironment.dev),
      tokenProvider: () => token,
      refreshTokenHandler: () async => token = 'fresh',
      onSessionExpired: () async {},
    );
    dio.httpClientAdapter = adapter;
    return dio;
  }

  setUp(() async {
    token = 'old';
    tmp = await Directory.systemTemp.createTemp('encoded_upload_');
    photoPath = '${tmp.path}${Platform.pathSeparator}evidence.jpg';
    await File(photoPath).writeAsBytes(_jpeg);
  });

  tearDown(() => tmp.delete(recursive: true));

  test('checklist photo upload is sent base64-encoded with its boundary',
      () async {
    final adapter = _RecordingAdapter((_) => 201);

    await WorkOrderApiService(client(adapter)).uploadLineAttachment(
      88,
      lineId: 4970,
      kind: 'before',
      imagePath: photoPath,
      source: 'gallery',
    );

    final request = adapter.sent.single;
    expect(request.headers[_encodingHeader], 'base64');
    expect(request.headers[Headers.contentTypeHeader], 'text/plain');
    final boundary = RegExp(r'^multipart/form-data; boundary=(.+)$')
        .firstMatch(request.headers[kOriginalContentTypeHeader.toLowerCase()]
            as String)!
        .group(1)!;
    expect(_indexOf(request.body, _jpeg), -1,
        reason: 'raw JPEG bytes must never reach the edge');

    final decoded = base64Decode(ascii.decode(request.body));
    final text = latin1.decode(decoded);
    expect(text, startsWith('--$boundary'));
    expect(text, contains('name="kind"\r\n\r\nBEFORE'));
    expect(text, contains('name="source"\r\n\r\nGALLERY'));
    expect(text, contains('filename="evidence.jpg"'));
    expect(_indexOf(decoded, _jpeg), greaterThan(0));
  });

  test('a token-refresh retry replays the same encoded photo', () async {
    final adapter = _RecordingAdapter((options) =>
        options.headers['Authorization'] == 'Bearer fresh' ? 201 : 401);

    final result = await WorkOrderApiService(client(adapter))
        .uploadLineAttachment(88,
            lineId: 4970, kind: 'AFTER', imagePath: photoPath);

    expect(result['id'], 9);
    expect(adapter.sent, hasLength(2));
    expect(adapter.sent[1].body, adapter.sent[0].body);
    expect(adapter.sent[1].body, isNotEmpty);
    expect(adapter.sent[1].headers[_encodingHeader], 'base64');
  });

  test('requests without files are not encoded', () async {
    final adapter = _RecordingAdapter((_) => 200);
    final dio = client(adapter);

    await dio.post<dynamic>('/api/v1/x/', data: {'status': 'OK'});
    await dio.post<dynamic>('/api/v1/x/',
        data: FormData.fromMap({'remarks': 'fields only'}));

    for (final request in adapter.sent) {
      expect(request.headers.containsKey(_encodingHeader), isFalse);
    }
    expect(utf8.decode(adapter.sent.first.body), '{"status":"OK"}');
  });
}
