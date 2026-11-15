// [INPUT]: Caller-owned backup bytes and passphrase from the import dialog.
// [OUTPUT]: Secret-free inspection summary or installed-identity outcome.
// [POS]: Thin Dart adapter; decryption, validation and key installation stay
// inside Core.

import 'dart:typed_data';

import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/ports/identity_backup_import_port.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreIdentityBackupImportAdapter
    implements IdentityBackupImportPort {
  AwikiImCoreIdentityBackupImportAdapter({
    required AwikiImCoreRuntime runtime,
  }) : _coreInstance = runtime.coreInstance;

  AwikiImCoreIdentityBackupImportAdapter.withCoreInstance({
    required Future<core.AwikiImCore> Function() coreInstance,
  }) : _coreInstance = coreInstance;

  final Future<core.AwikiImCore> Function() _coreInstance;

  @override
  bool get isSupported => true;

  @override
  Future<IdentityBackupSummary> inspectIdentityBackup({
    required Uint8List bytes,
    required Uint8List passphrase,
  }) async {
    final instance = await _coreInstance();
    try {
      final summary = await instance.inspectIdentityBackup(
        bytes,
        passphrase: passphrase,
      );
      return IdentityBackupSummary(
        did: summary.did,
        handle: summary.handle,
        fullHandle: summary.fullHandle,
        displayName: summary.displayName,
        custody: summary.custody,
        createdAt: summary.createdAt,
        exportedAt: summary.exportedAt,
        sourceCoreVersion: summary.sourceCoreVersion,
        keyKinds: summary.keyKinds,
        hasDidDocument: summary.hasDidDocument,
      );
    } on core.AwikiImCoreException catch (error) {
      throw _mapError(error, fallback: 'identity_backup_import.inspect_failed');
    }
  }

  @override
  Future<IdentityBackupImportOutcome> importIdentityBackup({
    required Uint8List bytes,
    required Uint8List passphrase,
    required bool userPresenceConfirmed,
  }) async {
    final instance = await _coreInstance();
    try {
      final result = await instance.importIdentityBackup(
        bytes,
        passphrase: passphrase,
        userPresenceConfirmed: userPresenceConfirmed,
      );
      return IdentityBackupImportOutcome(
        identityId: result.identityId,
        did: result.did,
        rootKeyId: result.rootKeyId,
        alreadyPresent: result.alreadyPresent,
      );
    } on core.AwikiImCoreException catch (error) {
      throw _mapError(error, fallback: 'identity_backup_import.failed');
    }
  }

  IdentityBackupImportException _mapError(
    core.AwikiImCoreException error, {
    required String fallback,
  }) {
    final code = error.code;
    if (code.startsWith('identity_backup_')) {
      return IdentityBackupImportException(code, cause: error);
    }
    if (code == 'unsupported_capability' &&
        (error.capability ?? '').startsWith('identity_backup.')) {
      return IdentityBackupImportException(
        'identity_backup_import.unsupported',
        cause: error,
      );
    }
    if (code == 'permission_denied') {
      return IdentityBackupImportException(
        'identity_backup_import.denied',
        cause: error,
      );
    }
    if (code == 'identity_binding_conflict') {
      return IdentityBackupImportException(
        'identity_backup_import.conflict',
        cause: error,
      );
    }
    return IdentityBackupImportException(fallback, cause: error);
  }
}
