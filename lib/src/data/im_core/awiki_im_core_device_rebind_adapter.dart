// [INPUT]: Exact local identity id from the restore-identity intent.
// [OUTPUT]: Secret-free bind outcome for the same DID.
// [POS]: Thin Dart adapter; document signing, operation retry and key
// installation stay inside Core.

import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/ports/device_rebind_port.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreDeviceRebindAdapter implements DeviceRebindPort {
  AwikiImCoreDeviceRebindAdapter({required AwikiImCoreRuntime runtime})
    : _coreInstance = runtime.coreInstance;

  AwikiImCoreDeviceRebindAdapter.withCoreInstance({
    required Future<core.AwikiImCore> Function() coreInstance,
  }) : _coreInstance = coreInstance;

  final Future<core.AwikiImCore> Function() _coreInstance;

  @override
  bool get isSupported => true;

  @override
  Future<DeviceRebindOutcome> rebindDevice({
    required String identityId,
    required bool userPresenceConfirmed,
  }) async {
    final normalizedId = identityId.trim();
    if (normalizedId.isEmpty) {
      throw const DeviceRebindException('device_rebind.invalid_request');
    }
    final instance = await _coreInstance();
    try {
      final result = await instance.rebindDevice(
        selector: core.IdentitySelector.id(normalizedId),
        userPresenceConfirmed: userPresenceConfirmed,
      );
      return DeviceRebindOutcome(
        did: result.did,
        deviceId: result.deviceId,
        alreadyBound: result.alreadyBound,
      );
    } on core.AwikiImCoreException catch (error) {
      throw _mapError(error);
    }
  }

  DeviceRebindException _mapError(core.AwikiImCoreException error) {
    final code = error.code;
    if (code == 'permission_denied') {
      return DeviceRebindException('device_rebind.denied', cause: error);
    }
    if (code == 'identity_binding_conflict') {
      return DeviceRebindException('device_rebind.conflict', cause: error);
    }
    if (code == 'unsupported_capability') {
      return DeviceRebindException('device_rebind.unsupported', cause: error);
    }
    return DeviceRebindException('device_rebind.failed', cause: error);
  }
}
