# 上游合并与架构

- 上游：`moonlight-stream/moonlight-qt`。
- 初始基线：`v6.2.0` / `de2467e433821664cdd2224aad8c89a625be1ad9`。
- 完整 Git 历史及子模块保留。`upstream` 跟踪官方，`origin` 指向办公版。公开 main 不重写历史。

| 位置 | 职责与合并检查 |
| --- | --- |
| `app/office/recoverypolicy.h` | 有界重连策略，使用单调时钟；主动退出不可恢复 |
| `app/office/officestate.*` | 每主机偏好、已认证 serverinfo、幂等光标请求及有界队列；不能 HTTP 降级 |
| `app/office/sessionhooks.cpp` | Session 小适配点，鼠标与分辨率应用、恢复实例创建；工具栏启动时传入主机名（`NvComputer::name`）并同步输入暂停状态 |
| `app/office/sessionpreferences.cpp` | 私有设置快照；新增上游非 Q_PROPERTY 字段需人工检查 |
| `app/office/toolbar*` | Mac 原生工具栏（左侧连接信息胶囊 NSButton、居中图标组：显示/鼠标与键盘为 `NSMenuToolbarItem`，全屏/设备列表为图标按钮，macOS 13 起 `centeredItemIdentifiers`；右侧红色断开；`Toolbar` 接口含 `setDeviceName`/`setInputPaused`，`office::Action` 不变）；串流运行于 SDL 循环，不能依赖暂停中的 Qt Quick UI。全屏自动隐藏在运行时包装 SDL 窗口 delegate 的实际类（`object_getClass(window.delegate)`，当前为 sdl2-compat/SDL3 的 `SDL3Cocoa_WindowListener`，会话日志 `Office toolbar: fullscreen auto-hide ...` 记录类名与已包装方法）的 `window:willUseFullScreenPresentationOptions:`、`windowDidEnterFullScreen:`、`windowDidBecomeKey:`（只作用于已登记的办公窗口，先调原实现）；升级 SDL 时须复核这三个方法仍存在且行为未变（SDL3 `src/video/cocoa/SDL_cocoawindow.m`），并看会话日志确认不是 “not installed” |
| `app/office/videostats.*` | 解码统计样本、中文摘要/详情、解码线程→主线程最新样本通道（互斥 + 原子标志）；`copyVideoStats` 按 `VIDEO_STATS` 字段名复制，上游增删字段时同步 |
| `app/streaming/video/ffmpeg.cpp` | 办公统计适配点：仅 `Session::get()->officeEnabled()` 时在统计窗口滚动处发布样本（双窗口合计、解码尺寸、编码、`m_BwTracker` 平均/峰值码率）；上游叠加统计分支不变 |
| `app/office/displayscale.*` / `backend/nvhttp.*` | Windows DPI严格解析和配对HTTPS GET/POST；仅扩展省略GameStream身份query；无HTTP降级 |
| `app/office/devicename.*` / `backend/nvpairingmanager.cpp` | 配对 `devicename` 取本机电脑名称（mac 用 SystemConfiguration），清洗、截断到 64 字节 UTF-8 并 URL 编码；上游只把五处 `devicename=roth` 换成同一个参数 |
| `app/office/connectconfirm.*` / `backend/nvhttp.*` | 每次连接确认：`office/connect-request` 严格 XML 解析（唯一 `state`、合法枚举）、start→status 1 秒轮询、65 秒客户端期限、取消/超时/传输异常撤回；走配对 HTTPS GET，无 HTTP 降级 |
| `app/office/sessionhooks.cpp` / `streaming/session.*` | `startConnectionAsync` 在 launch/resume 前调用 `officeAwaitApproval`；批准后向工作台报告 `starting`；launch/resume 返回 403 `Host approval required` 时尽力发送 `action=cancel` 撤回服务端自动弹出的确认窗，报告 `approval_required`，提示“被控端需要本机确认，请重新连接”；拒绝/超时/失败置不可恢复，不自动重试；新增信号 `officeApprovalWaiting` |
| `app/office/ApprovalWaiting.qml` / `gui/StreamSegue.qml` | 串流准备页显示等待确认与“取消”，取消复用 `cancelDeskClose()`；等待时隐藏“取消恢复” |
| `app/office/OfficeRecovery.qml` | finished → cleanup ready → timer → new session；取消/返回不丢失清理所有权 |
| `app/office/DeskHome.qml` / `DeskView.qml` / `DeskConnector.qml` / `desklogic.js` | 远控式工作台：地址栏连接（已有地址直连，新地址添加→配对→进入）、设备卡片与“⋯”菜单；`DeskHome`/`DeskConnector`/`desklogic.js` 不依赖 C++ 模块，便于 QML 测试；流程每步只提示一次失败，不自动重试；配对窗口“取消”仅本地放弃（上游无中止配对接口），同一时间只允许一个添加和一个配对请求，晚到结果忽略；IPv6 按 RFC 5952 规范化匹配；真实 ComputerModel 数据与操作，不放未实现功能入口 |
| `app/office/DeskSettings.qml` / `DeskButton.qml` / `DeskDialog.qml` / `DeskProgress.qml` / `deskstyle.js` | 简化设置页（只读写注入的 `StreamingPreferences`，自动码率沿用上游 `getDefaultBitrate` 规则）、统一按钮/对话框/过渡页与配色；新增 `StreamingPreferences` 字段不会自动出现，需要时在此补 |
| `app/gui/computermodel.*` | 新增 `AddressRole`/`AddressesRole`（`address`、`addresses`），供工作台按地址查找已有设备；只读，不改上游角色顺序 |
| `app/main.cpp`（`deskSessionMode`） | 在 `deskManagerMode` 旁注册 `deskSessionMode`（`SessionBridge::isSessionProcess()`），QML 据此在会话进程中也启用办公界面 |
| `app/gui/main.qml`（办公界面） | `deskUi = deskManagerMode \|\| deskSessionMode`；办公模式浅色主题、隐藏原版顶部工具栏（仅原版 `SettingsView`“高级设置”页显示，命令式改 `toolBar.visible` 的旧代码由 `onVisibleChanged` 守卫拦下）；齿轮打开 `DeskSettings`（已打开则返回该页）；退出走 `DeskDialog`（`requestDeskQuit()` 按 `deskUi` 选择：管理进程“退出 Moonlight Desk”并 `DeskSessions.stopAll()`，会话进程“断开远程桌面”只关闭自己）；上游 `quitConfirmationDialog` 恢复原样、`addPcDialog` 保留，仅供非办公路径；Esc/Back 在根页触发退出确认 |
| `app/gui/NavigableMessageDialog.qml` / `ErrorMessageDialog.qml` | 办公模式下隐藏图标、按钮改中文（确定/取消/帮助），错误框不显示“帮助”按钮；非办公路径不变 |
| `app/gui/StreamSegue.qml` / `CliStartStreamSegue.qml` / `QuitSegue.qml` | 办公模式叠加 `DeskProgress` 过渡页（中文阶段文字原样显示，上游英文阶段统一为“正在连接远程桌面…”/“正在退出…”），原 Row 置透明但保留，状态与取消逻辑不变；`StreamSegue` 的“取消恢复”改用 `DeskButton`；`CliStartStreamSegue` 的“关闭正在运行的应用”提示改中文 |
| `app/qml.qrc` | 登记新增的 `office/*.qml` 与 `desklogic.js`、`deskstyle.js` |
| `app/office/desksessions.*` / `sessionbridge.*` | 每主机独立进程；用户权限本地 IPC；SDL 阻塞 Qt 时仍能取消和回传状态；状态白名单含 `approval`/`denied`/`expired`，工作台据此显示等待确认并可“断开 / 取消” |
| `app/backend/computermanager.*` / `gui/computermodel.*` | 仅管理进程写设备列表；启动前有界持久化等待；UUID role/get、初始化模型重置信号 |
| `app/gui/CliStartStreamSegue.qml` | 复用原有 CLI 发现、配对验证、Desktop 启动；接入状态和取消 |
| `app/gui/AppView.qml` / `appmodel.*` | 保留旧界面兼容路径；工作台独立请求服务端 Desktop，不过滤服务器应用目录 |
| `app/gui/StreamSegue.qml` / `main.qml` | 恢复展示、取消、导航保护；非办公串流保留原路径 |
| `app/streaming/session.*` | 回调错误分类、主动与远端断开区分、worker 清理后才 ready、Desktop 不 quit host app |
| `app/streaming/input/input.h` | 鼠标模式切换接口，调用原有输入处理 |
| `app/streaming/input/mouse.cpp` | 记录真正发给远端的鼠标按键；本地确认框只释放已按下的键，避免发送多余释放事件 |
| `app/main.cpp` / `Info.plist` / `app.pro` | 独立应用/偏好标识，模块注册；不覆盖原版 |
| `autoupdatechecker.cpp` | 禁用原版更新提示，避免安装错误发行包；办公版更新源尚未实现 |
| `office/macos` / CI | 独立构建/测试/打包；上游总入口只在官方仓库运行 |
| `office/ci/upstream-drift.sh` / `.github/workflows/office-upstream-drift.yml` | 每周一及手动触发：取官方最新正式版 tag（`git ls-remote --tags --sort=-v:refname`，仅 `vX.Y.Z`），`git merge-tree --write-tree` 试合并当前分支，冲突数与文件、自基线以来上游新增的 workflow 写入运行摘要；有冲突则任务失败。只读权限，不推送、不建分支；合并上游后同步脚本内 `BASELINE_TAG`/`BASELINE_SHA` |

## 更新步骤

1. 先看最近一次 “Desk upstream drift” 运行摘要（或本地 `bash office/ci/upstream-drift.sh`）了解冲突文件和上游新增 workflow。干净工作树创建维护分支，fetch upstream，再 merge 指定已审查的 tag。
2. 检查上表全部适配点。不要大段复制替换上游 Session；优先让新增功能留在 office 模块。
3. 核对配对认证、TLS 信任、取消与清理时序、SDL 输入生命周期、CLI 非办公行为。
4. 运行 `office/macos/test.sh`，完整构建，两端安装/锁屏恢复/分辨率/鼠标实测。
5. 更新基线、测试记录和限制。新增 workflow 要审查权限及发布目标，不能继承上游发布凭据或向上游提交。
6. 核查 `Session::s_ActiveSession`、底层 `Connection.c` 全局状态及 CLI 接口。多连接依靠进程隔离，不删除上游单连接信号量。验证每窗口焦点/释放按键、关闭一连接不影响另一连接、管理进程退出等待清理，以及会话进程不回写旧设备列表。
7. 原生窗口工具栏不能修改视频contentView或覆盖其内容；确认sheet异步显示，销毁后不能回调Session。SDL确认期间暂停键鼠转发，保留窗口/网络事件处理。DPI队列在LiStopConnection之前清理，避免显示器恢复过程中发送旧请求。统计浮窗不能成为key/main窗口（`officePollUi` 依赖 `SDL_GetKeyboardFocus() == m_Window` 决定是否恢复捕获），随工具栏销毁。

## 协议扩展

完整契约见 [CONNECTION.md](CONNECTION.md)。每次连接确认：已配对 HTTPS `serverinfo` 宣告 `OfficeConnectConfirm=1` 时，客户端在 launch/resume 前调用 `office/connect-request?action=start`，`pending` 时每 1 秒 `action=status`，最多 65 秒；`approved`/`not_required` 继续，`denied`/`expired` 终止，用户取消或客户端超时发送 `action=cancel`。XML 必须恰好一个 `state` 且为已知枚举，否则按失败处理并撤回；未知叶子字段忽略以便服务端扩展诊断信息。launch/resume 以 XML `status_code=403`、`status_message="Host approval required"` 退回时不重试：服务端会同时自动发起一次确认，客户端随即尽力发送一次 `action=cancel` 撤回该弹窗，并提示“被控端需要本机确认，请重新连接”（不称“拒绝”）。服务端在 denied/expired 后 30 秒内对同一证书的 start 直接返回原结果，客户端按普通 denied/expired 处理，无需额外逻辑。自动恢复同样先 start，由服务端 120 秒宽限直接返回 `approved`。未宣告能力的主机不调用。

Sunshine Desk 在已配对 HTTPS `serverinfo` 宣告 `OfficeCursorSet=1`。客户端才会调用已认证 `office/cursor?visible=0|1`。请求设置目标值，不 toggle；重复请求不会反转。成功还需 XML `cursorVisible` 与目标一致。

这是视频光标合成开关，不改变 Windows 本机指针，也不是光标形状传输协议。多观看者共享服务端状态，最后设置生效。未知能力主机不尝试该扩展。光标请求只允许一条执行、一条最新待发，旧返回不覆盖新状态。

连接结束时，清理线程尽力恢复远端光标可见，然后才允许重连。断网或强制杀进程时无法保证恢复请求送达；多观看者的独立光标仍未实现。

切换到远端/相对模式前，先等待主机确认远端光标可见。请求等待或失败时保留本地指针；状态更新受同一代次锁保护，迟到响应不覆盖最新设置。

Sunshine 在解锁/控制台迁移之后，可能已接受 HTTPS 但采集器或 Desktop 尚未准备好，返回 503。仅对曾建立过串流的恢复链重试此状态，仍受统一预算约束；400/401/403/404/409 等请求、认证和占用错误不重试。
