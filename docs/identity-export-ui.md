# 身份备份导出（App 侧方案）

> 状态：App 编排、口令确认与保存链路已落地；**加密包的字节生产仍由 Core 提供**。
> 在 Core 暴露 typed export API 之前，产品入口会以稳定错误码 fail closed，不生成任何文件。
>
> 相关文档：[identity-secret-storage.md](identity-secret-storage.md)、
> [storage-scope-vault-contract.md](storage-scope-vault-contract.md)、
> [multi-device-join-ui.md](multi-device-join-ui.md)、
> [root-key-transfer-ui.md](root-key-transfer-ui.md)。

## 1. 目标与边界

用户需要一个可以离线保管、换机后可恢复的身份备份。备份必须包含恢复该身份所需的
DID 私钥材料，因此不能沿用历史实现中的明文 ZIP。

| 能力 | 归属 |
|---|---|
| 决定备份内包含哪些密钥/元数据 | Core（`im-core` identity vault） |
| 口令派生、加密、完整性保护 | Core |
| 文件命名、MIME、密文容器版本 | Core |
| 用户确认、系统身份认证、状态围栏、保存文件 | App |
| 读取或解析包内明文 | **App 禁止** |
| 持有 DID 私钥、JWT、`SecretRef`、E2EE 私钥 | **App 禁止** |

App 只接收一段不透明密文字节，并把这段字节交给平台保存面板。App 不解析容器、
不读取内部 JSON、不把包内容写入日志或诊断。

本方案不是 Root Key Transfer。`identity_vault_root`、设备管理根和管理权转移仍走
[`root-key-transfer-ui.md`](root-key-transfer-ui.md)，不得塞进身份备份包。

## 2. 历史实现为什么不复用

已删除的 `credential_archive_service.dart` 会生成明文 ZIP：

```
awiki-credential-<handle>-<credential>-<timestamp>.zip
  manifest.json
  credential/identity.json
  credential/auth.json
  credential/key-1-private.pem
```

它把 DID 私钥和 JWT 直接写入文件，任何拿到文件的人都可以完整冒充身份；同时 App
需要读取 PEM，违反 secret ownership。该实现已禁用，不能作为新格式的兼容目标。
旧 ZIP 也不应被新导入流程自动接受。

## 3. 用户流程

1. 设置 → 安全 → 导出身份凭证（现有入口）。
2. App 弹出“导出加密身份备份”对话框：
   - 显示当前身份；
   - 输入备份口令；
   - 再次输入确认；
   - 明确提示：文件和口令需分开保管，AWiki Me 无法找回口令。
3. 校验通过后关闭对话框，调用系统身份认证（`UserPresencePort`）。
4. 认证通过后，Core 在该身份的 exact scope 内读取 vault、组装 payload 并加密。
5. App 收到不透明包，调用 `AttachmentPickerService.saveAttachment` 打开系统保存面板。
6. 用户选择位置后显示“已导出到 …”；取消保存则不提示成功。

口令只存在于当前对话框与一次 Core 调用的内存中：

- 关闭对话框后清空 `TextEditingController`；
- 服务层在调用 Core 后把临时 `Uint8List` 清零；
- Core 契约要求同步复制口令字节，不得保留引用；
- 口令、包内容、身份 DID 不进入日志、崩溃上报、E2E attestation 或诊断。

## 4. Core 接口契约

App 侧端口位于
[`lib/src/application/ports/identity_export_port.dart`](../lib/src/application/ports/identity_export_port.dart)：

```dart
class IdentityExportPackage {
  final String fileName;   // 建议以 .awiki-backup 结尾
  final String mimeType;   // application/vnd.awiki.identity-backup
  final Uint8List bytes;   // 已加密，App 不得解析
}

abstract interface class IdentityExportPort {
  bool get isSupported;
  Future<IdentityExportPackage> exportIdentityPackage({
    required String identityId, // exact localIdentityId / local selector
    required Uint8List passphrase,
  });
}
```

Core 必须：

1. 按 `identityId` 解析 exact local identity，不做 Handle/alias 猜测。
2. 在既有 vault 锁与 Storage Scope 内读取，不复制 root key。
3. 只导出该身份的恢复材料，不跨 tenant、不跨 owner。
4. 在返回前完成加密；返回后不得保留口令引用的语义。
5. 对不可导出状态返回稳定错误码，而不是空包或明文降级。
6. 保证同一输入产生可解密、可校验的容器；nonce 每次随机。

App 默认注入 `UnsupportedIdentityExportPort`，`isSupported == false` 时在系统认证前
直接失败。Core SDK 就绪后，在 `lib/src/data/im_core/` 增加适配器并在
`app_services.dart` 用 `identityExportPortProvider` 覆盖，不改 UI 与 service。

## 5. 建议的 v1 容器格式（Core 权威）

以下格式供 Core 实现与跨端测试对齐；App 不依赖这些字节布局。

### 5.1 外层二进制

```
magic            8 bytes   "AWIKIBK1"
version          u16 LE    1
header_len       u16 LE    后续 header 字节数
kdf_id           u8        1 = Argon2id
aead_id          u8        1 = XChaCha20-Poly1305
reserved         u16 LE    0
salt             16 bytes
nonce            24 bytes
ciphertext_len   u64 LE
ciphertext       ciphertext_len bytes
```

- KDF：Argon2id，`m = 64 MiB`、`t = 3`、`p = 1`，输出 32 字节密钥。
- AEAD：XChaCha20-Poly1305，24 字节随机 nonce。
- AAD：`magic || version || header_len || kdf_id || aead_id || reserved || salt || nonce`，
  防止头部被替换。
- 解密失败、AAD 不匹配、版本未知都必须拒绝，不能部分恢复。

### 5.2 明文 payload（仅 Core 可见）

```json
{
  "schema": "awiki.identity-backup.v1",
  "identity": {
    "did": "did:wba:...",
    "handle": "alice.awiki",
    "local_identity_id": "identity-uuid",
    "created_at": "2026-11-15T00:00:00Z"
  },
  "keys": [
    {
      "key_id": "key-1",
      "algorithm": "Ed25519",
      "private_key_pem": "-----BEGIN PRIVATE KEY-----..."
    }
  ],
  "identity_document": {},
  "e2ee": {
    "direct_identity_private_key": "base64...",
    "signed_prekey_private": "base64..."
  },
  "metadata": {
    "exported_at": "2026-11-15T00:00:00Z",
    "core_version": "...",
    "app_version": "..."
  }
}
```

默认**不包含**：

- `identity_vault_root` 或任何设备管理根；
- 设备注册凭证、device certificate、管理权 token；
- JWT、refresh token、cookie、server session；
- 已消费的一次性 PreKey；
- 群组 MLS 设备态（设备相关；恢复后按 Core 的重新加入/恢复流程处理）；
- 附件、消息、read state、product overlay。

如后续需要“恢复后可解密历史”，由 Core 以新的 schema 版本显式扩展，并单独评审；
不能在本版本静默加入。

### 5.3 文件名与 MIME

```
awiki-identity-<handle>-<yyyyMMdd-HHmmss>.awiki-backup
mimeType: application/vnd.awiki.identity-backup
```

文件名由 Core 生成。App 只拒绝空文件名、路径分隔符和超长名称，不重写扩展名。

## 6. App 实现结构

| 文件 | 职责 |
|---|---|
| `lib/src/application/ports/identity_export_port.dart` | 不透明包、typed 异常、默认 fail-closed 端口 |
| `lib/src/application/identity_export_service.dart` | 支持性检查、口令/身份校验、presence、session 围栏、Core 调用、保存 |
| `lib/src/presentation/settings/identity_export_dialog.dart` | 口令输入、确认、长度/一致性校验 |
| `lib/src/presentation/settings/settings_page.dart` | 从三套响应式入口打开同一弹窗 |
| `lib/src/presentation/app_shell/providers/app_runtime_provider.dart` | 捕获 `SessionEpoch`、调用 service、映射稳定错误码到 UI 反馈 |
| `lib/src/app/app_services.dart` | `identityExportPortProvider` / `identityExportServiceProvider` |

服务层顺序固定：

1. 端口不支持 → `identity_export.unsupported`；
2. 无 exact identity → `identity_export.no_identity`；
3. 口令 UTF-8 字节数 < 8 → `identity_export.passphrase_too_short`；
4. `UserPresencePort.confirm` 拒绝或平台失败 → `identity_export.user_presence_denied` /
   `user_presence_failed`，**不调用 Core**；
5. `SessionEpoch` 已变化 → `identity_export.state_changed`，**不调用 Core**；
6. Core 返回空包 / 空文件名 / 路径分隔符 / 空 MIME → `identity_export.invalid_package`；
7. 保存失败 → `identity_export.save_failed`；用户取消返回 `null`，不显示成功。

保存阶段不修改会话、不写 product store、不删除任何现有数据。

## 7. 失败与 UI

| 错误码 | UI |
|---|---|
| `identity_export.unsupported` | “当前版本暂不支持加密身份备份” |
| `identity_export.no_identity` | 复用 `noCredentialToExport` |
| `identity_export.passphrase_too_short` | 对话框内联错误 |
| `identity_export.user_presence_denied` | “身份验证已取消，未创建备份” |
| `identity_export.state_changed` | “当前登录身份已变化，导出已取消” |
| `identity_export.invalid_package` / `failed` / `save_failed` | 通用导出失败提示 |

错误只包含稳定 code、stage、count、时间；不包含异常正文、身份、路径或包内容。
用户取消系统认证或保存面板属于正常路径，不按错误上报。

## 8. 测试

App 侧（已加入/待跑，`tests/unit/application/identity_export_service_test.dart`）：

- 不支持端口时不调用 presence、不保存；
- 短口令、空身份被拒绝；
- presence 拒绝时不调用 Core；
- presence 后 session 变化时不调用 Core；
- 成功路径：Core 收到同一 identity 与口令字节，保存收到同一文件名/MIME/bytes；
- Core 返回空包、带路径文件名、空 MIME 时拒绝保存；
- 保存返回 `null`（用户取消）时 service 返回 `null`；
- 保存抛错映射为 `save_failed`。

Widget：设置页点击入口打开弹窗；口令过短、两次不一致时不能提交；输入一致后关闭
弹窗并调用 runtime。

Core/跨端（待 Core API）：

- 金标向量：固定 payload + 固定 salt/nonce 的容器可被独立实现解密；
- 错误口令、篡改 header、篡改 ciphertext、未知版本全部失败；
- 导出 → 新 root 导入 → DID/Handle/Direct 连续性 exact-one；
- 包内不含 root key、JWT、设备 token（字节级检查）；
- 大 payload 与并发导出不破坏 vault 锁。

## 9. 落地顺序

1. Core：实现 `exportIdentityBackup` 与 v1 容器/解密校验，提供 Rust 与 Dart 测试向量。
2. App：新增 `AwikiImCoreIdentityExportAdapter`，覆盖 `identityExportPortProvider`。
3. 恢复：为 `importCredentialArchive` 增加对应的 Core import API 与专用 UI；在此之前
   导入入口继续保持不可用。
4. E2E：在 `tests/e2e/` 增加 secret-free attestation，只记录“导出成功/大小/版本/
   恢复后 ID 连续性”，不记录口令、私钥或包内容。
5. 平台：复用现有 `saveAttachment`（macOS `NSSavePanel`、iOS `UIDocumentPicker`），
   不新增平台通道；Android/Windows/Linux 按现有保存能力逐步开放。

## 10. 安全红线

- 不恢复明文 ZIP、PEM、`auth.json` 或任何未加密的私钥导出。
- 不允许 App 读取、解析或重新打包 Core 的密文。
- 不允许在没有 `UserPresencePort` 成功确认时调用 Core。
- 不允许把口令写入 `ProductLocalStore`、Keychain、日志、剪贴板或 URL。
- 不允许用 Handle、DID、credentialName 猜 exact identity。
- 不允许把身份备份当作 Root Key Transfer 或管理权转移。
- 不允许在 Core 返回失败时回退到“仅导出公开资料”并宣称成功。
