import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/github_tls_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('creates a client with the audited roots', () async {
    final client = await GitHubTlsSupport.createTrustedClient();
    client.close();
  });

  test('bundled GitHub root certificates match audited fingerprints', () async {
    for (final entry in GitHubTlsSupport.rootCertificates.entries) {
      final pem = await File(entry.key).readAsString();
      final body = const LineSplitter()
          .convert(pem)
          .where((line) => !line.startsWith('-----'))
          .join();
      final fingerprint = sha256
          .convert(base64.decode(body))
          .toString()
          .toUpperCase();

      expect(fingerprint, entry.value, reason: entry.key);
    }
  });
}
