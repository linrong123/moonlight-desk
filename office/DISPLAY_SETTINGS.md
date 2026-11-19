# 0.3.0 连接中显示设置

## 操作

窗口顶部使用macOS原生工具栏，保留视频内容区域；小窗口把放不下的选项收进系统溢出菜单。全屏显示由macOS管理，移到顶部显示窗口工具栏。

- 远端分辨率：选择尺寸就弹出确认；确认才保存本机的每设备偏好并重连，取消不变。不注销Windows。工具栏尺寸表示当前协商的串流尺寸，实际Windows显示模式仍由服务端和驱动决定。
- Windows缩放：串流开始后读取真实的文字和图标比例，仅展示主机支持档位。选择后直接设置，成功读回才显示生效；不改变串流分辨率，不做本地zoom，不主动注销或重启。部分旧式Windows程序可能要重新打开才适应新DPI。
- 鼠标、统计、设备列表和断开保持原有作用。工具栏只操作当前会话。

确认窗口出现时释放远端按键并暂停键鼠转发，关闭时丢弃本地对话框积压事件后恢复；断开或销毁后的迟到确认不能重新启动会话。

## 两端协议与边界

新版Sunshine Desk通过已配对HTTPS `serverinfo` 声明 `OfficeDisplayScale=1`。初始查询在串流启动之后执行，避免读取自动分辨率调整之前的显示器。客户端使用同一配对证书验证通道，不回退HTTP。

`GET /office/display-scale` 不带query；`POST /office/display-scale?scale=150&displayToken=...` 空body。仅此扩展省略上游GameStream附加的uniqueid/uuid参数。令牌来自读取结果，绑定被控端捕获显示器和拓扑，不能用旧令牌误改另一块屏幕。

成功XML直接字段为 `scale`、`recommended`、`supportedScales`、`displayToken`。客户端严格解析档位、顺序、实际值、令牌与文档结构；错误、缺失或未知数据不会当成功。写请求失败时只补一次读取核实实际值，不重复写入；读取仍失败时禁用菜单并提示重连重试。原生菜单等待请求期间禁用，SDL视频线程不等待网络。

服务端采用Windows未公开的DisplayConfig DPI子类型，属于兼容性受限实现；不修改注册表、不注销用户、不安装新驱动。非Windows、旧服务端、自定义DPI、无控制台访问、驱动不支持或显示器有歧义时不提供可用档位。多观看者仍共享同一个Windows桌面DPI，不是每客户端独立比例。

## 维护和验收

- `app/office/toolbar_mac.mm`：原生工具栏与异步确认。
- `app/office/displayscale.*`：纯XML校验；`officestate.*`：单线程网络队列与读回状态。
- `backend/nvhttp.*`：复用TLS校验的小型GET/POST适配；默认上游请求行为不变。
- `sessionhooks.cpp`、`streaming/session.*`：初始查询、输入暂停、清理时等待请求结束。

`bash office/macos/test.sh` 包括不显示窗口的原生交互检查、严格XML测试及原有工作台/多进程/恢复测试。真实两端验收还需检查Windows设置页实际比例、文本尺寸变化、分辨率确认和取消、窄窗口溢出菜单、全屏、重连和多窗口隔离。测试通过不等于实际主机已更新或DPI已生效。
