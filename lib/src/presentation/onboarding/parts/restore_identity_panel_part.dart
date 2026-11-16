part of '../onboarding_page.dart';

class _RestoreIdentityActions {
  const _RestoreIdentityActions({
    required this.onDirectEnter,
    required this.onRebind,
    required this.onJoin,
    required this.onRecovery,
    required this.onImportAnother,
    required this.onBack,
  });

  final VoidCallback onDirectEnter;
  final VoidCallback onRebind;
  final VoidCallback onJoin;
  final VoidCallback onRecovery;
  final VoidCallback onImportAnother;
  final VoidCallback onBack;
}

/// In-place next step after an identity backup is imported: direct entry with
/// an existing device credential, Device Join under the same DID, or importing
/// the backup again when nothing from it remains. It never signs in, joins, or
/// recovers on its own.
class _RestoreIdentityPanel extends ConsumerWidget {
  const _RestoreIdentityPanel({
    required this.actionsEnabled,
    required this.actions,
  });

  final bool actionsEnabled;
  final _RestoreIdentityActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(restoreIdentityViewProvider);
    if (view == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final enabled = actionsEnabled;
    return Container(
      key: const Key('restore-identity-panel'),
      padding: EdgeInsets.all(responsive.spacing(16)),
      decoration: _loginPaperDecoration(
        context,
        radius: responsive.radius(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                CupertinoIcons.arrow_counterclockwise,
                color: theme.title,
                size: responsive.iconMd,
              ),
              SizedBox(width: responsive.spacing(8)),
              Expanded(
                child: Text(
                  l10n.restoreIdentityTitle,
                  style: TextStyle(
                    color: theme.title,
                    fontSize: responsive.bodyMd,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.spacing(10)),
          _RestoreIdentitySubject(view: view),
          SizedBox(height: responsive.spacing(12)),
          Text(
            _stateMessage(l10n, view),
            key: const Key('restore-identity-state'),
            style: TextStyle(
              color: theme.body,
              fontSize: responsive.bodySm,
              height: 1.45,
            ),
          ),
          SizedBox(height: responsive.spacing(14)),
          ..._phaseActions(context, l10n, view, enabled),
          SizedBox(height: responsive.spacing(6)),
          _MacSecondaryAction(
            key: const Key('restore-identity-back'),
            label: l10n.commonBack,
            onPressed: enabled ? actions.onBack : null,
          ),
        ],
      ),
    );
  }

  List<Widget> _phaseActions(
    BuildContext context,
    AppLocalizations l10n,
    RestoreIdentityView view,
    bool enabled,
  ) {
    final widgets = <Widget>[];
    void gap() => widgets.add(const SizedBox(height: 8));
    switch (view.phase) {
      case RestoreIdentityPhase.directEntry:
        widgets.add(
          AppPrimaryButton(
            key: const Key('restore-identity-direct-enter'),
            label: l10n.restoreIdentityDirectEnterAction,
            semanticsIdentifier: 'restore-identity-direct-enter',
            onPressed: enabled ? actions.onDirectEnter : null,
          ),
        );
      case RestoreIdentityPhase.authorizationRequired:
        if (view.rebindAvailable) {
          widgets.add(
            AppPrimaryButton(
              key: const Key('restore-identity-rebind-action'),
              label: l10n.restoreIdentityRebindAction,
              semanticsIdentifier: 'restore-identity-rebind-action',
              onPressed: enabled ? actions.onRebind : null,
            ),
          );
          gap();
          widgets.add(
            Text(
              l10n.restoreIdentityRebindNote,
              key: const Key('restore-identity-rebind-note'),
              style: TextStyle(
                color: context.awikiTheme.secondaryText,
                fontSize: context.awikiResponsive.metaSm,
                height: 1.4,
              ),
            ),
          );
          gap();
          widgets.add(
            AppSecondaryButton(
              key: const Key('restore-identity-join-action'),
              label: l10n.rootOnlyAuthorizeDeviceAction,
              semanticsIdentifier: 'restore-identity-join-action',
              onPressed: enabled ? actions.onJoin : null,
            ),
          );
        } else {
          widgets.add(
            AppPrimaryButton(
              key: const Key('restore-identity-join-action'),
              label: l10n.rootOnlyAuthorizeDeviceAction,
              semanticsIdentifier: 'restore-identity-join-action',
              onPressed: enabled ? actions.onJoin : null,
            ),
          );
        }
        if (view.recoveryAvailable) {
          gap();
          widgets.add(
            AppSecondaryButton(
              key: const Key('restore-identity-recovery-action'),
              label: l10n.restoreIdentityRecoveryAction,
              semanticsIdentifier: 'restore-identity-recovery-action',
              onPressed: enabled ? actions.onRecovery : null,
            ),
          );
          gap();
          widgets.add(
            Text(
              l10n.restoreIdentityRecoveryNote,
              style: TextStyle(
                color: context.awikiTheme.secondaryText,
                fontSize: context.awikiResponsive.metaSm,
                height: 1.4,
              ),
            ),
          );
        }
      case RestoreIdentityPhase.credentialMissing:
        if (view.importSupported) {
          widgets.add(
            AppPrimaryButton(
              key: const Key('restore-identity-import-another'),
              label: l10n.restoreIdentityImportAnotherAction,
              semanticsIdentifier: 'restore-identity-import-another',
              onPressed: enabled ? actions.onImportAnother : null,
            ),
          );
        }
    }
    return widgets;
  }

  String _stateMessage(AppLocalizations l10n, RestoreIdentityView view) {
    return switch (view.phase) {
      RestoreIdentityPhase.directEntry =>
        l10n.restoreIdentityDirectEntryMessage,
      RestoreIdentityPhase.authorizationRequired => view.rebindAvailable
          ? l10n.restoreIdentityRebindRequiredMessage
          : l10n.restoreIdentityAuthorizationRequiredMessage,
      RestoreIdentityPhase.credentialMissing =>
        l10n.restoreIdentityCredentialMissingMessage,
    };
  }
}

class _RestoreIdentitySubject extends StatelessWidget {
  const _RestoreIdentitySubject({required this.view});

  final RestoreIdentityView view;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final title = (view.displayName ?? view.handle ?? '').trim();
    final handle = view.handle?.trim() ?? '';
    return Column(
      key: const Key('restore-identity-subject'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title.isNotEmpty)
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.title,
              fontSize: responsive.bodySm,
              fontWeight: FontWeight.w500,
            ),
          ),
        if (handle.isNotEmpty && handle != title)
          Text(
            handle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.secondaryText,
              fontSize: responsive.metaSm,
            ),
          ),
        if (view.did.isNotEmpty)
          Text(
            view.did,
            key: const Key('restore-identity-did'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.secondaryText,
              fontSize: responsive.metaSm,
              height: 1.35,
            ),
          ),
      ],
    );
  }
}
