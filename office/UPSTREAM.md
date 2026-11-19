# 上游合并与架构

- 上游：`moonlight-stream/moonlight-qt`。
- 初始基线：`v6.2.0` / `de2467e433821664cdd2224aad8c89a625be1ad9`。
- 完整 Git 历史及子模块保留。`upstream` 跟踪官方，`origin` 指向办公版。公开 main 不重写历史。

| 位置 | 职责与合并检查 |
| --- | --- |
| `app/office/recoverypolicy.h` | 有界重连策略，使用单调时钟；主动退出不可恢复 |
| `app/office/officestate.*` | 每主机偏好、已认证 serverinfo、幂等光标请求及有界队列；不能 HTTP 降级 |
| `app/office/sessionhooks.cpp` | Session 小适配点，鼠标与分辨率应用、恢复实例创建 |
| `app/office/sessionpreferences.cpp` | 私有设置快照；新增上游非 Q_PROPERTY 字段需人工检查 |
| `app/office/toolbar*` | Mac 原生工具栏；串流运行于 SDL 循环，不能依赖暂停中的 Qt Quick UI |
| `app/office/displayscale.*` / `backend/nvhttp.*` | Windows DPI严格解析和配对HTTPS GET/POST；仅扩展省略GameStream身份query；无HTTP降级 |
| `app/office/devicename.*` / `backend/nvpairingmanager.cpp` | 配对 `devicename` 取本机电脑名称（mac 用 SystemConfiguration），清洗、截断到 64 字节 UTF-8 并 URL 编码；上游只把五处 `devicename=roth` 换成同一个参数 |
| `app/office/connectconfirm.*` / `backend/nvhttp.*` | 每次连接确认：`office/connect-request` 严格 XML 解析（唯一 `state`、合法枚举）、start→status 1 秒轮询、65 秒客户端期限、取消/超时/传输异常撤回；走配对 HTTPS GET，无 HTTP 降级 |
| `app/office/sessionhooks.cpp` / `streaming/session.*` | `startConnectionAsync` 在 launch/resume 前调用 `officeAwaitApproval`；launch/resume 返回 403 `Host approval required` 视为拒绝；拒绝/超时/失败置不可恢复，不自动重试；新增信号 `officeApprovalWaiting` |
| `app/office/ApprovalWaiting.qml` / `gui/StreamSegue.qml` | 串流准备页显示等待确认与“取消”，取消复用 `cancelDeskClose()`；等待时隐藏“取消恢复” |
| `app/office/OfficeRecovery.qml` | finished → cleanup ready → timer → new session；取消/返回不丢失清理所有权 |
| `app/office/DeskHome.qml` / `DeskView.qml` | 设备工作台；真实 ComputerModel 数据与操作，不放未实现功能入口 |
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
7. 原生窗口工具栏不能修改视频contentView或覆盖其内容；确认sheet异步显示，销毁后不能回调Session。SDL确认期间暂停键鼠转发，保留窗口/网络事件处理。DPI队列在LiStopConnection之前清理，避免显示器恢复过程中发送旧请求。

## 协议扩展

完整契约见 [CONNECTION.md](CONNECTION.md)。每次连接确认：已配对 HTTPS `serverinfo` 宣告 `OfficeConnectConfirm=1` 时，客户端在 launch/resume 前调用 `office/connect-request?action=start`，`pending` 时每 1 秒 `action=status`，最多 65 秒；`approved`/`not_required` 继续，`denied`/`expired` 终止，用户取消或客户端超时发送 `action=cancel`。XML 必须恰好一个 `state` 且为已知枚举，否则按失败处理并撤回；未知叶子字段忽略以便服务端扩展诊断信息。launch/resume 以 XML `status_code=403`、`status_message="Host approval required"` 拒绝时视为被拒。自动恢复同样先 start，由服务端 120 秒宽限直接返回 `approved`。未宣告能力的主机不调用。

Sunshine Desk 在已配对 HTTPS `serverinfo` 宣告 `OfficeCursorSet=1`。客户端才会调用已认证 `office/cursor?visible=0|1`。请求设置目标值，不 toggle；重复请求不会反转。成功还需 XML `cursorVisible` 与目标一致。

这是视频光标合成开关，不改变 Windows 本机指针，也不是光标形状传输协议。多观看者共享服务端状态，最后设置生效。未知能力主机不尝试该扩展。光标请求只允许一条执行、一条最新待发，旧返回不覆盖新状态。

连接结束时，清理线程尽力恢复远端光标可见，然后才允许重连。断网或强制杀进程时无法保证恢复请求送达；多观看者的独立光标仍未实现。

切换到远端/相对模式前，先等待主机确认远端光标可见。请求等待或失败时保留本地指针；状态更新受同一代次锁保护，迟到响应不覆盖最新设置。

Sunshine 在解锁/控制台迁移之后，可能已接受 HTTPS 但采集器或 Desktop 尚未准备好，返回 503。仅对曾建立过串流的恢复链重试此状态，仍受统一预算约束；400/401/403/404/409 等请求、认证和占用错误不重试。
