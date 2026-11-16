// [INPUT]: A seeded restore intent, local credential inventory, server capabilities, and Core import support.
// [OUTPUT]: The restore panel view, recomputed whenever any of those inputs change.
// [POS]: Composition layer for restore_identity_provider.dart; kept separate so the runtime can seed the intent without importing onboarding providers.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../app_shell/providers/session_provider.dart';
import 'onboarding_provider.dart';
import 'restore_identity_provider.dart';

final restoreIdentityViewProvider = Provider<RestoreIdentityView?>((ref) {
  final intent = ref.watch(restoreIdentityProvider);
  if (intent == null) {
    return null;
  }
  final credentials = ref.watch(
    sessionProvider.select((state) => state.localCredentials),
  );
  final recoveryAvailable = ref.watch(
    onboardingProvider.select(
      (state) => state.serverInfo?.supportsPhoneHandleRecovery == true,
    ),
  );
  final importSupported = ref.watch(
    identityBackupImportPortProvider,
  ).isSupported;
  final rebindAvailable =
      ref.watch(multiDeviceDeviceRebindEnabledProvider) &&
      ref.watch(deviceRebindPortProvider).isSupported &&
      ref.watch(
        onboardingProvider.select(
          (state) =>
              state.serverInfo?.supportsRootSignatureDeviceRebind == true,
        ),
      );
  return resolveRestoreIdentityView(
    intent: intent,
    credentials: credentials,
    recoveryAvailable: recoveryAvailable,
    importSupported: importSupported,
    rebindAvailable: rebindAvailable,
  );
});
