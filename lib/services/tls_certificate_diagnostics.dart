import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Read-only TLS diagnostics. Rejected certificates are never accepted.
class TlsCertificateDiagnostics {
  static const _timeout = Duration(seconds: 10);

  static bool isTlsFailure(Object error) {
    if (error is HandshakeException || error is TlsException) return true;
    final message = error.toString().toLowerCase();
    return message.contains('handshakeexception') ||
        message.contains('certificate_verify_failed') ||
        message.contains('unable to get local issuer certificate');
  }

  static Future<String> inspect(Uri uri) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    X509Certificate? rejectedCertificate;
    var certificateHost = uri.host;
    var certificatePort = uri.hasPort ? uri.port : 443;

    client.badCertificateCallback = (certificate, host, port) {
      rejectedCertificate = certificate;
      certificateHost = host;
      certificatePort = port;
      return false;
    };

    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'nt_helper TLS diagnostics',
      );
      final response = await request.close().timeout(_timeout);
      final certificate = response.certificate;
      final redirectHosts = response.redirects
          .map((redirect) => redirect.location.host)
          .where((host) => host.isNotEmpty)
          .toSet()
          .join(',');
      if (response.redirects.isNotEmpty) {
        final finalHost = response.redirects.last.location.host;
        if (finalHost.isNotEmpty) certificateHost = finalHost;
      }
      await response.drain<void>().timeout(_timeout);
      return [
        'requestedHost=${uri.host}',
        'validation=succeeded during diagnostic retry',
        if (redirectHosts.isNotEmpty) 'redirectHosts=$redirectHosts',
        if (certificate != null)
          describeCertificate(
            certificate,
            host: certificateHost,
            port: certificatePort,
          ),
        'systemTime=${DateTime.now().toUtc().toIso8601String()}',
      ].join('; ');
    } catch (error) {
      return [
        'requestedHost=${uri.host}',
        'validation=rejected',
        'error=${_singleLine(error)}',
        if (rejectedCertificate != null)
          describeCertificate(
            rejectedCertificate!,
            host: certificateHost,
            port: certificatePort,
          )
        else
          'peerCertificate=unavailable',
        'systemTime=${DateTime.now().toUtc().toIso8601String()}',
      ].join('; ');
    } finally {
      client.close(force: true);
    }
  }

  static String describeCertificate(
    X509Certificate certificate, {
    required String host,
    required int port,
  }) {
    final fingerprint = sha256
        .convert(certificate.der)
        .toString()
        .toUpperCase();
    return [
      'host=$host:$port',
      'subject=${_singleLine(certificate.subject)}',
      'issuer=${_singleLine(certificate.issuer)}',
      'validFrom=${certificate.startValidity.toUtc().toIso8601String()}',
      'validUntil=${certificate.endValidity.toUtc().toIso8601String()}',
      'sha256=$fingerprint',
    ].join('; ');
  }

  static String _singleLine(Object value) =>
      value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}
