# 文本剪贴板同步（主控端 Mac）

## 背景与目标

办公场景下最常见的跨机操作是“在 Mac 上复制、在 Windows 里粘贴”，反之亦然。本功能在 Moonlight Desk（Mac 主控端）与 Sunshine Desk（Windows 被控端）之间同步**纯文本**剪贴板，体验接近“远程桌面”：切换窗口时自动带过去，不需要额外按钮。

非目标：图片、文件、富文本（RTF/HTML）；实时双向推送（被控端主动通知）；Windows 以外的被控端；原版 Sunshine。

## 行为

| 时机 | 动作 |
| --- | --- |
| 连接建立（工具栏启动） | 后台 GET 一次，只记下被控端当前序号（baseline），**不**把 Windows 已有内容拉到 Mac；若此时串流窗口有键盘焦点，按“获得焦点”处理一次，把连接前在 Mac 上复制的文本推过去 |
| 串流窗口获得键盘焦点 | Mac `NSPasteboard.changeCount` 有变化且是文本 → 后台 POST 到被控端 |
| 串流窗口失去键盘焦点 | 后台 GET；被控端序号有变化且是文本 → 写入 Mac 剪贴板 |
| 主动断开（工具栏“断开”、关闭窗口、退出） | 在 `LiStopConnection` 之前再 GET 一次，最多等 1.5 秒，“复制后马上断开”也能带回 Windows 的文本 |
| 连接中断、分辨率切换重连 | 不做最后一次拉取（会话已不可用或马上恢复），挂起的结果丢弃 |

- 焦点判定沿用 `officePollUi` 的 `SDL_GetKeyboardFocus() == m_Window`，在 SDL 主循环中边沿触发；统计浮窗不抢键盘焦点；点工具栏按钮不改变键盘焦点（推断，待实机确认）。分辨率确认框等 sheet 会短暂取走焦点，只会多一次无害的拉取。
- HTTP 请求在单线程 `QThreadPool` 中执行（3 秒超时，最后一次拉取 1.5 秒），读写 `NSPasteboard` 只在 SDL 主线程。后台完成后推送一个自注册的 SDL 事件唤醒主循环，让拉取结果在一帧内落到 Mac。
- 日志只记录状态码和字节数，从不记录剪贴板内容。

## 去重规则

决策逻辑在平台无关的 `office::ClipboardSync`（`app/office/clipboardsync.*`），单测覆盖。

- **Mac → Windows**：记住最后一次“已同步”的 `changeCount`（推送过的、或本端写入后的）。获得焦点时 `changeCount` 未变则跳过；变了先登记，非文本（图片、文件）或空文本不推送，也不反复重试。
- **Windows → Mac**：记住被控端最后一个 `sequence`（baseline、推送返回、拉取返回都会更新）。拉取时序号未变则跳过；序号变了但文本与 Mac 当前文本（换行规范化后）相同也不写，避免无意义地改动 `changeCount`。
- **本端写入不回推**：写 Mac 剪贴板后把新的 `changeCount` 登记为已同步；推送返回的 `sequence` 登记为已同步，所以自己推过去的内容不会被拉回来。
- **本地优先**：拉取请求发出后 Mac 上又复制了新内容（`changeCount` 变化），丢弃这次拉取结果，只更新序号，新内容在下次获得焦点时推送。
- **换行**：线上一律 LF；Mac 文本中的 CRLF/单独 CR 推送前转 LF，拉取结果同样规范化。
- **大小**：UTF-8 不超过 1 MiB（规范化后计算）。Mac 侧超限不推送并记日志；被控端回 `tooLarge=1` 时不拉取并记日志。

## 失败处理

- 网络错误、超时、503（剪贴板被占用）、其他 5xx：只记日志、不弹窗。推送失败时撤销“已同步”登记，**下次获得焦点**再试一次（不在后台循环重试）。
- 400、413：内容本身不被接受，不重试。
- 403：被控端关闭了剪贴板开关、未授权或未在串流。本次连接停止同步（只记一次日志），菜单提示“被控端拒绝了剪贴板同步”；重新连接后再尝试。
- 不发起额外的重连；剪贴板失败不影响串流，也不改变“主动断开不自动重连”的规则。

## 开关

工具栏“鼠标与键盘”图标菜单中的“同步剪贴板”可勾选项：

- 按设备记忆（`QSettings` 的 `office/hosts/<sha256>/clipboard`），默认开启。
- 被控端未宣告 `OfficeClipboard=1`（旧版或原版 Sunshine）时置灰，悬停提示“被控端不支持剪贴板同步，请更新被控端”。
- 关闭后不再读写任何一端；重新开启时把两端当前内容都视为已同步（本地登记当前 `changeCount`，后台 GET 一次 baseline），之后的复制才会同步，打开开关本身不搬运内容。
- 分辨率确认框打开期间不可切换。

## 协议（引用被控端）

协议以被控端仓库 [sunshine-desk 的 office/CLIPBOARD.md](https://github.com/linrong123/sunshine-desk/blob/main/office/CLIPBOARD.md) 为准（功能合并前见其 `feat/clipboard` 分支；两端修改需同步）。主控端依赖的要点：

- 能力位：已配对 HTTPS `serverinfo` 的 `OfficeClipboard=1`；未宣告不调用。
- 认证：配对证书双向 TLS，走 `m_BaseUrlHttps`，不附 uniqueid 查询参数，不降级到 HTTP。
- `GET office/clipboard`：`root.sequence`、`hasText`（0/1）、`text`（base64 的 UTF-8）、`tooLarge`。
- `POST office/clipboard`：body 为原始 UTF-8 文本（`Content-Type: text/plain; charset=utf-8`），返回 `root.sequence`。
- XML `status_code` 随 HTTP 200 返回：400 非法/空、413 超限、403 拒绝、503 剪贴板被占用。

客户端解析（`app/office/clipboardresponse.*`）与其他办公接口同样严格：唯一根 `root` 且只有一个 `status_code`；拒绝 DTD/实体/命名空间、重复或带属性的字段、嵌套元素；`sequence` 只接受十进制数字且不超过 `uint64`；`hasText`/`tooLarge` 只接受 0/1；`text` 必须是标准带填充 base64、解码后是合法 UTF-8 且不超过 1 MiB；响应总长不超过 2 MiB。任一不符合按传输失败处理。未知叶子字段忽略。

## 代码位置

| 文件 | 职责 |
| --- | --- |
| `app/office/clipboardsync.*` | 平台无关决策：去重、重试、403、换行规范化 |
| `app/office/clipboardresponse.*` | 严格 XML 解析 |
| `app/office/localclipboard.h`、`clipboard_mac.mm`、`clipboard_stub.cpp` | Mac `NSPasteboard` 读写（`changeCount`、UTF-8 文本）；其他平台空实现 |
| `app/office/clipboardhooks.cpp` | 会话侧：后台请求队列、结果代次、焦点边沿、开关、最后一次拉取 |
| `app/office/sessionhooks.cpp` | `officeStartUi`/`officePollUi`/`officeStopUi`/`officeAction` 中的调用点 |
| `app/office/toolbar*` | “同步剪贴板”菜单项（`Action::Clipboard`、`Toolbar::setClipboard`） |
| `app/backend/nvhttp.*` | `requestOfficeClipboard`；`openConnection` 增加可选 POST body |

## 已知限制

- 只同步纯文本；Mac 上复制图片/文件时不推送，Windows 上是图片时不拉取。
- 不过滤密码管理器等标记为 concealed/transient 的剪贴板内容（与系统“通用剪贴板”的行为不同），关闭开关可避免。
- 被控端无推送通道，Windows 上的新复制要等 Mac 切走焦点（或主动断开）才会拉取；串流窗口一直在前台时 Mac 剪贴板不会变化。
- 重连（中断恢复、分辨率切换）时丢弃挂起的请求结果，正在进行的推送不会自动补发，下次获得焦点时会重新判断。
- 多个主控端同时连接同一被控端时，各自独立同步，最后写入者生效。
- 最后一次拉取最多让断开慢 1.5 秒；被控端无响应时同样受此上限约束。
