# 0.3.0 连接中显示设置

## 操作

窗口顶部使用macOS原生工具栏，保留视频内容区域；小窗口把放不下的选项收进系统溢出菜单。全屏显示由macOS管理：进入独立空间（Spaces）全屏后工具栏和菜单栏自动隐藏，鼠标移到屏幕顶部才出现，移开后再收起；退出全屏恢复常驻。“全屏”按钮与溢出菜单项按窗口实际状态显示“全屏”或“退出全屏”。

- 远端分辨率：选择尺寸就弹出确认；确认才保存本机的每设备偏好并重连，取消不变。不注销Windows。工具栏尺寸表示当前协商的串流尺寸，实际Windows显示模式仍由服务端和驱动决定。
- Windows缩放：串流开始后读取真实的文字和图标比例，仅展示主机支持档位。选择后直接设置，成功读回才显示生效；不改变串流分辨率，不做本地zoom，不主动注销或重启。部分旧式Windows程序可能要重新打开才适应新DPI。
- 鼠标、设备列表和断开保持原有作用。工具栏只操作当前会话。下拉菜单只在当前选中项上打勾。
- 统计：工具栏右侧常驻中文摘要（“延迟 12 ms · 60 帧/秒 · 18.5 Mbps”，取不到的项省略；尚无数据时显示“统计读取中”），悬停显示完整中文详情；状态提示（光标、DPI）单独显示，不被摘要覆盖。“统计”按钮打开/关闭可拖动、可关闭的浮动统计面板（HUD NSPanel），每秒随解码统计刷新，按钮按下状态与面板一致；面板不成为key/main窗口，不抢走串流窗口的键盘焦点；全屏空间里同样可见，应用切到后台时隐藏，断开时随工具栏销毁。同一会话重连后面板保持打开。上游 Ctrl+Alt+Shift+S 视频叠加统计不变。

### 全屏实现说明

SDL2 的 `Cocoa_WindowListener` 在全屏（FULLSCREEN_DESKTOP 走 Spaces）时返回 `FullScreen|HideDock|HideMenuBar`，并在进入全屏/获得焦点时调用 `[NSMenu setMenuBarVisible:NO]`，工具栏因此一直隐藏。办公版不改 SDL 源码，只对已登记的办公会话窗口在运行时包装这三个委托方法（`class_replaceMethod`，先调用原实现）：把 `HideMenuBar` 换成 `AutoHideMenuBar`，补 `AutoHideDock` 和 `AutoHideToolbar`（AppKit 要求 AutoHideToolbar 搭配 FullScreen 与 AutoHideMenuBar，否则抛异常），并在原实现隐藏菜单栏后恢复 `setMenuBarVisible:YES` 交给系统自动隐藏。未登记的窗口（原版 Moonlight 会话、测试窗口）原样走 SDL 逻辑；退出全屏后系统恢复普通外观。工具栏已经处在全屏空间时创建（如重连），直接设置当前 presentationOptions。用户用绿色按钮切换后 SDL 标志可能过期，工具栏“全屏”按钮在原生全屏状态与 SDL 标志不一致时改用 `toggleFullScreen:` 退出。

确认窗口出现时释放远端按键并暂停键鼠转发，关闭时丢弃本地对话框积压事件后恢复；断开或销毁后的迟到确认不能重新启动会话。

## 两端协议与边界

新版Sunshine Desk通过已配对HTTPS `serverinfo` 声明 `OfficeDisplayScale=1`。初始查询在串流启动之后执行，避免读取自动分辨率调整之前的显示器。客户端使用同一配对证书验证通道，不回退HTTP。

`GET /office/display-scale` 不带query；`POST /office/display-scale?scale=150&displayToken=...` 空body。仅此扩展省略上游GameStream附加的uniqueid/uuid参数。令牌来自读取结果，绑定被控端捕获显示器和拓扑，不能用旧令牌误改另一块屏幕。

成功XML直接字段为 `scale`、`recommended`、`supportedScales`、`displayToken`。客户端严格解析档位、顺序、实际值、令牌与文档结构；错误、缺失或未知数据不会当成功。写请求失败时只补一次读取核实实际值，不重复写入；读取仍失败时禁用菜单并提示重连重试。原生菜单等待请求期间禁用，SDL视频线程不等待网络。

服务端采用Windows未公开的DisplayConfig DPI子类型，属于兼容性受限实现；不修改注册表、不注销用户、不安装新驱动。非Windows、旧服务端、自定义DPI、无控制台访问、驱动不支持或显示器有歧义时不提供可用档位。多观看者仍共享同一个Windows桌面DPI，不是每客户端独立比例。

## 维护和验收

- `app/office/toolbar_mac.mm`：原生工具栏、异步确认、统计摘要与浮窗、全屏自动隐藏（SDL窗口委托运行时包装）。
- `app/office/videostats.*`：解码统计样本、中文摘要/详情格式化、解码线程到主线程的最新样本通道；`streaming/video/ffmpeg.cpp` 仅在办公会话中发布样本。
- `app/office/displayscale.*`：纯XML校验；`officestate.*`：单线程网络队列与读回状态。
- `backend/nvhttp.*`：复用TLS校验的小型GET/POST适配；默认上游请求行为不变。
- `sessionhooks.cpp`、`streaming/session.*`：初始查询、输入暂停、清理时等待请求结束。

`bash office/macos/test.sh` 包括不显示窗口的原生交互检查（下拉勾选、全屏文字、presentationOptions组合、统计摘要与浮窗）、统计格式化与通道测试、严格XML测试及原有工作台/多进程/恢复测试。真实两端验收还需检查Windows设置页实际比例、文本尺寸变化、分辨率确认和取消、窄窗口溢出菜单、全屏（工具栏/菜单栏自动隐藏、鼠标移到顶部出现、退出后恢复、绿色按钮与工具栏按钮交替使用）、统计摘要与浮窗数值、浮窗打开时键盘鼠标仍转发远端、重连和多窗口隔离。测试通过不等于实际主机已更新或DPI已生效。
