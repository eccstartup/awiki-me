import 'package:flutter/cupertino.dart';

import '../../application/identity_backup_import_service.dart';
import '../../application/ports/identity_backup_import_port.dart';
import '../../l10n/l10n.dart';
import '../shared/app_dialog.dart';
import '../shared/awiki_me_design.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';

class IdentityBackupImportDialog extends StatefulWidget {
  const IdentityBackupImportDialog({
    super.key,
    required this.isSupported,
    required this.pickBackup,
    required this.inspectBackup,
    required this.importBackup,
  });

  final bool isSupported;
  final Future<IdentityBackupSelection?> Function() pickBackup;
  final Future<IdentityBackupSummary> Function(
    IdentityBackupSelection backup,
    String passphrase,
  )
  inspectBackup;
  final Future<void> Function(
    IdentityBackupSelection backup,
    String passphrase,
  )
  importBackup;

  @override
  State<IdentityBackupImportDialog> createState() =>
      _IdentityBackupImportDialogState();
}

class _IdentityBackupImportDialogState extends State<IdentityBackupImportDialog> {
  final TextEditingController _passphraseController = TextEditingController();
  IdentityBackupSelection? _backup;
  IdentityBackupSummary? _summary;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _passphraseController.dispose();
    final backup = _backup;
    if (backup != null) {
      backup.bytes.fillRange(0, backup.bytes.length, 0);
    }
    super.dispose();
  }

  Future<void> _pickBackup() async {
    if (_busy || !widget.isSupported) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final backup = await widget.pickBackup();
      if (!mounted) {
        if (backup != null) {
          backup.bytes.fillRange(0, backup.bytes.length, 0);
        }
        return;
      }
      if (backup == null) {
        setState(() => _busy = false);
        return;
      }
      _discardBackup();
      setState(() {
        _backup = backup;
        _summary = null;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _errorText(error);
      });
    }
  }

  Future<void> _inspect() async {
    if (_busy || !widget.isSupported) return;
    final l10n = context.l10n;
    final backup = _backup;
    if (backup == null) {
      setState(() => _error = l10n.identityBackupImportNoFile);
      return;
    }
    final passphrase = _passphraseController.text;
    if (passphrase.isEmpty) {
      setState(() => _error = l10n.identityBackupImportPassphraseRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final summary = await widget.inspectBackup(backup, passphrase);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _errorText(error);
      });
    }
  }

  Future<void> _import() async {
    if (_busy || !widget.isSupported) return;
    final backup = _backup;
    final summary = _summary;
    if (backup == null || summary == null) return;
    final passphrase = _passphraseController.text;
    if (passphrase.isEmpty) {
      setState(
        () => _error = context.l10n.identityBackupImportPassphraseRequired,
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.importBackup(backup, passphrase);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _errorText(error);
      });
    }
  }

  void _discardBackup() {
    final previous = _backup;
    if (previous != null) {
      previous.bytes.fillRange(0, previous.bytes.length, 0);
    }
  }

  String _errorText(Object error) {
    final l10n = context.l10n;
    if (error is! IdentityBackupImportException) {
      return l10n.identityBackupImportFailed;
    }
    return switch (error.code) {
      'identity_backup_import.unsupported' =>
        l10n.identityBackupImportUnsupported,
      'identity_backup_import.invalid_file' ||
      'identity_backup_bad_magic' ||
      'identity_backup_unsupported_version' ||
      'identity_backup_payload_invalid' =>
        l10n.identityBackupImportInvalidFile,
      'identity_backup_import.too_large' ||
      'identity_backup_too_large' => l10n.identityBackupImportTooLarge,
      'identity_backup_import.passphrase_required' ||
      'identity_backup_bad_passphrase' =>
        l10n.identityBackupImportBadPassphrase,
      'identity_backup_unsupported_custody' =>
        l10n.identityBackupImportUnsupportedCustody,
      'identity_backup_import.conflict' => l10n.identityBackupImportConflict,
      'identity_backup_import.user_presence_denied' ||
      'identity_backup_import.user_presence_failed' =>
        l10n.identityBackupImportUserPresenceDenied,
      'identity_backup_import.state_changed' =>
        l10n.identityBackupImportStateChanged,
      _ => l10n.identityBackupImportFailed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final summary = _summary;
    final backup = _backup;
    final inspecting = summary == null;
    return AppConfirmationDialog(
      title: l10n.identityBackupImportDialogTitle,
      message: inspecting
          ? l10n.identityBackupImportDialogMessage
          : l10n.identityBackupImportReviewMessage,
      helperMessage: inspecting
          ? l10n.identityBackupImportHelperMessage
          : l10n.identityBackupImportWarning,
      confirmLabel: inspecting
          ? l10n.identityBackupImportInspectAction
          : l10n.identityBackupImportConfirmAction,
      confirmButtonKey: const Key('identity-backup-import-confirm'),
      destructive: !inspecting,
      onConfirm: _busy || !widget.isSupported
          ? null
          : (inspecting ? _inspect : _import),
      onCancel: _busy ? () {} : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!widget.isSupported)
            Text(
              l10n.identityBackupImportUnsupported,
              style: TextStyle(color: theme.danger, fontSize: responsive.bodySm),
            )
          else if (inspecting) ...<Widget>[
            SizedBox(
              width: double.infinity,
              child: AppSecondaryButton(
                key: const Key('identity-backup-import-pick-file'),
                label: l10n.identityBackupImportSelectFile,
                onPressed: _busy ? null : _pickBackup,
              ),
            ),
            if (backup != null) ...<Widget>[
              SizedBox(height: responsive.spacing(8)),
              Text(
                l10n.identityBackupImportSelectedFile(backup.fileName),
                style: TextStyle(
                  color: theme.body,
                  fontSize: responsive.bodySm,
                ),
              ),
            ],
            SizedBox(height: responsive.spacing(12)),
            AppTextField(
              key: const Key('identity-backup-import-passphrase-field'),
              controller: _passphraseController,
              label: l10n.identityBackupImportPassphraseLabel,
              placeholder: l10n.identityBackupImportPassphrasePlaceholder,
              obscureText: true,
              enabled: !_busy,
              semanticsIdentifier: 'identity-backup-import-passphrase',
              bottomPadding: 0,
            ),
          ] else ...<Widget>[
            _SummaryRow(
              label: l10n.identityBackupImportDidLabel,
              value: summary.did,
            ),
            if ((summary.fullHandle ?? summary.handle)?.trim().isNotEmpty ==
                true)
              _SummaryRow(
                label: l10n.identityBackupImportHandleLabel,
                value: (summary.fullHandle ?? summary.handle)!.trim(),
              ),
            _SummaryRow(
              label: l10n.identityBackupImportCustodyLabel,
              value: summary.custody == 'anp_root'
                  ? l10n.identityBackupImportCustodyAnpRoot
                  : summary.custody,
            ),
            _SummaryRow(
              label: l10n.identityBackupImportExportedAtLabel,
              value: summary.exportedAt,
            ),
          ],
          if (_error != null) ...<Widget>[
            SizedBox(height: responsive.spacing(8)),
            Text(
              _error!,
              style: TextStyle(color: theme.danger, fontSize: responsive.bodySm),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Padding(
      padding: EdgeInsets.only(bottom: responsive.spacing(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: theme.secondaryText,
              fontSize: responsive.metaSm,
            ),
          ),
          Text(
            value,
            style: TextStyle(color: theme.title, fontSize: responsive.bodySm),
          ),
        ],
      ),
    );
  }
}
