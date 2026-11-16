import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/tenant/app_tenant.dart';
import '../../core/app_transport_failure.dart';
import '../../domain/entities/session_identity.dart';
import '../shared/awiki_me_feedback.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/session_provider.dart';
import '../shared/widgets/app_widgets.dart';
import '../recovery/pending_handle_recovery_entry.dart';
import 'onboarding_provider.dart';
import 'onboarding_outlined_field.dart';
import 'registration_entry_provider.dart';

/// Inline invitation and validation details for the fixed auth form.
class RegistrationEntryForm extends ConsumerWidget {
  const RegistrationEntryForm({
    super.key,
    required this.handleController,
    required this.inviteController,
    required this.phoneController,
    this.showLoading = true,
    this.importSupported = false,
    this.onRestoreIdentity,
  });

  final TextEditingController handleController;
  final TextEditingController inviteController;
  final TextEditingController phoneController;
  final bool showLoading;
  final bool importSupported;

  /// Opens the restore-identity flow. The matched root-only credential, when
  /// available, lets the caller seed the restore panel instead of re-importing.
  final ValueChanged<SessionIdentity?>? onRestoreIdentity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(registrationEntryProvider);
    final onboarding = ref.watch(onboardingProvider);
    final showInviteHandleHint =
        onboarding.authMode != 'phone' ||
        onboarding.usesNoVerificationRegistration;
    final l10n = context.l10n;
    final localStateIssue = const <String>{
      'identity.local_registry_conflict',
      'handle_recovery.local_state_conflict',
    }.contains(onboarding.phoneRegistrationFailureCode);
    final typedHandle = handleController.text.trim();
    final rootOnlyIdentity = _rootOnlyIdentityForCredentials(
      ref.watch(sessionProvider).localCredentials,
      typedHandle,
      allowSingleFallback: localStateIssue,
    );
    final showLocalStateGuidance =
        localStateIssue || (typedHandle.isNotEmpty && rootOnlyIdentity != null);
    final error = switch (state.error) {
      null => null,
      'invite_required' => l10n.onboardingInviteRequired,
      'invite_invalid' =>
        state.step == RegistrationEntryStep.invite
            ? l10n.onboardingInviteInvalidBeforeContact
            : l10n.onboardingInviteInvalid,
      'invite_length_six' => l10n.onboardingInviteLengthSix,
      'invite_length_max_64' => l10n.onboardingInviteLengthMax64,
      'registration_closed' => l10n.onboardingRegistrationClosed,
      tlsHandshakeFailureCode => l10n.secureConnectionFailed,
      trustBundleFailureCode => l10n.trustResourcesInvalid,
      'check_timeout' => l10n.requestTimeoutRetry,
      'check_network' => l10n.networkUnavailableRetry,
      'check_unsupported' => l10n.onboardingAccountCheckUnsupported,
      'check_failed' => l10n.onboardingAccountCheckFailed,
      _ => l10n.onboardingAccountUnavailable,
    };
    return Column(
      key: const Key('registration-entry-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.step == RegistrationEntryStep.invite &&
            state.check?.inviteRequired == true) ...[
          if (showInviteHandleHint) ...[
            Text(l10n.onboardingInviteHandleHint),
            const SizedBox(height: 8),
          ],
          OnboardingOutlinedField(
            controller: inviteController,
            label: l10n.onboardingInviteCode,
            placeholder: l10n.onboardingInviteCode,
            labelHint: showInviteHandleHint
                ? null
                : l10n.onboardingShortHandleInviteHint,
            semanticsIdentifier: 'e2e-invite-input',
          ),
          const SizedBox(height: 4),
        ],
        if (onboarding
                    .serverInfo
                    ?.identity
                    .handleRegistration
                    .registrationPolicy?['source'] ==
                'tenant' &&
            !onboarding.existingAccountMethods)
          AppSecondaryButton(
            label: l10n.onboardingExistingAccountAction,
            semanticsIdentifier: 'e2e-existing-account-methods',
            onPressed: state.busy || onboarding.isServerInfoLoading
                ? null
                : () async {
                    final handle = handleController.text.trim().toLowerCase();
                    final domain = ref.read(activeAppTenantProvider).didHost;
                    final entry = ref.read(registrationEntryProvider.notifier);
                    entry.continueExisting(handle, domain);
                    if (await entry.prepareVerification(
                          handle: handle,
                          domain: domain,
                        ) &&
                        context.mounted) {
                      await ref
                          .read(onboardingProvider.notifier)
                          .loadServerInfo(force: true, existingAccount: true);
                    }
                  },
          ),
        if (state.check?.decision == 'unavailable')
          Text(l10n.onboardingAccountUnavailable),
        PendingHandleRecoveryEntry(
          handleController: handleController,
          phoneController: phoneController,
        ),
        if (showLocalStateGuidance)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.registrationLocalStateNeutralHint,
                  key: const Key('registration-local-state-guidance'),
                ),
                const SizedBox(height: 8),
                if (onRestoreIdentity != null &&
                    (rootOnlyIdentity != null || importSupported))
                  AppPrimaryButton(
                    key: const Key('registration-local-state-restore-identity'),
                    label: l10n.restoreIdentityTitle,
                    semanticsIdentifier:
                        'registration-local-state-restore-identity',
                    onPressed: () => onRestoreIdentity!(rootOnlyIdentity),
                  )
                else
                  AppSecondaryButton(
                    key: const Key('registration-local-state-open-login'),
                    label: l10n.registrationLocalStateOpenLoginAction,
                    semanticsIdentifier: 'registration-local-state-open-login',
                    onPressed: () => ref
                        .read(onboardingProvider.notifier)
                        .setVisibleEntryMode('login'),
                  ),
              ],
            ),
          ),
        if (error != null && state.errorDetail != null)
          AppSecondaryButton(
            label: l10n.commonDetails,
            onPressed: () => showAwikiMeErrorDetailDialog(
              context,
              message: error,
              detail: state.errorDetail!,
            ),
          ),
        if (state.busy && showLoading) const CupertinoActivityIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error,
              key: const Key('registration-entry-error'),
              style: const TextStyle(color: CupertinoColors.systemRed),
            ),
          ),
      ],
    );
  }
}

SessionIdentity? _rootOnlyIdentityForCredentials(
  List<SessionIdentity> credentials,
  String rawHandle, {
  bool allowSingleFallback = false,
}) {
  final rootOnly = credentials
      .where((identity) => identity.rootOnly)
      .toList(growable: false);
  if (rootOnly.isEmpty) {
    return null;
  }
  final handle = rawHandle.trim().toLowerCase();
  if (handle.isEmpty) {
    return allowSingleFallback && rootOnly.length == 1
        ? rootOnly.single
        : null;
  }
  final short = handle.split('.').first;
  for (final identity in rootOnly) {
    final identityHandle = identity.handle?.trim().toLowerCase() ?? '';
    if (identityHandle == handle || identityHandle.split('.').first == short) {
      return identity;
    }
  }
  return null;
}
