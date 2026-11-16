import 'package:awiki_me/src/application/models/onboarding_server_info.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _method({
  Object? id = OnboardingDeviceRebindCapabilities.rootSignatureMethodId,
  Object? enabled = true,
  Object? verification = const <String, Object?>{
    'required': true,
    'type': OnboardingDeviceRebindCapabilities.rootSignatureVerificationType,
  },
}) {
  return <String, Object?>{
    'id': id,
    'enabled': enabled,
    'verification': verification,
  };
}

Map<String, Object?> _capability({
  Object? enabled = true,
  Object? purpose = OnboardingDeviceRebindCapabilities.purpose,
  Object? methods,
}) {
  return <String, Object?>{
    'enabled': enabled,
    'purpose': purpose,
    'methods': methods ?? <Object?>[_method()],
  };
}

OnboardingServerInfo _serverInfo(Map<String, Object?> identity) {
  return OnboardingServerInfo.fromJson(<String, Object?>{
    'schema_version': 1,
    'service': <String, Object?>{
      'kind': 'awiki-open-server',
      'name': 'AWiki Open Server',
    },
    'identity': identity,
  });
}

void main() {
  test('a root-signature declaration enables device rebind', () {
    final capability = OnboardingDeviceRebindCapabilities.fromJson(
      _capability(),
    );

    expect(capability.enabled, isTrue);
  });

  test('an omitted purpose is accepted', () {
    final raw = _capability()..remove('purpose');

    expect(OnboardingDeviceRebindCapabilities.fromJson(raw).enabled, isTrue);
  });

  test('a missing or non-map declaration is disabled', () {
    expect(OnboardingDeviceRebindCapabilities.fromJson(null).enabled, isFalse);
    expect(
      OnboardingDeviceRebindCapabilities.fromJson('enabled').enabled,
      isFalse,
    );
    expect(
      OnboardingDeviceRebindCapabilities.fromJson(<String, Object?>{}).enabled,
      isFalse,
    );
  });

  test('a disabled declaration is disabled', () {
    expect(
      OnboardingDeviceRebindCapabilities.fromJson(
        _capability(enabled: false),
      ).enabled,
      isFalse,
    );
    expect(
      OnboardingDeviceRebindCapabilities.fromJson(
        _capability(enabled: 'true'),
      ).enabled,
      isFalse,
    );
  });

  test('an unknown purpose is disabled', () {
    expect(
      OnboardingDeviceRebindCapabilities.fromJson(
        _capability(purpose: 'awiki.identity.device-rebind.v2'),
      ).enabled,
      isFalse,
    );
  });

  test('exactly one supported method is required', () {
    expect(
      OnboardingDeviceRebindCapabilities.fromJson(
        _capability(methods: const <Object?>[]),
      ).enabled,
      isFalse,
    );
    expect(
      OnboardingDeviceRebindCapabilities.fromJson(
        _capability(methods: <Object?>[_method(), _method()]),
      ).enabled,
      isFalse,
    );
    expect(
      OnboardingDeviceRebindCapabilities.fromJson(
        _capability(methods: const <Object?>['root_signature']),
      ).enabled,
      isFalse,
    );
  });

  test('an unexpected method id or disabled method is disabled', () {
    expect(
      OnboardingDeviceRebindCapabilities.fromJson(
        _capability(methods: <Object?>[_method(id: 'phone_otp')]),
      ).enabled,
      isFalse,
    );
    expect(
      OnboardingDeviceRebindCapabilities.fromJson(
        _capability(methods: <Object?>[_method(enabled: false)]),
      ).enabled,
      isFalse,
    );
  });

  test('the proof verification must be required and root-signature typed', () {
    expect(
      OnboardingDeviceRebindCapabilities.fromJson(
        _capability(
          methods: <Object?>[
            _method(verification: const <String, Object?>{'required': false}),
          ],
        ),
      ).enabled,
      isFalse,
    );
    expect(
      OnboardingDeviceRebindCapabilities.fromJson(
        _capability(
          methods: <Object?>[
            _method(
              verification: const <String, Object?>{
                'required': true,
                'type': 'did_document_device_signature',
              },
            ),
          ],
        ),
      ).enabled,
      isFalse,
    );
    expect(
      OnboardingDeviceRebindCapabilities.fromJson(
        _capability(methods: <Object?>[_method(verification: 'required')]),
      ).enabled,
      isFalse,
    );
  });

  test('server info exposes the capability only through identity', () {
    final supported = _serverInfo(<String, Object?>{
      'handle_registration': <String, Object?>{
        'enabled': false,
        'methods': <Object?>[],
      },
      'device_rebind': _capability(),
    });
    final unsupported = _serverInfo(<String, Object?>{
      'handle_registration': <String, Object?>{
        'enabled': false,
        'methods': <Object?>[],
      },
    });

    expect(supported.supportsRootSignatureDeviceRebind, isTrue);
    expect(unsupported.supportsRootSignatureDeviceRebind, isFalse);
    expect(
      OnboardingServerInfo.openServerDefault()
          .supportsRootSignatureDeviceRebind,
      isFalse,
    );
  });
}
