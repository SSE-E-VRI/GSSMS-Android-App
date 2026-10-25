import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Header telling the backend (gssms_project/middleware.py) that the body is
/// base64-encoded and must be decoded before parsing.
const String kBodyEncodingHeader = 'X-GSSMS-Body-Encoding';

/// Carries the real multipart Content-Type (with its boundary).
const String kOriginalContentTypeHeader = 'X-GSSMS-Content-Type';

/// Minimum send and receive timeout for any file upload.
const Duration kUploadTimeout = Duration(seconds: 120);

/// Sends file uploads base64-encoded.
///
/// The public edge in front of the production API (an AWS load balancer)
/// answers 403 to any request body containing a real JPEG, before the
/// request reaches Django — so every checklist photo was rejected regardless
/// of permissions. It also rejects a multipart Content-Type whose body is not
/// literal multipart, so the encoded body travels as text/plain and the real
/// Content-Type in [kOriginalContentTypeHeader].
///
/// The encoded body is a [Uint8List], so the auth interceptor can replay it
/// after a token refresh without re-finalizing the [FormData].
///
/// Every upload also gets at least [kUploadTimeout] to send and to wait for
/// the reply. Dio's receive timer starts once the body is handed to the
/// socket, so on a weak field signal the client's 15 s default also has to
/// cover the tail of the transmission plus server-side image processing.
class EncodedUploadInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final data = options.data;
    if (data is! FormData || data.files.isEmpty) {
      return handler.next(options);
    }
    try {
      final body = await data.readAsBytes();
      options.data = Uint8List.fromList(ascii.encode(base64Encode(body)));
      options.contentType = Headers.textPlainContentType;
      options.headers[kOriginalContentTypeHeader] =
          '${Headers.multipartFormDataContentType}; boundary=${data.boundary}';
      options.headers[kBodyEncodingHeader] = 'base64';
      options.headers.remove(Headers.contentLengthHeader);
      options.sendTimeout = _atLeastUploadTimeout(options.sendTimeout);
      options.receiveTimeout = _atLeastUploadTimeout(options.receiveTimeout);
      return handler.next(options);
    } catch (e) {
      return handler.reject(DioException(
        requestOptions: options,
        error: e,
        message: 'Unable to prepare the upload.',
      ));
    }
  }

  /// A null or zero timeout means "no limit" in Dio — keep that.
  static Duration? _atLeastUploadTimeout(Duration? current) {
    if (current == null || current == Duration.zero) return current;
    return current < kUploadTimeout ? kUploadTimeout : current;
  }
}
