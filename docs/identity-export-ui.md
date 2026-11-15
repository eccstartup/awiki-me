# 身份备份导出（App 侧方案）

> 状态：App 编排、口令确认、保存链路与 Core 加密导出均已落地。
> `im-core` 提供 `IdentityBackupPackage`（`AWIKIBK1` v1 容器，Argon2id + XChaCha20-Poly1305），
> Dart SDK 通过 `exportIdentityBackup` 暴露，App 通过 `AwikiImCoreIdentityExportAdapter`
> 覆盖 `identityExportPortProvider`。当前 onboarding 产生的 ANP 托管身份导出
> root-control 私钥（`custody: "anp_root"`），设备签名/E2EE 密钥不可导出。
> 导入/恢复 API 仍未实现。
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
直接失败。Core 导出已实现后，`AppBootstrap` 在装配 Core runtime 的同一路径上创建
[`AwikiImCoreIdentityExportAdapter`](../lib/src/data/im_core/awiki_im_core_identity_export_adapter.dart)，
经 `awiki_me_app.dart` 覆盖 `identityExportPortProvider`，不改 UI 与 service。

Core 侧对应的 Dart SDK 契约（`packages/awiki_im_core`）：

```dart
Future<IdentityBackupPackage> exportIdentityBackup(
  IdentitySelector selector, {
  required Uint8List passphrase,
});
```

- `selector` 固定为 `IdentitySelector.id(localIdentityId)`，不做 Handle/DID 猜测。
- Core 同步复制口令字节；Dart 侧传入的 `Uint8List` 仍由 service 在调用后清零。
- 口令长度由 Core 校验：8–1024 UTF-8 字节，越界返回 `invalid_input`。
- ANP 托管身份（当前 onboarding 默认）导出 **root-control 私钥**及其 DID document
  与身份元数据，`custody == "anp_root"`；设备签名密钥与 E2EE 密钥属于设备作用域，
  不可导出，新设备重新注册自己的密钥。
- 仅托管且没有本地 root-control 密钥的身份（例如加入设备）返回
  `unsupported_capability`，`capability == "identity_backup.custody_only"`；
  适配器将其映射为 App 的 `identity_export.unsupported`，其余 Core 错误
  映射为 `identity_export.failed`，均不生成文件。
- App 已在调用 Core 前完成 `UserPresencePort`；Core 在向 ANP identity store 请求
  root 导出时仍显式设置 `user_presence_confirmed: true`，该信任边界不变。

## 5. v1 容器格式（Core 权威，已实现）

以下格式由 `crates/im-core/src/internal/identity_backup.rs` 实现；App 不依赖这些字节布局。

### 5.1 外层二进制

```
offset  size  field
0       8     magic = "AWIKIBK1"
8       2     version = 1 (u16 LE)
10      2     header_len = 64 (u16 LE，整个 header 的长度)
12      1     kdf_id = 1 (Argon2id)
13      1     aead_id = 1 (XChaCha20-Poly1305)
14      2     reserved = 0 (u16 LE)
16      16    salt
32      24    nonce
56      8     ciphertext_len (u64 LE，含 16 字节 tag)
64      N     ciphertext
```

- KDF：Argon2id v0x13，`m = 64 MiB`、`t = 3`、`p = 1`，输出 32 字节密钥。
- AEAD：XChaCha20-Poly1305，24 字节随机 nonce；salt 与 nonce 每次导出重新生成。
- AAD：header 前 56 字节（`magic` 到 `nonce`，即不含 `ciphertext_len`），
  防止头部被替换。
- 校验：文件总长必须等于 `64 + ciphertext_len`；magic/version/header_len/kdf/aead/reserved
  任一不符、AAD 不匹配、解密失败都整体拒绝，不能部分恢复。

### 5.2 明文 payload（仅 Core 可见）

```json
{
  "schema": "awiki.identity-backup.v1",
  "identity": {
    "local_identity_id": "identity-uuid",
    "did": "did:wba:...",
    "handle": "alice",
    "full_handle": "alice.awiki.ai",
    "credential_name": "alice",
    "created_at": "2026-11-15T00:00:00Z",
    "custody": "vnext"
  },
  "keys": {
    "signing_private_pem": "-----BEGIN PRIVATE KEY-----...",
    "did_document_root_private_pem": "-----BEGIN PRIVATE KEY-----...",
    "e2ee_signing_private_pem": "-----BEGIN PRIVATE KEY-----...",
    "e2ee_agreement_private_pem": "-----BEGIN PRIVATE KEY-----..."
  },
  "did_document": {},
  "excluded": [
    "auth_jwt",
    "daemon_subkey_private",
    "device_certificates",
    "identity_vault_root",
    "mls_device_state",
    "messages",
    "read_state",
    "attachments",
    "product_overlay"
  ],
  "metadata": {
    "exported_at": "2026-11-15T00:00:00Z",
    "core_version": "0.1.9",
    "container": "AWIKIBK1",
    "kdf": { "id": "argon2id", "memory_kib": 65536, "iterations": 3, "parallelism": 1 },
    "aead": { "id": "xchacha20-poly1305", "nonce_bytes": 24 }
  }
}
```

密钥按角色导出，来自该身份的 vault migration refs 或 file-compat 本地材料：

| 字段 | vnext refs | legacy refs | file-compat |
|---|---|---|---|
| `signing_private_pem` | `device_request_signing_private`（必有） | `default_signing_private`（必有） | `key-1-private.pem` / `private.key` |
| `did_document_root_private_pem` | `did_document_root_private`（可选） | 无 | 可选 |
| `e2ee_signing_private_pem` | 无 | `e2ee_signing_private`（可选） | `e2ee-signing-private.pem` |
| `e2ee_agreement_private_pem` | `e2ee_agreement_private`（必有） | `e2ee_agreement_private`（必有） | `e2ee-agreement-private.pem` / `key-3-private.pem` |

`keys` 的每个字段都是可选的，但至少必须存在一项，否则 Core 返回
`identity_not_ready`（`missing: ["identity_private_key"]`），不写部分包。
ANP 托管身份只导出 `did_document_root_private_pem`：Core 从 ANP identity store 的
唯一 active managed RootControl key 取得 PKCS#8 DER，并重新编码为与 file-compat
一致的 PEM 形状；`identity.custody == "anp_root"`，设备签名/E2EE 字段省略。
设备签名与 E2EE 私钥属于设备作用域，按设计不可导出，新设备重新注册。

`handle`/`full_handle`/`created_at` 在缺失时省略；`credential_name` 取 local alias，
否则退回 local identity id。`did_document` 来自身份目录中的 `did_document.json`/`did.json`，
缺失时省略。vault/file-compat 路径上必需材料缺失时按 `identity_not_ready` 失败，
不写部分包；ANP 托管身份缺少设备密钥属于预期，不属于缺失。

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
awiki-identity-<component>-<yyyyMMdd-HHmmss>.awiki-backup
mimeType: application/vnd.awiki.identity-backup
```

`component` 优先取 full handle，其次 handle，最后 local identity id；非
`[a-zA-Z0-9_-]` 字符替换为 `-`，去首尾 `-`，转小写并截断到 48 字符。
文件名由 Core 生成。App 只拒绝空文件名、路径分隔符和超长名称，不重写扩展名。

## 6. App 实现结构

| 文件 | 职责 |
|---|---|
| `lib/src/application/ports/identity_export_port.dart` | 不透明包、typed 异常、默认 fail-closed 端口 |
| `lib/src/data/im_core/awiki_im_core_identity_export_adapter.dart` | 调用 Core `exportIdentityBackup`，映射 `identity_backup.*` 能力错误 |
| `lib/src/application/identity_export_service.dart` | 支持性检查、口令/身份校验、presence、session 围栏、Core 调用、保存 |
| `lib/src/presentation/settings/identity_export_dialog.dart` | 口令输入、确认、长度/一致性校验 |
| `lib/src/presentation/settings/settings_page.dart` | 从三套响应式入口打开同一弹窗 |
| `lib/src/presentation/app_shell/providers/app_runtime_provider.dart` | 捕获 `SessionEpoch`、调用 service、映射稳定错误码到 UI 反馈 |
| `lib/src/app/bootstrap.dart` / `awiki_me_app.dart` | 在 Core runtime 装配处创建适配器并覆盖 `identityExportPort` |
| `lib/src/app/app_services.dart` | `identityExportPortProvider` / `identityExportServiceProvider`（默认 `UnsupportedIdentityExportPort`） |

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

App 侧（`tests/unit/application/identity_export_service_test.dart`、
`tests/unit/data/im_core/awiki_im_core_identity_export_adapter_test.dart`）：

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

适配器（`awiki_im_core_identity_export_adapter_test.dart`）：

- 传入 exact `IdentitySelector.id` 与调用方口令字节（同一 `Uint8List` 引用）；
- 返回 Core 的文件名/MIME/bytes；
- `unsupported_capability` + `identity_backup.*` → `identity_export.unsupported`；
- 其他 Core 错误 → `identity_export.failed`。

Core（`crates/im-core/src/internal/identity_backup.rs`，Rust unit tests）：

- 密封→解密 round-trip，payload 字段与 schema 一致；
- 错误口令、篡改 header（salt）、篡改 ciphertext、截断容器全部拒绝；
- 文件名 handle 清洗、时间戳格式；
- 口令 8–1024 字节校验；
- ANP root-only 材料只保留 root PEM 且 `custody == "anp_root"`；
- 无任何密钥材料时 fail closed；
- PEM 编码只接受 48 字节 Ed25519 PKCS#8。

Core（`crates/im-core/src/identity/registry.rs`，Rust 集成测试）：

- 注入 workspace root key 创建的真实 ANP 身份：导出包解密后
  `custody == "anp_root"`、无设备签名/E2EE 字段，root PEM 解码后的 DER
  等于 ANP identity store 导出的 root-control PKCS#8。

Core/跨端（待实现）：

- 金标向量：固定 payload + 固定 salt/nonce 的容器可被独立实现解密；
- 导出 → 新 root 导入 → DID/Handle/Direct 连续性 exact-one；
- 包内不含 root key、JWT、设备 token（字节级检查）；
- 大 payload 与并发导出不破坏 vault 锁。

## 9. 落地顺序

1. ~~Core：实现 `exportIdentityBackup` 与 v1 容器/解密校验，提供 Rust 与 Dart 测试向量。~~
   已完成：`ImCore::export_identity_backup(_async)` + FRB `exportIdentityBackup`。
2. ~~App：新增 `AwikiImCoreIdentityExportAdapter`，覆盖 `identityExportPortProvider`。~~
   已完成：`AppBootstrap` 装配并透传到 `AwikiMeApp`。
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
