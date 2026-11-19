# Moonlight Office 初版

面向办公的 Moonlight 定制客户端，首个目标平台为 Apple Silicon Mac。配套 [Sunshine Office](https://github.com/linrong123/sunshine-office) 在被控端只提供 Desktop，不提供新增应用入口。本客户端没有按名称隐藏 Steam，也没有复刻传输、解码或配对协议。

## 当前功能

- 已配对且仅提供 Desktop 的主机，点击主机后直接进入桌面。首次连接仍走原有 PIN 配对。
- 已建立桌面串流发生连接中断后，旧连接清理完再退避重连。主动断开、认证/配对失败、受保护内容或编码转换错误不循环重试；恢复可取消。
- Mac 串流窗口中的原生办公工具栏：本地/远端/相对鼠标，720p/1080p/1200p/1440p/1600p/4K，应用、全屏、统计和断开。
- 分辨率应用会短暂断开并恢复串流，不注销 Windows；服务端和显示器必须支持所选模式。请求的串流尺寸不等于已经验证的 Windows 物理显示模式。
- 鼠标与分辨率按主机记忆；每次串流使用独立设置副本，不改变其他电脑的全局偏好。
- 办公本地光标通过配对后的 HTTPS 请求让 Sunshine Office 隐藏视频里的远端光标。原版 Sunshine 无此能力时保留远端光标，并显示说明。

恢复调度最多 10 次、约一分钟的退避预算，网络握手和清理本身也需要时间。首次连接失败不会无限自动重试。Windows 密码仍由 Windows 锁屏界面处理；本软件不保存、自动输入或绕过 Windows 登录密码。

## 构建与启动

需要 macOS、Xcode 命令行工具、Python 3 和 Qt 6.11.2 macOS SDK。所有额外依赖可装在项目内：

```bash
git clone --recursive https://github.com/linrong123/moonlight-office.git
cd moonlight-office
python3 -m venv .work/py
.work/py/bin/pip install aqtinstall==3.3.0
.work/py/bin/aqt install-qt mac desktop 6.11.2 clang_64 -O .work/Qt -m qtshadertools qtimageformats
bash office/macos/test.sh
bash office/macos/build.sh
open dist/MoonlightOffice.app
```

已有 Qt 时设置 `OFFICE_QT_BIN` 为对应 `bin` 目录。脚本沿用上游依赖下载器，生成 ARM64 应用和 ZIP；本地临时构建目录保留在 `build/`。这是本地签名的开发版，尚无 Developer ID 签名/Apple 公证。

办公版拥有独立应用标识、配对身份及偏好，与原版 Moonlight 分开。首次需重新添加主机并经本人确认 PIN，不导入原版配对私钥。构建脚本不会替换 `/Applications/Moonlight.app`。

连接后可直接操作工具栏。相对鼠标模式会捕获指针，使用 Moonlight 原有 `Control + Option + Shift + Z` 释放后再操作工具栏。工具栏只作用于当前串流；全局画质、码率、声音等高级选项仍在连接前的设置中。

## 交付范围与验收

本轮保留上游编码/传输性能，不宣称降低跨洋基础延迟，不自动安装虚拟显示驱动，也不包含公网中转服务。主机发现、首次账户设置和配对仍需用户完成，尚不是最终零配置安装体验。

查看 [验证记录](VALIDATION.md) 区分已通过的本地检查和待完成的双端实测。[上游维护说明](UPSTREAM.md) 记录所有适配位置。保留上游 GPLv3 许可及依赖许可；这是独立社区定制项目，不是 Moonlight/Sunshine 官方发行版。
