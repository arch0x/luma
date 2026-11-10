# 开发说明

[返回项目首页](../README.md) · [使用指南](USAGE.md)

所有命令均在仓库根目录运行。需要 macOS 14+、Swift 6.2+ 和 Apple Command Line Tools；安装的 Apple 工具链须满足 Swift 版本要求。项目没有远程 SwiftPM 依赖，构建和运行无需 npm。

## 构建与调试

```sh
swift run Luma
```

也可以将文件或文件夹路径作为参数传入：

```sh
swift run Luma "Sources/Luma/Resources/Samples/欢迎.md"
```

生成可从 Finder 打开的应用：

```sh
zsh scripts/build-app.sh
open dist/Luma.app
```

使用 release 配置：

```sh
zsh scripts/build-app.sh release
```

脚本生成图标、编译可执行文件、复制资源并进行本地临时签名。当前打包产物未经过 Developer ID 签名或 Apple 公证；版本号与应用标识定义在 `scripts/build-app.sh`。`dist/` 和 `.build/` 不纳入版本控制。

## 工程结构与测试

- `Sources/ReaderCore`：文件读取边界、格式识别、CSV / JSON 数据模型。
- `Sources/ReaderCore/PlainTextFallback.swift`：未知格式的文本检测与二进制排除；`Sources/ReaderCore/SVGDocument.swift`：共享 SVG 校验；`SVGReader.swift`：独立 SVG 的隔离矢量预览与缩放。
- `Sources/Luma`：窗口、工作区状态、SwiftUI 阅读器及 AppKit / PDFKit / WebKit 桥接。`MarkdownImages.swift` 负责图片路径范围、后台读取和缩略缓存；`MarkdownOutline.swift` 负责目录层级和原生大纲界面；`MarkdownFind.swift` 负责正文查找栏与状态，包内 `search.js` 负责可见文字索引和覆盖层高亮。
- `MarkdownReading.swift` / `MarkdownBookmarks.swift`：按文档保存的阅读位置与书签、原生书签列表；包内 `reading.js` 负责段落锚点、阅读位置捕获和恢复。
- `MarkdownTypography.swift`：正文字体选项、字号 / 行距范围及传给预览的排版配置；`Workspace` 负责偏好保存。
- `SourceEditor.swift`：每个标签独立的原生文本视图与撤销历史；`DocumentDialogs.swift` / `WorkspaceWindowBridge.swift`：未保存与冲突决策、窗口关闭保护；`Sources/ReaderCore/TextFileStore.swift`：文件版本、编码 / 换行与协调保存。
- `Sources/Luma/Resources/Samples`：本地示例工作区。
- `Tests/ReaderCoreTests`：解析边界、错误输入、读取限制及符号链接循环验证。
- `Tests/LumaTests`：真实文件打开、标签复用、源码回退、重新载入、工作区恢复、文件搜索和原生示例资源验证。使用隔离的测试偏好设置，不修改应用配置。
- `Tests/LumaTests/MarkdownPreviewTests.swift`：实际 WebKit 排版 / 图表 / 高亮 / 公式 / 图片结果、离线字体、路径编码、目录边界、深浅色切换、错误回退与内容隔离。测试创建独立预览视图，不读取桌面，也不需要屏幕录制权限；运行环境须允许启动系统 WebKit 子进程。

```sh
zsh scripts/test.sh --no-parallel
```

`ViewState.swift` 和测试脚本兼容部分 Command Line Tools 的宏加载差异。若在不支持嵌套沙盒的 CI 中构建，可给打包或测试脚本追加 `--disable-sandbox`；这只影响 SwiftPM 构建过程，不授予应用额外权限。

测试包含真实 AppKit 窗口、系统粘贴板和 WebKit 预览，需要运行环境允许这些系统服务。外观测试显式给 AppKit 测试窗口提供与 SwiftUI Window 场景相同的外观呈现边界；应用的外观实现保持不变。`--disable-sandbox` 仅关闭 SwiftPM 的构建沙盒，不能解除宿主环境对这些服务的限制。历史阶段的验证结果保存在[变更记录](../CHANGELOG.md)，不代表当前工作区测试状态。

## 持续集成

[CI 工作流](../.github/workflows/ci.yml)在 push、pull request 和手动触发时运行，权限仅为读取仓库内容。配置使用 macOS 15、macOS 26 的 Apple Silicon runner，并通过 `DEVELOPER_DIR` 固定选择 Xcode 26.3。

每个环境依次执行：

1. 记录系统、Xcode、Swift 和芯片架构。
2. 运行 `ReaderCoreTests`。
3. 串行运行全部 `LumaTests`，包括 AppKit 与 WebKit 验证。
4. 构建 release 应用，校验本地临时签名，并打包 ZIP。

构建通过后保留 ZIP 产物 7 天，测试／构建日志也保留 7 天，失败时仍上传已生成的日志。CI 不需要 Developer ID、签名证书或仓库 Secrets；产物未经过 Apple 公证。

运行最低版本仍由 `Package.swift` 声明为 macOS 14；CI 的两个环境不替代 macOS 14 或 Intel 实机验证。GitHub 端的实际执行结果将在仓库配置并推送后产生。

## 界面本地化

`Localization/en.json` 是应用自有中文文案与英文译文的统一来源。Swift 界面使用 `tr` / `trKey`，ReaderCore 的非主线程错误使用 `coreText`；插值保留为编号占位符，用户文件名和内容只作为数据插入。

修改文案后运行：

```sh
python3 scripts/generate-localizations.py
python3 scripts/generate-localizations.py --check
```

脚本生成 ReaderCore 资源包中的 `zh-Hans.lproj` / `en.lproj` 及离线预览的 `localization.js`，CI 会检查生成结果是否同步。新增用户文案需要同时补充英文译文，并保留 `{0}` 等占位符。目录名称、用户正文、代码内容与格式标识不进行翻译。

语言偏好保存在本机。切换时更新现有视图及菜单，不以重建工作区的方式刷新语言；预览重排前会捕获当前阅读锚点。Apple 原生面板的语言仍由系统呈现机制管理。

## 原生交互

- 标签右键菜单通过 AppKit 原生菜单处理，支持鼠标右键与 Control-click；命中检查同时限制到标签自身和横向滚动的可见区域，普通点击、关闭按钮和滚动保持原有行为。关闭标签或拆卸工具栏时清理对应的事件监听。

## 读取与渲染限制

源码支持编辑、手动保存及可选的自动保存，PDF 与位图仍为预览。Markdown 的原始 HTML 显示为文本；常见代码文件支持高亮预览与语言标识，源码模式保持纯文本编辑。超过 100,000 字符时预览保留纯文本，仍可查看完整内容。JSON 格式化展开超过约 200 万字符时回退原文预览；超过 20,000 行时省略行号，完整内容仍保留。GIF 显示首帧。UTF-8 文本读取与保存上限 4 MB，CSV / TSV 表格预览上限 10,000 行 / 200 列，PDF 上限 128 MB，独立位图上限 64 MB，缩略预览最长边 4096px。独立 SVG 预览上限 1 MB，超过预览上限但不超过 4 MB 的文件仍可编辑源码；SVG 作为隔离图片显示，不执行文件脚本、不加载外部资源，不接受 DTD / 实体声明。工作区文件名搜索最多扫描 25,000 个条目，展示 200 个匹配，包含隐藏条目，跳过常见构建目录。暂未做工作区全文内容搜索、持续文件监听、App Sandbox 安全作用域文件访问或 App Store 分发。

默认情况下编辑内容保存在当前应用内存中，按 `⌘S` 写入原文件；可在设置中开启自动保存，停止输入约 1 秒后写入。不提供崩溃草稿恢复。保存使用系统文件协调与原子替换，保留 UTF-8 BOM、原有换行风格（LF / CRLF / CR，混合换行按首种统一），不自动格式化 JSON 或重写 CSV 数据。无法读取、无写权限、超过大小限制或写入失败时保留编辑，并取消关闭流程。外部修改检查不会自动替换当前内容。

Markdown 通过内嵌 WebKit 展示，Marked 解析 GFM，highlight.js 高亮，Mermaid 绘图，KaTeX 排版公式，DOMPurify 清理生成内容。引擎版本、哈希和许可保存在 `Sources/Luma/Resources/Markdown/vendor/manifest.json` 和 `THIRD_PARTY_NOTICES.txt`。运行时只从包内白名单加载引擎与字体，禁用网络子资源；用户点击链接才交给应用打开。图表使用严格模式，每份文档最多渲染 40 个图表、单个图表最多 50,000 字符 / 500 条边；超限或解析失败保留源码。超过 100,000 字符的代码块保留纯文本，避免长时间高亮。

本地图片通过单独的图片协议读取。相对路径基于 Markdown 文件的位置，自动读取范围是包含此文件的最具体工作区；未添加工作区时限于文档所在文件夹及其子目录。引用 `../assets/…` 时，请添加包含文档和图片的父文件夹。路径解码、标准化及符号链接解析后仍须位于该范围内。远程图片不自动加载。位图经 ImageIO 缩略处理（最长边 2048px，原始文件最多 64 MB），SVG 最多 1 MB、仅作为独立图片展示且禁用其子资源；DTD / 实体声明不接受。每份文档最多预览 100 张图片，图片缓存总量最多 64 MB。

数学公式是 KaTeX 支持的 LaTeX 数学子集，并非完整 TeX 文档编译器。每页最多渲染 500 条公式，单条最多 10,000 字符；超限或错误内容保留原文。宏仅在当前公式内生效，禁用 HTML 和外部资源相关的受信任命令，并限制宏展开次数。普通金额、转义美元符号和围栏 / 行内代码保持原样。

目录按实际渲染的标题生成，代码块和原始 HTML 不进入大纲。中文标题和重复标题具有唯一锚点，空白 / 纯标点标题使用稳定的备用锚点。目录最多显示前 2,000 条标题，正文和后续标题的锚点继续保留；极长标题的目录文字会截短。章节位置在图片、公式字体加载完和阅读区尺寸变化后更新，滚动时使用缓存位置查找当前章节。

## 查找与阅读记录

正文搜索基于可见文字，空白按连续空白匹配，不将搜索词解释为正则表达式。不做图片文字识别，不包含复制按钮 / 工具栏、隐藏 MathML 或折叠源码中的文字，也不跨段落或表格单元格拼接短语。公式按渲染出的文字检索，LaTeX 命令应在源码模式查看。最多显示并导航前 5,000 处结果，超限在计数后标 `+`；过长搜索词会提示缩短。高亮通过文本 Range 和透明覆盖层绘制，保留链接、语法结构、文本选择和复制内容；仅绘制视口附近结果。窗口 / 内容布局变化及代码横向滚动时更新高亮位置，主题切换和重新载入后重新查找并保留当前结果位置。

字体、字号、行距和宽度修改直接调整当前页面的布局，不重新解析文档或重新加载图片，保留搜索结果并更新高亮位置。排版设置适用于所有 Markdown 预览，保存在本机；三种字体使用 macOS 自带字体，无须联网下载。阅读位置使用段落内容签名、段内比例、章节锚点和整体进度组合保存；重开时等待图片、公式字体和图表排版后，优先恢复原段落。原段落消失时回退到章节，再回退到整体进度。窗口尺寸或排版设置不同也能尽量保持阅读内容。记录按规范化后的文件路径保存；通过 Luma 重命名或移动文件时会迁移记录，在外部移动的文件暂不自动关联旧记录。

阅读记录与每份文档最多 500 个书签保存在应用自己的 UserDefaults 元数据中，不写入原文档。滚动位置在停顿后延迟合并写入，添加 / 移除书签立即写入；关闭文档、切换到源码或正常退出前会再捕获一次最新位置，并在退出时完成待处理的书签和保存。启动恢复文件标签的顺序和选中项，忽略已经不存在的文件；仅 Markdown 预览位置跨重启恢复，源码 / PDF 等其他阅读器的位置仍为会话状态。`长文档导航.md` 末尾有书签与恢复体验步骤。

## 维护示例资源

维护示例需要额外准备带 Pillow 的 Python。按顺序运行以下命令，重生成蓝色 PNG / PDF、原生图片编码、代码样例、格式目录和 WebP：

```sh
swift -module-cache-path "$PWD/.build/module-cache" scripts/generate-assets.swift "$PWD" --refresh-samples
python3 scripts/refresh-samples.py
```

WebP 使用真实无损编码；普通应用构建直接打包已提交的资源，仍只需要 Apple 工具链。`Sources/Luma/Resources/SampleCatalog.json` 是示例清单，测试会对照 `DocumentKind.extensionsByKind` 检查覆盖并验证真实文件。

仅更新文本、JSON / CSV 与格式清单时，可运行 `python3 scripts/refresh-samples.py --text-only`，无需 Pillow，也不会重编码 WebP。

仅更新 PDF 页脚或内容时，可运行 `swift -module-cache-path "$PWD/.build/module-cache" scripts/generate-assets.swift "$PWD" --refresh-pdf`，避免重生成其他图片编码。

示例安装目录为 `~/Library/Application Support/Luma/Samples-2026.11.2`，旧版 `Samples-2026.11.1`、`Samples-2026.11` 与 `Samples-0.8` 保留。修改示例版本时同步检查 `SampleWorkspace.swift`、示例清单和相关测试。

## 图标与界面资源

应用图标使用[蓝色图标原图](../Sources/Luma/Resources/Brand/AppIcon.png)。打包时按蓝色底板的不透明边界等比例裁切，去除外侧透明边距，保留标志比例与圆角透明角，再生成各尺寸图标和 `dist/AppIcon.icns`；原图保持不变，示例中的 ICNS 同步更新。[设计提示词](../design/AppIcon-prompt.txt)也随项目保留。

原生界面与 Markdown 预览共用蓝色强调色。浅色使用 `#3A6095` 和纸白 `#FCFCFA`，深色使用 `#A6C5F2` 和灰蓝 `#1A202B`。活动标签、链接和焦点用蓝色标识，正文查找用琥珀色区分普通匹配和当前匹配。
