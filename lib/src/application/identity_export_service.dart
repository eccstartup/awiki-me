import 'dart:convert';
import 'dart:typed_data';

import 'attachment_picker_service.dart';
import 'ports/identity_export_port.dart';
import 'ports/user_presence_port.dart';

/// Orchestrates the App-side half of an encrypted identity backup.
///
/// Core owns the package bytes, the cryptographic format and the exact set of
/// identity material. This service only fences the operation, asks for user
/// presence and hands the opaque package to the platform save surface.
class IdentityExportService {
  const IdentityExportService({
    required IdentityExportPort exportPort,
    required AttachmentPickerService attachmentPicker,
    required UserPresencePort userPresence,
  }) : _exportPort = exportPort,
       _attachmentPicker = attachmentPicker,
       _userPresence = userPresence;

  static const int minimumPassphraseBytes = 8;

  final IdentityExportPort _exportPort;
  final AttachmentPickerService _attachmentPicker;
  final UserPresencePort _userPresence;

  Future<String?> exportCurrentIdentity({
    required String identityId,
    required String passphrase,
    required String presenceReason,
    required bool Function() isContextCurrent,
  }) async {
    if (!_exportPort.isSupported) {
      throw const IdentityExportException('identity_export.unsupported');
    }
    final normalizedIdentityId = identityId.trim();
    if (normalizedIdentityId.isEmpty) {
      throw const IdentityExportException('identity_export.no_identity');
    }
    final passphraseBytes = Uint8List.fromList(utf8.encode(passphrase));
    if (passphraseBytes.length < minimumPassphraseBytes) {
      passphraseBytes.fillRange(0, passphraseBytes.length, 0);
      throw const IdentityExportException(
        'identity_export.passphrase_too_short',
      );
    }

    try {
      final confirmed = await _confirmPresence(presenceReason);
      if (!confirmed) {
        throw const IdentityExportException(
          'identity_export.user_presence_denied',
        );
      }
      if (!isContextCurrent()) {
        throw const IdentityExportException('identity_export.state_changed');
      }

      final IdentityExportPackage package;
      try {
        package = await _exportPort.exportIdentityPackage(
          identityId: normalizedIdentityId,
          passphrase: passphraseBytes,
        );
      } on IdentityExportException {
        rethrow;
      } catch (error) {
        throw IdentityExportException('identity_export.failed', cause: error);
      }

      _validatePackage(package);

      try {
        return await _attachmentPicker.saveAttachment(
          filename: package.fileName,
          mimeType: package.mimeType,
          bytes: package.bytes,
        );
      } catch (error) {
        throw IdentityExportException(
          'identity_export.save_failed',
          cause: error,
        );
      }
    } finally {
      passphraseBytes.fillRange(0, passphraseBytes.length, 0);
    }
  }

  Future<bool> _confirmPresence(String reason) async {
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw const IdentityExportException(
        'identity_export.invalid_presence_reason',
      );
    }
    try {
      return await _userPresence.confirm(reason: normalizedReason);
    } catch (error) {
      throw IdentityExportException(
        'identity_export.user_presence_failed',
        cause: error,
      );
    }
  }

  void _validatePackage(IdentityExportPackage package) {
    final fileName = package.fileName.trim();
    if (package.bytes.isEmpty ||
        fileName.isEmpty ||
        fileName.length > 255 ||
        fileName.contains('/') ||
        fileName.contains('\\') ||
        fileName.contains('\u0000') ||
        package.mimeType.trim().isEmpty) {
      throw const IdentityExportException('identity_export.invalid_package');
    }
  }
}
