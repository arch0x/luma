# Contributing to Luma

English · [简体中文](CONTRIBUTING.zh-CN.md)

Reports and fixes for reading and editing workflows are welcome. Luma is an early preview.

## Issues and suggestions

Choose Bug Report or Feature Request in the repository's Issues. Include the app version, macOS version, processor architecture, reproduction steps, expected behavior and actual behavior. For parsing problems, a minimal sample you can share publicly is useful.

For larger interaction changes or new format support, describe the reading or editing task first so the scope can be discussed. Remove private information, credentials and sensitive document content from screenshots, logs and examples.

## Run from source

Requires macOS 14+, Swift 6.2+ and Apple Command Line Tools. Normal builds need no remote SwiftPM or npm dependencies, and no Developer ID.

```sh
swift run Luma
```

See the [Development Guide](docs/DEVELOPMENT.md) for packaging, modules and sample maintenance.

## Validate changes

Tests use real AppKit windows and WebKit subprocesses. Run them serially:

```sh
zsh scripts/test.sh --no-parallel
```

You can first run the relevant suite:

```sh
zsh scripts/test.sh --no-parallel --filter ReaderCoreTests
zsh scripts/test.sh --no-parallel --filter LumaTests
```

For interface changes, use the bundled examples to check both languages, light and dark appearance, narrow windows, keyboard focus, and draft / selection preservation. For documentation-only edits, check images and local links without running the full UI suite.

CI is configured for macOS 15 and macOS 26 Apple Silicon runners with Xcode 26.3. It runs core and app tests, a release build and ad hoc signature verification. Native tests need window services; see the [test environment notes](docs/DEVELOPMENT.md#structure-and-tests).

## Language conventions

Write project documentation, source comments, commit messages and GitHub templates in English. Keep the Chinese README current when user-facing setup or behavior changes. Chinese translations and localized Chinese sample fixtures intentionally use Chinese.

Maintain interface translations in `Localization/en.json`, then run `python3 scripts/generate-localizations.py`. Chinese message keys are stable localization identifiers, not the default display language. Preserve interpolation placeholders and check both languages in narrow windows.

Edit sample text directly in `Sources/Luma/Resources/Samples/en` and `zh-Hans`. Keep both collections equivalent. Update `Samples/catalog.json` for format changes, then run `python3 scripts/refresh-samples.py`; it generates both catalogs and format guides without overwriting editable fixtures.

## Submit a patch

- Keep a PR focused on one problem. Describe the trigger, resulting behavior and validation.
- Prefer regression tests covering actual invalid input, file operations or interactions.
- Maintain fixtures and their generators together.
- Preserve third-party origins, versions, hashes and license notices. Luma uses the [MIT License](LICENSE).

Do not commit `.build/`, `dist/`, local configuration, credentials or runtime logs. CI artifacts are ad hoc signed, without Developer ID signing or Apple notarization.
