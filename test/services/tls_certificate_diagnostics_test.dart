import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/tls_certificate_diagnostics.dart';

void main() {
  test('formats rejected certificate metadata without including its PEM', () {
    final certificate = _FakeCertificate(
      subject: 'CN=release-assets.githubusercontent.com',
      issuer: 'CN=Test Issuer',
      startValidity: DateTime.utc(2026, 1, 1),
      endValidity: DateTime.utc(2026, 12, 31),
      der: Uint8List.fromList([1, 2, 3, 4]),
      pem: '-----BEGIN CERTIFICATE-----\nsecret\n-----END CERTIFICATE-----',
    );

    final details = TlsCertificateDiagnostics.describeCertificate(
      certificate,
      host: 'release-assets.githubusercontent.com',
      port: 443,
    );

    expect(details, contains('host=release-assets.githubusercontent.com:443'));
    expect(
      details,
      contains('subject=CN=release-assets.githubusercontent.com'),
    );
    expect(details, contains('issuer=CN=Test Issuer'));
    expect(details, contains('validFrom=2026-01-01T00:00:00.000Z'));
    expect(details, contains('validUntil=2026-12-31T00:00:00.000Z'));
    expect(
      details,
      contains(
        'sha256=9F64A747E1B97F131FABB6B447296C9B6F0201E79FB3C5356E6C77E89B6A806A',
      ),
    );
    expect(details, isNot(contains('BEGIN CERTIFICATE')));
    expect(details, isNot(contains('secret')));
  });
}

class _FakeCertificate implements X509Certificate {
  _FakeCertificate({
    required this.subject,
    required this.issuer,
    required this.startValidity,
    required this.endValidity,
    required this.der,
    required this.pem,
  });

  @override
  final String subject;

  @override
  final String issuer;

  @override
  final DateTime startValidity;

  @override
  final DateTime endValidity;

  @override
  final Uint8List der;

  @override
  final String pem;

  @override
  Uint8List get sha1 => Uint8List(0);
}
