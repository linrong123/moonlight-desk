# 应用图标（Moonlight Desk）

## 背景与目标

办公版不再使用上游 Moonlight 的月亮图标，换成原创矢量图标，与配套的 Sunshine Desk 共用同一套“显示器 + 指针/信号”造型，一眼可区分客户端（蓝紫）与被控端（青绿）。

## 设计

- 轮廓：圆角方形底板（824 × 824，位于 1024 画布 (100, 100)，圆角 185），中间是白色显示器（短颈、宽底座）。
- 客户端：显示器右下方一个白色指针（表示“控制”），指针外沿用底板渐变描边，与显示器自然分开。
- 被控端（Sunshine Desk 使用，同一套源文件）：显示器右上两道四分之一圆弧信号带（表示“共享”）。
- 无文字、无天体图案，没有使用任何上游或第三方美术资源。

| 用途 | 颜色 |
| --- | --- |
| 客户端渐变（左上到右下） | `#326BEA` → `#4332A9` |
| 被控端渐变 | `#14A9AD` → `#117D57` |
| 托盘主色 / 描边 | `#14A9AD` / `#075761` |
| 播放 / 暂停 / 锁定徽标 | `#23864F` / `#C5840C` / `#61717D` |
| 图形与徽标白圈 | `#FFFFFF` |

## 文件

| 路径 | 格式 |
| --- | --- |
| `app/res/moonlight.svg` | 即 `office/icons/client-app.svg`，1024 viewBox；运行时窗口图标和 `session.cpp` 32/64 px 渲染都用它（Qt SVG Tiny 1.2：只用 `linearGradient`、`path`、`rect`，无滤镜/蒙版/CSS） |
| `app/moonlight.ico` | Windows 可执行文件图标（`RC_ICONS`）、安装包：256 px PNG + 192/128/96/64/48/40/32/24/16 px 32 位 BMP |
| `app/moonlight.icns` | macOS：`iconutil` 生成，16–512 及 @2x（含 1024） |
| `app/moonlight_wix.png` | 安装包徽标，64×64 RGBA |
| `app/deploy/steamlink/moonlight.png` | Steam Link 元数据，116×116 RGBA |
| `office/icons/*.svg` | 6 个源矢量（`client-app`、`host-app`、`tray-normal/playing/pausing/locked`），后 5 个由 Sunshine Desk 使用，此处保留同一份 |
| `office/icons/render-previews.py`、`build-assets.py`、`sheet.png` | 渲染脚本与效果总览 |

文件名与路径保持上游原样，构建与代码引用不变。

## 重新生成

在 macOS 上（需要 ImageMagick 7、`iconutil`、Pillow）：

```sh
cd office/icons
python3 build-assets.py /tmp/icons-out      # 输出 client/ 与 server/ 两棵目录树，路径与仓库相对路径一致
cp /tmp/icons-out/client/app/moonlight.ico ../../app/   # 其余文件同理
cp client-app.svg ../../app/res/moonlight.svg
python3 render-previews.py                  # 可选：刷新 preview/ 与 sheet.png
```

不要用 `scripts/generate-ico.sh` 或直接 `magick x.svg` 栅格化：Mac 上的 ImageMagick 7 SVG 读取器会丢掉渐变和描边透明度。`render-previews.py` 把 SVG 几何转成 ImageMagick 绘图原语再渲染，已规避此问题。

## 来源与许可

矢量图由 OpenAI Codex 按所有者的指示在所有者的机器上原创生成；未使用上游 Moonlight 或任何第三方美术。随本仓库以 GPL-3.0 许可。

## 已知限制

`moonlight.icns` 由当前系统 `iconutil` 生成，容器块类型以 iconutil 输出为准；`.ico` 中 256 px 以外的条目为 BMP 以兼容旧版资源编译器。
