/// Secret-free result of binding this device to an imported root-only DID.
///
/// The DID, Handle and root key never change; Core root-signs a replacement DID
/// Document that carries the freshly generated device keys.
class DeviceRebindOutcome {
  const DeviceRebindOutcome({
    required this.did,
    required this.deviceId,
    required this.alreadyBound,
  });

  final String did;
  final String deviceId;
  final bool alreadyBound;
}

class DeviceRebindException implements Exception {
  const DeviceRebindException(this.code, {this.cause});

  final String code;
  final Object? cause;

  @override
  String toString() => 'DeviceRebindException($code)';
}

abstract interface class DeviceRebindPort {
  bool get isSupported;

  /// Binds this device to the imported root-only identity selected by
  /// [identityId].
  ///
  /// [userPresenceConfirmed] must only be true after the host completed a real
  /// system authentication. Core fails closed when it is false.
  Future<DeviceRebindOutcome> rebindDevice({
    required String identityId,
    required bool userPresenceConfirmed,
  });
}

/// Fail-closed default used until the Core SDK exposes device rebind.
class UnsupportedDeviceRebindPort implements DeviceRebindPort {
  const UnsupportedDeviceRebindPort();

  @override
  bool get isSupported => false;

  @override
  Future<DeviceRebindOutcome> rebindDevice({
    required String identityId,
    required bool userPresenceConfirmed,
  }) async {
    throw const DeviceRebindException('device_rebind.unsupported');
  }
}
