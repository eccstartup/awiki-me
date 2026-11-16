import 'dart:async';

import 'package:awiki_me/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_locale.dart';
import '../../app/app_router.dart';
import '../../app/app_services.dart';
import '../../app/e2e_semantics.dart';
import '../../app/ui_feedback.dart';
import '../../application/models/onboarding_server_info.dart';
import '../../application/ports/device_rebind_port.dart';
import '../../application/ports/identity_backup_import_port.dart';
import '../../application/ports/identity_core_port.dart';
import '../../application/tenant/app_tenant.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../../domain/entities/session_identity.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../devices/device_join_page.dart';
import '../recovery/handle_recovery_page.dart';
import '../recovery/handle_recovery_provider.dart';
import '../shared/app_language_menu.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/avatar_badge.dart';
import '../shared/local_credential_delete_dialog.dart';
import '../shared/responsive_layout.dart';
import '../shared/sms_otp_cooldown_provider.dart';
import '../shared/tenant_management_dialog.dart';
import '../shared/widgets/app_widgets.dart';
import '../shared/widgets/awiki_glass_controls.dart';
import '../recovery/pending_handle_recovery_entry.dart';
import '../settings/identity_backup_import_dialog.dart';
import 'onboarding_provider.dart';
import 'onboarding_outlined_field.dart';
import 'registration_entry_provider.dart';
import 'registration_entry_form.dart';
import 'identity_method_picker.dart';
import 'restore_identity_provider.dart';
import 'restore_identity_view_provider.dart';

part 'parts/onboarding_mac_part.dart';
part 'parts/onboarding_mobile_controls_part.dart';
part 'parts/restore_identity_panel_part.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  static const int _e2eOtpMaxAttempts = 15;
  static const Duration _e2eOtpRetryInterval = Duration(seconds: 5);

  bool _checkingLocalRecovery = false;
  bool _submittingRegistration = false;
  int _registrationSubmissionGeneration = 0;
  bool _requestingOtp = false;
  int _otpRequestGeneration = 0;
  int _recoveryLookupGeneration = 0;
  (String, String, String) _lastRecoveryLookupInputs = ('', '', '');

  final phoneController = TextEditingController();
  final otpController = TextEditingController();
  final emailController = TextEditingController();
  final handleController = TextEditingController();
  final inviteController = TextEditingController();
  ProviderSubscription<AppTenantProfile>? _tenantSubscription;
  Timer? _e2eOtpRetryTimer;
  int _e2eOtpAttempts = 0;

  String get _normalizedPhone => phoneController.text.trim();
  String get _normalizedHandle => handleController.text.trim();

  @override
  void initState() {
    super.initState();
    handleController.addListener(_onHandleChanged);
    for (final controller in [
      handleController,
      phoneController,
      emailController,
    ]) {
      controller.addListener(_onRecoveryLookupInputsChanged);
    }
    _tenantSubscription = ref.listenManual<AppTenantProfile>(
      activeAppTenantProvider,
      (previous, next) {
        if (previous?.id == next.id) {
          return;
        }
        inviteController.clear();
        otpController.clear();
        _invalidateRecoveryLookup();
        unawaited(
          ref.read(onboardingProvider.notifier).loadServerInfo(force: true),
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(ref.read(onboardingProvider.notifier).loadServerInfo());
    });
  }

  @override
  void dispose() {
    _stopE2eOtpRequestLoop();
    _tenantSubscription?.close();
    handleController.removeListener(_onHandleChanged);
    for (final controller in [
      handleController,
      phoneController,
      emailController,
    ]) {
      controller.removeListener(_onRecoveryLookupInputsChanged);
    }
    phoneController.dispose();
    otpController.dispose();
    emailController.dispose();
    handleController.dispose();
    inviteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final otpCooldown = ref.watch(smsOtpCooldownProvider);
    final credentials = ref.watch(sessionProvider).localCredentials;
    final activeTenant = ref.watch(activeAppTenantProvider);
    final localeMode = ref.watch(appLocaleModeProvider);
    ref.listen(sessionProvider.select((state) => state.session != null), (
      _,
      signedIn,
    ) {
      if (signedIn) {
        ref.read(restoreIdentityProvider.notifier).clear();
      }
    });
    return _withLegacyUpgradeProjection(
      _MacOnboardingScaffold(
        registrationEntry: _registrationEntryForm(),
        registrationReady: true,
        registrationSubmitting: _submittingRegistration,
        otpRequesting: _requestingOtp || otpCooldown.isSending,
        onboarding: onboarding,
        otpCooldown: otpCooldown,
        credentials: credentials,
        phoneController: phoneController,
        otpController: otpController,
        emailController: emailController,
        handleController: handleController,
        onLogin: _loginWithLocalCredential,
        onDeleteCredential: (identity) =>
            _showDeleteCredentialDialog(context, identity),
        onRestoreCredential: _openRestoreIdentityForCredential,
        restoreActions: _RestoreIdentityActions(
          onDirectEnter: () => unawaited(_restoreDirectEnter()),
          onRebind: () => unawaited(_restoreRebind(context)),
          onJoin: () => unawaited(_restoreJoin(context)),
          onRecovery: () => unawaited(_restoreRecovery(context)),
          onImportAnother: () => _showImportIdentityBackupDialog(context),
          onBack: () => ref.read(restoreIdentityProvider.notifier).clear(),
        ),
        onRestoreIdentityEntry: () => _showImportIdentityBackupDialog(context),
        onAuthModeChanged: _setAuthMode,
        onRequestOtp: _requestOtp,
        onRequestEmailActivation: _requestEmailActivation,
        onCheckEmailActivation: _checkEmailActivation,
        onSubmitRegister: () => _submitRegister(context),
        activeTenant: activeTenant,
        localeMode: localeMode,
        onLanguagePressed: _showLanguageSheet,
      ),
      onboarding,
    );
  }

  Future<void> _showLanguageSheet(BuildContext anchorContext) {
    return showAppLanguageMenu(
      anchorContext,
      ref,
      ref.read(appLocaleModeProvider),
    );
  }

  void _showImportIdentityBackupDialog(BuildContext context) {
    final presenceReason = context.l10n.identityBackupImportPresenceReason;
    final service = ref.read(identityBackupImportServiceProvider);
    AppNavigator.showDialog<IdentityBackupImportOutcome>(
      context,
      (_) => IdentityBackupImportDialog(
        isSupported: service.isSupported,
        pickBackup: service.pickBackupFile,
        inspectBackup: (backup, passphrase) =>
            service.inspectBackup(backup: backup, passphrase: passphrase),
        importBackup: (backup, passphrase) async {
          final outcome = await ref
              .read(appRuntimeProvider.notifier)
              .importIdentityBackup(
                backup: backup,
                passphrase: passphrase,
                presenceReason: presenceReason,
              );
          // The restore panel is the login pane's next step; never leave the
          // user on a registration form for the restored Handle.
          ref.read(onboardingProvider.notifier).setVisibleEntryMode('login');
          return outcome;
        },
      ),
    );
  }

  Future<void> _submitRegister(BuildContext context) async {
    if (_submittingRegistration || _requestingOtp) return;
    final generation = ++_registrationSubmissionGeneration;
    setState(() => _submittingRegistration = true);
    try {
      await _performSubmitRegister(context, generation);
    } finally {
      _finishRegistrationSubmission(generation);
    }
  }

  void _finishRegistrationSubmission(int generation) {
    if (mounted &&
        generation == _registrationSubmissionGeneration &&
        _submittingRegistration) {
      setState(() => _submittingRegistration = false);
    }
  }

  Future<void> _performSubmitRegister(
    BuildContext context,
    int generation,
  ) async {
    final notifier = ref.read(onboardingProvider.notifier);
    final handle = handleController.text.trim();
    if (_checkingLocalRecovery) return;
    if (handle.isNotEmpty &&
        await _openPendingRecovery(
          handle,
          onHandoff: () => _finishRegistrationSubmission(generation),
        )) {
      return;
    }
    if (!mounted || generation != _registrationSubmissionGeneration) return;
    final tenant = ref.read(activeAppTenantProvider);
    final phone = _normalizedPhone;
    final profileMarkdown = '# $handle\n\n';
    final onboarding = ref.read(onboardingProvider);
    if (!await _prepareRegistrationVerification(requireInvite: true)) {
      return;
    }
    if (!mounted || generation != _registrationSubmissionGeneration) return;
    IdentityRegistrationStatus? result;
    if (onboarding.usesNoVerificationRegistration) {
      result = await notifier.registerWithoutContactVerification(
        phone: _normalizedPhone,
        handle: handle,
        inviteCode: ref.read(registrationEntryProvider).inviteCode,
        nickName: handle,
        profileMarkdown: profileMarkdown,
      );
    } else if (onboarding.authMode == 'phone') {
      result = await notifier.registerWithPhone(
        phone: _normalizedPhone,
        otp: otpController.text.trim(),
        handle: handle,
        inviteCode: ref.read(registrationEntryProvider).inviteCode,
        handleDomain: ref.read(activeAppTenantProvider).didHost,
        nickName: handle,
        profileMarkdown: profileMarkdown,
      );
    } else {
      result = await notifier.registerWithEmail(
        email: emailController.text.trim(),
        handle: handle,
        inviteCode: ref.read(registrationEntryProvider).inviteCode,
        nickName: handle,
        profileMarkdown: profileMarkdown,
      );
    }
    if (!mounted) {
      return;
    }
    _finishRegistrationSubmission(generation);
    if (ref.read(onboardingProvider).isPhoneOtpConsumed) {
      otpController.clear();
    }
    if (result == IdentityRegistrationStatus.recoveryRequired &&
        context.mounted &&
        ref.read(activeAppTenantProvider).id == tenant.id &&
        handleController.text.trim() == handle &&
        _normalizedPhone == phone) {
      await AppNavigator.push<void>(
        context,
        (_) => HandleRecoveryPage(
          initialHandle:
              '${handle.toLowerCase()}.${tenant.didHost.toLowerCase()}',
          initialPhone: phone,
          autoRequestOtp: false,
          allowPhoneInput: phone.isEmpty,
        ),
      );
      if (mounted) ref.invalidate(pendingHandleRecoveryProvider);
      return;
    }
    if (result == IdentityRegistrationStatus.joinRequired && context.mounted) {
      final verifiedOnboarding = ref.read(onboardingProvider);
      await _chooseExistingHandleAction(
        context,
        fullHandle:
            verifiedOnboarding.otpTargetFullHandle ??
            '${handle.toLowerCase()}.${ref.read(activeAppTenantProvider).didHost.toLowerCase()}',
        phone: verifiedOnboarding.otpTargetPhone ?? _normalizedPhone,
      );
    }
  }

  void _invalidateRecoveryLookup() {
    _recoveryLookupGeneration++;
    _checkingLocalRecovery = false;
    // Inputs can supersede a pending lookup/precheck. Its late completion must
    // neither keep the new target disabled nor clear a newer submission.
    if (_submittingRegistration && !ref.read(onboardingProvider).isBusy) {
      _finishRegistrationSubmission(_registrationSubmissionGeneration);
      _registrationSubmissionGeneration++;
    }
    if (_requestingOtp && !ref.read(onboardingProvider).isBusy) {
      _finishOtpRequest(_otpRequestGeneration);
      _otpRequestGeneration++;
    }
  }

  void _onRecoveryLookupInputsChanged() {
    final inputs = (
      handleController.text.trim().toLowerCase(),
      _normalizedPhone,
      emailController.text.trim(),
    );
    if (inputs == _lastRecoveryLookupInputs) return;
    final previous = _lastRecoveryLookupInputs;
    _lastRecoveryLookupInputs = inputs;
    final onboarding = ref.read(onboardingProvider.notifier);
    if (previous.$1 != inputs.$1) onboarding.resetPhoneOtpTarget();
    if (previous.$2 != inputs.$2) onboarding.updateOtpPhone(inputs.$2);
    if (previous.$1 != inputs.$1 || previous.$3 != inputs.$3) {
      onboarding.resetEmailActivation();
    }
    ref.read(registrationEntryProvider.notifier).invalidateVerification();
    _invalidateRecoveryLookup();
  }

  Future<bool> _openPendingRecovery(
    String handle, {
    required VoidCallback onHandoff,
  }) async {
    if (ref.read(onboardingProvider).didMethod != IdentityDidMethod.wba) {
      return false;
    }
    if (ref.read(onboardingProvider).serverInfo?.supportsPhoneHandleRecovery !=
        true) {
      return false;
    }
    final generation = ++_recoveryLookupGeneration;
    _checkingLocalRecovery = true;
    final tenant = ref.read(activeAppTenantProvider);
    bool current() =>
        mounted &&
        generation == _recoveryLookupGeneration &&
        ref.read(activeAppTenantProvider) == tenant;
    final fullHandle =
        '${handle.toLowerCase()}.${tenant.didHost.toLowerCase()}';
    final phone = _normalizedPhone;
    try {
      final pending = await ref
          .read(handleRecoveryServiceProvider)
          .inspectContext(handle: fullHandle);
      if (!mounted || !current()) return true;
      if (!hasPendingHandleRecovery(pending)) return false;
      onHandoff();
      otpController.clear();
      await AppNavigator.push<void>(
        context,
        (_) => HandleRecoveryPage(
          initialHandle: fullHandle,
          initialPhone: phone,
          allowPhoneInput: true,
          autoRequestOtp: false,
        ),
      );
      if (mounted) ref.invalidate(pendingHandleRecoveryProvider);
      return true;
    } catch (_) {
      if (mounted && current()) {
        onHandoff();
        await showAwikiMeErrorDetailDialog(
          context,
          message: context.l10n.handleRecoveryErrorLocalStateUnavailable,
          detail: context.l10n.handleRecoveryErrorLocalStateUnavailable,
        );
      }
      return true;
    } finally {
      if (generation == _recoveryLookupGeneration) {
        _checkingLocalRecovery = false;
      }
    }
  }

  Future<void> _chooseExistingHandleAction(
    BuildContext context, {
    required String fullHandle,
    required String phone,
  }) async {
    final rebindContinuation =
        ref.read(onboardingProvider).existingHandleJoinMode ==
        ExistingHandleJoinMode.handleRecoveryRebind;
    final recoveryAvailable =
        !rebindContinuation &&
        phone.isNotEmpty &&
        ref
                .read(onboardingProvider)
                .existingHandleMethodCapabilities
                ?.handleRecovery ==
            true &&
        (ref.read(onboardingProvider).serverInfo?.supportsPhoneHandleRecovery ??
            false);
    final action = await showAwikiGlassAlert<_ExistingHandleAction>(
      context,
      dismissible: false,
      title: context.l10n.onboardingExistingHandleTitle,
      message: recoveryAvailable
          ? context.l10n.onboardingExistingHandleMessage
          : context.l10n.onboardingExistingHandleJoinOnlyMessage,
      actions: <AwikiAlertAction<_ExistingHandleAction>>[
        AwikiAlertAction<_ExistingHandleAction>(
          key: const Key('existing-handle-join-action'),
          label: context.l10n.deviceJoinEntry,
          value: _ExistingHandleAction.joinDevice,
          tone: AwikiPillTone.primary,
        ),
        if (recoveryAvailable)
          AwikiAlertAction<_ExistingHandleAction>(
            key: const Key('existing-handle-recovery-action'),
            label: context.l10n.handleRecoveryTitle,
            value: _ExistingHandleAction.recoverHandle,
          ),
        AwikiAlertAction<_ExistingHandleAction>(
          key: const Key('existing-handle-cancel-action'),
          label: context.l10n.commonCancel,
          value: _ExistingHandleAction.cancel,
          tone: AwikiPillTone.text,
        ),
      ],
    );
    if (!context.mounted) return;
    final controller = ref.read(onboardingProvider.notifier);
    switch (action ?? _ExistingHandleAction.cancel) {
      case _ExistingHandleAction.joinDevice:
        final started = await controller.beginExistingHandleDeviceJoin(
          presenceReason: context.l10n.handleRecoveryPresenceReason,
        );
        if (started && context.mounted) await openDeviceJoinPage(context);
      case _ExistingHandleAction.recoverHandle:
        if (rebindContinuation) {
          throw StateError('rebind_join_recovery_action_forbidden');
        }
        await controller.discardExistingHandleContinuation();
        if (context.mounted) {
          await AppNavigator.push<void>(
            context,
            (_) => HandleRecoveryPage(
              startNew: true,
              initialHandle: fullHandle,
              initialPhone: phone,
            ),
          );
          if (mounted) ref.invalidate(pendingHandleRecoveryProvider);
        }
      case _ExistingHandleAction.cancel:
        await controller.discardExistingHandleContinuation();
    }
  }

  Widget _registrationEntryForm() => RegistrationEntryForm(
    handleController: handleController,
    inviteController: inviteController,
    phoneController: phoneController,
    showLoading: !_submittingRegistration && !_requestingOtp,
    importSupported: ref.read(identityBackupImportPortProvider).isSupported,
    onRestoreIdentity: (identity) {
      if (identity != null) {
        _openRestoreIdentityForCredential(identity);
      } else {
        _showImportIdentityBackupDialog(context);
      }
    },
  );

  void _onHandleChanged() {
    if (handleController.text.trim().toLowerCase() !=
        ref.read(registrationEntryProvider).handle) {
      _resetRegistrationEntry();
    }
  }

  void _resetRegistrationEntry() {
    if (!mounted) return;
    _stopE2eOtpRequestLoop();
    ref.read(registrationEntryProvider.notifier).reset();
    if (ref.read(onboardingProvider).existingAccountMethods) {
      unawaited(
        ref.read(onboardingProvider.notifier).loadServerInfo(force: true),
      );
    }
    inviteController.clear();
    otpController.clear();
    ref.read(onboardingProvider.notifier).resetPhoneOtpTarget();
    ref.read(onboardingProvider.notifier).resetEmailActivation();
  }

  Future<bool> _prepareRegistrationVerification({bool requireInvite = false}) {
    final onboarding = ref.read(onboardingProvider);
    return ref
        .read(registrationEntryProvider.notifier)
        .prepareVerification(
          handle: _normalizedHandle,
          domain: ref.read(activeAppTenantProvider).didHost,
          inviteCode: inviteController.text,
          requireInvite: requireInvite,
          phone: onboarding.authMode == 'email' ? null : _normalizedPhone,
          email: onboarding.authMode == 'email'
              ? emailController.text.trim()
              : null,
        );
  }

  Future<void> _requestOtp() async {
    if (_requestingOtp || _submittingRegistration) return;
    final generation = ++_otpRequestGeneration;
    setState(() => _requestingOtp = true);
    try {
      if (!await _prepareRegistrationVerification() ||
          !mounted ||
          generation != _otpRequestGeneration) {
        return;
      }
      if (!awikiE2eEnabled) {
        await ref
            .read(onboardingProvider.notifier)
            .requestOtp(
              phone: _normalizedPhone,
              handle: _normalizedHandle,
              handleDomain: ref.read(activeAppTenantProvider).didHost,
            );
      } else {
        _startE2eOtpRequestLoop();
      }
    } finally {
      _finishOtpRequest(generation);
    }
  }

  void _finishOtpRequest(int generation) {
    if (mounted && generation == _otpRequestGeneration && _requestingOtp) {
      setState(() => _requestingOtp = false);
    }
  }

  void _requestEmailActivation() async {
    if (!await _prepareRegistrationVerification() || !mounted) return;
    unawaited(
      ref
          .read(onboardingProvider.notifier)
          .requestEmailActivation(
            email: emailController.text.trim(),
            handle: _normalizedHandle,
          ),
    );
  }

  void _checkEmailActivation() {
    unawaited(
      ref
          .read(onboardingProvider.notifier)
          .checkEmailActivation(
            email: emailController.text.trim(),
            handle: _normalizedHandle,
          ),
    );
  }

  void _setAuthMode(String value) {
    ref.read(registrationEntryProvider.notifier).invalidateVerification();
    final controller = ref.read(onboardingProvider.notifier);
    if (ref.read(onboardingProvider).authMode != value) {
      _invalidateRecoveryLookup();
    }
    controller.setAuthMode(value);
    if (value == 'phone') {
      controller.updateOtpPhone(phoneController.text);
    }
  }

  Future<void> _loginWithLocalCredential(String credentialName) {
    return ref
        .read(onboardingProvider.notifier)
        .loginWithLocalCredential(credentialName);
  }

  void _showDeleteCredentialDialog(
    BuildContext context,
    SessionIdentity identity,
  ) {
    AppNavigator.showDialog<void>(
      context,
      (dialogContext) => LocalCredentialDeleteDialog(
        identity: identity,
        loadRecoveryImpact: () => ref
            .read(appSessionServiceProvider)
            .hasPendingLocalIdentityRecovery(identity.localIdentitySelector),
        signsOut: false,
        onConfirm: () {
          Navigator.of(dialogContext).pop();
          unawaited(
            ref
                .read(onboardingProvider.notifier)
                .deleteLocalCredential(identity),
          );
        },
      ),
    );
  }

  void _openRestoreIdentityForCredential(SessionIdentity identity) {
    ref.read(restoreIdentityProvider.notifier).beginForCredential(identity);
    ref.read(onboardingProvider.notifier).setVisibleEntryMode('login');
  }

  /// Direct entry uses an existing non-root device credential. The imported
  /// root credential is never a login credential.
  Future<void> _restoreDirectEnter() async {
    final view = ref.read(restoreIdentityViewProvider);
    final credential = view?.credential;
    if (credential == null || credential.rootOnly) {
      return;
    }
    await _loginWithLocalCredential(credential.credentialName);
    if (mounted && ref.read(sessionProvider).session != null) {
      ref.read(restoreIdentityProvider.notifier).clear();
    }
  }

  /// Binds this device to the imported root-only DID: the imported root key
  /// root-signs a replacement DID document that carries this device's fresh
  /// keys, so the DID, Handle and root key stay unchanged. Irreversible for
  /// any device still listed in the current DID document, so it is confirmed
  /// here before user presence and Core run.
  Future<void> _restoreRebind(BuildContext context) async {
    final view = ref.read(restoreIdentityViewProvider);
    final identityId = view?.identityId.trim() ?? '';
    final did = view?.did.trim() ?? '';
    if (view == null ||
        !view.rebindAvailable ||
        identityId.isEmpty ||
        did.isEmpty) {
      return;
    }
    final confirmed = await showAwikiGlassAlert<bool>(
      context,
      dismissible: false,
      title: context.l10n.restoreIdentityRebindConfirmTitle,
      message: context.l10n.restoreIdentityRebindConfirmMessage,
      actions: <AwikiAlertAction<bool>>[
        AwikiAlertAction<bool>(
          key: const Key('restore-identity-rebind-confirm'),
          label: context.l10n.restoreIdentityRebindConfirmAction,
          value: true,
          tone: AwikiPillTone.primary,
        ),
        AwikiAlertAction<bool>(
          key: const Key('restore-identity-rebind-cancel'),
          label: context.l10n.commonCancel,
          value: false,
          tone: AwikiPillTone.text,
        ),
      ],
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final outcome = await ref
          .read(appRuntimeProvider.notifier)
          .rebindRestoredIdentity(
            identityId: identityId,
            did: did,
            presenceReason: context.l10n.restoreIdentityRebindPresenceReason,
          );
      if (outcome == null || !mounted) return;
      ref
          .read(uiFeedbackProvider.notifier)
          .showInfo(AppMessage.deviceRebindSucceeded());
    } on DeviceRebindException catch (error) {
      if (!mounted) return;
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(_deviceRebindMessage(error));
    } catch (_) {
      if (!mounted) return;
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.deviceRebindFailed());
    }
  }

  AppMessage _deviceRebindMessage(DeviceRebindException error) {
    return switch (error.code) {
      'device_rebind.unsupported' => AppMessage.deviceRebindUnsupported(),
      'device_rebind.user_presence_denied' =>
        AppMessage.deviceRebindUserPresenceDenied(),
      'device_rebind.conflict' => AppMessage.deviceRebindConflict(),
      'device_rebind.state_changed' => AppMessage.deviceRebindStateChanged(),
      _ => AppMessage.deviceRebindFailed(),
    };
  }

  Future<void> _restoreJoin(BuildContext context) {
    return _continueRestoredIdentity(context, _RootOnlyAction.joinDevice);
  }

  Future<void> _restoreRecovery(BuildContext context) {
    return _continueRestoredIdentity(context, _RootOnlyAction.recoverHandle);
  }

  Future<void> _continueRestoredIdentity(
    BuildContext context,
    _RootOnlyAction action,
  ) {
    final view = ref.read(restoreIdentityViewProvider);
    return _startRootOnlyAuthorization(
      context,
      view?.credential,
      action,
      fallbackDid: view?.did,
      fallbackHandle: view?.handle,
    );
  }

  /// Core refuses to finalize a Device Join while the imported root-only entry
  /// is still installed, and finalization runs as soon as the managing device
  /// approves. The join page therefore removes that entry right after the join
  /// request is sent, so cancelling before that point keeps the import.
  Future<void> _startRootOnlyAuthorization(
    BuildContext context,
    SessionIdentity? identity,
    _RootOnlyAction action, {
    String? fallbackDid,
    String? fallbackHandle,
  }) async {
    final confirmed = await showAwikiGlassAlert<bool>(
      context,
      dismissible: false,
      title: context.l10n.rootOnlyRemoveLocalIdentityTitle,
      message: context.l10n.rootOnlyRemoveLocalIdentityMessage,
      actions: <AwikiAlertAction<bool>>[
        AwikiAlertAction<bool>(
          key: const Key('restore-identity-remove-local-identity-confirm'),
          label: context.l10n.rootOnlyRemoveLocalIdentityConfirm,
          value: true,
          tone: AwikiPillTone.primary,
        ),
        AwikiAlertAction<bool>(
          key: const Key('restore-identity-remove-local-identity-cancel'),
          label: context.l10n.commonCancel,
          value: false,
          tone: AwikiPillTone.text,
        ),
      ],
    );
    if (confirmed != true || !context.mounted) return;
    if (action == _RootOnlyAction.recoverHandle && identity != null) {
      final removed = await ref
          .read(onboardingProvider.notifier)
          .deleteLocalCredential(identity);
      if (!removed || !context.mounted) return;
    }
    final handle = (identity?.handle ?? fallbackHandle)?.trim() ?? '';
    switch (action) {
      case _RootOnlyAction.joinDevice:
        await openDeviceJoinPage(
          context,
          initialHandle: handle.isEmpty ? null : handle,
          restoreIdentity: true,
          restoreIdentityDid: identity?.did ?? fallbackDid,
        );
      case _RootOnlyAction.recoverHandle:
        final tenant = ref.read(activeAppTenantProvider);
        final fullHandle = handle.isEmpty
            ? ''
            : handle.contains('.')
            ? handle.toLowerCase()
            : '${handle.toLowerCase()}.${tenant.didHost.toLowerCase()}';
        await AppNavigator.push<void>(
          context,
          (_) => HandleRecoveryPage(
            startNew: true,
            initialHandle: fullHandle,
            initialPhone: '',
            allowPhoneInput: true,
          ),
        );
        if (mounted) ref.invalidate(pendingHandleRecoveryProvider);
      case _RootOnlyAction.cancel:
        break;
    }
  }

  SessionIdentity? _rootOnlyIdentityForLegacyUpgrade(OnboardingState onboarding) {
    final identityId = onboarding.legacyUpgradeStatus.identityId;
    if (identityId == null || identityId.isEmpty) return null;
    for (final identity in ref.read(sessionProvider).localCredentials) {
      if (identity.localIdentityId == identityId) return identity;
    }
    return null;
  }

  Widget _withLegacyUpgradeProjection(
    Widget child,
    OnboardingState onboarding,
  ) {
    final rootOnlyIdentity = onboarding.legacyUpgradeRequiresDeviceJoin
        ? _rootOnlyIdentityForLegacyUpgrade(onboarding)
        : null;
    final recoveryAvailable =
        onboarding.serverInfo?.supportsPhoneHandleRecovery == true;
    void dismissStatus() =>
        ref.read(onboardingProvider.notifier).dismissLegacyUpgradeStatus();
    return Stack(
      children: <Widget>[
        child,
        if (onboarding.isLegacyUpgradeRunning)
          const AwikiMeLoadingMask(key: Key('legacy-upgrade-loading-mask')),
        if (onboarding.legacyUpgradeRequiresDeviceJoin)
          Positioned.fill(
            child: ColoredBox(
              color: CupertinoColors.systemBackground,
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          context.l10n.legacyIdentityBackupRequiresDeviceJoin,
                          key: const Key('legacy-upgrade-device-join-message'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context
                              .l10n
                              .legacyIdentityBackupRequiresDeviceJoinHint,
                          key: const Key('legacy-upgrade-device-join-hint'),
                          textAlign: TextAlign.center,
                        ),
                        if (onboarding.legacyUpgradeStatus.failureCode
                            case final failureCode?) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            'Diagnostic code: $failureCode',
                            key: const Key('legacy-upgrade-diagnostic-code'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: CupertinoColors.systemGrey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (rootOnlyIdentity != null) ...<Widget>[
                          AppPrimaryButton(
                            label: context.l10n.rootOnlyAuthorizeDeviceAction,
                            semanticsIdentifier:
                                'legacy-upgrade-device-join-authorize',
                            onPressed: () {
                              dismissStatus();
                              unawaited(
                                _startRootOnlyAuthorization(
                                  context,
                                  rootOnlyIdentity,
                                  _RootOnlyAction.joinDevice,
                                ),
                              );
                            },
                          ),
                          if (recoveryAvailable) ...<Widget>[
                            const SizedBox(height: 10),
                            AppSecondaryButton(
                              label: context.l10n.rootOnlyHandleRecoveryAction,
                              semanticsIdentifier:
                                  'legacy-upgrade-device-join-recovery',
                              onPressed: () {
                                dismissStatus();
                                unawaited(
                                  _startRootOnlyAuthorization(
                                    context,
                                    rootOnlyIdentity,
                                    _RootOnlyAction.recoverHandle,
                                  ),
                                );
                              },
                            ),
                          ],
                          const SizedBox(height: 10),
                        ],
                        AppSecondaryButton(
                          label: context.l10n.commonBack,
                          semanticsIdentifier:
                              'legacy-upgrade-device-join-back',
                          onPressed: dismissStatus,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
        else if (onboarding.isLegacyUpgradeRetryRequired)
          Positioned.fill(
            child: ColoredBox(
              color: CupertinoColors.systemBackground,
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          context.l10n.legacyIdentityUpgradeFailed,
                          key: const Key('legacy-upgrade-retry-message'),
                          textAlign: TextAlign.center,
                        ),
                        if (onboarding.legacyUpgradeStatus.failureCode
                            case final failureCode?) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            'Diagnostic code: $failureCode',
                            key: const Key('legacy-upgrade-diagnostic-code'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: CupertinoColors.systemGrey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        AppPrimaryButton(
                          label: context.l10n.commonRetry,
                          semanticsIdentifier: 'legacy-upgrade-retry',
                          onPressed: () => unawaited(
                            ref
                                .read(onboardingProvider.notifier)
                                .retryLegacyUpgrade(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _startE2eOtpRequestLoop() {
    _stopE2eOtpRequestLoop();
    _e2eOtpAttempts = 0;
    _tryRequestOtpForE2e();
    _e2eOtpRetryTimer = Timer.periodic(
      _e2eOtpRetryInterval,
      (_) => _tryRequestOtpForE2e(),
    );
  }

  void _tryRequestOtpForE2e() {
    if (!mounted) {
      _stopE2eOtpRequestLoop();
      return;
    }
    final onboarding = ref.read(onboardingProvider);
    final otpCooldown = ref.read(smsOtpCooldownProvider);
    if (otpCooldown.isCoolingDown || onboarding.authMode != 'phone') {
      _stopE2eOtpRequestLoop();
      return;
    }
    if (onboarding.isBusy) {
      return;
    }
    if (_e2eOtpAttempts >= _e2eOtpMaxAttempts) {
      _stopE2eOtpRequestLoop();
      return;
    }
    _e2eOtpAttempts += 1;
    unawaited(
      ref
          .read(onboardingProvider.notifier)
          .requestOtp(
            phone: _normalizedPhone,
            handle: _normalizedHandle,
            handleDomain: ref.read(activeAppTenantProvider).didHost,
          )
          .then((_) {
            if (mounted && ref.read(onboardingProvider).canSubmitPhoneOtp) {
              _stopE2eOtpRequestLoop();
            }
          }),
    );
  }

  void _stopE2eOtpRequestLoop() {
    _e2eOtpRetryTimer?.cancel();
    _e2eOtpRetryTimer = null;
  }
}

enum _ExistingHandleAction { joinDevice, recoverHandle, cancel }

enum _RootOnlyAction { joinDevice, recoverHandle, cancel }
