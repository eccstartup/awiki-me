# Plan：身份备份导入与身份公钥展示

> 归档说明：本文档是 2026-11-15 的方案，规划两项能力——“身份备份（AWIKIBK1）导入”和“‘我’面板展示 DID 文档链接与当前身份公钥”。两项能力均已实现，落地差异见 §0；正文保留原始方案。Core 侧契约最终以 `awiki-cli-rs2` 的 Flutter SDK 文档为准。

状态：done（App/Core 已实现；E2E 未覆盖）
DOC：`awiki-me/docs/plan/20261115-identity-backup-import-and-public-keys/`
Harness：—
创建时间：2026-11-15
恢复指针：无；剩余工作仅 E2E（§4.5）。

## 0. 落地结果（2026-11-15）

- 特性 B（已实现）：
  - `lib/src/domain/services/did_document_url.dart`：`did:wba:<host>:<path...>` →
    `https://<host>/<path...>/did.json`，校验 host/scheme。
  - `AwikiImCoreIdentityAdapter` 解析 `verificationMethod` 为
    `IdentityVerificationMethod{keyId,type,relationship,publicKeyMultibase}`（mapper：
    `lib/src/data/im_core/identity_method_mapper.dart`）。
  - “我”面板身份信息区新增 DID 文档链接与只读公钥列表；compact 布局同样可用。
  - 测试：`tests/unit/data/im_core/identity_method_mapper_test.dart`、
    `tests/unit/identity_document_url_test.dart`、`tests/unit/profile_page_test.dart`。
- 特性 A Core（已实现）：
  - `im-core` 新增 `inspect_identity_backup(_async)` / `import_identity_backup`，
    FRB binding `inspectIdentityBackup` / `importIdentityBackup`；
  - V1 只接受 `custody == "anp_root"`，只安装 root 私钥 + DID 文档；
  - 错误码 `identity_backup_bad_magic|unsupported_version|bad_passphrase|
    unsupported_custody|payload_invalid|too_large`；
  - `permission_denied`（未确认 presence）、`identity_binding_conflict`、
    `already_present` 幂等；
  - 导入后设备 readiness 为 `root_only`；App runtime custody gate 已接受该状态
    （`lib/src/data/im_core/awiki_im_core_runtime.dart`）。
  - Rust 测试：`cargo test -p awiki-im-core identity_backup` 共 21 个通过。
- 特性 A App（已实现）：
  - 新增 port / service / adapter / dialog：
    `identity_backup_import_port.dart`、`identity_backup_import_service.dart`、
    `awiki_im_core_identity_backup_import_adapter.dart`、
    `identity_backup_import_dialog.dart`；
  - 入口在设置 → 安全（三套响应式布局共用），**未新增 onboarding 入口**，
    符合 CLAUDE.md 的统一登录/注册约束；
  - 文件选择复用现有 `AttachmentPickerService.pickAttachment`，没有新增
    `openFile` channel 或 `file_selector` 依赖；
  - `app_runtime_provider.dart` 的 `importCredentialArchive()` 占位已替换为
    `importIdentityBackup()`；
  - 测试：service 21、adapter 13、dialog widget 6、settings 入口接线更新。
- 与草案的差异：
  - 导入成功后**不重建 tenant runtime**。Core 已在当前 runtime 内完成身份注册；
    `alreadyPresent` 且导入的是当前身份时保留会话，否则退出当前会话、重新读取
    本地凭证并回到统一登录，用户按普通登录流程选择新凭证（提示
    `importSuccessSelectCredential`）。
  - §4.4 的“导入后如何登录”问题按上述方式落地：备份不含 JWT，导入后仍走正常
    登录/激活流程；本轮不验证 root 私钥直接换 JWT。
- 未完成：
  - §4.5 的 `identity-backup-import` E2E 未实现，`docs/test-case-catalog.md` 未改；
    当前覆盖为 Rust + App unit/adapter/widget。
  - `docs/identity-export-ui.md` 与 README 已按实际实现更新。

## 1. 目标

- 任务目标：
  - 特性 B：在“我”面板的身份信息区，展示当前 DID 对应的 DID 文档链接（可在浏览器打开 `did.json`），以及当前身份的公钥列表（key id、类型、用途、publicKeyMultibase，只读可复制）。
  - 特性 A：在设置页提供“导入身份备份”，用户选择 AWIKIBK1 备份文件并输入口令后，先做预检并展示摘要，经用户确认和 `UserPresencePort` 系统认证后，由 Core 完成身份安装。
- 预期行为：
  - 特性 B：链接 URL 由 DID（`did:wba:<host>:user:<user>:<id>`）按 WBA 规则推导为 `https://<host>/user/<user>/<id>/did.json`；公钥来自 Core 返回的 identity document 的 `verificationMethod`，不引入第二套身份事实源，不联网解析。
  - 特性 A：坏文件、错口令、超限文件、不支持的 custody 均在预检阶段以 typed 错误拒绝，不触达 Core 状态变更；成功导入后 App 重建 runtime，回到统一登录/身份加载流程。
- 非目标：
  - 不恢复消息、会话或联系人历史。备份只含身份材料（ANP custody 下为 root 私钥 PEM + DID 文档）；Handle Recovery 之后的 tail-only 历史缺口不能靠导入备份补回。
  - App 不持有、不显示、不持久化任何私钥或口令；不解析备份 payload。
  - 不实现 vault custody 备份的导入（V1 仅支持 `custody=anp`）。
  - 不修改 message-service 契约，不新增 App 侧 durable 身份事实源。
- 完成标准：
  - 特性 B：面板显示 DID 文档链接与公钥；公钥内容与本地 identity document 的 `verificationMethod` 一致；compact 布局可用；unit/widget 覆盖。
  - 特性 A：预检与服务层 typed 错误齐全且 fail closed；成功路径经过 `UserPresencePort`；安全诊断只记录 stage/稳定 code，不含口令、payload、身份或 key 材料；Core/App 两侧测试更新；E2E 与 `docs/test-case-catalog.md` 按需更新。

## 2. 现状与证据

### 2.1 导出已实现（App + Core）

| 层 | 位置 |
|---|---|
| 设置页入口 | `lib/src/presentation/settings/settings_page.dart:263-273, 421-430, 639-651, 803-820` |
| 导出对话框 | `lib/src/presentation/settings/identity_export_dialog.dart:13-110` |
| 导出 service / port / adapter | `lib/src/application/identity_export_service.dart:28-89`、`lib/src/application/ports/identity_export_port.dart:29-50`、`lib/src/data/im_core/awiki_im_core_identity_export_adapter.dart:12-58` |
| 保存文件面板 | `lib/src/data/.../method_channel_attachment_picker_service.dart:543-571`（`saveAttachment` channel；目前没有 `openFile`） |
| Core 导出 | `awiki-cli-rs2/crates/im-core/src/identity/registry.rs:436-484`（export）、`486-620`（backup_material_for_entry）、`628-696`（ANP 分支） |
| Core 容器 | `awiki-cli-rs2/crates/im-core/src/internal/identity_backup.rs:9-25`（容器定义）、`148-152`（seal） |

### 2.2 导入尚未实现

- `lib/src/presentation/app_shell/providers/app_runtime_provider.dart:984`：`importCredentialArchive()` 仍是占位，调用 `AppMessage.featureNotImplemented()`，且 lib 内无调用方。
- Core 的解密函数 `open_identity_backup` 目前是 `#[cfg(test)]`（`awiki-cli-rs2/crates/im-core/src/internal/identity_backup.rs:325-401`），没有生产入口。
- Core 内部已有 receiver-side root import 原语（`import_legacy_completion_root`、`promote_verified_root_import`，`root_key_id = {did}#auth`，幂等；SecretKind `IdentityRootPrivate` / `IdentityRootImportPending`），但没有任何 Dart binding。
- Dart bindings 现状（`awiki-cli-rs2/crates/im-core-dart/src/api/identity.rs`）：`identityDocument` 已有（:27，native `://awiki_im_core_native.dart:486`）、`export_identity_backup` 已有（:1047-1066）、root transfer 已有（:335-374）；**没有** import/inspect binding，也**没有** DID 文档 URL API。
- `docs/identity-export-ui.md` §9 落地顺序第 3 条明确记录 import/restore API 未实现。

### 2.3 可复用的既有能力

- App 已经调用 Core `identityDocument`：`lib/src/data/im_core/awiki_im_core_identity_adapter.dart:123-136`（目前只解析 `service`），是特性 B 公钥数据的现成扩展点。
- 面板落点：`lib/src/presentation/profile/profile_page.dart:209-255`（身份信息 section：DID 行 223-244，主页行 245-255），外链打开模式见 `350-358`（`launchUrl` + `AppMessage.linkOpenFailed`）；compact 分支 `137-166` 目前没有 DID 行。`showCurrentIdentityDialog/Page` 在 `profile_workspace_page.dart:21-69`。
- 可复制行组件：`lib/src/presentation/shared/copyable_did_line.dart:8, 63-71`；metadata/link 行：`lib/src/presentation/shared/identity_profile_surface.dart:445, 607`。

### 2.4 备份文件格式（AWIKIBK1，已实测）

- 64 字节头部：magic `AWIKIBK1`、version 1、header_len 64、kdf_id 1（Argon2id，64 MiB / t=3 / p=1）、aead_id 1（XChaCha20-Poly1305）、salt[16]、nonce[24]、ciphertext_len u64 LE；AAD = `header[..56]`。
- Payload schema `awiki.identity-backup.v1`：`identity{did, full_handle, display_name, anp_identity_store_id, anp_identity_id, custody}`、`keys{PEMs}`、`did_document`、`metadata{created_at, source, app_version}`、`excluded_material`。
- ANP custody 只导出 `did_document_root` 私钥 PEM 和 DID 文档；不包含消息、联系人、会话。
- 本机实测本身份导出：`custody=anp`；公钥含 `#key-1`（root）、设备签名 key、设备 E2EE X25519 key。
- DID → URL 规则已验证：`did:wba:awiki.me:user:yushanren:e1_cGz…` → `https://awiki.me/user/yushanren/e1_cGz…/did.json`（HTTP 200）。

## 3. 特性 B：“我”面板 DID 文档链接与公钥

### 3.1 数据来源

- identity document：继续走 Core `identityDocument`（App 已有 adapter，见 §2.3），在 adapter 中新增解析 `verificationMethod`，产出 domain entity：
  - `IdentityVerificationMethod { keyId, type, relationship（由 id 片段/controller 推导），publicKeyMultibase }`。
- DID 文档 URL：由 DID 按 §2.4 规则在 App 内推导（纯字符串变换，WBA 规则固定），或由 Core 提供 helper；推荐 App 内推导，避免为一个纯函数新增 Core API。展示与打开前校验 host 非空、scheme 固定 https。

### 3.2 UI

- `profile_page.dart` 身份信息 section（209-255 行区域）新增两行：
  - `DID 文档`：`IdentityProfileMetadataRow` + `IdentityProfileLinkValue`，点击经 `launchUrl(..., mode: LaunchMode.externalApplication)` 打开；失败提示复用 `AppMessage.linkOpenFailed`。key：`profile-did-document-row`。
  - `公钥`：默认收起为一行摘要（如“3 个公钥”），点击展开一个只读弹层/sheet，逐条展示 key id、type、relationship、publicKeyMultibase，可复制（复用 `CopyableDidLine` 的复制语义与 toast）。
- compact 分支（137-166）：至少加入 DID 文档链接；是否加入公钥入口与主布局保持一致，评审时确认。
- 新增 l10n key（en/zh），文案只描述“DID 文档/公钥”，不暗示私钥能力。

### 3.3 测试

- unit：identity adapter 对 fixture did document 的 `verificationMethod` 解析；DID→URL 推导的合法/非法用例。
- widget：profile 页两行存在、链接 URL 正确、复制回调、compact 布局渲染；provider 在 identity document 缺失时不崩溃（fail soft，仅隐藏公钥行）。
- 工作量：1-2 天，纯 App。

## 4. 特性 A：身份备份导入

### 4.1 语义

导入 = 在一台没有身份的 fresh App/Core root 上安装备份中的身份（root 私钥 + DID 文档），等价于离线版的 root 导入；不恢复消息历史（见 §1 非目标）。已有身份时属于高风险覆盖操作，必须二次确认 + `UserPresencePort`。

### 4.2 Core 侧（awiki-cli-rs2）

1. 解除 `open_identity_backup` 的 test 门禁，抽出可复用解密/校验路径；`validate_passphrase` 等保持现有实现。
2. `im-core-dart/src/api/identity.rs` 新增两个 binding：
   - `inspectIdentityBackup({required Uint8List bytes, required String passphrase}) -> IdentityBackupInspection`
     - 返回：did、full_handle、display_name、custody、created_at、source/app_version、key 种类列表、did_document 是否存在。
     - typed 错误：`bad_magic`、`unsupported_version`、`bad_passphrase`、`unsupported_custody`、`payload_invalid`、`too_large`。
   - `importIdentityBackup({required Uint8List bytes, required String passphrase, required bool userPresenceConfirmed}) -> IdentityImportResult`
     - 复用 `import_legacy_completion_root` + `promote_verified_root_import`（`root_key_id = {did}#auth`，幂等），写 SecretKind `IdentityRootPrivate` / `IdentityRootImportPending` 与现有 root import 路径一致。
     - 返回：installed identity_id / did、root_key_id、`already_present`（幂等标记）。
   - presence 用 boolean 传入（同现有 root transfer 模式）；App 侧仍在调用前经 `UserPresencePort` 做真实系统认证。
3. flutter_rust_bridge 重新生成；Rust 测试覆盖：roundtrip、错口令、截断/坏 magic、超限、custody fail-closed、幂等重复导入、presence=false 拒绝。

### 4.3 App 侧（awiki-me）

1. Port：`IdentityBackupImportPort`（inspect / import 两方法），adapter 调 frb。
2. Service：`identity_backup_import_service.dart`
   - 文件上限 1 MiB（超限在读取阶段拒绝，`too_large`）。
   - 文件一次性读入内存，不落盘；passphrase 只在调用参数中存在，不写入任何 store；bytes 在 finally 中 `fillRange` 清零。
   - 错误映射为 l10n 文案；诊断只记 stage / 稳定 code / 文件字节数，**不记** did、handle、passphrase、payload 或 key 材料。
3. 文件选择：现有 `method_channel_attachment_picker_service.dart` 只有 `saveAttachment` channel，没有 `openFile`。二选一，评审决策：
   - 新增 `openFile` file-picker channel（macOS NSOpenPanel；平台 runner 改动只触 macOS）；
   - 引入 `file_selector` 插件（引入新依赖，需评估）。
4. UI：设置 → 身份备份 区域新增“导入身份备份”，对话框流程：
   选文件 → 输入口令 → 调 `inspect` 展示摘要（DID、handle、创建时间、custody）→ 高风险二次确认（尤其已有身份时）→ `UserPresencePort` 认证 → `import` → 成功后重建 runtime（`app_runtime_provider` 现有 runtime 释放/重开路径），回到统一登录/身份加载。
5. 收尾：删除或改造 `app_runtime_provider.dart:984` 的 `importCredentialArchive()` 占位（确认无调用方后删除）。
6. Storage Scope：导入产生新 identity，必须落新/隔离 scope，遵守 CLAUDE.md 的 tenant/state/vault 归属约束；不得改写现有 owner 数据（已有身份覆盖时先提示并走认证）。

### 4.4 导入后的登录路径（开放问题，见 §6）

ANP root 私钥能否直接换取 JWT（identity activation / auth token）尚未确认。若不能，导入完成后仍需依赖现有 Handle Recovery/Join 流程，UI 文案必须如实说明“导入只安装身份材料”。

### 4.5 测试

- Core：见 4.2 第 3 条。
- App unit：service + fake port（大小上限、typed 错误、passphrase 不保留、presence 失败 fail closed）、导入对话框 widget 测试、provider 重建路径测试。
- E2E：新增 `identity-backup-import` suite（fresh App root + 真实 backend：导入本账号备份 → 断言 identity/DID 收敛、Direct exact-one），或按评审并入现有 multi-device 阶段；同步 `docs/test-case-catalog.md` 并过 `tool/validate_test_catalog.dart`。
- 工作量：Core 3-5 天；App 2-3 天；E2E + docs 1-2 天。

## 5. 实施顺序

1. 特性 B：面板 DID 文档链接 + 公钥（App only，无 Core 依赖）。
2. 特性 A Core：inspect/import API + bindings + Rust 测试（awiki-cli-rs2）。
3. 特性 A App：service / 文件选择 / 对话框 / runtime 重建 / 占位清理。
4. E2E + 文档：`docs/identity-export-ui.md` §9、README、`docs/test-case-catalog.md`，并回填本 plan 状态。

## 6. 风险与开放问题

- **导入后如何登录**：ANP root 私钥 → JWT 的路径未知；直接影响特性 A 的完成形态与文案（见 4.4）。
- **`anp_identity_store_id` 冲突策略**：目标机已存在同名 store 时，覆盖还是拒绝，需要 Core 明确并 fail closed。
- **vault custody**：V1 直接拒绝导入，文案需要解释。
- **文件选择器实现**：新增 channel vs `file_selector` 插件（§4.3.3）。
- **已有身份覆盖**：必须二次确认 + `UserPresencePort`；导入不得删除旧 owner 数据，除非用户显式选择（对应 Handle Recovery 的 owner 保留约束）。
- **安全红线**（CLAUDE.md）：App 不持有 DID/E2EE 私钥——解密与安装全部在 Core 内完成；App 只经 frb 一次性传递 bytes + passphrase；诊断不含异常正文、身份、payload 或 token。

## 7. 参考文件索引

- App：`lib/src/presentation/profile/profile_page.dart`、`profile_workspace_page.dart`、`lib/src/presentation/shared/identity_profile_surface.dart`、`copyable_did_line.dart`、`lib/src/data/im_core/awiki_im_core_identity_adapter.dart`、`lib/src/application/identity_export_service.dart`、`lib/src/application/ports/identity_export_port.dart`、`lib/src/data/im_core/awiki_im_core_identity_export_adapter.dart`、`lib/src/presentation/settings/identity_export_dialog.dart`、`settings_page.dart`、`lib/src/presentation/app_shell/providers/app_runtime_provider.dart`、`lib/src/data/.../method_channel_attachment_picker_service.dart`。
- Core（awiki-cli-rs2）：`crates/im-core/src/internal/identity_backup.rs`、`crates/im-core/src/identity/registry.rs`、`crates/im-core-dart/src/api/identity.rs`、`packages/awiki_im_core/lib/src/awiki_im_core_native.dart`。
- 文档：`docs/identity-export-ui.md`、`docs/root-key-transfer-ui.md`、`docs/handle-recovery-ui.md`、`docs/storage-scope-vault-contract.md`、`docs/scope-secret-platform.md`。
