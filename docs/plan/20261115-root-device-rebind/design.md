# 设计：仅持根凭据时把本机绑定到既有 DID

状态：已实现（服务端、Core、SDK、App；生产部署未包含）
关联：`20261115-identity-backup-import-and-public-keys`、`../awiki-cli-rs2/docs/architecture/multi-device/multi-device-architecter.md`、`../awiki-cli-rs2/docs/architecture/identity-secret-storage.md`
创建时间：2026-11-15
最后更新：2026-11-16

实现位置：

| 层 | 仓库/分支 | 关键文件 |
|---|---|---|
| 服务端 | `eccstartup/awiki-open-server` | `src/awiki_open_server/user_compat/core.py`（`device_rebind`）、`registration.py`（能力声明） |
| Core | `eccstartup/awiki-cli-rs2` `feat/device-rebind` | `crates/im-core/src/identity/device_rebind.rs`、`internal/identity_device_rebind*.rs`、`internal/identity_wire/device_rebind.rs` |
| SDK | 同上（`im-core-dart`） | `AwikiImCore.rebindDevice`、`AwikiImCoreOpenOptions.multiDeviceDeviceRebindEnabled` |
| App | `eccstartup/awiki-me` | `application/device_rebind_service.dart`、`data/im_core/awiki_im_core_device_rebind_adapter.dart`、restore 面板与 `AppRuntimeController.rebindRestoredIdentity` |

## 1. 目标与现场事实

目标场景：用户导入了 `AWIKIBK1` 根凭据备份（`custody = anp_root`），DID 在服务端已经存在，
但本机不持有任何该 DID 的设备私钥。用户要求用导入的根凭据把**当前这台机器**绑定为该 DID 的
设备，不新增账号、不更换 Handle、不更换 DID。

2026-11-16 对本机与线上环境的只读复核：

| 事实 | 证据 |
|---|---|
| DID 文档线上只有 1 台设备 `dev-R945Z0Ldb4zHAHYqwTh0JQ` | `GET /user/yushanren/e1_na8QK.../did.json`，`deviceManifest.devices` 长度 1 |
| 文档 proof 由 `#key-1`（根）签发，`created = 2026-11-15T09:46:14Z` | 同一响应 |
| 本机只有根密钥，无设备密钥 | `.anp-identity/identities/KWMDE…json`：`keys = [root_control]` |
| 生产 `server-info` 未声明 `identity.device_rebind` | `GET https://awiki.me/user-service/v1/server-info` → `identity.device_rebind` 为 `null` |
| eccstartup 服务端构建已实现该能力，默认关闭、按部署配置开启 | `registration.py`；`tests/test_device_rebind.py` |

因此本设计在代码层已可端到端执行；线上 `awiki.me` 要等 eccstartup 服务端构建部署并开启
feature 开关后才会在 `server-info` 中声明。未声明时 App 不展示入口、Core 拒绝调用。

`dev-…` 是协议设备身份，不是硬件信息：`ProtocolDeviceId::generate()` 取 16 字节 `OsRng`
随机数做 base64url 后加前缀 `dev-`。设备身份等于设备密钥对；DID 文档不承载机型或主机名。

## 2. 根签名重绑：职责与不变量

根密钥唯一被授权的新用途是**控制面替换文档**：根对 HTTP 请求签名，同时对替换后的 DID 文档
签名。它不成为设备凭据，也不签发设备 token。除此之外：

- DID、Handle、根公钥与根 `verificationMethod` 不变；
- 替换后的 Manifest 恰好一台设备（本机新生成的设备密钥）；
- `replaced_device_ids` 必须精确等于旧 Manifest 的设备集合，防止漏删；
- 该 RPC 只做“全部旧设备 → 唯一新设备”；正常加设备仍走 Device Join，不允许静默追加第二台；
- `update_document` 的既有不变量不动：设备 token 永远不能修改 Manifest。

## 3. 服务端契约

### 3.1 能力声明

`server-info` 的 `identity` 增加：

```json
"device_rebind": {
  "enabled": true,
  "methods": [{
    "id": "root_signature",
    "enabled": true,
    "verification": {"required": true, "type": "did_document_root_http_signature"}
  }],
  "purpose": "awiki.identity.device-rebind.v1"
}
```

关闭时 `enabled = false`、`methods = []`。App 只在 `enabled`、唯一 `root_signature` 方法与
proof 类型全部匹配时视为可用；任何偏差按未声明处理，不按域名或产品名猜测。

### 3.2 RPC

`POST https://<host>/user-service/v1/did-auth/rpc`，请求本身由根 key 做 HTTP Message
Signature（`signature-input` / `signature` 中的 key id 必须等于当前文档 proof 的
`verificationMethod`，nonce 一次性消费）。

```json
{
  "method": "device_rebind",
  "params": {
    "did": "did:wba:awiki.me:user:yushanren:e1_...",
    "operation_id": "awiki-me-rebind-...",
    "expected_document_hash": "sha256:<43 chars base64url>",
    "expected_document_version": 1,
    "expected_registry_version": 0,
    "new_document": { "...": "根 #key-1 不变；deviceManifest 仅含新设备" },
    "new_device": {
      "device_id": "dev-...",
      "signing_key_id": "#dev-...-sign",
      "e2ee_key_id": "#dev-...-e2ee"
    },
    "new_device_object_proof": { "...": "新设备 signing key 对 operation_id 的持有证明" },
    "replaced_device_ids": ["dev-R945..."]
  },
  "proof": { "...": "根对 canonical params 的 Object Proof" }
}
```

无 OTP。参数校验顺序与要点：

1. 根签名认证与 `did` 匹配；`operation_id` 必需、去空白、≤200 字符。
2. `operation_id` 已存在：同 DID 同 method 时直接返回已提交结果并重新签发 token
   （`replayed: true`），不再对照已重绑文档重新校验；跨 DID/method 返回 `operation_replayed`。
3. `expected_document_hash` 必须匹配 `sha256:[A-Za-z0-9_-]{43}`；版本计数器可选，提供时必须精确。
4. `new_document.id` 与 DID 一致、含 proof、消息服务条目完整；根 key 与旧文档完全一致，
   否则 `root_change_not_supported`。
5. 新旧 Manifest 都必须可解析；新 Manifest 恰好一台设备，`new_device` 三个 id 与文档一致。
6. `replaced_device_ids` 排序后等于旧 Manifest 设备集合；与旧设备账户完全相同则
   `device_rebind_unchanged`。
7. 新设备持有证明通过后进入单事务：版本/代次 CAS、旧设备账户整体替换、签发新设备 token、
   轮换 `users.token` 与 refresh token、写 `identity_operations` 幂等结果。

稳定错误码：`root_signature_required`、`invalid_http_signature`、`did_not_found`、
`did_mismatch`、`operation_id_required`、`operation_replayed`、`expected_document_hash_invalid`、
`expected_document_version_invalid`、`expected_registry_version_invalid`、
`new_document_required`、`new_document_id_mismatch`、`new_document_proof_required`、
`root_change_not_supported`、`new_document_device_manifest_required`、
`device_manifest_invalid`、`new_device_required`、`new_device_manifest_mismatch`、
`replaced_device_ids_mismatch`、`device_rebind_unchanged`、`document_digest_mismatch`、
`registry_version_mismatch`、`document_version_exhausted`、`registry_version_exhausted`。

响应只属于新设备：`did`、`document`、`document_version`、`registry_version`、
`device_id`、`signing_key_id`、`replaced_device_ids`、access/refresh token 与过期时间。
旧设备的访问与刷新 token 在同一事务中失效。

### 3.3 安全性质

- 单独持有根备份即可重绑，但这正是根凭据的定义；客户端仍必须完成不可逆风险确认与系统认证。
- 旧设备被原子替换并失去 token；不会获得“在新文档里继续存在”的半状态。
- 幂等结果只含脱敏字段（token 不落库），重放时重新签发。
- 根签名路径独立于 `current_did`，其他 handler 不会继承根认证。

## 4. Core 行为

公共边界（`identity/device_rebind.rs`）：

```rust
DeviceRebindRequest { identity: IdentitySelector, user_presence_confirmed: bool }
DeviceRebindResult  { did, device_id, already_bound }
```

- feature 关闭 → `ImError::unsupported("awiki-device-rebind-disabled")`；
  `user_presence_confirmed = false` → `PermissionDenied`。两者都不触网。
- 结果投影不含 operation id、文档、证明、密钥或 bearer 凭据。
- 只接受 root-only 身份：`identity_custody_backend == anp_identity`、
  `anp_identity_store_id` / `anp_identity_id` 存在、`device_state` 为空、且有 RootControl key。
  非 root-only 身份直接拒绝，不会重复重绑。
- 已绑定（live 文档摘要等于本机身份）→ `already_bound: true`，不上传。

内部编排（`internal/identity_device_rebind.rs`）：

1. 解析 live DID 文档并计算摘要，确认与 pending 记录或新意图一致。
2. 通过 SecretVault 导出根 PKCS#8，生成新的 signing/e2ee 种子，构造单设备新文档，
   根签名 Object Proof，写 Vault-only pending 记录
   （`internal/identity_device_rebind_pending.rs`，schema v1，每个身份最多 8 条）。
3. 根签名 HTTP 调用 §3.2；token 与文档留在 pending/内部，不投影。
4. 校验响应 token（Admin / management_ready、`key_id` 等于新 signing key）后，
   在同一 local operation 内替换同 DID 的 provider 身份、安装根 PKCS#8 与设备种子、
   保存 VNext Index（保留同一 `local_alias` / `unique_id`），最后才删除 pending 记录。
5. 远端失败按类别处理：
   - `document_digest_mismatch` / `did_document_changed` → 重新解析后重试，最多
     `MAX_REBIND_ATTEMPTS = 2` 次；仍不一致则保留 pending 供后续精确续跑；
   - `operation_replayed` / `root_change_not_supported` → Fatal，不重试；
   - `device_rebind_unchanged` / `new_device_manifest_mismatch` /
     `replaced_device_ids_mismatch` / `document_version_exhausted` /
     `registry_version_exhausted` → Conflict，不自动绕过；
   - 其他失败保留 pending，严格续跑同一 `operation_id`，不重新生成设备密钥。
6. 诊断只记录 stage/category/稳定 code/HTTP status/count/time；错误正文经
   `redact_rebind_error` 脱敏。

Core 不改变 DID、Handle 或根密钥；`localIdentityId`（Index `unique_id`）跨重绑稳定，
App 可以据同一 ID 静默刷新凭据而不按 DID 猜测身份。

## 5. SDK 与 App

- SDK：`AwikiImCore.rebindDevice({selector, userPresenceConfirmed})`；
  `AwikiImCoreOpenOptions` 的四个构造器都接受 `multiDeviceDeviceRebindEnabled`，默认开启。
- App 配置：`AwikiEnvironmentConfig.multiDeviceDeviceRebindEnabled`（dart-define
  `AWIKI_MULTI_DEVICE_DEVICE_REBIND_ENABLED`，默认 `true`），传入 `AwikiImCoreRuntime`
  （vaultRequired 打开选项）；关闭时不创建 adapter，provider 保持
  `UnsupportedDeviceRebindPort`。
- `DeviceRebindService`：先校验 Core 支持与参数，再调 `UserPresencePort`；取消/不支持即
  fail closed，绝不触网；绑定前后检查 tenant 与 session epoch，变化即
  `device_rebind.state_changed`；Core 返回的 DID 必须等于 intent DID。
- 错误映射：`permission_denied → device_rebind.denied`、
  `identity_binding_conflict → device_rebind.conflict`、
  `unsupported_capability → device_rebind.unsupported`，其余 `device_rebind.failed`。
- restore 入口三向门禁同时成立才展示“把本机绑定到这个 DID”：
  构建开关开启、Core adapter 支持、`server-info` 声明根签名重绑；且仅当面板处于
  `authorizationRequired`（本机只有 root-only 凭据）。Join 降为次要操作；Recovery 仍按其
  服务端声明展示为更换 DID 的最后手段。
- 点击后先弹不可逆风险确认（会替换 DID 文档中现有设备），再走系统认证；成功后静默刷新
  本地凭据。凭据刷新失败不回写为绑定失败——DID 文档已经提交，只影响当前视图。

## 6. 测试

- 服务端：`tests/test_device_rebind.py` 覆盖能力声明、成功替换、重放、摘要/版本冲突、
  根变化拒绝、设备持有证明与不变更错误。
- Core：`im-core` 全量 lib 测试（1763+）通过；pending 生命周期、错误分类、脱敏与
  root-only 判定均有单测。
- App：`tests/unit/onboarding_device_rebind_capabilities_test.dart`、
  `tests/unit/application/device_rebind_service_test.dart`、
  `tests/unit/restore_identity_rebind_view_test.dart`、
  `tests/unit/restore_identity_rebind_panel_test.dart`。
- E2E：尚未新增真实远端 rebind suite；线上验证需要先部署 eccstartup 服务端构建并开启
  `identity.device_rebind`，否则 `server-info` 不声明、App 不展示入口（fail closed 本身即为
  预期行为）。

## 7. 当前可用路径

- 部署了 eccstartup 构建且声明能力的服务端：导入根备份 → restore 面板 →
  “把本机绑定到这个 DID” → 系统认证 → DID 文档替换为本机唯一设备 → 直接进入。
- 未声明能力的生产 `awiki.me`（Release-1106）：同 DID 仍无法在本机获得设备凭据；App 只展示
  Device Join（需列表内设备批准）与 Handle Recovery（更换 DID）。
