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
| `app/office/OfficeRecovery.qml` | finished → cleanup ready → timer → new session；取消/返回不丢失清理所有权 |
| `app/gui/AppView.qml` / `appmodel.*` | 仅当完整目录唯一 Desktop 才一键启动，不筛掉其他应用 |
| `app/gui/StreamSegue.qml` / `main.qml` | 恢复展示、取消、导航保护；非办公串流保留原路径 |
| `app/streaming/session.*` | 回调错误分类、主动与远端断开区分、worker 清理后才 ready、Desktop 不 quit host app |
| `app/streaming/input/input.h` | 鼠标模式切换接口，调用原有输入处理 |
| `app/main.cpp` / `Info.plist` / `app.pro` | 独立应用/偏好标识，模块注册；不覆盖原版 |
| `autoupdatechecker.cpp` | 禁用原版更新提示，避免安装错误发行包；办公版更新源尚未实现 |
| `office/macos` / CI | 独立构建/测试/打包；上游总入口只在官方仓库运行 |

## 更新步骤

1. 干净工作树创建维护分支，fetch upstream，再 merge 指定已审查的 tag。
2. 检查上表全部适配点。不要大段复制替换上游 Session；优先让新增功能留在 office 模块。
3. 核对配对认证、TLS 信任、取消与清理时序、SDL 输入生命周期、CLI 非办公行为。
4. 运行 `office/macos/test.sh`，完整构建，两端安装/锁屏恢复/分辨率/鼠标实测。
5. 更新基线、测试记录和限制。新增 workflow 要审查权限及发布目标，不能继承上游发布凭据或向上游提交。

## 协议扩展

Sunshine Office 在已配对 HTTPS `serverinfo` 宣告 `OfficeCursorSet=1`。客户端才会调用已认证 `office/cursor?visible=0|1`。请求设置目标值，不 toggle；重复请求不会反转。成功还需 XML `cursorVisible` 与目标一致。

这是视频光标合成开关，不改变 Windows 本机指针，也不是光标形状传输协议。多观看者共享服务端状态，最后设置生效。未知能力主机不尝试该扩展。光标请求只允许一条执行、一条最新待发，旧返回不覆盖新状态。

连接结束时，清理线程尽力恢复远端光标可见，然后才允许重连。断网或强制杀进程时无法保证恢复请求送达；多观看者的独立光标仍未实现。

切换到远端/相对模式前，先等待主机确认远端光标可见。请求等待或失败时保留本地指针；状态更新受同一代次锁保护，迟到响应不覆盖最新设置。

Sunshine 在解锁/控制台迁移之后，可能已接受 HTTPS 但采集器或 Desktop 尚未准备好，返回 503。仅对曾建立过串流的恢复链重试此状态，仍受统一预算约束；400/401/403/404/409 等请求、认证和占用错误不重试。
