# Moonlight Desk 初版

面向办公的 Moonlight 定制客户端，首个目标平台为 Apple Silicon Mac。配套 [Sunshine Desk](https://github.com/linrong123/sunshine-desk) 在被控端只提供 Desktop，不提供新增应用入口。本客户端没有按名称隐藏 Steam，也没有复刻传输、解码或配对协议。

## 当前功能

- 中文工作台：左侧设备列表与搜索，右侧设备状态、进入桌面、配对、唤醒和重命名。选择设备不会立即连接；点击“进入桌面”启动主机提供的 Desktop。首次连接仍走原有 PIN 配对。
- 配对时向被控端发送本机真实名称（Mac 的“电脑名称”，去除控制字符、最长 64 字节 UTF-8，取不到时为 `Moonlight Desk`），便于被控端识别是哪台设备。配对窗口提示在被控电脑弹出的窗口中输入验证码；旧版或原版 Sunshine 不弹窗时，仍在其网页管理后台的 PIN 页面输入。协议见[连接与授权契约](CONNECTION.md)。
- 每次连接确认：被控端在已配对 HTTPS `serverinfo` 宣告 `OfficeConnectConfirm=1` 时，启动或恢复 Desktop 前先请求被控端用户允许。等待期间串流窗口与工作台都显示“正在等待被控端确认…”，可点“取消”撤回请求；被控端拒绝显示“被控端拒绝了连接”，60 秒未处理显示“被控端未在 60 秒内确认”。拒绝、超时和启动被拒（403）都不自动重试；未宣告该能力的主机保持原流程。
- 一台 Mac 可启动多台电脑的独立桌面窗口。主界面保持可用，重复打开同一设备会显示已有窗口；连接中的工具栏可点“设备”返回工作台。关闭管理窗口只隐藏，显式退出会先断开各会话。多进程隔离已通过本地测试，多台真实主机同时串流仍待验收。
- 已建立桌面串流发生连接中断后，旧连接清理完再退避重连。主动断开、认证/配对失败、受保护内容或编码转换错误不循环重试；恢复可取消。
- Mac 串流窗口顶部的原生工具栏：本地/远端/相对鼠标、远端分辨率、Windows文字和图标缩放、全屏、统计和断开。窗口模式占用独立顶部区域，不再悬浮遮挡远端内容；窄窗口使用系统溢出菜单。
- 选择新分辨率立即出现确认框，确认后短暂重连，不再需要“应用”按钮。取消保留原值，不注销 Windows；服务端和显示器必须支持所选模式。请求的串流尺寸不等于已经验证的 Windows 物理显示模式。
- Windows缩放从新版 Sunshine Desk 读取当前值和支持档位（例如125%、150%、200%），选择后即时请求修改并核对实际值，不重连。它改变Windows系统文字和图标大小，并非Mac画面放大。旧版主机、驱动不支持、目标显示器不明确或自定义DPI时禁用并说明原因。详见[显示设置](DISPLAY_SETTINGS.md)。
- 鼠标与分辨率按主机记忆；每次串流使用独立设置副本，不改变其他电脑的全局偏好。
- 办公本地光标通过配对后的 HTTPS 请求让 Sunshine Desk 隐藏视频里的远端光标。原版 Sunshine 无此能力时保留远端光标，并显示说明。

恢复调度最多 10 次、约一分钟的退避预算，网络握手和清理本身也需要时间。首次连接失败不会无限自动重试。Windows 密码仍由 Windows 锁屏界面处理；本软件不保存、自动输入或绕过 Windows 登录密码。

## 构建与启动

需要 macOS、Xcode 命令行工具、Python 3 和 Qt 6.11.2 macOS SDK。所有额外依赖可装在项目内：

```bash
git clone --recursive https://github.com/linrong123/moonlight-desk.git
cd moonlight-desk
python3 -m venv .work/py
.work/py/bin/pip install aqtinstall==3.3.0
.work/py/bin/aqt install-qt mac desktop 6.11.2 clang_64 -O .work/Qt -m qtshadertools qtimageformats
bash office/macos/test.sh
bash office/macos/build.sh
open dist/MoonlightDesk.app
```

已有 Qt 时设置 `OFFICE_QT_BIN` 为对应 `bin` 目录。脚本沿用上游依赖下载器，生成 ARM64 应用和 ZIP；本地临时构建目录保留在 `build/`。这是本地签名的开发版，尚无 Developer ID 签名/Apple 公证。

办公版拥有独立应用标识、配对身份及偏好，与原版 Moonlight 分开。首次需重新添加主机并经本人确认 PIN，不导入原版配对私钥。构建脚本不会替换 `/Applications/Moonlight.app`。

项目现名为 Moonlight Desk，配套服务端为 Sunshine Desk。为保留既有设置，早期 `MoonlightOffice` 的应用标识、设置目录和内部协议名继续沿用；`office/` 源码目录也保留，避免仅为改名扩大上游合并差异。新的应用包与 ZIP 使用 `MoonlightDesk` 名称。

连接后可直接操作工具栏。相对鼠标模式会捕获指针，使用 Moonlight 原有 `Control + Option + Shift + Z` 释放后再操作工具栏。工具栏只作用于当前串流；工作台中的全局画质、码率、声音设置用于后续新建的会话，不修改已经打开的其他桌面。

测试新版本时可使用 `OFFICE_OUTPUT_DIR="$PWD/dist/desk-multi" bash office/macos/build.sh`，再自行打开该目录中的应用。脚本拒绝替换仍在运行的目标应用包。开发时保留旧连接不动，只构建新包；同一设备请先结束旧版本连接再使用新版本进入。

## 交付范围与验收

本轮保留上游编码/传输性能，不宣称降低跨洋基础延迟，不自动安装虚拟显示驱动，也不包含公网中转服务。主机发现、首次账户设置和配对仍需用户完成，尚不是最终零配置安装体验。

查看 [验证记录](VALIDATION.md) 区分已通过的本地检查和待完成的双端实测。[上游维护说明](UPSTREAM.md) 记录所有适配位置。保留上游 GPLv3 许可及依赖许可；这是独立社区定制项目，不是 Moonlight/Sunshine 官方发行版。

[多窗口设计与验收](MULTI_SESSION.md) 说明进程隔离、连接退出和配置保存的边界。

[连接与授权契约](CONNECTION.md) 定义设备名、配对弹窗和每次连接确认的客户端/服务端协议；决策见 [ADR 0001 直连 IP 与授权](adr/0001-direct-ip-authorization.md)，后续计划见[路线图](ROADMAP.md)。

[第三方许可与源码出处](THIRD_PARTY.md) 随包保存；`Contents/Resources/OfficeSource/SOURCE.json` 给出确切源码提交。当前是开发版，SDK 间接组件的精确来源映射仍有待补项，未制作正式二进制发行版。
