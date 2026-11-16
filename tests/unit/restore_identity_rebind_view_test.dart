import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/onboarding/restore_identity_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _did = 'did:wba:awiki.me:users:alice:e1_imported';
const _identityId = 'identity-alice';

SessionIdentity _credential({bool rootOnly = false}) {
  return SessionIdentity(
    did: _did,
    localIdentityId: _identityId,
    credentialName: rootOnly ? 'root' : 'device',
    displayName: 'Alice',
    rootOnly: rootOnly,
  );
}

RestoreIdentityView _view({
  required List<SessionIdentity> credentials,
  bool rebindAvailable = false,
}) {
  return resolveRestoreIdentityView(
    intent: const RestoreIdentityIntent(identityId: _identityId, did: _did),
    credentials: credentials,
    rebindAvailable: rebindAvailable,
  )!;
}

void main() {
  test('rebind is offered when only the imported root credential remains', () {
    final view = _view(
      credentials: <SessionIdentity>[_credential(rootOnly: true)],
      rebindAvailable: true,
    );

    expect(view.phase, RestoreIdentityPhase.authorizationRequired);
    expect(view.rebindAvailable, isTrue);
  });

  test('rebind is hidden when the device capability gate is closed', () {
    final view = _view(
      credentials: <SessionIdentity>[_credential(rootOnly: true)],
    );

    expect(view.phase, RestoreIdentityPhase.authorizationRequired);
    expect(view.rebindAvailable, isFalse);
  });

  test('rebind never appears next to direct entry', () {
    final view = _view(
      credentials: <SessionIdentity>[_credential()],
      rebindAvailable: true,
    );

    expect(view.phase, RestoreIdentityPhase.directEntry);
    expect(view.rebindAvailable, isFalse);
  });

  test('rebind never appears when the credential is missing', () {
    final view = _view(
      credentials: const <SessionIdentity>[],
      rebindAvailable: true,
    );

    expect(view.phase, RestoreIdentityPhase.credentialMissing);
    expect(view.rebindAvailable, isFalse);
  });
}
