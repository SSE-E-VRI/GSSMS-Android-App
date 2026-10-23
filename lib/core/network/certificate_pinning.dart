import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/io.dart';

/// Optional SPKI (SubjectPublicKeyInfo) certificate pinning.
///
/// Pins are base64 SHA-256 hashes of the DER-encoded SPKI, i.e. the output of
/// `openssl x509 -pubkey -noout | openssl pkey -pubin -outform der |
/// openssl dgst -sha256 -binary | base64`. Everything here fails closed: any
/// parse problem or mismatch means the certificate is rejected.

class _Tlv {
  const _Tlv(this.tag, this.start, this.valueStart, this.end);
  final int tag;
  final int start; // offset of the tag byte
  final int valueStart; // offset of the first content byte
  final int end; // offset just past the content
}

/// Reads one DER TLV at [offset]; throws [FormatException] if malformed.
_Tlv _readTlv(Uint8List d, int offset, int limit) {
  if (offset < 0 || offset + 2 > limit) {
    throw const FormatException('DER: truncated header');
  }
  final tag = d[offset];
  if ((tag & 0x1f) == 0x1f) {
    throw const FormatException('DER: high tag numbers unsupported');
  }
  var pos = offset + 1;
  final first = d[pos++];
  var length = 0;
  if (first < 0x80) {
    length = first;
  } else {
    final n = first & 0x7f;
    if (n == 0 || n > 4 || pos + n > limit) {
      throw const FormatException('DER: bad length');
    }
    for (var i = 0; i < n; i++) {
      length = (length << 8) | d[pos++];
    }
  }
  final end = pos + length;
  if (length < 0 || end > limit) {
    throw const FormatException('DER: length exceeds buffer');
  }
  return _Tlv(tag, offset, pos, end);
}

/// Extracts the full SubjectPublicKeyInfo SEQUENCE (header included) from an
/// X.509 certificate in DER form. Throws [FormatException] if malformed.
Uint8List extractSpki(Uint8List der) {
  final cert = _readTlv(der, 0, der.length);
  if (cert.tag != 0x30) throw const FormatException('Certificate not a SEQUENCE');
  final tbs = _readTlv(der, cert.valueStart, cert.end);
  if (tbs.tag != 0x30) throw const FormatException('TBSCertificate not a SEQUENCE');

  var field = _readTlv(der, tbs.valueStart, tbs.end);
  // Optional [0] EXPLICIT version.
  if (field.tag == 0xa0) {
    field = _readTlv(der, field.end, tbs.end);
  }
  // `field` is serialNumber; step over serialNumber, signature, issuer,
  // validity and subject to land on SubjectPublicKeyInfo.
  for (var i = 0; i < 5; i++) {
    field = _readTlv(der, field.end, tbs.end);
  }
  if (field.tag != 0x30) {
    throw const FormatException('SubjectPublicKeyInfo not a SEQUENCE');
  }
  return Uint8List.sublistView(der, field.start, field.end);
}

/// Base64 SHA-256 of the certificate's SPKI.
String spkiPin(Uint8List der) =>
    base64.encode(sha256.convert(extractSpki(der)).bytes);

/// True only when [cert] parses and its SPKI hash is in [pins].
bool spkiMatches(X509Certificate? cert, Set<String> pins) {
  if (cert == null || pins.isEmpty) return false;
  try {
    return pins.contains(spkiPin(cert.der));
  } catch (_) {
    return false;
  }
}

/// Builds a dio adapter that rejects any connection whose leaf certificate
/// SPKI hash is not in [pins]. System trust validation still applies first.
IOHttpClientAdapter buildPinnedAdapter(Set<String> pins) {
  final frozen = Set<String>.unmodifiable(pins);
  return IOHttpClientAdapter(
    validateCertificate: (cert, host, port) => spkiMatches(cert, frozen),
  );
}
