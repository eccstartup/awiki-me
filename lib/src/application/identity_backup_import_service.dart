import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'attachment_picker_service.dart';
import 'models/attachment_models.dart';
import 'ports/identity_backup_import_port.dart';
import 'ports/user_presence_port.dart';

/// One backup file selected by the user, held in memory for a single import.
class IdentityBackupSelection {
  IdentityBackupSelection({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

/// Orchestrates the App-side half of importing an encrypted identity backup.
///
/// Core owns the container format, decryption, validation and key installation.
/// This service enforces the App-side size cap, reads the picked file exactly
/// once and asks for user presence before Core may install anything.
class IdentityBackupImportService {
  const IdentityBackupImportService({
    required IdentityBackupImportPort importPort,
    required AttachmentPickerService attachmentPicker,
    required UserPresencePort userPresence,
  }) : _importPort = importPort,
       _attachmentPicker = attachmentPicker,
       _userPresence = userPresence;

  static const int maximumBackupBytes = 1024 * 1024;

  final IdentityBackupImportPort _importPort;
  final AttachmentPickerService _attachmentPicker;
  final UserPresencePort _userPresence;

  bool get isSupported => _importPort.isSupported;

  /// Returns null when the user cancels the platform picker.
  Future<IdentityBackupSelection?> pickBackupFile() async {
    if (!_importPort.isSupported) {
      throw const IdentityBackupImportException(
        'identity_backup_import.unsupported',
      );
    }
    final AttachmentDraft? draft;
    try {
      draft = await _attachmentPicker.pickAttachment();
    } catch (error) {
      throw IdentityBackupImportException(
        'identity_backup_import.read_failed',
        cause: error,
      );
    }
    if (draft == null) {
      return null;
    }
    final declaredSize = draft.sizeBytes ?? draft.bytes?.length;
    if (declaredSize != null && declaredSize > maximumBackupBytes) {
      throw const IdentityBackupImportException(
        'identity_backup_import.too_large',
      );
    }

    Uint8List bytes;
    final stagedBytes = draft.bytes;
    if (stagedBytes != null) {
      bytes = Uint8List.fromList(stagedBytes);
    } else {
      final path = draft.localPath?.trim();
      if (path == null || path.isEmpty) {
        throw const IdentityBackupImportException(
          'identity_backup_import.invalid_file',
        );
      }
      final file = File(path);
      try {
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file) {
          throw const IdentityBackupImportException(
            'identity_backup_import.invalid_file',
          );
        }
        if (stat.size > maximumBackupBytes) {
          throw const IdentityBackupImportException(
            'identity_backup_import.too_large',
          );
        }
        bytes = await file.readAsBytes();
      } on IdentityBackupImportException {
        rethrow;
      } catch (error) {
        throw IdentityBackupImportException(
          'identity_backup_import.read_failed',
          cause: error,
        );
      } finally {
        // The picker stages an app-owned copy; the import never keeps a file.
        try {
          await file.delete();
        } catch (_) {
          // Best-effort cleanup must not mask the read outcome.
        }
      }
    }

    if (bytes.isEmpty) {
      throw const IdentityBackupImportException(
        'identity_backup_import.invalid_file',
      );
    }
    if (bytes.length > maximumBackupBytes) {
      bytes.fillRange(0, bytes.length, 0);
      throw const IdentityBackupImportException(
        'identity_backup_import.too_large',
      );
    }
    return IdentityBackupSelection(
      fileName: _displayFileName(draft.filename),
      bytes: bytes,
    );
  }

  /// Decrypts and validates the selected backup without changing local state.
  Future<IdentityBackupSummary> inspectBackup({
    required IdentityBackupSelection backup,
    required String passphrase,
  }) async {
    final passphraseBytes = _encodePassphrase(passphrase);
    try {
      return await _importPort.inspectIdentityBackup(
        bytes: backup.bytes,
        passphrase: passphraseBytes,
      );
    } on IdentityBackupImportException {
      rethrow;
    } catch (error) {
      throw IdentityBackupImportException(
        'identity_backup_import.inspect_failed',
        cause: error,
      );
    } finally {
      passphraseBytes.fillRange(0, passphraseBytes.length, 0);
    }
  }

  /// Installs identity material after a real system authentication.
  Future<IdentityBackupImportOutcome> importBackup({
    required IdentityBackupSelection backup,
    required String passphrase,
    required String presenceReason,
    required bool Function() isContextCurrent,
  }) async {
    if (!_importPort.isSupported) {
      throw const IdentityBackupImportException(
        'identity_backup_import.unsupported',
      );
    }
    final passphraseBytes = _encodePassphrase(passphrase);
    try {
      final confirmed = await _confirmPresence(presenceReason);
      if (!confirmed) {
        throw const IdentityBackupImportException(
          'identity_backup_import.user_presence_denied',
        );
      }
      if (!isContextCurrent()) {
        throw const IdentityBackupImportException(
          'identity_backup_import.state_changed',
        );
      }
      try {
        return await _importPort.importIdentityBackup(
          bytes: backup.bytes,
          passphrase: passphraseBytes,
          userPresenceConfirmed: true,
        );
      } on IdentityBackupImportException {
        rethrow;
      } catch (error) {
        throw IdentityBackupImportException(
          'identity_backup_import.failed',
          cause: error,
        );
      }
    } finally {
      passphraseBytes.fillRange(0, passphraseBytes.length, 0);
    }
  }

  /// Zeroes the in-memory backup so it does not outlive the dialog.
  void discard(IdentityBackupSelection selection) {
    selection.bytes.fillRange(0, selection.bytes.length, 0);
  }

  Future<bool> _confirmPresence(String reason) async {
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw const IdentityBackupImportException(
        'identity_backup_import.invalid_presence_reason',
      );
    }
    try {
      return await _userPresence.confirm(reason: normalizedReason);
    } catch (error) {
      throw IdentityBackupImportException(
        'identity_backup_import.user_presence_failed',
        cause: error,
      );
    }
  }

  Uint8List _encodePassphrase(String passphrase) {
    if (passphrase.isEmpty) {
      throw const IdentityBackupImportException(
        'identity_backup_import.passphrase_required',
      );
    }
    return Uint8List.fromList(utf8.encode(passphrase));
  }

  String _displayFileName(String filename) {
    final value = filename.trim();
    if (value.isEmpty || value.length > 255) {
      return 'identity-backup.awikibk';
    }
    return value;
  }
}
