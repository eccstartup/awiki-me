import 'package:awiki_me/src/application/device_rebind_service.dart';
import 'package:awiki_me/src/application/ports/device_rebind_port.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:flutter_test/flutter_test.dart';

const _identityId = 'identity-alice';
const _did = 'did:wba:awiki.me:users:alice:e1_bound';

class _FakeDeviceRebindPort implements DeviceRebindPort {
  _FakeDeviceRebindPort({
    this.supported = true,
    this.outcome = const DeviceRebindOutcome(
      did: _did,
      deviceId: 'device-new',
      alreadyBound: false,
    ),
    this.error,
  });

  bool supported;
  DeviceRebindOutcome outcome;
  Object? error;
  int calls = 0;
  String? lastIdentityId;
  bool? lastUserPresenceConfirmed;

  @override
  bool get isSupported => supported;

  @override
  Future<DeviceRebindOutcome> rebindDevice({
    required String identityId,
    required bool userPresenceConfirmed,
  }) async {
    calls += 1;
    lastIdentityId = identityId;
    lastUserPresenceConfirmed = userPresenceConfirmed;
    final failure = error;
    if (failure != null) throw failure;
    return outcome;
  }
}

class _FakeUserPresence implements UserPresencePort {
  _FakeUserPresence({this.result = true});

  bool result;
  int calls = 0;
  String? lastReason;

  @override
  Future<bool> confirm({required String reason}) async {
    calls += 1;
    lastReason = reason;
    return result;
  }
}

DeviceRebindService _service({
  _FakeDeviceRebindPort? port,
  _FakeUserPresence? presence,
}) {
  return DeviceRebindService(
    rebind: port ?? _FakeDeviceRebindPort(),
    userPresence: presence ?? _FakeUserPresence(),
  );
}

Future<DeviceRebindOutcome> _rebind(
  DeviceRebindService service, {
  String identityId = _identityId,
  String expectedDid = _did,
  String presenceReason = 'bind this device to the imported identity',
  bool Function()? contextStillValid,
}) {
  return service.rebind(
    identityId: identityId,
    expectedDid: expectedDid,
    presenceReason: presenceReason,
    contextStillValid: contextStillValid ?? () => true,
  );
}

Matcher _deviceRebindError(String code) {
  return isA<DeviceRebindException>().having(
    (error) => error.code,
    'code',
    code,
  );
}

void main() {
  test('a confirmed rebind returns the same-DID outcome', () async {
    final port = _FakeDeviceRebindPort();
    final presence = _FakeUserPresence();
    final outcome = await _rebind(
      _service(port: port, presence: presence),
      identityId: ' $_identityId ',
      presenceReason: '  bind device  ',
    );

    expect(outcome.did, _did);
    expect(outcome.deviceId, 'device-new');
    expect(outcome.alreadyBound, isFalse);
    expect(presence.calls, 1);
    expect(presence.lastReason, 'bind device');
    expect(port.calls, 1);
    expect(port.lastIdentityId, _identityId);
    expect(port.lastUserPresenceConfirmed, isTrue);
  });

  test('an unsupported Core fails closed before user presence', () async {
    final port = _FakeDeviceRebindPort(supported: false);
    final presence = _FakeUserPresence();

    await expectLater(
      _rebind(_service(port: port, presence: presence)),
      throwsA(_deviceRebindError('device_rebind.unsupported')),
    );
    expect(presence.calls, 0);
    expect(port.calls, 0);
  });

  test('an empty identity, DID or presence reason is rejected', () async {
    final port = _FakeDeviceRebindPort();
    final presence = _FakeUserPresence();
    final service = _service(port: port, presence: presence);

    await expectLater(
      _rebind(service, identityId: '  '),
      throwsA(_deviceRebindError('device_rebind.invalid_request')),
    );
    await expectLater(
      _rebind(service, expectedDid: '  '),
      throwsA(_deviceRebindError('device_rebind.invalid_request')),
    );
    await expectLater(
      _rebind(service, presenceReason: '  '),
      throwsA(_deviceRebindError('device_rebind.invalid_request')),
    );
    expect(presence.calls, 0);
    expect(port.calls, 0);
  });

  test('denied user presence never reaches Core', () async {
    final port = _FakeDeviceRebindPort();
    final presence = _FakeUserPresence(result: false);

    await expectLater(
      _rebind(_service(port: port, presence: presence)),
      throwsA(_deviceRebindError('device_rebind.user_presence_denied')),
    );
    expect(port.calls, 0);
  });

  test('an invalidated context stops before Core', () async {
    final port = _FakeDeviceRebindPort();

    await expectLater(
      _rebind(_service(port: port), contextStillValid: () => false),
      throwsA(_deviceRebindError('device_rebind.state_changed')),
    );
    expect(port.calls, 0);
  });

  test(
    'a different DID or missing device id is treated as a lost context',
    () async {
      final wrongDid = _FakeDeviceRebindPort(
        outcome: const DeviceRebindOutcome(
          did: 'did:wba:awiki.me:users:mallory:e1_other',
          deviceId: 'device-new',
          alreadyBound: false,
        ),
      );
      final missingDevice = _FakeDeviceRebindPort(
        outcome: const DeviceRebindOutcome(
          did: _did,
          deviceId: '  ',
          alreadyBound: true,
        ),
      );

      await expectLater(
        _rebind(_service(port: wrongDid)),
        throwsA(_deviceRebindError('device_rebind.state_changed')),
      );
      await expectLater(
        _rebind(_service(port: missingDevice)),
        throwsA(_deviceRebindError('device_rebind.state_changed')),
      );
    },
  );

  test('Core errors propagate unchanged', () async {
    final port = _FakeDeviceRebindPort(
      error: const DeviceRebindException('device_rebind.conflict'),
    );

    await expectLater(
      _rebind(_service(port: port)),
      throwsA(_deviceRebindError('device_rebind.conflict')),
    );
    expect(port.calls, 1);
  });

  test('the unsupported default port fails closed', () async {
    const port = UnsupportedDeviceRebindPort();

    expect(port.isSupported, isFalse);
    await expectLater(
      port.rebindDevice(identityId: _identityId, userPresenceConfirmed: true),
      throwsA(_deviceRebindError('device_rebind.unsupported')),
    );
    await expectLater(
      _rebind(
        DeviceRebindService(rebind: port, userPresence: _FakeUserPresence()),
      ),
      throwsA(_deviceRebindError('device_rebind.unsupported')),
    );
  });
}
