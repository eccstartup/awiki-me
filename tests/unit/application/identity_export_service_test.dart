import 'dart:convert';
import 'dart:typed_data';

import 'package:awiki_me/src/application/identity_export_service.dart';
import 'package:awiki_me/src/application/ports/identity_export_port.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support.dart';

void main() {
  group('IdentityExportService', () {
    late _FakeIdentityExportPort port;
    late _FakeUserPresence presence;
    late FakeAttachmentPickerService picker;
    late IdentityExportService service;

    setUp(() {
      port = _FakeIdentityExportPort();
      presence = _FakeUserPresence();
      picker = FakeAttachmentPickerService()
        ..nextSavedPath = '/tmp/awiki-identity-alice.awiki-backup';
      service = IdentityExportService(
        exportPort: port,
        attachmentPicker: picker,
        userPresence: presence,
      );
    });

    test('unsupported port fails before user presence', () async {
      port.supported = false;

      await _expectCode(
        service.exportCurrentIdentity(
          identityId: 'identity-alice',
          passphrase: 'correct horse',
          presenceReason: 'export identity backup',
          isContextCurrent: () => true,
        ),
        'identity_export.unsupported',
      );

      expect(presence.calls, 0);
      expect(port.calls, 0);
      expect(picker.saveCalls, 0);
    });

    test('empty identity is rejected', () async {
      await _expectCode(
        service.exportCurrentIdentity(
          identityId: '  ',
          passphrase: 'correct horse',
          presenceReason: 'export identity backup',
          isContextCurrent: () => true,
        ),
        'identity_export.no_identity',
      );

      expect(presence.calls, 0);
      expect(port.calls, 0);
    });

    test('short passphrase is rejected before user presence', () async {
      await _expectCode(
        service.exportCurrentIdentity(
          identityId: 'identity-alice',
          passphrase: 'short',
          presenceReason: 'export identity backup',
          isContextCurrent: () => true,
        ),
        'identity_export.passphrase_too_short',
      );

      expect(presence.calls, 0);
      expect(port.calls, 0);
      expect(picker.saveCalls, 0);
    });

    test('denied user presence never calls Core or saves', () async {
      presence.result = false;

      await _expectCode(
        service.exportCurrentIdentity(
          identityId: 'identity-alice',
          passphrase: 'correct horse',
          presenceReason: 'export identity backup',
          isContextCurrent: () => true,
        ),
        'identity_export.user_presence_denied',
      );

      expect(presence.calls, 1);
      expect(port.calls, 0);
      expect(picker.saveCalls, 0);
    });

    test('blank presence reason is rejected without user presence', () async {
      await _expectCode(
        service.exportCurrentIdentity(
          identityId: 'identity-alice',
          passphrase: 'correct horse',
          presenceReason: '  ',
          isContextCurrent: () => true,
        ),
        'identity_export.invalid_presence_reason',
      );

      expect(presence.calls, 0);
      expect(port.calls, 0);
    });

    test('user presence platform failure never calls Core', () async {
      presence.error = StateError('biometrics unavailable');

      await _expectCode(
        service.exportCurrentIdentity(
          identityId: 'identity-alice',
          passphrase: 'correct horse',
          presenceReason: 'export identity backup',
          isContextCurrent: () => true,
        ),
        'identity_export.user_presence_failed',
      );

      expect(presence.calls, 1);
      expect(port.calls, 0);
      expect(picker.saveCalls, 0);
    });

    test('session change after user presence never calls Core', () async {
      await _expectCode(
        service.exportCurrentIdentity(
          identityId: 'identity-alice',
          passphrase: 'correct horse',
          presenceReason: 'export identity backup',
          isContextCurrent: () => false,
        ),
        'identity_export.state_changed',
      );

      expect(presence.calls, 1);
      expect(port.calls, 0);
      expect(picker.saveCalls, 0);
    });

    test('success saves the opaque package and zeroes the passphrase', () async {
      final savedPath = await service.exportCurrentIdentity(
        identityId: 'identity-alice',
        passphrase: 'correct horse',
        presenceReason: 'export identity backup',
        isContextCurrent: () => true,
      );

      expect(savedPath, '/tmp/awiki-identity-alice.awiki-backup');
      expect(port.identityId, 'identity-alice');
      expect(utf8.decode(port.passphraseCopy!), 'correct horse');
      expect(port.passphrase, everyElement(0));
      expect(picker.saveCalls, 1);
      expect(
        picker.lastSavedFilename,
        'awiki-identity-alice-20261115-000000.awiki-backup',
      );
      expect(picker.lastSavedMimeType, 'application/vnd.awiki.identity-backup');
      expect(picker.lastSavedBytes, orderedEquals(<int>[1, 2, 3, 4]));
    });

    test('empty package is rejected without saving', () async {
      port.package = _package(bytes: Uint8List(0));

      await _expectCode(
        service.exportCurrentIdentity(
          identityId: 'identity-alice',
          passphrase: 'correct horse',
          presenceReason: 'export identity backup',
          isContextCurrent: () => true,
        ),
        'identity_export.invalid_package',
      );

      expect(picker.saveCalls, 0);
    });

    test('empty package file name is rejected', () async {
      port.package = _package(fileName: '  ');

      await _expectCode(
        service.exportCurrentIdentity(
          identityId: 'identity-alice',
          passphrase: 'correct horse',
          presenceReason: 'export identity backup',
          isContextCurrent: () => true,
        ),
        'identity_export.invalid_package',
      );

      expect(picker.saveCalls, 0);
    });

    test('path separators in package file name are rejected', () async {
      port.package = _package(fileName: '../awiki-backup');

      await _expectCode(
        service.exportCurrentIdentity(
          identityId: 'identity-alice',
          passphrase: 'correct horse',
          presenceReason: 'export identity backup',
          isContextCurrent: () => true,
        ),
        'identity_export.invalid_package',
      );

      expect(picker.saveCalls, 0);
    });

    test('empty MIME type is rejected without saving', () async {
      port.package = _package(mimeType: ' ');

      await _expectCode(
        service.exportCurrentIdentity(
          identityId: 'identity-alice',
          passphrase: 'correct horse',
          presenceReason: 'export identity backup',
          isContextCurrent: () => true,
        ),
        'identity_export.invalid_package',
      );

      expect(picker.saveCalls, 0);
    });

    test('Core typed failure keeps its stable code', () async {
      port.error = const IdentityExportException(
        'identity_export.vault_locked',
      );

      await _expectCode(
        service.exportCurrentIdentity(
          identityId: 'identity-alice',
          passphrase: 'correct horse',
          presenceReason: 'export identity backup',
          isContextCurrent: () => true,
        ),
        'identity_export.vault_locked',
      );

      expect(picker.saveCalls, 0);
    });

    test('Core failure is wrapped as identity_export.failed', () async {
      port.error = StateError('vault locked');

      await _expectCode(
        service.exportCurrentIdentity(
          identityId: 'identity-alice',
          passphrase: 'correct horse',
          presenceReason: 'export identity backup',
          isContextCurrent: () => true,
        ),
        'identity_export.failed',
      );

      expect(picker.saveCalls, 0);
    });

    test('save failure is reported as identity_export.save_failed', () async {
      final failingService = IdentityExportService(
        exportPort: port,
        attachmentPicker: _ThrowingAttachmentPickerService(),
        userPresence: presence,
      );

      await _expectCode(
        failingService.exportCurrentIdentity(
          identityId: 'identity-alice',
          passphrase: 'correct horse',
          presenceReason: 'export identity backup',
          isContextCurrent: () => true,
        ),
        'identity_export.save_failed',
      );
    });

    test('cancelled save returns null without success feedback', () async {
      picker.nextSavedPath = null;

      final savedPath = await service.exportCurrentIdentity(
        identityId: 'identity-alice',
        passphrase: 'correct horse',
        presenceReason: 'export identity backup',
        isContextCurrent: () => true,
      );

      expect(savedPath, isNull);
      expect(picker.saveCalls, 1);
    });
  });
}

Future<void> _expectCode(Future<String?> future, String code) {
  return expectLater(
    future,
    throwsA(
      isA<IdentityExportException>().having(
        (error) => error.code,
        'code',
        code,
      ),
    ),
  );
}

IdentityExportPackage _package({
  String fileName = 'awiki-identity-alice-20261115-000000.awiki-backup',
  String mimeType = 'application/vnd.awiki.identity-backup',
  Uint8List? bytes,
}) {
  return IdentityExportPackage(
    fileName: fileName,
    mimeType: mimeType,
    bytes: bytes ?? Uint8List.fromList(<int>[1, 2, 3, 4]),
  );
}

class _FakeIdentityExportPort implements IdentityExportPort {
  bool supported = true;
  IdentityExportPackage? package;
  Object? error;
  int calls = 0;
  String? identityId;
  Uint8List? passphrase;
  Uint8List? passphraseCopy;

  @override
  bool get isSupported => supported;

  @override
  Future<IdentityExportPackage> exportIdentityPackage({
    required String identityId,
    required Uint8List passphrase,
  }) async {
    calls += 1;
    this.identityId = identityId;
    this.passphrase = passphrase;
    passphraseCopy = Uint8List.fromList(passphrase);
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return package ?? _package();
  }
}

class _FakeUserPresence implements UserPresencePort {
  bool result = true;
  Object? error;
  int calls = 0;

  @override
  Future<bool> confirm({required String reason}) async {
    calls += 1;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return result;
  }
}

class _ThrowingAttachmentPickerService extends FakeAttachmentPickerService {
  @override
  Future<String?> saveAttachment({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    throw StateError('save failed');
  }
}
