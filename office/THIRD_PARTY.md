# Moonlight Desk macOS 开发包：第三方许可与源码出处

本清单针对 `dist/MoonlightDesk.app` 的本地开发构建，基线为 Moonlight Qt **v6.2.0**、`moonlight-qt-deps` **v19**、Qt **6.11.2**。这里只整理可复核的原文与来源，不构成法律结论。尚未完成的材料列在文末；不能仅凭本文件宣称公开二进制分发材料已经齐备。

## 文件与证据

- `licenses/vendored/`：从当前仓库及已检出的子模块逐字复制的许可文件。项目根目录 `LICENSE` 保留不动；此处另存其副本。
- `licenses/dependencies/`：从依赖锁定提交读取的上游许可、版权文件。目录名前缀为 `SDK-reference-` 的文件仅是参考，不代表已证明与 SDK 二进制精确对应。
- `licenses/SOURCES.json`：每个收集文件的上游仓库、revision、原始路径、下载 URL、本地相对路径、SHA-256。下载到的许可证原文未改写。
- `licenses/Qt-6.11.2/`：本次 Qt 官方安装自带的 binary SPDX JSON 和 source SPDX，使用 gzip 无损压缩；可用 `gzip -dc 文件.gz` 阅读。另提取其中的自定义许可全文，保留官方 SPDX 原件中的版权、许可证表达式和组件关系。它们覆盖完整模块，可能包含未随本应用分发的构建工具，**不是逐个 Mach-O 的已裁剪结论**。
- `licenses/source-manifests/`：v19 完整小型构建脚本、补丁、工作流、子模块 gitlink 清单；不包含大型递归源码。FFmpeg、libplacebo 有 v19 本地补丁，不能只提供未打补丁的上游源码而称作此构建的完整源码。
- `licenses/source-manifests/BUNDLE-MACHO-SHA256.json`：本次检查时包内 **111 个 Mach-O** 的相对路径、大小及 SHA-256。后续重新构建、签名或修改二进制后需重新生成；资源文件增补本身不改变其二进制哈希。

## 主项目与本仓库内代码

Moonlight Qt v6.2.0 指向提交 [`de2467e433821664cdd2224aad8c89a625be1ad9`](https://github.com/moonlight-stream/moonlight-qt/tree/de2467e433821664cdd2224aad8c89a625be1ad9)，根许可证为 GNU GPL v3。Moonlight Desk 的修改和完整上游历史已经公开在 [本项目](https://github.com/linrong123/moonlight-desk)。包内 `Contents/Resources/OfficeSource/SOURCE.json` 记录构建时源码提交及链接；请递归检出子模块，并遵循 `office/README.md` 构建说明。

| 组件 | 当前源码提交/出处 | 保存文件 |
| --- | --- | --- |
| moonlight-common-c | `f900dd4767759c7b9d0e93bcea666b55c69ea62f`，moonlight-stream/moonlight-common-c | `vendored/moonlight-common-c/LICENSE.txt` |
| ENet | `aca87840b57f045a1f7f9299e4b1b9b8e2a5e2f1`，cgutman/enet | `vendored/enet/LICENSE` |
| nanors | `b1e3c22ca0cdc0bb83e3cd6ed1a2fc77869ed99a`，sleepybishop/nanors | `vendored/nanors/LICENSE` |
| qmdnsengine | `920c097ffa742e2968290f15d4dde6693aec02e5`，cgutman/qmdnsengine | `vendored/qmdnsengine/LICENSE.txt` |
| SDL_GameControllerDB | `8d9fefd7b810f2541f78cc7a8ccbd185bc84c7a5`，gabomdq/SDL_GameControllerDB | `vendored/SDL_GameControllerDB/LICENSE` |
| h264bitstream | 随上述 Moonlight Qt 基线 vendored，未单独宣称外部版本 | `vendored/h264bitstream/LICENSE` |
| ModeSeven 字体 | 当前 `app/ModeSeven.ttf` 的内嵌 name 表 | `vendored/ModeSeven-font-metadata.txt` |

ModeSeven 内嵌文字为 “This rendition (C) 1998 Andrew C. Bul+hac?k. Freely distributable.”；保留实际字体中的原文和各平台记录，不自行纠正署名、不扩写成标准许可证。尚未找到独立许可证或更完整的字体来源证据。

## moonlight-qt-deps v19：直接与锁定内嵌依赖

构建出处：[moonlight-qt-deps v19](https://github.com/moonlight-stream/moonlight-qt-deps/tree/79621271459ebb945343f58d7acd6ad24d402c38)，提交 **`79621271459ebb945343f58d7acd6ad24d402c38`**。

下载入口：[macos-universal.zip](https://github.com/moonlight-stream/moonlight-qt-deps/releases/download/v19/macos-universal.zip)。项目 `setup-deps.py` 使用此标签资产。标签和发行资产可能被上游重置；本清单记录的是查询到的源提交及本地二进制哈希，未声称已用可复现构建证明资产内容。

实际 `libSDL2.dylib` 来自 **sdl2-compat**，并依赖 **SDL3**；不能按旧版 SDL2 库遗漏 SDL3。

| 组件 | 锁定提交 | 源码 | 原文目录 |
| --- | --- | --- | --- |
| SDL3 | `829a65d769d935c4852f8159e964312c0957260a` | [SDL](https://github.com/libsdl-org/SDL/tree/829a65d769d935c4852f8159e964312c0957260a) | `dependencies/SDL3/` |
| sdl2-compat | `e4df8a55f20da762290a78c2bbe8f8d89d01486a` | [sdl2-compat](https://github.com/libsdl-org/sdl2-compat/tree/e4df8a55f20da762290a78c2bbe8f8d89d01486a) | `dependencies/sdl2-compat/` |
| SDL_ttf | `a883e490e30fb44a5336ea3dcb990c6982c5216f` | [SDL_ttf](https://github.com/libsdl-org/SDL_ttf/tree/a883e490e30fb44a5336ea3dcb990c6982c5216f) | `dependencies/SDL_ttf/` |
| FFmpeg | `946fcce07b6dcd0331c8cc609192aeff5e1924f8` | [FFmpeg](https://github.com/FFmpeg/FFmpeg/tree/946fcce07b6dcd0331c8cc609192aeff5e1924f8) | `dependencies/FFmpeg/` |
| OpenSSL | `c8bd5a57108599ac650bbae77fcabe3109dab2e8` | [openssl](https://github.com/openssl/openssl/tree/c8bd5a57108599ac650bbae77fcabe3109dab2e8) | `dependencies/OpenSSL/` |
| Opus | `22244de5a79bd1d6d623c32e72bf1954b56235be` | [opus](https://github.com/xiph/opus/tree/22244de5a79bd1d6d623c32e72bf1954b56235be) | `dependencies/Opus/` |
| discord-rpc | `7bcf3b3fdd02d4d5072971ef1d5b4e6dd3a765dc` | [discord-rpc](https://github.com/cgutman/discord-rpc/tree/7bcf3b3fdd02d4d5072971ef1d5b4e6dd3a765dc) | `dependencies/discord-rpc/` |
| dav1d | `54706fc6bc0cdecab7e9593974a4039cc038fca7` | [dav1d](https://github.com/videolan/dav1d/tree/54706fc6bc0cdecab7e9593974a4039cc038fca7) | `dependencies/dav1d/` |
| libplacebo | `92b5ac6db79f4d680eb656692f7bf51e9606f42a` | [libplacebo](https://github.com/haasn/libplacebo/tree/92b5ac6db79f4d680eb656692f7bf51e9606f42a) | `dependencies/libplacebo/` |
| Vulkan-Headers | `6802bb4733b63ed5efd3adb308a6c885ef180ea1` | [Vulkan-Headers](https://github.com/KhronosGroup/Vulkan-Headers/tree/6802bb4733b63ed5efd3adb308a6c885ef180ea1) | `dependencies/Vulkan-Headers/` |
| moonlight-qt-deps | `79621271459ebb945343f58d7acd6ad24d402c38` | [moonlight-qt-deps](https://github.com/moonlight-stream/moonlight-qt-deps/tree/79621271459ebb945343f58d7acd6ad24d402c38) | `dependencies/moonlight-qt-deps/` |
| FreeType | `535d2993d2cab67cc8b270132b1b1bcb62f269aa` | [freetype](https://github.com/libsdl-org/freetype/tree/535d2993d2cab67cc8b270132b1b1bcb62f269aa) | `dependencies/FreeType/` |
| HarfBuzz | `950d232cdcd29e2e83a2099307e5624a8f1aa937` | [harfbuzz](https://github.com/libsdl-org/harfbuzz/tree/950d232cdcd29e2e83a2099307e5624a8f1aa937) | `dependencies/HarfBuzz/` |
| fast_float | `97b54ca9e75f5303507699d27c6b4f4efe4641a1` | [fast_float](https://github.com/fastfloat/fast_float/tree/97b54ca9e75f5303507699d27c6b4f4efe4641a1) | `dependencies/fast_float/` |

FreeType 和 HarfBuzz 的 gitlink 由 **SDL_ttf 自身**的 `external/` 树锁定。v19 指向 `libsdl-org/freetype`、`libsdl-org/harfbuzz` 的下游镜像；已下载的许可对象在原仓库相同提交也可读取，manifest 同时标出权威下游地址。FreeType 的 FTL、GPLv2 及顶层 LICENSE 全部保存，不擅自替发行者选择条款。libplacebo 内嵌 fast_float 的三份可选许可也全部保留。

macOS FFmpeg 脚本启用 libdav1d，dav1d **静态并入** FFmpeg，故即使包内没有 `libdav1d.dylib`，仍收集其许可。脚本没有启用 FFmpeg GPL 编码器；保留其官方 LICENSE 和各 COPYING 原文，由发布者对实际配置确认适用许可。

## Qt 6.11.2

通用说明：[Qt 官方许可说明](https://doc.qt.io/qt-6/licensing.html)。不能把所有 Qt 文件统一描述为 LGPL；部分模块/文件仅提供 GPL 等选择，另有 Qt 内嵌第三方代码。应以本版本每文件声明及保留的官方 SBOM 为依据。

- 官方源码全集入口：[qt-everywhere-src-6.11.2.tar.xz](https://download.qt.io/official_releases/qt/6.11/6.11.2/single/qt-everywhere-src-6.11.2.tar.xz)。本次未下载该大型源码包，未校验其 SHA-256。
- GPL v2/v3、LGPL v3、Qt GPL exception 及 Qt 声明的其他 SPDX 许可原文，来自精确 qtbase/qtdeclarative/qtsvg 源提交的 `LICENSES/` 目录，位于 `dependencies/Qt-*/LICENSES/`。
- `Qt-6.11.2/MODULE-SOURCES.json` 逐字保留官方 binary SBOM 中的源码下载位置与版本：qtbase `ef55f427f2c8b410d34f8a7681020a3000cf6866`；qtdeclarative `4e3399c26ec57246c08de019cfcbda8d23604cfa`；qtsvg `17ca512f903f935282ebeca496aac5d11ba4199a`。qtimageformats/qtshadertools/qttranslations 的 SBOM 仅声明 `6.11.2` 和仓库，未给完整提交，因此不补造 revision。
- 包内 QtCore/Gui/Widgets/Network/DBus/Sql/OpenGL 来自 qtbase；Qml/Quick/QuickControls2 等来自 qtdeclarative；Svg 来自 qtsvg。保存 imageformats/shadertools/translations 的 SBOM 是保守覆盖，不表示它们所有工具都随包分发。

## Vulkan SDK 来源缺口与公开分发前待补材料

v19 的 macOS 工作流安装 **Vulkan SDK 1.4.363.0**，`archive.sh` 直接从 SDK 拷贝 MoltenVK，libplacebo 从 SDK 链入 shaderc；shaderc 又带入 glslang、SPIRV-Tools/SPIRV-Headers 等。因此，这些组件不能因没有独立 dylib 而省略。

已保存 SDK 版本构建证据和该 SDK 标签的 VulkanTools `known_good.json`，但该文件只锁定 VulkanTools 自身依赖，**不能代替 SDK 全部组件的锁定清单**。本地 MoltenVK 二进制含 `1.4.2` 版本串；其官方 v1.4.2 源码可作为对应版本线索，尚未证明 SDK 使用的精确构建提交、补丁及其 SPIRV-Cross 等嵌入版本。`SDK-reference-*` 下的许可仅用于避免漏列已识别组件，未宣称其 revision 就是包内版本。shaderc 不使用 `vulkan-sdk-1.4.363.0` 标签；没有把不存在的标签写成已核实来源。

公开二进制发布材料仍有以下实质缺口，应作为发布前检查项，而非将本目录称作已完成的分发许可包：

1. **构建与源码对应核验**：本项目源码已公开，构建脚本会把确定提交和源码链接写入包内 `SOURCE.json`；正式发包前须确认 `working_tree_modified=false`，并核对包所用依赖及补丁仍可取得。
2. **SDK 间接依赖精确版本与完整 notices**：需要 SDK 1.4.363.0 的组件 manifest/源码包及许可证目录，核对 MoltenVK、shaderc、glslang、SPIRV-Tools、SPIRV-Headers、SPIRV-Cross（及实际嵌入的其他组件）。本次未下载整个 SDK，也未做二进制对应源码重建；参考许可不能掩盖此缺口。
3. **逐二进制与内嵌代码覆盖确认**：本次保存了 111 个 Mach-O 清单和主要来源，但尚未逐项完成每个二进制的内嵌依赖映射；SDL 等第三方源码中的逐文件版权声明可能不只存在于顶层 LICENSE。Qt 官方 source SPDX 保留了逐文件版权证据，但仍需核对实际发出的全部模块/插件。
4. **字体来源**：ModeSeven 的内嵌分发声明已原样保存；独立原始发行包/许可证未取得。不要将其擅自标为 MIT/OFL。
5. **打包动作**：`office/macos/build.sh` 已把许可证、来源清单和 `SOURCE.json` 放入 `.app` 的 `Contents/Resources/OfficeSource`，随后签名并重算 ZIP 校验值。`BUNDLE-MACHO-SHA256.json` 是许可调查时的参考快照，重新签名后部分哈希会变化，不是最终包的验签依据；最终以 ZIP 的 `SHA256SUMS` 为准。

这些是可复核材料的完整性边界，不是关于特定分发方式是否合法的判断。
