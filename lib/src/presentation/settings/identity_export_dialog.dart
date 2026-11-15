import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';

import '../../application/identity_export_service.dart';
import '../../l10n/l10n.dart';
import '../shared/app_dialog.dart';
import '../shared/awiki_me_design.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';

class IdentityExportDialog extends StatefulWidget {
  const IdentityExportDialog({
    super.key,
    required this.identityLabel,
    required this.onExport,
  });

  final String identityLabel;
  final Future<void> Function(String passphrase) onExport;

  @override
  State<IdentityExportDialog> createState() => _IdentityExportDialogState();
}

class _IdentityExportDialogState extends State<IdentityExportDialog> {
  final TextEditingController _passphraseController = TextEditingController();
  final TextEditingController _confirmationController = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitting) return;
    final l10n = context.l10n;
    final passphrase = _passphraseController.text;
    if (utf8.encode(passphrase).length <
        IdentityExportService.minimumPassphraseBytes) {
      setState(() => _error = l10n.identityExportPassphraseTooShort);
      return;
    }
    if (passphrase != _confirmationController.text) {
      setState(() => _error = l10n.identityExportPassphraseMismatch);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    Navigator.of(context).pop();
    unawaited(widget.onExport(passphrase));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return AppConfirmationDialog(
      title: l10n.identityExportDialogTitle,
      message: l10n.identityExportDialogMessage(widget.identityLabel),
      helperMessage: l10n.identityExportHelperMessage,
      confirmLabel: l10n.identityExportConfirmAction,
      confirmButtonKey: const Key('identity-export-confirm'),
      onConfirm: _submitting ? null : _submit,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppTextField(
            key: const Key('identity-export-passphrase-field'),
            controller: _passphraseController,
            label: l10n.identityExportPassphraseLabel,
            placeholder: l10n.identityExportPassphrasePlaceholder,
            obscureText: true,
            enabled: !_submitting,
            semanticsIdentifier: 'identity-export-passphrase',
          ),
          AppTextField(
            key: const Key('identity-export-confirmation-field'),
            controller: _confirmationController,
            label: l10n.identityExportPassphraseConfirmLabel,
            placeholder: l10n.identityExportPassphrasePlaceholder,
            obscureText: true,
            enabled: !_submitting,
            semanticsIdentifier: 'identity-export-passphrase-confirmation',
            bottomPadding: 0,
          ),
          if (_error != null) ...<Widget>[
            SizedBox(height: responsive.spacing(8)),
            Text(
              _error!,
              style: TextStyle(
                color: theme.danger,
                fontSize: responsive.bodySm,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
