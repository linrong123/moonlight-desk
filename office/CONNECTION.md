# 直连与授权设计

本文是 Moonlight Desk（主控端）与 Sunshine Desk（被控端）共同遵守的连接与授权约定。决策背景见 [ADR 0001](adr/0001-direct-ip-authorization.md)，整体路线见 [路线图](ROADMAP.md)。

## 背景

主流远控（ToDesk、向日葵、RustDesk）的体验是：输入对方标识 → 对方点允许 → 连上；被控端能随时看到和撤销谁有权限。本项目是公开仓库，不能内置或依赖任何私有服务器，因此首期只做「输入 IP/域名直连」，为以后用户自建中转保留接口。

## 目标与非目标

目标：

- 主控端输入 IP 或域名即可发起授权，被控端弹出原生窗口确认，不再需要打开网页管理后台输入 PIN。
- 被控端托盘可查看、禁用和删除已授权设备，禁用/删除立即断开该设备的串流。
- 可选「每次连接需本机确认」，默认关闭以支持无人值守。
- 默认强制串流加密，为以后经第三方中转打基础。
- 继续兼容 GameStream 协议、官方 Moonlight 客户端与上游合并。

非目标（本期不做）：设备号体系、内置/默认中转或打洞服务、绕过或保存 Windows 登录密码、手机端。

## 方案

### 1. 首次授权：被控端弹窗输入 4 位验证码

沿用 GameStream PIN 配对协议，不改报文：

1. 主控端发起配对，生成 4 位验证码并显示「请在被控电脑弹出的窗口中输入验证码 1234」。
2. 配对请求的 `devicename` 由上游写死的 `roth` 改为本机名称（去控制字符、去首尾空白、UTF-8 截断到 64 字节，为空时用 `Moonlight Desk`）。Sunshine 允许 1–128 字节。
3. Sunshine Desk 收到配对请求后，在当前用户桌面弹出「授权请求」窗口：设备名称、来源 IP、验证码输入框、允许/拒绝。允许即以该验证码和设备名完成配对；拒绝立即让该配对请求失败，主控端不必等到超时。
4. 验证码错误时配对失败，与上游行为一致。主控端不自动重试配对（认证失败不得循环重试）。
5. 防弹窗轰炸：同时最多 3 个授权窗口，超出的请求只保留上游托盘通知和网页入口；配对会话过期或完成时窗口自动关闭。

为什么不做「只点允许」：只点按钮时，同网段他人同时发起的请求可能被误放行；验证码把这次允许绑定到具体请求，保留 GameStream 的防中间人能力。

### 2. 再次连接：默认免确认，可开启每次确认

被控端配置项 `desk_confirm_connections`（`disabled`/`enabled`，默认 `disabled`），托盘有对应勾选项并写回配置。

协议（仅注册在已配对客户端证书保护的 HTTPS 上，与 `office/cursor` 相同的认证）：

- `serverinfo` 宣告 `OfficeConnectConfirm`：`1` 表示当前开启每次确认，`0` 表示未开启；缺失表示旧版或原版主机。
- `GET /office/connect-request?action=start|status|cancel`，返回 GameStream XML：

  ```xml
  <root status_code="200"><state>pending</state><timeoutSeconds>60</timeoutSeconds></root>
  ```

  `state` 取值：`not_required`（未开启确认）、`pending`、`approved`、`denied`、`expired`、`none`（status 时无请求）。`action` 缺失、重复或非法返回 `status_code=400`。
  - `start`：为该证书建立待确认请求并弹出「「名称」请求连接此电脑 允许/拒绝」窗口；已有 pending/approved 时原样返回，不重复弹窗。每证书最多 1 个 pending，全局最多 3 个。
  - `status`：只查询，不创建。
  - `cancel`：撤回 pending 并关闭窗口。
  - 60 秒无人处理变为 `expired`；`denied`/`expired` 结果保留 30 秒供查询。
- 批准后发放绑定该客户端证书的一次性许可，30 秒内有效，由下一次 `/launch` 或 `/resume` 消耗。
- 开启确认时，没有有效许可的 `/launch`、`/resume` 返回 XML `status_code=403`、`status_message="Host approval required"`，同时自动发起一次 `start`，便于官方 Moonlight 用户在被控端批准后手动重试。
- 已批准串流在断开后 120 秒内，由同一证书恢复（Moonlight Desk 断线重连）无需再次确认，避免网络抖动后要求被控端有人点击。主动断开、禁用或删除授权时立即取消该宽限。

主控端行为：

- 主机宣告 `OfficeConnectConfirm=1` 时，在 launch/resume 前调用 `start`，界面显示「正在等待被控端确认…」与取消按钮，每秒 `status` 轮询，最长 65 秒。
- `approved`/`not_required` → 继续原有启动流程；`denied` → 「被控端拒绝了连接」；`expired` → 「被控端未在 60 秒内确认」。两者都不自动重试，恢复链终止。
- 用户取消 → 发送 `cancel` 后返回工作台。
- 启动仍收到 `403 Host approval required` 时按拒绝处理，不重试。
- 未宣告该能力的主机按原流程连接。

### 3. 授权管理与撤销

被控端托盘「已授权设备」子菜单列出已配对设备（名称、启用状态），每项可「禁用/启用」「删除授权」（删除前确认）。复用上游 `nvhttp::set_client_enabled` / `nvhttp::unpair_client`，禁用和删除都立即结束该证书的串流。上游网页「故障排除 → 取消配对」入口保留。

### 4. 加密默认值

Sunshine Desk 在未显式配置时，`lan_encryption_mode` 与 `wan_encryption_mode` 默认 `2`（强制），已有显式配置优先。Moonlight Desk 在具备 AES 硬件加速且多于 2 核的设备上请求全量加密（Apple Silicon 满足）。不支持加密的旧客户端将被拒绝，这是有意的取舍。

### 5. 预留：自建中转

以后支持用户自建中转时，主控端的设备记录增加「连接路线」：`direct(地址:端口)`（当前唯一一种）与 `relay(中转地址, 令牌)`。中转只做转发，身份靠配对证书锁定、内容靠强制加密，不需要信任中转方。仓库不内置任何默认中转地址。实现倾向主控端本地端口转发，避免修改 moonlight-common-c；各串流端口能否整体映射需届时实测。

## 安全边界

- 弹窗由被控端用户会话中的 Sunshine 进程直接显示和处理，不新增本机或网络管理接口，不复用网页管理员密码。
- Windows 锁屏/安全桌面时弹窗不可见，请求按超时处理；本软件不绕过 Windows 登录。
- 公网直连只需开放 GameStream 串流端口；网页管理端口保持上游默认仅本机访问，不应暴露到公网。
- 多个主控端同时请求时各自独立确认，不共享许可。

## 已知限制

- 授权弹窗与托盘管理首期仅 Windows 实现；其他平台保留上游网页 PIN 流程。
- 被控端无人且未授权的设备无法首次连接，这是设计目标而非缺陷。
