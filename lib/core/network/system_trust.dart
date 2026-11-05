import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds a current CA bundle to Dart's default TLS context.
///
/// Flutter Windows links BoringSSL with a root set that can lag the operating
/// system. Music platform endpoints currently use DigiCert GeoTrust/Secure
/// Site and GlobalSign R46 chains; without those roots every HTTPS request in
/// the app (including all three QR-code endpoints) fails during the handshake
/// with `unable to get local issuer certificate` or `self signed certificate
/// in certificate chain`, while the same machine's mobile app works.
///
/// This augments - it never disables - certificate verification:
/// [SecurityContext.setTrustedCertificatesBytes] only adds trusted roots. A
/// bad certificate still fails.
Future<void> installBundledCaBundle() async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      final data = await rootBundle.load('assets/certs/cacert.pem');
      SecurityContext.defaultContext.setTrustedCertificatesBytes(
        data.buffer.asUint8List(),
      );
    } catch (error, stack) {
      debugPrint('installBundledCaBundle failed: $error\n$stack');
    }
  }
}
