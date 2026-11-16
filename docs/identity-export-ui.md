# 身份备份导出与导入（App 侧方案）

> 状态：App 编排、口令确认、系统认证、保存链路，Core 加密导出，以及 Core 校验/安装的
> 加密导入均已落地。`im-core` 提供 `IdentityBackupPackage`（`AWIKIBK1` v1 容器，
> Argon2id + XChaCha20-Poly1305），Dart SDK 通过 `exportIdentityBackup` /
> `inspectIdentityBackup` / `importIdentityBackup` 暴露。App 通过
> `AwikiImCoreIdentityExportAdapter` / `AwikiImCoreIdentityBackupImportAdapter` 分别覆盖
> `identityExportPortProvider` / `identityBackupImportPortProvider`。当前 onboarding 产生的
> ANP 托管身份导出和接受导入的都是 root-control 私钥（`custody: "anp_root"`），
> 设备签名/E2EE 密钥不可导出，也不会从备份恢复。导入入口同时位于设置 → 安全和
> 统一登录/注册页，仅在 Core 端口支持时展示：已登录时用于把备份身份导入当前
> 本机，未登录时用于换机/首装后的身份恢复。导入只安装身份材料，不恢复消息、
> 联系人或会话，也不使本机成为该身份的授权设备：导入的凭证是 `root_only`，
> 没有设备密钥，不能兑换 JWT 或建立会话；使用该身份仍需真实设备 Join 或
> Handle Recovery 授权本机。未登录导入或点按 root-only 凭证后，登录面板就地
> 展示“恢复身份”面板，按本机实际凭证给出唯一正确的下一步：已有可用设备凭证时
> 直接进入（无 OTP），只有 root 材料时授权本机（服务端声明根签名重绑时以根凭据
> 把本机绑定到同一 DID，否则设备 Join；两者 DID 均不变），凭证缺失时重新导入；
> 面板绝不自动登录、加入或恢复。
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

导入方向同样按这条边界拆分：

| 能力 | 归属 |
|---|---|
| 选择备份文件、1 MiB 上限、单次内存读取、选后删除暂存副本 | App |
| 解密、容器校验、返回 secret-free 摘要（DID/Handle/托管方式/时间） | Core |
| 安装 root 私钥与 DID 文档、判定 `already_present` 与绑定冲突 | Core |
| 摘要展示、高风险确认、`UserPresencePort`、会话围栏、导入后登出 | App |
| 从备份恢复消息、联系人、会话、read state、JWT、设备 token | **双方都不做**（v1 显式排除） |

App 只接收一段不透明密文字节：导出时交给平台保存面板，导入时只在内存中交给 Core。
App 不解析容器、不读取内部 JSON、不把包内容写入日志或诊断。

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
新导入流程只接受 Core 解密校验通过的 `AWIKIBK1` v1 容器，且 v1 仅支持
`custody == "anp_root"`；旧 ZIP、明文 PEM 或其他托管方式一律 fail closed。

## 3. 用户流程

### 3.1 导出

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

### 3.2 导入

1. 设置 → 安全 → 导入身份备份，或统一登录/注册页的“恢复身份”。入口只在
   Core 端口支持时可用；未登录时入口仍可用，用于换机/首装后先把备份身份的 root
   材料安装到本机。该凭证只具备 root 托管，不包含设备密钥，因此不能直接登录
   （见本节第 9 条）。已登录导入要求同一 `SessionEpoch`；未登录导入要求
   tenant 不变且流程结束时仍未出现会话。
2. 打开“导入加密身份备份”对话框；选择文件走现有平台选择器
   （`AttachmentPickerService.pickAttachment`），App 拒绝空文件和超过 1 MiB 的文件，
   只读取一次，选后删除选择器暂存的应用内副本。
3. 输入备份口令后点“检查备份”：Core 解密并校验容器，只返回 DID、Handle、
   密钥托管方式、导出时间等摘要，**不改变本地状态**。
4. 摘要展示后按钮变为高风险的“导入身份”，并提示：导入会把该身份的根密钥和
   DID 文档安装到本设备；消息、联系人和会话不会被恢复；同时持有文件和口令的人
   可以恢复此身份。
5. 确认后调用系统身份认证（`UserPresencePort`）。拒绝、平台认证失败或本机身份
   状态已变化时都不调用 Core。
6. 认证通过后 Core 安装身份材料，返回 `identityId` / `did` / `rootKeyId` /
   `alreadyPresent`。
7. 若导入的正是当前登录身份（Core 返回 `alreadyPresent`），保留会话并提示
   “该身份已存在于本设备且已登录”。否则 App 退出当前会话（未登录时无需退出）、
   重新读取本地凭证，回到统一登录/注册并切到“登录”面板；同时以 Core 返回的
   exact `identityId` / `did` 初始化“恢复身份”面板（见本条第 9 项），而不是只
   弹一次 toast。导入路径本身不重建 tenant runtime，也不创建会话。
8. 关闭或取消对话框会把已选备份字节清零；失败时对话框保持打开并显示脱敏错误。
9. 导入凭证是 `root_only`：本机没有该身份的签名/E2EE 设备密钥，也没有服务端设备
   记录；ANP 不能为既有 DID 追加设备密钥，v1 备份也不携带设备密钥。App 用 Core 的
   `identityDeviceSummary(...).readiness == rootOnly` 判定该状态，在本地身份卡上展示
   “仅根凭据 · 需授权本机”标记，并把点按行为从登录改为打开同一个恢复面板。面板
   按精确 `did` + `localIdentityId`（绝不按 Handle 猜测；精确匹配优先于同 DID
   回退）解析三个阶段：
   - **直接进入**：本机已有该身份可用的非 root 设备凭证。主操作“直接进入”使用
     该凭证一键登录，不发送验证码，也不触碰导入的 root 材料。
   - **授权本机**：只有该身份的 root 条目（导入凭证或同 DID 仅有的 root 条目）。
     默认主操作“授权本机（设备加入）”：DID 不变，只为当前设备追加设备密钥，必须由
     该身份的已有设备批准；验证码只用于定位账号并请求批准，不创建新身份。当 Core
     adapter 支持且服务端 `server-info` 声明 `identity.device_rebind` 根签名方法时，
     主操作改为“把本机绑定到这个 DID”：不可逆确认后经 `UserPresencePort`，由根密钥
     签发同 DID 的单设备替换文档，旧设备被原子替换，DID/Handle/根公钥/
     `localIdentityId` 不变，设备加入降为次要操作；任一方未声明即 fail closed
     回退到设备加入，不按域名或产品名猜测。仅当
     服务端声明支持 phone OTP Handle Recovery 时，展示次要操作“改用 Handle
     Recovery”并注明这是最后手段、会更换该身份的 DID，绝不自动触发。
   - **凭证缺失**：本机没有匹配凭证。Core 仍支持导入时只提供“重新导入备份”；
     该状态只会在开始过的设备加入移除本机 root 条目后出现，面板文案说明备份
     文件不受影响、重新导入同一备份即可继续。
   两条授权续接都要求移除这份不能登录的根凭据（Core 在 Join/Recovery 激活时
   拒绝被 root-only 条目污染的状态），因此 App 先展示“本机导入的根凭据将被
   移除”的确认，明确说明移除只影响本机、备份文件不会被删除。设备 Join 在用户提交
   加入请求（OTP 换取 join session）成功后、任何轮询看到批准前删除本地 root-only
   条目，再继续激活；这样在加入页返回或取消时导入仍可用。删除失败时立即取消该
   Join 请求并停在本页，不进入激活。Handle Recovery 仍在进入恢复页前删除。
   面板的“返回”只清除恢复意图，不改变任何凭证。设备 Join 页在恢复上下文显示
   提示：加入后仍是同一个身份，DID 不会改变，验证码只用于找到账号并请求已有
   设备批准本机。若用户仍走登录
   路径，Core 对旧身份升级返回 `retry_required` +
   `root_only_requires_device_join`，App 跳过升级、不创建会话，并在同一授权
   说明投影中提供两个续接入口和一个返回按钮，而不是仅可返回的死路或可重复点击
   的“重试”。Handle/手机号已绑定该 DID 只说明账户归属，不代表本设备已被该身份
   的设备注册表授权；管理权/root 转移走独立流程，不由身份备份导入触发。

导入口令与备份字节同样只存在于对话框和单次 Core 调用的内存中：服务层在每次 Core
调用后清零口令副本，对话框在替换文件、关闭或导入完成时清零已选字节。App 不把备份
写入磁盘（选择器的暂存副本读取后即删除），也不持久化口令或摘要。

## 4. Core 接口契约

### 4.1 导出

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

### 4.2 导入

App 侧端口位于
[`lib/src/application/ports/identity_backup_import_port.dart`](../lib/src/application/ports/identity_backup_import_port.dart)：

```dart
class IdentityBackupSummary {
  final String did;
  final String? handle;
  final String? fullHandle;
  final String displayName;      // Core 取 credential_name
  final String custody;          // v1 固定 "anp_root"
  final String? createdAt;
  final String exportedAt;
  final String sourceCoreVersion;
  final List<String> keyKinds;   // v1: ["did_document_root"]
  final bool hasDidDocument;
}

class IdentityBackupImportOutcome {
  final String identityId;       // 已安装或已存在的 exact local identity
  final String did;
  final String rootKeyId;
  final bool alreadyPresent;
}

abstract interface class IdentityBackupImportPort {
  bool get isSupported;
  Future<IdentityBackupSummary> inspectIdentityBackup({
    required Uint8List bytes,
    required Uint8List passphrase,
  });
  Future<IdentityBackupImportOutcome> importIdentityBackup({
    required Uint8List bytes,
    required Uint8List passphrase,
    required bool userPresenceConfirmed,
  });
}
```

`UnsupportedIdentityBackupImportPort` 是默认实现，`isSupported == false` 时在打开
选择器前直接失败。`AppBootstrap` 装配 Core runtime 时创建
[`AwikiImCoreIdentityBackupImportAdapter`](../lib/src/data/im_core/awiki_im_core_identity_backup_import_adapter.dart)，
经 `awiki_me_app.dart` 覆盖 `identityBackupImportPortProvider`。

Core 必须：

1. 只接受 `AWIKIBK1` v1 且 `custody == "anp_root"` 的备份；其他版本/托管方式返回
   typed 错误（`identity_backup_unsupported_version` /
   `identity_backup_unsupported_custody`），不写任何状态。payload 还要求 DID 以
   `did:wba:` 开头、`did_document.id` 等于该 DID、`proof.verificationMethod` 存在，
   且只携带 root PEM（出现设备签名/E2EE 字段即 `identity_backup_payload_invalid`）。
2. `inspectIdentityBackup` 无副作用，只返回 secret-free 摘要；App 只展示，
   不把摘要写入持久化存储或诊断。
3. `importIdentityBackup` 必须收到 `user_presence_confirmed == true`，否则
   `permission_denied`；App 侧拒绝、取消或平台认证失败都不会走到这里。
4. 已存在同 DID 的 ANP 身份时，校验公钥身份一致后返回 `already_present: true`，
   不覆盖本地数据；同 DID 但非 ANP 托管、或本地 identity ID 已绑定其他 DID 时返回
   `identity_binding_conflict`。
5. 只安装 root 私钥与 DID 文档；消息、联系人、会话、read state、JWT、device token、
   MLS 设备态、PreKey 和 product overlay 均不恢复，也不写入。
6. 失败时不得留下部分身份或部分密钥材料。
7. 导入的身份只具备 root 材料，设备 readiness 为 `root_only`；App 的 runtime 启动
   检查必须接受 `root_only`（同时仍要求 ANP custody active/ready），否则导入后无法
   完成本地身份确认。root-only 身份没有本地设备密钥，Core 的
   `legacy_upgrade_status` / `upgrade_legacy_identity` 必须直接返回
   `retry_required` + 稳定码 `root_only_requires_device_join`，不得尝试 legacy→vault
   迁移；App 必须跳过升级、不创建会话，并展示设备 Join/Recovery 说明。设备签名/
   E2EE 密钥只能来自真实设备 Join（或 Handle Recovery）在该 DID 上的授权，不来自
   备份，也不能通过普通登录为既有 DID 追加。

App 服务层顺序固定（[`identity_backup_import_service.dart`](../lib/src/application/identity_backup_import_service.dart)）：

1. 端口不支持 → `identity_backup_import.unsupported`（选择文件前）；
2. 选择器取消 → 返回 `null`，不提示错误；
3. 选择器异常 → `identity_backup_import.read_failed`；
4. 声明或实际大小 > 1 MiB → `identity_backup_import.too_large`，已读字节清零；
5. 空文件 / 非普通文件 → `identity_backup_import.invalid_file`；
6. 空口令 → `identity_backup_import.passphrase_required`；
7. presence reason 为空 → `identity_backup_import.invalid_presence_reason`；
   `UserPresencePort` 返回 false → `user_presence_denied`；抛错 →
   `user_presence_failed`；三种情况都**不调用 Core**；
8. `SessionEpoch` 已变化 → `identity_backup_import.state_changed`，**不调用 Core**；
9. Core 的 `identity_backup_*` 稳定码原样透传；能力缺失映射为
   `identity_backup_import.unsupported`，`permission_denied` → `.denied`，
   `identity_binding_conflict` → `.conflict`；其余 inspect/import 异常分别映射为
   `.inspect_failed` / `.failed`。

导入不修改 product store，不删除或重写现有 owner 数据；唯一的状态变化来自 Core
安装的新身份材料。桌面端的三套响应式设置布局共用同一入口与同一弹窗。

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

导入 v1 只接受 `custody == "anp_root"` 的包；`vnext`、legacy 或任何携带额外设备
密钥的包即使能解密，也会以 `identity_backup_unsupported_custody` fail closed，
直到 Core 以新的 schema 版本显式扩展并单独评审。

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
| `lib/src/application/ports/identity_backup_import_port.dart` | 摘要、导入结果、typed 异常与默认 fail-closed 端口 |
| `lib/src/data/im_core/awiki_im_core_identity_backup_import_adapter.dart` | 调用 Core `inspectIdentityBackup` / `importIdentityBackup`，映射能力/权限/冲突错误 |
| `lib/src/application/identity_backup_import_service.dart` | 文件选择与 1 MiB 上限、单次读取、口令编码/清零、presence、session 围栏、Core 调用 |
| `lib/src/presentation/settings/identity_backup_import_dialog.dart` | 两阶段确认：检查备份 → 核对摘要 → 高风险导入 |
| `lib/src/presentation/onboarding/onboarding_page.dart` / `parts/onboarding_mac_part.dart` | 统一登录/注册页在 Core 支持时展示同一导入入口“恢复身份”，并在登录面板就地渲染恢复面板 |
| `lib/src/presentation/onboarding/restore_identity_provider.dart` | 纯状态：恢复意图、按精确 identity/DID 解析三阶段、`begin` / `beginFromOutcome` / `beginForCredential` / `clear` |
| `lib/src/presentation/onboarding/restore_identity_view_provider.dart` | 组合意图、本机凭证、服务端 Recovery 能力与 Core 导入支持，得到 `RestoreIdentityView` |
| `lib/src/presentation/onboarding/parts/restore_identity_panel_part.dart` | 恢复面板：直接进入、授权本机/Recovery、刷新/重新导入与返回；自身不登录、不 Join、不恢复 |
| `lib/src/presentation/onboarding/registration_entry_form.dart` / `parts/restore_identity_panel_part.dart` | 注册死路改为中性提示与唯一“恢复身份”入口；设备 Join 恢复上下文提示 |
| `settings_page.dart` / `onboarding_page.dart` / `app_runtime_provider.dart` | 设置三套响应式入口与登录页共用同一弹窗；`already_present` 保留会话，否则登出并重新加载本地凭证；未登录导入按 tenant 围栏放行 |
| `lib/src/app/app_services.dart`（导入） | `identityBackupImportPortProvider` / `identityBackupImportServiceProvider`（默认 `UnsupportedIdentityBackupImportPort`） |

导出服务层顺序固定：

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

导入错误码与 UI：

| 错误码 | UI |
|---|---|
| `identity_backup_import.unsupported` | “当前版本暂不支持导入身份备份。” |
| `identity_backup_import.invalid_file` / `identity_backup_bad_magic` / `identity_backup_unsupported_version` / `identity_backup_payload_invalid` | “该文件不是有效的身份备份。” |
| `identity_backup_import.too_large` / `identity_backup_too_large` | “备份文件超过 1 MB。” |
| `identity_backup_import.passphrase_required` / `identity_backup_bad_passphrase` | “口令错误或备份已损坏。” |
| `identity_backup_unsupported_custody` | “暂不支持该备份的密钥托管方式。” |
| `identity_backup_import.conflict` | “该身份与本机已有身份数据冲突。” |
| `identity_backup_import.user_presence_denied` / `user_presence_failed` | “身份验证已取消，未导入任何内容。” |
| `identity_backup_import.state_changed` | “当前登录身份已变化，导入已取消。” |
| `identity_backup_import.read_failed` / `inspect_failed` / `failed` | 通用导入失败提示 |

成功路径：`alreadyPresent` 且导入的正是当前身份时提示“该身份已存在于本设备且已
登录”；其余成功路径回到统一登录/注册，自动切到“登录”面板，并就地展示“恢复
身份”面板给出下一步（直接进入 / 授权本机 / 重新导入），而不是停留在注册表单或
只提示一次成功。登录/注册表单的输入与本地 root-only 条目 Handle 匹配时，不等
提交注册就展示中性提示与唯一的“恢复身份”入口，不再把“授权本机”和“Handle
Recovery”拆成注册侧动作；Core 的未完成注册入口只在对应 DID 方法已不可新建时
展示，本地已有身份材料的 Handle 也一律不展示（Core 记录仍保留，只是不再提供无法
继续的重试入口）。

错误只包含稳定 code、stage、count、时间；不包含异常正文、身份、路径或包内容。
用户取消系统认证、保存面板或文件选择器属于正常路径，不按错误上报。

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

导入 App 侧（`tests/unit/application/identity_backup_import_service_test.dart`、
`tests/unit/data/im_core/awiki_im_core_identity_backup_import_adapter_test.dart`、
`tests/unit/identity_backup_import_dialog_test.dart`，以及
`tests/unit/settings_page_test.dart` 的入口接线）：

- 端口不支持时在选择文件前失败；选择器取消返回 `null`；
- 声明大小与实际大小超过 1 MiB 都拒绝；路径文件只读一次且选后删除；空文件拒绝；
- 口令以 UTF-8 传给 Core，调用后临时字节清零；空口令不调用 Core；
- Core `identity_backup_*` 稳定码透传；能力缺失、`permission_denied`、
  `identity_binding_conflict` 映射为 App 稳定码；
- presence 拒绝、平台异常、reason 为空、session 变化时不调用 Core import；
- 成功路径把同一引用字节与口令交给 Core，且 `userPresenceConfirmed == true`；
- 对话框先检查再导入，摘要展示 DID/Handle/托管方式/导出时间，二次确认才调用导入；
- 关闭对话框清零已选字节；失败保留对话框与脱敏错误；Core 不支持时失败关闭；
- 设置页与登录页在 Core 支持时可打开导入对话框；Core 不支持时两处都不展示入口；
- 未登录时导入只要求 tenant 不变且不出现会话；成功后刷新本地凭证但不建立会话。

恢复面板与 root-only 授权路径（`tests/unit/restore_identity_view_test.dart`、
`tests/unit/onboarding_page_test.dart`、
`tests/unit/registration_entry_widget_test.dart`、
`tests/unit/data/im_core/awiki_im_core_identity_adapter_test.dart`、
`tests/unit/data/im_core/awiki_im_core_mappers_test.dart`、
`tests/unit/devices/devices_ui_test.dart`）：

- `resolveRestoreIdentityView` 按精确 `did` + `localIdentityId` 匹配，精确匹配优先于
  同 DID 回退，绝不按 Handle；非 root 设备凭证 → 直接进入，仅 root 条目 → 授权本机，
  无匹配 → 凭证缺失；Recovery 只在服务端声明支持时可用；
- `listLocalIdentities` 按 `identityDeviceSummary(...).readiness` 标记 `rootOnly`，
  selector 是 exact `IdIdentitySelector`；readiness 查询失败时按普通可登录凭证处理；
- `rootOnly` 经 `appSessionFromIdentity` / `toLegacySessionIdentity` 透传；
- 根凭据身份卡展示“仅根凭据 · 需授权本机”标记，点按打开恢复面板而不是登录
  （`loginCalls == 0`）；
- 直接进入一键登录且不发送验证码；凭证缺失只在 Core 支持时展示“重新导入备份”
  （不再提供刷新），点按打开导入对话框；服务端未声明恢复能力时不展示 Handle
  Recovery；
- “授权本机（设备加入）”与“改用 Handle Recovery”先要求确认移除本机 root-only
  条目（备份文件不删除，确认文案说明）；设备 Join 在提交加入请求成功后才删除本地
  条目，返回或取消不会失去导入；删除失败时取消该 Join 请求；Handle Recovery 在
  进入恢复页前删除，失败则留在面板；Handle 预填；取消确认则既不删除也不登录；
  面板“返回”清除恢复意图；
- 旧身份升级投影同样提供授权/恢复/返回三个动作，不再只有返回；
- 注册冲突提示在中性提示内只提供唯一的“恢复身份”入口，点按打开恢复面板；不再
  在注册表单内直接提供授权/恢复按钮，也不展示可点击的“前往登录页”；
- 设备 Join 页在 `restoreIdentity` 上下文展示“DID 不会改变”提示，普通 Join 不展示；
  `initialHandle` / `initialPhone` 预填并 trim。

适配器导入（`awiki_im_core_identity_backup_import_adapter_test.dart`）：

- 传入同一 `bytes` / `passphrase` 引用与 `userPresenceConfirmed`；
- 摘要与结果字段映射完整；
- `unsupported_capability` + `identity_backup.*` → `identity_backup_import.unsupported`；
- 其他 Core 错误按 inspect/import 分别映射为 `.inspect_failed` / `.failed`。

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
- `inspect_identity_backup` 错误口令时返回 `identity_backup_bad_passphrase`，
  且目标 root 的 identity registry 仍为空。
- `import_identity_backup` 未确认 user presence 时返回 `permission_denied`，
  不写任何身份。
- 导入到 fresh root 后：摘要与源的 DID/Handle/root 材料一致，身份 readiness 为
  `root_only`，custody 为 ANP identity 且 ready，且没有 auth token；重复导入返回
  `already_present` 且不覆盖本地数据。
- 导入后的 `legacy_upgrade_status` 与 `upgrade_legacy_identity` 都返回
  `retry_required` + `root_only_requires_device_join`，且不写 pending 记录、
  `device_state` 或 vault migration。
- 部分安装（registry 投影丢失）后再次导入能完成投影并保持同一 identity ID。

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
3. ~~恢复：为 `importCredentialArchive` 增加对应的 Core import API 与专用 UI；在此之前
   导入入口继续保持不可用。~~
   已完成，实际落点与草案不同：
   - Core：`inspectIdentityBackup` / `importIdentityBackup`（`AWIKIBK1` v1，仅
     `custody == "anp_root"`，导入后 readiness 为 `root_only`）；
   - App：`IdentityBackupImportService` +
     `AwikiImCoreIdentityBackupImportAdapter` + `IdentityBackupImportDialog`；
     入口位于设置 → 安全和统一登录/注册页，仅 Core 支持时展示；
   - 没有沿用旧 `importCredentialArchive` / 明文 ZIP 路径；
   - 导入成功后不做 tenant runtime 重建：Core 已在当前 runtime 内完成身份注册。
     若导入的是当前身份（`alreadyPresent`）则保留会话；否则退出当前会话、
     重新读取本地凭证并回到统一登录。未登录时导入同一条路径可用，退出会话为空操作。
   - 导入凭证为 `root_only`，不能登录：身份卡标记“仅根凭据 · 需授权本机”，点按
     打开就地“恢复身份”面板。面板按本机凭证给出直接进入 / 授权本机 / 重新导入
     三种下一步；授权本机走设备 Join（DID 不变），Handle Recovery 仅在服务端声明
     支持时作为更换 DID 的最后手段展示。设备 Join 在加入请求提交成功后、批准被
     消费前才移除本机 root-only 条目（备份文件保留，提交前退出不影响导入）；
     Recovery 在进入恢复页前移除。若仍走登录路径，Core 返回
     `root_only_requires_device_join`，App 不进入旧身份升级重试，也不创建会话。
4. E2E：在 `tests/e2e/` 增加 secret-free attestation，只记录“导出成功/大小/版本/
   恢复后 ID 连续性”，不记录口令、私钥或包内容。**尚未实现**：当前只有 Rust、
   service/adapter 与 widget 覆盖，没有 `identity-backup-import` E2E case，
   也没有更新 `docs/test-case-catalog.md`；真实 root 上的导出 → 新 root 导入
   continuity 仍待评审后补齐。
5. 平台：复用现有 `saveAttachment`（macOS `NSSavePanel`、iOS `UIDocumentPicker`），
   不新增平台通道；Android/Windows/Linux 按现有保存能力逐步开放。

## 10. 安全红线

- 不恢复明文 ZIP、PEM、`auth.json` 或任何未加密的私钥导出；导入只接受 Core
  校验通过的 `AWIKIBK1` v1 且仅 `custody == "anp_root"`。
- 不允许 App 读取、解析或重新打包 Core 的密文；导入也只消费 Core 返回的摘要。
- 不允许在没有 `UserPresencePort` 成功确认时调用 Core 导出或导入。
- 不允许把口令写入 `ProductLocalStore`、Keychain、日志、剪贴板或 URL。
- 不允许用 Handle、DID、credentialName 猜 exact identity；导入只按备份内携带的
  identity 安装，`alreadyPresent` 由 Core 按 DID/公钥身份判定。
- 不允许把身份备份当作 Root Key Transfer 或管理权转移。
- 不允许把导入描述成消息、联系人、会话或 read state 的恢复。
- 不允许把 `root_only` 导入凭证送入旧身份升级或建立会话，也不允许在 UI 上宣称
  导入后可通过普通登录直接激活；该凭证只能配合设备 Join / Handle Recovery 使用。
  “直接进入”只使用本机既有的非 root 设备凭证；导入的 root 凭证永远不能登录。
  Recovery 只能在用户显式选择后启动，且必须说明它会更换该身份的 DID。
- 不允许在 Core 返回失败时回退到“仅导出公开资料”并宣称成功。
- 不允许在备份字节未通过 1 MiB 上限与 Core 校验时写入任何身份状态。
