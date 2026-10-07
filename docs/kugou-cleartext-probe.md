# 酷狗明文端点收口探针（v1.4.1 / task-17 §4b）

- 探针脚本：`scripts/test_kugou_tls_probe.dart`（Dart `HttpClient`，**证书校验开启**，默认拒绝自签/错配证书）
- 原始输出：`scripts/test_kugou_tls_probe_out.txt`
- 运行：`dart run scripts/test_kugou_tls_probe.dart`（2026-10-06/07，本机）

> 为什么用 Dart 而不是 `curl`：本机上 `curl` 对这些主机做 TLS 一律直接失败（握手层），
> 无法区分"没有 443"与"证书不可信"。Dart 的 boringssl 能完成握手并把区分的错误报出来，
> 所以探针必须用 Dart 写。同一脚本还对每个主机做了明文 HTTP 对照请求。

## 结论（决定性）

| 主机 / 端点 | 443 (HTTPS) | 对照 (HTTP) | 处置 |
|---|---|---|---|
| `tracker.kugou.com/v6/priv_url`（**私密取流地址**） | ✅ `HTTP 200`，证书有效 | ✅ 200 | **改为 HTTPS** |
| `mobilecdn.kugou.com/api/v2/user/vip`（token 在 query） | ❌ `CERTIFICATE_VERIFY_FAILED: Hostname mismatch` | 200/404 | 保持明文 + 注释标注风险 |
| `mobilecdn.kugou.com/api/v5/song/collect`（token 在 query） | ❌ 同上 | 200/404 | 保持明文 + 注释标注风险 |
| `mobilecdn.kugou.com/api/v3/rank/list`（读接口，对照） | ❌ 同上 | ✅ 200 | 保持明文（白名单支撑项） |
| `mobilecdnbj.kugou.com/api/v3/singer/info`（对照） | ❌ 同上 | ✅ 200 | 保持明文 |
| `login.user.kugou.com/v7/send_mobile_code`（手机号） | ❌ 同上 | ✅ 200 | **链路整体移除**（酷狗只留扫码） |
| `m.kugou.com/app/i/getSongInfo.php`（v1.4.0 已改 HTTPS，回归对照） | ✅ `HTTP 200`，`status:1` | — | 保持 HTTPS |

关键细节：`mobilecdn*.kugou.com` 的失败**不是**"没有 443"，而是**证书主机名不匹配**
（`CERTIFICATE_VERIFY_FAILED: Hostname mismatch`）。也就是说服务端 443 上有证书，
但它不适用于该主机名 —— 客户端（含 Android）会拒绝，因此**不可能**把这些端点迁到 HTTPS。

## 本次据此做的改动

1. `KugouEndpoints.songPrivateUrl`：`http://tracker.kugou.com/v6/priv_url` → `https://…`。
   这是 §4b 的优先项：它返回**私密取流地址**，被改写后会被下载器落盘（与 v1.4.0 已修的
   `getSongInfo` 同级风险），而现在该响应无法再被同路径中间人替换。
2. `songCollect` / `songUncollect` / `vipInfoApi`：**保持明文**，在代码里就地标注风险与理由
   （见 `kugou_endpoints.dart` 的注释）。理由：这两个主机没有可用 TLS，唯一替代是
   "收藏/取消收藏按钮永久不可用"；而暴露的是**用户自己的 token**、动作可逆，
   所以选择保留功能 + 明示风险，而不是静默降级。
3. 播放取流的兜底：`KugouPlatform.getSongUrl` 在私密路由与两条 v5 路由**全部失败**后，
   回退到已经走 HTTPS 的 `getSongInfo` 播放地址，并记一条
   `kugou_playback/quality_downgraded_to_songinfo` 诊断——降级可见，不是静默。

## 白名单（`network_security_config.xml`）**没有缩小**

只留扫码消除的是**手机号 + 验证码链路**（`login_page` 的表单与 `KugouPlatform.sendPhoneCode`/
`loginByPhone` 的网络调用）。白名单里 `kugou.com` 是**一条整域**条目，它同时支撑
search / rank / rank-song / singer / album / homepage / special / collect / uncollect /
vip / login-index / tracker 等十余个明文端点，`login.user.kugou.com` 从来没有独立条目，
所以本次**删不掉任何一条白名单**，条数不变。白名单的收窄依赖这些端点后续是否上 TLS，
不依赖登录方式。

## 残余风险（如实列出）

1. `mobilecdn.kugou.com` 与 `mobilecdnbj.kugou.com` 上的**全部读接口**仍是明文：
   同路径中间人可篡改榜单/搜索/专辑元数据。无法修复（服务端证书错配）。
2. `song/collect`、`song/uncollect`、`user/vip` 的 **token 明文出现在 query string**。
3. `login.user.kugou.com` 虽已从 UI 移除，但常量与 `KugouApi.sendMobileCode`/`login`
   仍在代码里（接口层删不掉），已在注释中标注"禁止重新启用"。
4. `gateway.kugou.com/v5/url` 取流路由仍未验证可用（复刻签名返回 `err 20006 err signature`），
   若它在线返回 `*.kgcdn.com` 之外的明文 CDN 地址会被 Android 拦截；白名单保留了
   `kgcdn.com` 作为兜底。
