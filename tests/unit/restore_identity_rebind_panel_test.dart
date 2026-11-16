import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/application/models/onboarding_server_info.dart';
import 'package:awiki_me/src/application/ports/device_rebind_port.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/onboarding/restore_identity_provider.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

const _did = 'did:wba:awiki.me:users:alice:e1_imported';
const _identityId = 'identity-alice';

const _rootOnlyCredential = SessionIdentity(
  did: _did,
  localIdentityId: _identityId,
  credentialName: 'imported-root',
  displayName: 'Alice',
  handle: 'alice.awiki.me',
  rootOnly: true,
);

OnboardingServerInfo _serverInfo({required bool deviceRebind}) {
  final base = OnboardingServerInfo.userServiceDefault();
  return OnboardingServerInfo(
    schemaVersion: base.schemaVersion,
    service: base.service,
    identity: OnboardingIdentityCapabilities(
      handleRegistration: base.identity.handleRegistration,
      handleRecovery: base.identity.handleRecovery,
      deviceRebind: OnboardingDeviceRebindCapabilities(enabled: deviceRebind),
    ),
  );
}

class _FakeRebindPort implements DeviceRebindPort {
  _FakeRebindPort({this.supported = true});

  final bool supported;
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
    return const DeviceRebindOutcome(
      did: _did,
      deviceId: 'device-new',
      alreadyBound: false,
    );
  }
}

class _FakePresence implements UserPresencePort {
  _FakePresence({this.result = true});

  final bool result;
  int calls = 0;

  @override
  Future<bool> confirm({required String reason}) async {
    calls += 1;
    return result;
  }
}

void _setTestViewSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _settleVerificationStep(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final next = find.text('下一步');
  if (next.evaluate().isEmpty ||
      find.byKey(const Key('registration-entry-form')).evaluate().isEmpty) {
    return;
  }
  final field = find.byType(CupertinoTextField).first;
  if (tester.widget<CupertinoTextField>(field).controller!.text.isEmpty) {
    await tester.enterText(field, 'alice');
    await tester.pump();
  }
  await tester.ensureVisible(next);
  await tester.tap(next);
  await tester.pumpAndSettle();
}

Future<ProviderContainer> _openRestorePanel(
  WidgetTester tester, {
  required OnboardingServerInfo serverInfo,
  required List<Override> overrides,
  List<SessionIdentity> credentials = const <SessionIdentity>[
    _rootOnlyCredential,
  ],
}) async {
  _setTestViewSize(tester, const Size(390, 844));
  final gateway = FakeAwikiGateway()
    ..localCredentials = credentials
    ..serverInfo = serverInfo;
  await tester.pumpWidget(
    buildLocalizedTestApp(
      home: const OnboardingPage(),
      gateway: gateway,
      providerOverrides: overrides,
    ),
  );
  await _settleVerificationStep(tester);
  await tester.tap(find.byKey(const Key('onboarding-identity-entry')));
  await tester.pumpAndSettle();

  final container = ProviderScope.containerOf(
    tester.element(find.byType(OnboardingPage)),
  );
  container
      .read(restoreIdentityProvider.notifier)
      .begin(const RestoreIdentityIntent(identityId: _identityId, did: _did));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('恢复面板：导入根凭据后可把本机绑定到同一 DID', (tester) async {
    await _openRestorePanel(
      tester,
      serverInfo: _serverInfo(deviceRebind: true),
      overrides: <Override>[
        deviceRebindPortProvider.overrideWithValue(_FakeRebindPort()),
      ],
    );

    expect(find.byKey(const Key('restore-identity-panel')), findsOneWidget);
    expect(
      tester.widget(find.byKey(const Key('restore-identity-rebind-action'))),
      isA<AppPrimaryButton>(),
    );
    expect(
      find.byKey(const Key('restore-identity-rebind-note')),
      findsOneWidget,
    );
    expect(
      tester.widget(find.byKey(const Key('restore-identity-join-action'))),
      isA<AppSecondaryButton>(),
    );
  });

  testWidgets('恢复面板：Core 未支持绑定时保留设备加入为主操作', (tester) async {
    await _openRestorePanel(
      tester,
      serverInfo: _serverInfo(deviceRebind: true),
      overrides: <Override>[
        deviceRebindPortProvider.overrideWithValue(
          _FakeRebindPort(supported: false),
        ),
      ],
    );

    expect(
      find.byKey(const Key('restore-identity-rebind-action')),
      findsNothing,
    );
    expect(
      tester.widget(find.byKey(const Key('restore-identity-join-action'))),
      isA<AppPrimaryButton>(),
    );
  });

  testWidgets('恢复面板：服务端未声明绑定时不展示绑定入口', (tester) async {
    await _openRestorePanel(
      tester,
      serverInfo: _serverInfo(deviceRebind: false),
      overrides: <Override>[
        deviceRebindPortProvider.overrideWithValue(_FakeRebindPort()),
      ],
    );

    expect(
      find.byKey(const Key('restore-identity-rebind-action')),
      findsNothing,
    );
    expect(
      tester.widget(find.byKey(const Key('restore-identity-join-action'))),
      isA<AppPrimaryButton>(),
    );
  });

  testWidgets('恢复面板：确认后用户取消认证则 DID 文档不变', (tester) async {
    final port = _FakeRebindPort();
    final presence = _FakePresence(result: false);
    final container = await _openRestorePanel(
      tester,
      serverInfo: _serverInfo(deviceRebind: true),
      overrides: <Override>[
        deviceRebindPortProvider.overrideWithValue(port),
        userPresencePortProvider.overrideWithValue(presence),
      ],
    );

    await _tapVisible(
      tester,
      find.byKey(const Key('restore-identity-rebind-action')),
    );
    expect(
      find.byKey(const Key('restore-identity-rebind-confirm')),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.byKey(const Key('restore-identity-rebind-confirm')),
    );

    expect(presence.calls, 1);
    expect(port.calls, 0);
    expect(
      container.read(uiFeedbackProvider)?.message.id,
      'deviceRebindUserPresenceDenied',
    );
  });

  testWidgets('恢复面板：确认认证后 Core 完成同 DID 绑定', (tester) async {
    final port = _FakeRebindPort();
    final presence = _FakePresence();
    final container = await _openRestorePanel(
      tester,
      serverInfo: _serverInfo(deviceRebind: true),
      overrides: <Override>[
        deviceRebindPortProvider.overrideWithValue(port),
        userPresencePortProvider.overrideWithValue(presence),
      ],
    );

    await _tapVisible(
      tester,
      find.byKey(const Key('restore-identity-rebind-action')),
    );
    await _tapVisible(
      tester,
      find.byKey(const Key('restore-identity-rebind-confirm')),
    );

    expect(presence.calls, 1);
    expect(port.calls, 1);
    expect(port.lastIdentityId, _identityId);
    expect(port.lastUserPresenceConfirmed, isTrue);
    expect(
      container.read(uiFeedbackProvider)?.message.id,
      'deviceRebindSucceeded',
    );
  });
}
