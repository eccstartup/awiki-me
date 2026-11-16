// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

import 'package:awiki_me/src/application/ports/identity_backup_import_port.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/onboarding/restore_identity_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _did = 'did:wba:awiki.info:users:alice';
const _identityId = 'identity-alice-device-a';

SessionIdentity _credential({
  String did = _did,
  String? localIdentityId = _identityId,
  String credentialName = 'default',
  String displayName = 'Alice',
  String? handle = 'alice.awiki.info',
  bool rootOnly = false,
}) {
  return SessionIdentity(
    did: did,
    credentialName: credentialName,
    displayName: displayName,
    localIdentityId: localIdentityId,
    handle: handle,
    rootOnly: rootOnly,
  );
}

RestoreIdentityIntent _intent({
  String identityId = _identityId,
  String did = _did,
  String? handle,
}) {
  return RestoreIdentityIntent(
    identityId: identityId,
    did: did,
    handle: handle,
  );
}

void main() {
  test('a same-DID non-root credential resolves to direct entry', () {
    final view = resolveRestoreIdentityView(
      intent: _intent(),
      credentials: <SessionIdentity>[_credential()],
      recoveryAvailable: true,
      importSupported: true,
    );

    expect(view, isNotNull);
    expect(view!.phase, RestoreIdentityPhase.directEntry);
    expect(view.canEnterDirectly, isTrue);
    expect(view.did, _did);
    expect(view.identityId, _identityId);
    expect(view.credential?.credentialName, 'default');
    expect(view.handle, 'alice.awiki.info');
    expect(view.displayName, 'Alice');
    expect(view.recoveryAvailable, isTrue);
    expect(view.importSupported, isTrue);
  });

  test('only the imported root credential resolves to authorization required', () {
    final view = resolveRestoreIdentityView(
      intent: _intent(),
      credentials: <SessionIdentity>[
        _credential(credentialName: 'root', rootOnly: true),
      ],
      recoveryAvailable: true,
    );

    expect(view!.phase, RestoreIdentityPhase.authorizationRequired);
    expect(view.canEnterDirectly, isFalse);
    expect(view.credential?.rootOnly, isTrue);
    expect(view.recoveryAvailable, isTrue);
  });

  test('a root credential never becomes direct entry even when listed first', () {
    final view = resolveRestoreIdentityView(
      intent: _intent(),
      credentials: <SessionIdentity>[
        _credential(credentialName: 'root', rootOnly: true),
        _credential(credentialName: 'device'),
      ],
    );

    expect(view!.phase, RestoreIdentityPhase.directEntry);
    expect(view.credential?.credentialName, 'device');
  });

  test('missing credentials resolve to credential refresh', () {
    final view = resolveRestoreIdentityView(
      intent: _intent(),
      credentials: const <SessionIdentity>[],
      importSupported: true,
    );

    expect(view!.phase, RestoreIdentityPhase.credentialMissing);
    expect(view.credential, isNull);
    expect(view.importSupported, isTrue);
  });

  test('credentials are not matched by Handle', () {
    final view = resolveRestoreIdentityView(
      intent: _intent(identityId: '', did: 'did:wba:other.example:users:alice'),
      credentials: <SessionIdentity>[_credential()],
    );

    expect(view!.phase, RestoreIdentityPhase.credentialMissing);
  });

  test('a same-DID credential with a different local identity id is not used', () {
    final view = resolveRestoreIdentityView(
      intent: _intent(),
      credentials: <SessionIdentity>[
        _credential(localIdentityId: 'identity-alice-device-b'),
      ],
    );

    expect(view!.phase, RestoreIdentityPhase.credentialMissing);
  });

  test('an exact identity match wins over a same-DID unbound credential', () {
    final view = resolveRestoreIdentityView(
      intent: _intent(),
      credentials: <SessionIdentity>[
        _credential(localIdentityId: null, credentialName: 'unbound'),
        _credential(credentialName: 'exact', rootOnly: true),
      ],
    );

    expect(view!.phase, RestoreIdentityPhase.authorizationRequired);
    expect(view.credential?.credentialName, 'exact');
  });

  test('a DID-only credential still resolves when Core omits the stable id', () {
    final view = resolveRestoreIdentityView(
      intent: _intent(),
      credentials: <SessionIdentity>[_credential(localIdentityId: null)],
    );

    expect(view!.phase, RestoreIdentityPhase.directEntry);
  });

  test('an intent without DID or identity id has no view', () {
    expect(
      resolveRestoreIdentityView(
        intent: const RestoreIdentityIntent(identityId: '', did: ''),
        credentials: const <SessionIdentity>[],
      ),
      isNull,
    );
  });

  test('the view falls back to the intent handle when no credential exists', () {
    final view = resolveRestoreIdentityView(
      intent: _intent(handle: 'alice.awiki.info'),
      credentials: const <SessionIdentity>[],
    );

    expect(view!.handle, 'alice.awiki.info');
    expect(view.displayName, isNull);
  });

  test('the controller seeds from an import outcome and clears', () {
    final controller = RestoreIdentityController();
    addTearDown(controller.dispose);

    expect(controller.state, isNull);

    controller.beginFromOutcome(
      const IdentityBackupImportOutcome(
        identityId: _identityId,
        did: _did,
        rootKeyId: 'root-key',
        alreadyPresent: false,
      ),
    );

    expect(controller.state!.identityId, _identityId);
    expect(controller.state!.did, _did);
    expect(controller.state!.alreadyPresent, isFalse);

    controller.clear();

    expect(controller.state, isNull);
  });

  test('the controller seeds from an existing root credential', () {
    final controller = RestoreIdentityController();
    addTearDown(controller.dispose);

    controller.beginForCredential(
      _credential(credentialName: 'root', rootOnly: true),
    );

    expect(controller.state!.identityId, _identityId);
    expect(controller.state!.did, _did);
    expect(controller.state!.handle, 'alice.awiki.info');
    expect(controller.state!.displayName, 'Alice');
  });

  test('an already present import still resolves the current local state', () {
    final controller = RestoreIdentityController();
    addTearDown(controller.dispose);

    controller.begin(
      const RestoreIdentityIntent(
        identityId: _identityId,
        did: _did,
        alreadyPresent: true,
      ),
    );

    final view = resolveRestoreIdentityView(
      intent: controller.state!,
      credentials: <SessionIdentity>[_credential()],
    );

    expect(view!.phase, RestoreIdentityPhase.directEntry);
  });
}
