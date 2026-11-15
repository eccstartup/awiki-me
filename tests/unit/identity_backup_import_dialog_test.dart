import 'dart:typed_data';

import 'package:awiki_me/src/app/app_router.dart';
import 'package:awiki_me/src/application/identity_backup_import_service.dart';
import 'package:awiki_me/src/application/ports/identity_backup_import_port.dart';
import 'package:awiki_me/src/presentation/settings/identity_backup_import_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('导入对话框先检查备份再确认导入', (tester) async {
    final harness = _DialogHarness();

    await tester.pumpWidget(
      buildLocalizedTestApp(home: _Host(builder: harness.build)),
    );
    await tester.tap(find.byKey(const Key('open-identity-backup-import')));
    await tester.pumpAndSettle();

    expect(find.text('导入加密身份备份'), findsOneWidget);
    expect(find.text('确认之前，备份始终保持加密。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('identity-backup-import-pick-file')));
    await tester.pumpAndSettle();

    expect(harness.pickCalls, 1);
    expect(find.text('已选择：alice.awikibk'), findsOneWidget);

    await tester.enterText(_passphraseField, 'correct horse');
    await tester.tap(find.byKey(const Key('identity-backup-import-confirm')));
    await tester.pumpAndSettle();

    expect(harness.inspectedPassphrases, <String>['correct horse']);
    expect(find.text('导入前请核对以下身份信息。'), findsOneWidget);
    expect(find.text('did:test:alice'), findsOneWidget);
    expect(find.text('alice.example.com'), findsOneWidget);
    expect(find.text('ANP 根密钥'), findsOneWidget);
    expect(find.text('2026-11-15T00:00:00Z'), findsOneWidget);
    expect(harness.importCalls, 0);

    await tester.tap(find.byKey(const Key('identity-backup-import-confirm')));
    await tester.pumpAndSettle();

    expect(harness.importCalls, 1);
    expect(harness.importedPassphrases, <String>['correct horse']);
    expect(harness.importedBackup!.fileName, 'alice.awikibk');
    expect(find.text('导入加密身份备份'), findsNothing);
    expect(harness.pickedBackup.bytes, everyElement(0));
  });

  testWidgets('空口令不会触发检查', (tester) async {
    final harness = _DialogHarness();

    await tester.pumpWidget(
      buildLocalizedTestApp(home: _Host(builder: harness.build)),
    );
    await tester.tap(find.byKey(const Key('open-identity-backup-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identity-backup-import-pick-file')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('identity-backup-import-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('请输入备份口令。'), findsOneWidget);
    expect(harness.inspectedPassphrases, isEmpty);
  });

  testWidgets('检查失败时显示脱敏错误并保留对话框', (tester) async {
    final harness = _DialogHarness()
      ..inspectError = const IdentityBackupImportException(
        'identity_backup_bad_passphrase',
      );

    await tester.pumpWidget(
      buildLocalizedTestApp(home: _Host(builder: harness.build)),
    );
    await tester.tap(find.byKey(const Key('open-identity-backup-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identity-backup-import-pick-file')));
    await tester.pumpAndSettle();
    await tester.enterText(_passphraseField, 'wrong horse');
    await tester.tap(find.byKey(const Key('identity-backup-import-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('口令错误或备份已损坏。'), findsOneWidget);
    expect(find.text('导入加密身份备份'), findsOneWidget);
    expect(harness.importCalls, 0);
  });

  testWidgets('导入失败时显示脱敏错误并保留备份', (tester) async {
    final harness = _DialogHarness()
      ..importError = const IdentityBackupImportException(
        'identity_backup_import.conflict',
      );

    await tester.pumpWidget(
      buildLocalizedTestApp(home: _Host(builder: harness.build)),
    );
    await tester.tap(find.byKey(const Key('open-identity-backup-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identity-backup-import-pick-file')));
    await tester.pumpAndSettle();
    await tester.enterText(_passphraseField, 'correct horse');
    await tester.tap(find.byKey(const Key('identity-backup-import-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identity-backup-import-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('该身份与本机已有身份数据冲突。'), findsOneWidget);
    expect(find.text('导入加密身份备份'), findsOneWidget);
    expect(harness.importCalls, 1);
  });

  testWidgets('关闭对话框会清零已选备份字节', (tester) async {
    final harness = _DialogHarness();

    await tester.pumpWidget(
      buildLocalizedTestApp(home: _Host(builder: harness.build)),
    );
    await tester.tap(find.byKey(const Key('open-identity-backup-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identity-backup-import-pick-file')));
    await tester.pumpAndSettle();
    expect(harness.pickedBackup.bytes, isNot(everyElement(0)));

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('导入加密身份备份'), findsNothing);
    expect(harness.pickedBackup.bytes, everyElement(0));
  });

  testWidgets('Core 不支持导入时失败关闭', (tester) async {
    final harness = _DialogHarness()..isSupported = false;

    await tester.pumpWidget(
      buildLocalizedTestApp(home: _Host(builder: harness.build)),
    );
    await tester.tap(find.byKey(const Key('open-identity-backup-import')));
    await tester.pumpAndSettle();

    expect(find.text('当前版本暂不支持导入身份备份。'), findsOneWidget);
    expect(
      find.byKey(const Key('identity-backup-import-pick-file')),
      findsNothing,
    );
  });
}

final Finder _passphraseField = find.descendant(
  of: find.byKey(const Key('identity-backup-import-passphrase-field')),
  matching: find.byType(EditableText),
);

class _Host extends StatelessWidget {
  const _Host({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Center(
        child: CupertinoButton(
          key: const Key('open-identity-backup-import'),
          onPressed: () => AppNavigator.showDialog<void>(context, builder),
          child: const Text('open'),
        ),
      ),
    );
  }
}

class _DialogHarness {
  bool isSupported = true;
  int pickCalls = 0;
  int importCalls = 0;
  Object? inspectError;
  Object? importError;
  late IdentityBackupSelection pickedBackup;
  IdentityBackupSelection? importedBackup;
  final List<String> inspectedPassphrases = <String>[];
  final List<String> importedPassphrases = <String>[];

  Widget build(BuildContext context) {
    return IdentityBackupImportDialog(
      isSupported: isSupported,
      pickBackup: () async {
        pickCalls += 1;
        pickedBackup = IdentityBackupSelection(
          fileName: 'alice.awikibk',
          bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        );
        return pickedBackup;
      },
      inspectBackup: (backup, passphrase) async {
        inspectedPassphrases.add(passphrase);
        final failure = inspectError;
        if (failure != null) throw failure;
        return const IdentityBackupSummary(
          did: 'did:test:alice',
          handle: 'alice.example.com',
          fullHandle: 'alice.example.com',
          displayName: 'Alice',
          custody: 'anp_root',
          exportedAt: '2026-11-15T00:00:00Z',
          sourceCoreVersion: '0.1.0',
          keyKinds: <String>['did_document_root'],
          hasDidDocument: true,
        );
      },
      importBackup: (backup, passphrase) async {
        importCalls += 1;
        importedBackup = backup;
        importedPassphrases.add(passphrase);
        final failure = importError;
        if (failure != null) throw failure;
      },
    );
  }
}
