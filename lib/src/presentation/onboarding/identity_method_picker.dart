import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/identity_method.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/session_provider.dart';
import '../shared/awiki_me_design.dart';
import 'onboarding_provider.dart';

class IdentityMethodPicker extends ConsumerWidget {
  const IdentityMethodPicker({super.key, required this.handleController});

  final TextEditingController handleController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);
    if (!state.isServerInfoReady) return const SizedBox.shrink();
    final controller = ref.read(onboardingProvider.notifier);
    final localHandles = ref
        .watch(sessionProvider)
        .localCredentials
        .map((identity) => identity.handle?.trim().toLowerCase() ?? '')
        .where((handle) => handle.isNotEmpty)
        .toSet();
    // A pending registration is only offered when its method is otherwise
    // unreachable, and never for a Handle that already has local identity
    // material: resuming such a record only leads back into the conflict.
    final pendingRegistrations = state.pendingRegistrations
        .where(
          (pending) =>
              !state.availableDidMethods.contains(pending.method) &&
              !_handleHasLocalIdentity(pending.fullHandle, localHandles),
        )
        .toList(growable: false);
    final selectedPending = state.selectedPendingRegistration;
    final showResumeHint =
        selectedPending != null && pendingRegistrations.contains(selectedPending);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.availableDidMethods.length > 1) ...[
          Text(context.l10n.identityMethodLabel),
          const SizedBox(height: 8),
          CupertinoSlidingSegmentedControl<IdentityDidMethod>(
            key: const Key('identity-method-picker'),
            groupValue: state.availableDidMethods.contains(state.didMethod)
                ? state.didMethod
                : null,
            children: {
              for (final method in state.availableDidMethods)
                method: Padding(
                  key: Key('identity-method-${method.name}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(method.name.toUpperCase()),
                ),
            },
            onValueChanged: (method) {
              if (method != null && !state.isBusy) {
                controller.setDidMethod(method);
              }
            },
          ),
          const SizedBox(height: 12),
        ],
        if (state.didMethod == IdentityDidMethod.web) ...[
          Text(
            context.l10n.identityWebAdminLimitation,
            key: const Key('identity-web-admin-limitation'),
            style: TextStyle(
              color: context.awikiTheme.secondaryText,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final pending in pendingRegistrations)
          CupertinoButton(
            key: Key('identity-registration-pending-${pending.fullHandle}'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            onPressed: state.isBusy
                ? null
                : () {
                    controller.selectPendingRegistration(pending);
                    // Handles are the provider's public subject. Core retains the
                    // exact creation operation and verifies subsequent inputs.
                    handleController.text = pending.fullHandle.split('.').first;
                  },
            child: Text(
              '${context.l10n.identityRegistrationPending}: ${pending.fullHandle} (${pending.method.name.toUpperCase()})',
            ),
          ),
        if (showResumeHint) ...[
          Text(
            context.l10n.identityRegistrationResumeHint,
            key: const Key('identity-registration-resume-hint'),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

bool _handleHasLocalIdentity(String fullHandle, Set<String> localHandles) {
  final pending = fullHandle.trim().toLowerCase();
  if (pending.isEmpty) return false;
  final short = pending.split('.').first;
  return localHandles.any(
    (handle) =>
        handle == pending ||
        handle == short ||
        handle.split('.').first == short,
  );
}
