/// Certificate pinning for self-hosted nodes.
///
/// Most nodes present a self-signed certificate, which no CA vouches for. Dart
/// only calls this back after normal validation has already failed, so a node
/// with a real certificate never reaches it: pinning can't override a CA's
/// verdict, only stand in where there is none. First contact accepts and records
/// the fingerprint; a later mismatch means the certificate changed and the
/// connection is refused.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

/// Formats as e.g. "AB:CD:12:...", matching `openssl x509 -fingerprint -sha256`
/// output so users can cross-check it against what install.sh prints.
String certFingerprint(X509Certificate cert) {
  final digest = sha256.convert(cert.der);
  return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
}

/// Trust-on-first-use pinning. `badCertificateCallback` is only invoked by
/// dart:io once normal chain validation has already failed — for a
/// Let's-Encrypt-signed node this callback never fires at all, so pinning
/// never overrides a real CA's judgement. For a self-signed node, this is
/// the only path: no [pinnedFingerprint] yet means first contact (accept
/// and let the caller persist it via [onFirstPin]); a mismatch against an
/// already-pinned fingerprint means the certificate changed since last
/// time and the connection is rejected.
bool Function(X509Certificate, String, int) buildPinningCallback({
  required String? pinnedFingerprint,
  required void Function(String fingerprint) onFirstPin,
}) {
  return (X509Certificate cert, String host, int port) {
    final fingerprint = certFingerprint(cert);
    if (pinnedFingerprint == null) {
      onFirstPin(fingerprint);
      return true;
    }
    return fingerprint == pinnedFingerprint;
  };
}
