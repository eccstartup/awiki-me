// [INPUT]: Exact restore intent and one platform user-presence confirmation.
// [OUTPUT]: Fail-closed bind outcome for the same DID.
// [POS]: Application policy around the Core-owned root-signed rebind.

import 'ports/device_rebind_port.dart';
import 'ports/user_presence_port.dart';

class DeviceRebindService {
  const DeviceRebindService({
    required DeviceRebindPort rebind,
    required UserPresencePort userPresence,
  }) : _rebind = rebind,
       _userPresence = userPresence;

  final DeviceRebindPort _rebind;
  final UserPresencePort _userPresence;

  Future<DeviceRebindOutcome> rebind({
    required String identityId,
    required String expectedDid,
    required String presenceReason,
    required bool Function() contextStillValid,
  }) async {
    if (!_rebind.isSupported) {
      throw const DeviceRebindException('device_rebind.unsupported');
    }
    final normalizedId = identityId.trim();
    final normalizedDid = expectedDid.trim();
    final reason = presenceReason.trim();
    if (normalizedId.isEmpty || normalizedDid.isEmpty || reason.isEmpty) {
      throw const DeviceRebindException('device_rebind.invalid_request');
    }
    final confirmed = await _userPresence.confirm(reason: reason);
    if (!confirmed) {
      throw const DeviceRebindException(
        'device_rebind.user_presence_denied',
      );
    }
    if (!contextStillValid()) {
      throw const DeviceRebindException('device_rebind.state_changed');
    }
    final outcome = await _rebind.rebindDevice(
      identityId: normalizedId,
      userPresenceConfirmed: true,
    );
    if (outcome.did != normalizedDid || outcome.deviceId.trim().isEmpty) {
      throw const DeviceRebindException('device_rebind.state_changed');
    }
    return outcome;
  }
}
