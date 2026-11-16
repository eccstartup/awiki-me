// [INPUT]: Secret-free identity backup import outcomes and local credential inventory.
// [OUTPUT]: The single next step for a restored identity (direct entry, device join, or credential refresh).
// [POS]: Pure presentation state for the login restore panel; never logs in or mutates identity material.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/ports/identity_backup_import_port.dart';
import '../../domain/entities/session_identity.dart';

/// The identity a restore started for. It is matched against local credentials
/// by DID and exact local identity ID; the Handle is display-only.
class RestoreIdentityIntent {
  const RestoreIdentityIntent({
    required this.identityId,
    required this.did,
    this.handle,
    this.displayName,
    this.alreadyPresent = false,
  });

  factory RestoreIdentityIntent.fromOutcome(
    IdentityBackupImportOutcome outcome,
  ) {
    return RestoreIdentityIntent(
      identityId: outcome.identityId.trim(),
      did: outcome.did.trim(),
      alreadyPresent: outcome.alreadyPresent,
    );
  }

  factory RestoreIdentityIntent.fromCredential(SessionIdentity credential) {
    return RestoreIdentityIntent(
      identityId: credential.localIdentityId?.trim() ?? '',
      did: credential.did.trim(),
      handle: credential.handle,
      displayName: credential.displayName,
    );
  }

  final String identityId;
  final String did;
  final String? handle;
  final String? displayName;
  final bool alreadyPresent;
}

enum RestoreIdentityPhase {
  /// A same-DID non-root credential exists: one-tap login, no OTP.
  directEntry,

  /// Only the imported root credential exists: this machine still needs a
  /// Device Join (same DID) or, as a last resort, Handle Recovery (new DID).
  authorizationRequired,

  /// Nothing for this identity remains locally: refresh or import again.
  credentialMissing,
}

class RestoreIdentityView {
  const RestoreIdentityView({
    required this.phase,
    required this.identityId,
    required this.did,
    required this.handle,
    required this.displayName,
    required this.credential,
    required this.recoveryAvailable,
    required this.importSupported,
    this.rebindAvailable = false,
  });

  final RestoreIdentityPhase phase;
  final String identityId;
  final String did;
  final String? handle;
  final String? displayName;

  /// The usable credential in [RestoreIdentityPhase.directEntry], otherwise
  /// the sole root credential when one exists.
  final SessionIdentity? credential;

  /// Server declares phone-based Handle Recovery; Recovery changes the DID.
  final bool recoveryAvailable;

  /// Core supports importing another backup.
  final bool importSupported;

  /// Server and Core can bind this device to the imported root-only DID by
  /// root-signing a replacement DID Document (DID and root key unchanged).
  final bool rebindAvailable;

  bool get canEnterDirectly => phase == RestoreIdentityPhase.directEntry;
}

RestoreIdentityView? resolveRestoreIdentityView({
  required RestoreIdentityIntent intent,
  required List<SessionIdentity> credentials,
  bool recoveryAvailable = false,
  bool importSupported = false,
  bool rebindAvailable = false,
}) {
  final identityId = intent.identityId.trim();
  final did = intent.did.trim();
  if (identityId.isEmpty && did.isEmpty) {
    return null;
  }
  final matching = _matchingCredentials(
    credentials,
    identityId: identityId,
    did: did,
  );
  final usable = matching.where((credential) => !credential.rootOnly);
  final rootOnly = matching.where((credential) => credential.rootOnly);
  final credential = usable.isNotEmpty
      ? usable.first
      : (rootOnly.isNotEmpty ? rootOnly.first : null);
  final phase = usable.isNotEmpty
      ? RestoreIdentityPhase.directEntry
      : (rootOnly.isNotEmpty
            ? RestoreIdentityPhase.authorizationRequired
            : RestoreIdentityPhase.credentialMissing);
  return RestoreIdentityView(
    phase: phase,
    identityId: identityId,
    did: did.isEmpty ? credential?.did.trim() ?? '' : did,
    handle: _nonEmpty(credential?.handle) ?? _nonEmpty(intent.handle),
    displayName:
        _nonEmpty(credential?.displayName) ?? _nonEmpty(intent.displayName),
    credential: credential,
    recoveryAvailable: recoveryAvailable,
    importSupported: importSupported,
    rebindAvailable:
        rebindAvailable &&
        phase == RestoreIdentityPhase.authorizationRequired,
  );
}

List<SessionIdentity> _matchingCredentials(
  List<SessionIdentity> credentials, {
  required String identityId,
  required String did,
}) {
  final exact = <SessionIdentity>[];
  final byDidOnly = <SessionIdentity>[];
  for (final credential in credentials) {
    final credentialDid = credential.did.trim();
    if (did.isNotEmpty && credentialDid != did) {
      continue;
    }
    final credentialIdentityId = credential.localIdentityId?.trim() ?? '';
    if (identityId.isNotEmpty && credentialIdentityId == identityId) {
      exact.add(credential);
    } else if (identityId.isEmpty || credentialIdentityId.isEmpty) {
      byDidOnly.add(credential);
    }
  }
  // Prefer the exact identity; fall back to a DID match only when Core did not
  // surface a stable local identity ID to compare against.
  return exact.isNotEmpty ? exact : byDidOnly;
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

class RestoreIdentityController
    extends StateNotifier<RestoreIdentityIntent?> {
  RestoreIdentityController() : super(null);

  void begin(RestoreIdentityIntent intent) {
    state = intent;
  }

  void beginFromOutcome(IdentityBackupImportOutcome outcome) {
    state = RestoreIdentityIntent.fromOutcome(outcome);
  }

  void beginForCredential(SessionIdentity credential) {
    state = RestoreIdentityIntent.fromCredential(credential);
  }

  void clear() {
    state = null;
  }
}

final restoreIdentityProvider =
    StateNotifierProvider<RestoreIdentityController, RestoreIdentityIntent?>(
      (ref) => RestoreIdentityController(),
    );
