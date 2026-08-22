import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Creates a short-lived HTTP client whose trust store includes the public
/// roots currently used by GitHub's API and release-asset CDN chains.
///
/// This does not pin GitHub certificates and does not modify the operating
/// system trust store. Callers must restrict use of this client to known
/// GitHub hosts.
class GitHubTlsSupport {
  static const rootCertificates = <String, String>{
    'assets/certificates/isrg-root-x1.pem':
        '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6',
    'assets/certificates/usertrust-ecc-certification-authority.pem':
        '4FF460D54B9C86DABFBCFC5712E0400D2BED3FBC4D4FBDAA86E06ADCD2A9AD7A',
  };

  static Future<http.Client> createTrustedClient() async {
    final context = SecurityContext(withTrustedRoots: true);

    for (final entry in rootCertificates.entries) {
      final data = await rootBundle.load(entry.key);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final actualDigest = sha256
          .convert(_decodePemCertificate(bytes))
          .toString()
          .toUpperCase();
      if (actualDigest != entry.value) {
        throw StateError(
          'Bundled root certificate fingerprint mismatch: ${entry.key}',
        );
      }

      try {
        context.setTrustedCertificatesBytes(bytes);
      } on TlsException catch (error) {
        // Current Dart builds already contain these Mozilla roots. Adding a
        // duplicate can report CERT_ALREADY_IN_HASH_TABLE; that is safe and
        // still leaves the built-in root available in this context.
        if (!error.toString().contains('CERT_ALREADY_IN_HASH_TABLE')) {
          rethrow;
        }
      }
    }

    return IOClient(HttpClient(context: context));
  }

  static Uint8List _decodePemCertificate(Uint8List pemBytes) {
    final body = const LineSplitter()
        .convert(ascii.decode(pemBytes))
        .where((line) => !line.startsWith('-----'))
        .join();
    if (body.isEmpty) {
      throw const FormatException('PEM certificate contains no DER data');
    }
    return base64.decode(body);
  }
}
