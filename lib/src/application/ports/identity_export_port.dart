import 'dart:typed_data';

/// Opaque, already-encrypted identity backup produced by Core.
///
/// The App must never parse [bytes] or inspect the plaintext payload. Format
/// and versioning are owned by `im-core`.
class IdentityExportPackage {
  const IdentityExportPackage({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String fileName;
  final String mimeType;
  final Uint8List bytes;
}

class IdentityExportException implements Exception {
  const IdentityExportException(this.code, {this.cause});

  final String code;
  final Object? cause;

  @override
  String toString() => 'IdentityExportException($code)';
}

abstract interface class IdentityExportPort {
  bool get isSupported;

  /// [passphrase] is owned by the caller. Core implementations must copy it
  /// synchronously and must not retain the [Uint8List] reference.
  Future<IdentityExportPackage> exportIdentityPackage({
    required String identityId,
    required Uint8List passphrase,
  });
}

/// Fail-closed default used until the Core SDK exposes an encrypted export API.
class UnsupportedIdentityExportPort implements IdentityExportPort {
  const UnsupportedIdentityExportPort();

  @override
  bool get isSupported => false;

  @override
  Future<IdentityExportPackage> exportIdentityPackage({
    required String identityId,
    required Uint8List passphrase,
  }) async {
    throw const IdentityExportException('identity_export.unsupported');
  }
}
