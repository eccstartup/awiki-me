import 'dart:convert';
import 'dart:typed_data';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/ports/identity_export_port.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_identity_export_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'passes the exact local identity and caller passphrase to Core',
    () async {
      final sdk = _ExportCore();
      final adapter = _adapterWithCore(sdk);
      final passphrase = Uint8List.fromList(utf8.encode('correct horse'));

      final package = await adapter.exportIdentityPackage(
        identityId: 'identity-alice',
        passphrase: passphrase,
      );

      expect(sdk.selector, isA<core.IdIdentitySelector>());
      expect((sdk.selector! as core.IdIdentitySelector).id, 'identity-alice');
      expect(sdk.passphrase, passphrase);
      expect(identical(sdk.passphrase, passphrase), isTrue);
      expect(package.fileName, 'awiki-identity-alice.awiki-backup');
      expect(package.mimeType, 'application/vnd.awiki.identity-backup');
      expect(package.bytes, sdk.bytes);
    },
  );

  test('custody-only identities fail closed as unsupported', () async {
    final sdk = _ExportCore()
      ..error = const core.AwikiImCoreException(
        code: 'unsupported_capability',
        message: 'unsupported capability: identity_backup.custody_only',
        capability: 'identity_backup.custody_only',
      );
    final adapter = _adapterWithCore(sdk);

    await expectLater(
      adapter.exportIdentityPackage(
        identityId: 'identity-alice',
        passphrase: Uint8List.fromList(utf8.encode('correct horse')),
      ),
      throwsA(
        isA<IdentityExportException>().having(
          (error) => error.code,
          'code',
          'identity_export.unsupported',
        ),
      ),
    );
  });

  test('other Core failures map to a closed export error', () async {
    final sdk = _ExportCore()
      ..error = const core.AwikiImCoreException(
        code: 'internal',
        message: 'vault unavailable',
      );
    final adapter = _adapterWithCore(sdk);

    await expectLater(
      adapter.exportIdentityPackage(
        identityId: 'identity-alice',
        passphrase: Uint8List.fromList(utf8.encode('correct horse')),
      ),
      throwsA(
        isA<IdentityExportException>().having(
          (error) => error.code,
          'code',
          'identity_export.failed',
        ),
      ),
    );
  });
}

AwikiImCoreIdentityExportAdapter _adapterWithCore(core.AwikiImCore sdk) {
  return AwikiImCoreIdentityExportAdapter.withCoreInstance(
    coreInstance: () async => sdk,
  );
}

class _ExportCore implements core.AwikiImCore {
  final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
  core.IdentitySelector? selector;
  Uint8List? passphrase;
  Object? error;

  @override
  Future<core.IdentityBackupPackage> exportIdentityBackup(
    core.IdentitySelector selector, {
    required Uint8List passphrase,
  }) async {
    this.selector = selector;
    this.passphrase = passphrase;
    if (error != null) throw error!;
    return core.IdentityBackupPackage(
      fileName: 'awiki-identity-alice.awiki-backup',
      mimeType: 'application/vnd.awiki.identity-backup',
      bytes: bytes,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
