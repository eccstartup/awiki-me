import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:awiki_me/src/application/identity_backup_import_service.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/ports/identity_backup_import_port.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support.dart';

void main() {
  group('IdentityBackupImportService', () {
    late _FakeIdentityBackupImportPort port;
    late _FakeUserPresence presence;
    late FakeAttachmentPickerService picker;
    late IdentityBackupImportService service;

    setUp(() {
      port = _FakeIdentityBackupImportPort();
      presence = _FakeUserPresence();
      picker = FakeAttachmentPickerService();
      service = IdentityBackupImportService(
        importPort: port,
        attachmentPicker: picker,
        userPresence: presence,
      );
    });

    test('unsupported port fails before the picker opens', () async {
      port.supported = false;

      await _expectCode(
        service.pickBackupFile(),
        'identity_backup_import.unsupported',
      );

      expect(picker.pickCalls, 0);
    });

    test('cancelled picker returns null', () async {
      picker.nextPick = null;

      expect(await service.pickBackupFile(), isNull);
      expect(picker.pickCalls, 1);
    });

    test('declared oversize file is rejected without reading it', () async {
      picker.nextPick = AttachmentDraft(
        filename: 'backup.awikibk',
        mimeType: 'application/vnd.awiki.identity-backup',
        bytes: Uint8List(IdentityBackupImportService.maximumBackupBytes + 1),
      );

      await _expectCode(
        service.pickBackupFile(),
        'identity_backup_import.too_large',
      );
    });

    test('path-backed file is read once and removed after selection', () async {
      final directory = await Directory.systemTemp.createTemp(
        'awiki-identity-import-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/backup.awikibk');
      await file.writeAsBytes(<int>[1, 2, 3, 4]);
      picker.nextPick = AttachmentDraft(
        filename: 'backup.awikibk',
        mimeType: 'application/vnd.awiki.identity-backup',
        localPath: file.path,
        sizeBytes: 4,
      );

      final selection = await service.pickBackupFile();

      expect(selection, isNotNull);
      expect(selection!.fileName, 'backup.awikibk');
      expect(selection.bytes, orderedEquals(<int>[1, 2, 3, 4]));
      expect(file.existsSync(), isFalse);
    });

    test('path-backed oversize stat is rejected before reading', () async {
      final directory = await Directory.systemTemp.createTemp(
        'awiki-identity-import-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/backup.awikibk');
      await file.writeAsBytes(<int>[1]);
      picker.nextPick = AttachmentDraft(
        filename: 'backup.awikibk',
        mimeType: 'application/vnd.awiki.identity-backup',
        localPath: file.path,
        sizeBytes: IdentityBackupImportService.maximumBackupBytes + 1,
      );

      await _expectCode(
        service.pickBackupFile(),
        'identity_backup_import.too_large',
      );
    });

    test('empty file is rejected as invalid', () async {
      picker.nextPick = AttachmentDraft(
        filename: 'backup.awikibk',
        mimeType: 'application/vnd.awiki.identity-backup',
        bytes: Uint8List(0),
      );

      await _expectCode(
        service.pickBackupFile(),
        'identity_backup_import.invalid_file',
      );
    });

    test('picker failure is reported as read_failed', () async {
      final failing = IdentityBackupImportService(
        importPort: port,
        attachmentPicker: _ThrowingAttachmentPickerService(),
        userPresence: presence,
      );

      await _expectCode(
        failing.pickBackupFile(),
        'identity_backup_import.read_failed',
      );
    });

    test('inspect forwards UTF-8 passphrase and zeroes its copy', () async {
      final backup = _selection();

      final summary = await service.inspectBackup(
        backup: backup,
        passphrase: 'pässphrase',
      );

      expect(summary.did, 'did:test:alice');
      expect(utf8.decode(port.passphraseCopy!), 'pässphrase');
      expect(port.passphrase, everyElement(0));
      expect(identical(port.bytes, backup.bytes), isTrue);
    });

    test('empty passphrase is rejected before Core inspect', () async {
      await _expectCode(
        service.inspectBackup(backup: _selection(), passphrase: ''),
        'identity_backup_import.passphrase_required',
      );

      expect(port.inspectCalls, 0);
    });

    test('Core inspect failure keeps its stable code', () async {
      port.inspectError = const IdentityBackupImportException(
        'identity_backup_bad_passphrase',
      );

      await _expectCode(
        service.inspectBackup(backup: _selection(), passphrase: 'wrong'),
        'identity_backup_bad_passphrase',
      );
    });

    test('unexpected inspect failure is wrapped', () async {
      port.inspectError = StateError('vault unavailable');

      await _expectCode(
        service.inspectBackup(backup: _selection(), passphrase: 'secret'),
        'identity_backup_import.inspect_failed',
      );
    });

    test('denied user presence never calls Core import', () async {
      presence.result = false;

      await _expectCode(
        service.importBackup(
          backup: _selection(),
          passphrase: 'secret',
          presenceReason: 'import identity backup',
          isContextCurrent: () => true,
        ),
        'identity_backup_import.user_presence_denied',
      );

      expect(presence.calls, 1);
      expect(port.importCalls, 0);
    });

    test('blank presence reason is rejected before user presence', () async {
      await _expectCode(
        service.importBackup(
          backup: _selection(),
          passphrase: 'secret',
          presenceReason: '  ',
          isContextCurrent: () => true,
        ),
        'identity_backup_import.invalid_presence_reason',
      );

      expect(presence.calls, 0);
      expect(port.importCalls, 0);
    });

    test('user presence platform failure never calls Core import', () async {
      presence.error = StateError('biometrics unavailable');

      await _expectCode(
        service.importBackup(
          backup: _selection(),
          passphrase: 'secret',
          presenceReason: 'import identity backup',
          isContextCurrent: () => true,
        ),
        'identity_backup_import.user_presence_failed',
      );

      expect(port.importCalls, 0);
    });

    test('session change after user presence never calls Core import', () async {
      await _expectCode(
        service.importBackup(
          backup: _selection(),
          passphrase: 'secret',
          presenceReason: 'import identity backup',
          isContextCurrent: () => false,
        ),
        'identity_backup_import.state_changed',
      );

      expect(presence.calls, 1);
      expect(port.importCalls, 0);
    });

    test('success installs only after presence and zeroes the passphrase', () async {
      final backup = _selection();

      final outcome = await service.importBackup(
        backup: backup,
        passphrase: 'pässphrase',
        presenceReason: 'import identity backup',
        isContextCurrent: () => true,
      );

      expect(presence.calls, 1);
      expect(presence.lastReason, 'import identity backup');
      expect(port.importCalls, 1);
      expect(port.userPresenceConfirmed, isTrue);
      expect(identical(port.bytes, backup.bytes), isTrue);
      expect(utf8.decode(port.passphraseCopy!), 'pässphrase');
      expect(port.passphrase, everyElement(0));
      expect(outcome.identityId, 'identity-alice');
      expect(outcome.alreadyPresent, isFalse);
    });

    test('already-present outcome is passed through', () async {
      port.outcome = const IdentityBackupImportOutcome(
        identityId: 'identity-alice',
        did: 'did:test:alice',
        rootKeyId: 'root-1',
        alreadyPresent: true,
      );

      final outcome = await service.importBackup(
        backup: _selection(),
        passphrase: 'secret',
        presenceReason: 'import identity backup',
        isContextCurrent: () => true,
      );

      expect(outcome.alreadyPresent, isTrue);
    });

    test('Core import failure keeps its stable code', () async {
      port.importError = const IdentityBackupImportException(
        'identity_backup_import.conflict',
      );

      await _expectCode(
        service.importBackup(
          backup: _selection(),
          passphrase: 'secret',
          presenceReason: 'import identity backup',
          isContextCurrent: () => true,
        ),
        'identity_backup_import.conflict',
      );
      expect(port.passphrase, everyElement(0));
    });

    test('discard zeroes the selected bytes', () {
      final backup = _selection();

      service.discard(backup);

      expect(backup.bytes, everyElement(0));
    });
  });
}

Future<void> _expectCode(Future<Object?> future, String code) {
  return expectLater(
    future,
    throwsA(
      isA<IdentityBackupImportException>().having(
        (error) => error.code,
        'code',
        code,
      ),
    ),
  );
}

IdentityBackupSelection _selection() {
  return IdentityBackupSelection(
    fileName: 'backup.awikibk',
    bytes: Uint8List.fromList(<int>[9, 8, 7, 6]),
  );
}

class _FakeIdentityBackupImportPort implements IdentityBackupImportPort {
  bool supported = true;
  Object? inspectError;
  Object? importError;
  IdentityBackupImportOutcome? outcome;
  int inspectCalls = 0;
  int importCalls = 0;
  Uint8List? bytes;
  Uint8List? passphrase;
  Uint8List? passphraseCopy;
  bool? userPresenceConfirmed;

  @override
  bool get isSupported => supported;

  @override
  Future<IdentityBackupSummary> inspectIdentityBackup({
    required Uint8List bytes,
    required Uint8List passphrase,
  }) async {
    inspectCalls += 1;
    this.bytes = bytes;
    this.passphrase = passphrase;
    passphraseCopy = Uint8List.fromList(passphrase);
    final failure = inspectError;
    if (failure != null) throw failure;
    return const IdentityBackupSummary(
      did: 'did:test:alice',
      handle: 'alice.example.com',
      fullHandle: 'alice.example.com',
      displayName: 'Alice',
      custody: 'anp_root',
      exportedAt: '2026-11-15T00:00:00Z',
      sourceCoreVersion: '0.1.0',
      keyKinds: <String>['did_document_root'],
      hasDidDocument: true,
    );
  }

  @override
  Future<IdentityBackupImportOutcome> importIdentityBackup({
    required Uint8List bytes,
    required Uint8List passphrase,
    required bool userPresenceConfirmed,
  }) async {
    importCalls += 1;
    this.bytes = bytes;
    this.passphrase = passphrase;
    passphraseCopy = Uint8List.fromList(passphrase);
    this.userPresenceConfirmed = userPresenceConfirmed;
    final failure = importError;
    if (failure != null) throw failure;
    return outcome ??
        const IdentityBackupImportOutcome(
          identityId: 'identity-alice',
          did: 'did:test:alice',
          rootKeyId: 'root-1',
          alreadyPresent: false,
        );
  }
}

class _FakeUserPresence implements UserPresencePort {
  bool result = true;
  Object? error;
  int calls = 0;
  String? lastReason;

  @override
  Future<bool> confirm({required String reason}) async {
    calls += 1;
    lastReason = reason;
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }
}

class _ThrowingAttachmentPickerService extends FakeAttachmentPickerService {
  @override
  Future<AttachmentDraft?> pickAttachment() async {
    throw StateError('picker failed');
  }
}
