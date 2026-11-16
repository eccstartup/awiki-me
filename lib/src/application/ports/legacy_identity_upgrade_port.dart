enum LegacyIdentityUpgradePhase { idle, running, retryRequired, completed }

/// Core status code for an ANP-custody identity installed from an identity
/// backup: it owns the DID root capability but has no device binding, so it
/// cannot log in until a real device Join (or Handle Recovery) authorizes this
/// machine. Retrying the legacy upgrade can never change that.
const String rootOnlyRequiresDeviceJoinCode = 'root_only_requires_device_join';

class LegacyIdentityUpgradeStatus {
  const LegacyIdentityUpgradeStatus._({
    required this.phase,
    this.identityId,
    this.failureCode,
  });

  const LegacyIdentityUpgradeStatus.idle()
    : this._(phase: LegacyIdentityUpgradePhase.idle);

  const LegacyIdentityUpgradeStatus.running()
    : this._(phase: LegacyIdentityUpgradePhase.running);

  const LegacyIdentityUpgradeStatus.retryRequired({
    required String identityId,
    String failureCode = 'legacy_upgrade_failed',
  }) : this._(
         phase: LegacyIdentityUpgradePhase.retryRequired,
         identityId: identityId,
         failureCode: failureCode,
       );

  const LegacyIdentityUpgradeStatus.completed()
    : this._(phase: LegacyIdentityUpgradePhase.completed);

  final LegacyIdentityUpgradePhase phase;
  final String? identityId;
  final String? failureCode;

  bool get requiresDeviceJoin =>
      phase == LegacyIdentityUpgradePhase.retryRequired &&
      failureCode == rootOnlyRequiresDeviceJoinCode;
}

abstract interface class LegacyIdentityUpgradePort {
  Future<LegacyIdentityUpgradeStatus> legacyUpgradeStatus(
    String identityIdOrAlias,
  );

  Future<LegacyIdentityUpgradeStatus> upgradeLegacyIdentity(
    String identityIdOrAlias,
  );
}
