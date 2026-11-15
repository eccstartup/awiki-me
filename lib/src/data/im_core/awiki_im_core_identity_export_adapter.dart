// [INPUT]: Current runtime's Core instance, exact local identity selector and caller-owned passphrase bytes.
// [OUTPUT]: Core-sealed opaque backup package or a closed App error code.
// [POS]: Thin Dart adapter; container format and exported material stay inside Core.

import 'dart:typed_data';

import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/ports/identity_export_port.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreIdentityExportAdapter implements IdentityExportPort {
  AwikiImCoreIdentityExportAdapter({required AwikiImCoreRuntime runtime})
    : _coreInstance = runtime.coreInstance;

  AwikiImCoreIdentityExportAdapter.withCoreInstance({
    required Future<core.AwikiImCore> Function() coreInstance,
  }) : _coreInstance = coreInstance;

  final Future<core.AwikiImCore> Function() _coreInstance;

  @override
  bool get isSupported => true;

  @override
  Future<IdentityExportPackage> exportIdentityPackage({
    required String identityId,
    required Uint8List passphrase,
  }) async {
    final instance = await _coreInstance();
    try {
      final package = await instance.exportIdentityBackup(
        core.IdentitySelector.id(identityId),
        passphrase: passphrase,
      );
      return IdentityExportPackage(
        fileName: package.fileName,
        mimeType: package.mimeType,
        bytes: package.bytes,
      );
    } on core.AwikiImCoreException catch (error) {
      if (error.code == 'unsupported_capability' &&
          (error.capability ?? '').startsWith('identity_backup.')) {
        throw IdentityExportException(
          'identity_export.unsupported',
          cause: error,
        );
      }
      throw IdentityExportException('identity_export.failed', cause: error);
    }
  }
}
