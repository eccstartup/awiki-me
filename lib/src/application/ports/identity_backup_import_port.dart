import 'dart:typed_data';

/// Secret-free summary Core returns after decrypting and validating a backup.
class IdentityBackupSummary {
  const IdentityBackupSummary({
    required this.did,
    this.handle,
    this.fullHandle,
    required this.displayName,
    required this.custody,
    this.createdAt,
    required this.exportedAt,
    required this.sourceCoreVersion,
    required this.keyKinds,
    required this.hasDidDocument,
  });

  final String did;
  final String? handle;
  final String? fullHandle;
  final String displayName;
  final String custody;
  final String? createdAt;
  final String exportedAt;
  final String sourceCoreVersion;
  final List<String> keyKinds;
  final bool hasDidDocument;
}

class IdentityBackupImportOutcome {
  const IdentityBackupImportOutcome({
    required this.identityId,
    required this.did,
    required this.rootKeyId,
    required this.alreadyPresent,
  });

  final String identityId;
  final String did;
  final String rootKeyId;
  final bool alreadyPresent;
}

class IdentityBackupImportException implements Exception {
  const IdentityBackupImportException(this.code, {this.cause});

  final String code;
  final Object? cause;

  @override
  String toString() => 'IdentityBackupImportException($code)';
}

abstract interface class IdentityBackupImportPort {
  bool get isSupported;

  /// Decrypts and validates [bytes] without changing local state.
  ///
  /// [passphrase] is owned by the caller; implementations must copy it
  /// synchronously and must not retain the [Uint8List] reference.
  Future<IdentityBackupSummary> inspectIdentityBackup({
    required Uint8List bytes,
    required Uint8List passphrase,
  });

  /// Installs identity material only.
  ///
  /// [userPresenceConfirmed] must only be true after the host completed a real
  /// system authentication. Core fails closed when it is false.
  Future<IdentityBackupImportOutcome> importIdentityBackup({
    required Uint8List bytes,
    required Uint8List passphrase,
    required bool userPresenceConfirmed,
  });
}

/// Fail-closed default used until the Core SDK exposes backup import.
class UnsupportedIdentityBackupImportPort implements IdentityBackupImportPort {
  const UnsupportedIdentityBackupImportPort();

  @override
  bool get isSupported => false;

  @override
  Future<IdentityBackupSummary> inspectIdentityBackup({
    required Uint8List bytes,
    required Uint8List passphrase,
  }) async {
    throw const IdentityBackupImportException(
      'identity_backup_import.unsupported',
    );
  }

  @override
  Future<IdentityBackupImportOutcome> importIdentityBackup({
    required Uint8List bytes,
    required Uint8List passphrase,
    required bool userPresenceConfirmed,
  }) async {
    throw const IdentityBackupImportException(
      'identity_backup_import.unsupported',
    );
  }
}
