# 参与 Luma

欢迎反馈阅读与编辑中遇到的问题，也欢迎提交修复。项目仍处于早期预览阶段。

## 反馈问题与建议

请在仓库的 Issues 中选择「问题反馈」或「功能建议」。问题反馈尽量包含应用版本、macOS 版本、芯片架构、复现步骤，以及预期与实际结果。涉及格式解析时，一份可公开的最小样例会很有帮助。

较大的交互调整或新格式支持，建议先描述你想完成的阅读／编辑任务，便于讨论范围。截图、日志与样例请去掉私人信息、真实凭据和敏感文档内容。

## 从源码开始

需要 macOS 14+、Swift 6.2+ 和 Apple Command Line Tools。普通构建没有远程 SwiftPM 或 npm 依赖，也不需要 Developer ID。

在仓库根目录运行：

```sh
swift run Luma
```

应用打包、模块结构与示例资源维护见[开发说明](docs/DEVELOPMENT.md)。

## 验证改动

完整测试包含真实 AppKit 窗口与 WebKit 子进程，使用串行执行：

```sh
zsh scripts/test.sh --no-parallel
```

也可以先按改动范围检查：

```sh
zsh scripts/test.sh --no-parallel --filter ReaderCoreTests
zsh scripts/test.sh --no-parallel --filter LumaTests
```

界面变更请用随应用提供的真实示例检查深浅外观、窄窗口、键盘焦点，以及草稿／选区是否保留。文档改动检查图片和本地链接即可；无需为了文字修正运行整套界面测试。

CI 配置在 macOS 15、macOS 26 的 Apple Silicon runner 上使用 Xcode 26.3，执行核心测试、应用测试、release 构建和临时签名校验。原生测试需要正常的窗口服务；具体环境限制见[开发说明](docs/DEVELOPMENT.md#工程结构与测试)。

新增或调整界面文案时，同步维护 `Localization/en.json`，运行 `python3 scripts/generate-localizations.py`，并检查中英文在窄窗口下的布局。

## 提交修改

- 一次 PR 聚焦一个问题，说明触发场景、修改后的行为和验证结果。
- 新增回归测试优先覆盖实际错误输入、文件操作或交互路径。
- 示例资源与对应生成脚本一起维护，避免刷新后恢复旧内容。
- 第三方组件保留来源、版本、哈希与许可声明；项目使用 [MIT License](LICENSE)。

`.build/`、`dist/`、本地配置、凭据和运行日志不提交到仓库。CI 下载产物也使用本地临时签名，不代表经过 Developer ID 签名或 Apple 公证。
