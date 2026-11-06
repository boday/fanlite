# Changelog

本專案遵循 [Semantic Versioning](https://semver.org/lang/zh-TW/)。

## [0.1.1] - 2026-11-06

### Fixed

- 選單列 App 加上 `NSAppSleepDisabled`，避免背景 App Nap 延遲刷新
- 本機刷新頻率重設為 10 秒，確保預設行為一致

## [0.1.0] - 2026-11-06

### Added

- 首個 MVP 版本
- macOS 選單列顯示 CPU 最高溫、兩顆風扇 RPM、封裝功耗
- 可調刷新頻率：5 / 10 / 30 / 60 秒，預設 10 秒
- 風扇模式選單：`auto`、`quiet`、`full`
- 以 `smctl` 0.2.4 讀取 Apple Silicon SMC
- `--once` CLI 驗證模式
- 建置、打包、SHA-256 與測試腳本

### Known limitations

- 僅支援 Apple Silicon
- ad-hoc 簽章，尚未 notarize
- 風扇控制需安裝 `smctl` root helper

[0.1.0]: https://github.com/boday/fanlite/releases/tag/v0.1.0
[0.1.1]: https://github.com/boday/fanlite/releases/tag/v0.1.1
