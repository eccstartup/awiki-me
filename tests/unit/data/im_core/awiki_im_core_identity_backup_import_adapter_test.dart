import 'dart:convert';
import 'dart:typed_data';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/ports/identity_backup_import_port.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_identity_backup_import_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('inspectIdentityBackup', () {
    test('passes the exact bytes and passphrase and maps the summary', () async {
      final sdk = _ImportCore();
      final adapter = _adapterWithCore(sdk);
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);
      final passphrase = Uint8List.fromList(utf8.encode('correct horse'));

      final summary = await adapter.inspectIdentityBackup(
        bytes: bytes,
        passphrase: passphrase,
      );

      expect(identical(sdk.bytes, bytes), isTrue);
      expect(identical(sdk.passphrase, passphrase), isTrue);
      expect(summary.did, 'did:test:alice');
      expect(summary.handle, 'alice.example.com');
      expect(summary.fullHandle, 'alice.example.com');
      expect(summary.displayName, 'Alice');
      expect(summary.custody, 'anp_root');
      expect(summary.createdAt, '2026-01-01T00:00:00Z');
      expect(summary.exportedAt, '2026-11-15T00:00:00Z');
      expect(summary.sourceCoreVersion, '0.1.0');
      expect(summary.keyKinds, <String>['did_document_root']);
      expect(summary.hasDidDocument, isTrue);
    });

    test('typed Core backup codes pass through', () async {
      final sdk = _ImportCore()
        ..error = const core.AwikiImCoreException(
          code: 'identity_backup_bad_passphrase',
          message: 'wrong passphrase',
        );

      await _expectCode(
        _adapterWithCore(sdk).inspectIdentityBackup(
          bytes: Uint8List.fromList(<int>[1]),
          passphrase: Uint8List.fromList(utf8.encode('wrong')),
        ),
        'identity_backup_bad_passphrase',
      );
    });

    test('missing capability maps to unsupported', () async {
      final sdk = _ImportCore()
        ..error = const core.AwikiImCoreException(
          code: 'unsupported_capability',
          message: 'unsupported capability: identity_backup.import',
          capability: 'identity_backup.import',
        );

      await _expectCode(
        _adapterWithCore(sdk).inspectIdentityBackup(
          bytes: Uint8List.fromList(<int>[1]),
          passphrase: Uint8List.fromList(utf8.encode('secret')),
        ),
        'identity_backup_import.unsupported',
      );
    });

    test('unrelated unsupported capability keeps the inspect fallback', () async {
      final sdk = _ImportCore()
        ..error = const core.AwikiImCoreException(
          code: 'unsupported_capability',
          message: 'unsupported capability: group.e2ee',
          capability: 'group.e2ee',
        );

      await _expectCode(
        _adapterWithCore(sdk).inspectIdentityBackup(
          bytes: Uint8List.fromList(<int>[1]),
          passphrase: Uint8List.fromList(utf8.encode('secret')),
        ),
        'identity_backup_import.inspect_failed',
      );
    });

    test('other Core failures map to the inspect fallback', () async {
      final sdk = _ImportCore()
        ..error = const core.AwikiImCoreException(
          code: 'internal',
          message: 'vault unavailable',
        );

      await _expectCode(
        _adapterWithCore(sdk).inspectIdentityBackup(
          bytes: Uint8List.fromList(<int>[1]),
          passphrase: Uint8List.fromList(utf8.encode('secret')),
        ),
        'identity_backup_import.inspect_failed',
      );
    });

    test('adapter reports support', () {
      expect(_adapterWithCore(_ImportCore()).isSupported, isTrue);
    });
  });

  group('importIdentityBackup', () {
    test('passes presence confirmation and maps the outcome', () async {
      final sdk = _ImportCore();
      final adapter = _adapterWithCore(sdk);
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);
      final passphrase = Uint8List.fromList(utf8.encode('correct horse'));

      final outcome = await adapter.importIdentityBackup(
        bytes: bytes,
        passphrase: passphrase,
        userPresenceConfirmed: true,
      );

      expect(identical(sdk.bytes, bytes), isTrue);
      expect(identical(sdk.passphrase, passphrase), isTrue);
      expect(sdk.userPresenceConfirmed, isTrue);
      expect(outcome.identityId, 'identity-alice');
      expect(outcome.did, 'did:test:alice');
      expect(outcome.rootKeyId, 'root-1');
      expect(outcome.alreadyPresent, isFalse);
    });

    test('typed Core backup codes pass through', () async {
      final sdk = _ImportCore()
        ..error = const core.AwikiImCoreException(
          code: 'identity_backup_payload_invalid',
          message: 'payload invalid',
        );

      await _expectCode(
        _adapterWithCore(sdk).importIdentityBackup(
          bytes: Uint8List.fromList(<int>[1]),
          passphrase: Uint8List.fromList(utf8.encode('secret')),
          userPresenceConfirmed: true,
        ),
        'identity_backup_payload_invalid',
      );
    });

    test('permission_denied maps to denied', () async {
      final sdk = _ImportCore()
        ..error = const core.AwikiImCoreException(
          code: 'permission_denied',
          message: 'user presence not confirmed',
        );

      await _expectCode(
        _adapterWithCore(sdk).importIdentityBackup(
          bytes: Uint8List.fromList(<int>[1]),
          passphrase: Uint8List.fromList(utf8.encode('secret')),
          userPresenceConfirmed: false,
        ),
        'identity_backup_import.denied',
      );
    });

    test('identity_binding_conflict maps to conflict', () async {
      final sdk = _ImportCore()
        ..error = const core.AwikiImCoreException(
          code: 'identity_binding_conflict',
          message: 'root key already bound elsewhere',
        );

      await _expectCode(
        _adapterWithCore(sdk).importIdentityBackup(
          bytes: Uint8List.fromList(<int>[1]),
          passphrase: Uint8List.fromList(utf8.encode('secret')),
          userPresenceConfirmed: true,
        ),
        'identity_backup_import.conflict',
      );
    });

    test('missing capability maps to unsupported', () async {
      final sdk = _ImportCore()
        ..error = const core.AwikiImCoreException(
          code: 'unsupported_capability',
          message: 'unsupported capability: identity_backup.import',
          capability: 'identity_backup.import',
        );

      await _expectCode(
        _adapterWithCore(sdk).importIdentityBackup(
          bytes: Uint8List.fromList(<int>[1]),
          passphrase: Uint8List.fromList(utf8.encode('secret')),
          userPresenceConfirmed: true,
        ),
        'identity_backup_import.unsupported',
      );
    });

    test('other Core failures map to the import fallback', () async {
      final sdk = _ImportCore()
        ..error = const core.AwikiImCoreException(
          code: 'internal',
          message: 'vault unavailable',
        );

      await _expectCode(
        _adapterWithCore(sdk).importIdentityBackup(
          bytes: Uint8List.fromList(<int>[1]),
          passphrase: Uint8List.fromList(utf8.encode('secret')),
          userPresenceConfirmed: true,
        ),
        'identity_backup_import.failed',
      );
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

AwikiImCoreIdentityBackupImportAdapter _adapterWithCore(core.AwikiImCore sdk) {
  return AwikiImCoreIdentityBackupImportAdapter.withCoreInstance(
    coreInstance: () async => sdk,
  );
}

class _ImportCore implements core.AwikiImCore {
  Uint8List? bytes;
  Uint8List? passphrase;
  bool? userPresenceConfirmed;
  Object? error;

  @override
  Future<core.IdentityBackupInspection> inspectIdentityBackup(
    Uint8List bytes, {
    required Uint8List passphrase,
  }) async {
    this.bytes = bytes;
    this.passphrase = passphrase;
    if (error != null) throw error!;
    return const core.IdentityBackupInspection(
      did: 'did:test:alice',
      handle: 'alice.example.com',
      fullHandle: 'alice.example.com',
      displayName: 'Alice',
      custody: 'anp_root',
      createdAt: '2026-01-01T00:00:00Z',
      exportedAt: '2026-11-15T00:00:00Z',
      sourceCoreVersion: '0.1.0',
      keyKinds: <String>['did_document_root'],
      hasDidDocument: true,
    );
  }

  @override
  Future<core.IdentityImportResult> importIdentityBackup(
    Uint8List bytes, {
    required Uint8List passphrase,
    required bool userPresenceConfirmed,
  }) async {
    this.bytes = bytes;
    this.passphrase = passphrase;
    this.userPresenceConfirmed = userPresenceConfirmed;
    if (error != null) throw error!;
    return const core.IdentityImportResult(
      identityId: 'identity-alice',
      did: 'did:test:alice',
      rootKeyId: 'root-1',
      alreadyPresent: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
