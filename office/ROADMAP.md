# 路线图

Moonlight Desk（主控端）与 [Sunshine Desk](https://github.com/linrong123/sunshine-desk)（被控端）的功能级里程碑。一项一行，完成时勾选并附提交。

## M0 上游合并卫生

- [x] Sunshine Desk 收缩上游文件差异并合并到上游最新 tag（sunshine-desk b82153e5，v2026.1118.30014）
- [x] 两端每周自动对上游最新 tag 做合并试算并报告冲突（moonlight-desk a8dfb136，sunshine-desk 204dc568）
- [ ] 0.3.0 遗留实机验收：Windows 缩放写入、分辨率切换、全屏工具栏、两台主机同时串流

## M1 直连与授权（[设计](CONNECTION.md)）

代码与 CI 已完成，双端实机验收待做（见两端 `office/VALIDATION.md`）。

- [x] 主控端发送真实设备名，配对界面提示在被控端弹窗输入验证码（moonlight-desk 7ab2131a）
- [x] 被控端原生授权弹窗（输入 4 位验证码）（sunshine-desk bf375400）
- [x] 被控端托盘管理已授权设备（禁用/删除立即断开）（sunshine-desk bf375400）
- [x] 可选「每次连接需本机确认」及主控端等待确认界面（moonlight-desk 7ab2131a，sunshine-desk bf375400）
- [x] 被控端默认强制串流加密（sunshine-desk bf375400）

## M1.5 界面对齐主流远控

代码与 CI 已完成，实机外观与交互验收待做（见两端 `office/VALIDATION.md`）。

- [x] 主控端远控式工作台：输入 IP/域名一键添加、配对、连接，设备卡片与简化设置页，原版设置收进「高级设置」（moonlight-desk bc39565a）
- [x] 被控端原生主窗口：托盘左键打开，显示本机地址、设备名称、已授权设备与确认开关，日常使用无需网页（sunshine-desk 1e5a843a）

## M2 被控端可独立安装

- [ ] 独立安装包身份、服务名与配置目录，可与官方 Sunshine 共存
- [ ] 首次启动无需网页建立管理员账户
- [ ] 被控端界面（托盘、授权弹窗、主窗口）在每个登录会话（含远程桌面）中可见可操作，不再只在控制台会话
- [ ] 升级安装不删除已有防火墙规则
- [ ] 安装包签名

## M3 主控端扩展

- [ ] Windows 主控端（Windows 原生工具栏）
- [x] 文本剪贴板同步（客户端 26069d62，被控端 71236fc1，2026-11-20 实机验收）
- [ ] 密码类剪贴板内容在 Windows 端不进入剪贴板历史与云剪贴板（主控端标记 concealed，被控端附加 `ExcludeClipboardContentFromMonitorProcessing`）
- [ ] 文件传输
- [ ] 滚轮速度设置（慢 / 中 / 标准，默认中；解决普通鼠标滚轮每格滚动过多）

## M4 远期

- [ ] 用户自建中转（连接路线 relay）
- [ ] 账号同步设备列表
- [ ] 手机端评估
