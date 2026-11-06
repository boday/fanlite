# Changelog

本專案遵循 [Semantic Versioning](https://semver.org/lang/zh-TW/)。

## [0.4.0] - 2026-11-06

### Added

- 登入時自動啟動：per-user LaunchAgent
  (`~/Library/LaunchAgents/io.github.boday.fanlite.plist`)
- 控制面板「登入時自動啟動 FanLite」與選單「開機自動啟動」開關
- CLI：`--enable-login-item`、`--disable-login-item`、`--login-item-status`
- 建議並於本機將 `smctld` 的 `[fan] profile` 設為 `auto`，避免登入前全速
- 新增 `docs/auto-start.md` 開機啟動策略文件

### Changed

- 溫控判斷改為獨立 **2 秒**輪詢，UI 刷新仍為 5/10/30/60 秒
- 降階加入 **45 秒最短停留**，避免風扇反覆升降
- 增壓出場門檻由 76°C 降到 **70°C**；高溫 82°C、全速 85°C

### Fixed

- 10 秒輪詢可能漏掉 80°C 短暫尖峰，導致自動增壓未觸發
- 20 個滿載程序下，3,000/4,500 RPM 每 6–12 秒抖動

### Verified

- 政策邊界測試 22/22 PASS
- 20 個滿載程序：4,500 RPM 連續 120 秒穩定，溫度 71.9–81.8°C
- 停止負載降至 67.9°C 後回到 3,000 RPM
- LaunchAgent bootstrap、kickstart、停用、重新啟用皆通過

## [0.3.0] - 2026-11-06

### Added

- **80°C 自動增壓**：依 CPU 熱點自動調整雙風扇
  - `< 80°C`：3,000 RPM
  - `>= 80°C`：4,500 RPM
  - `>= 88°C`：5,500 RPM
  - `>= 90°C`：6,000 RPM（依各風扇上限夾住）
- 滯後回退：86°C 以下離開全速、84°C 以下離開高溫、76°C 以下回日常
- 控制面板可開關自動增壓
- 新增 `--policy-test` 邊界測試

### Verified

- 邊界測試 14/14 PASS
- 真實負載：81.7°C 時自動切到 4,500 RPM
- 降溫後 75°C 自動回到 3,000 RPM

## [0.2.0] - 2026-11-06

### Added

- 控制面板視窗，可從選單開啟
- Fan 0 / Fan 1 獨立 RPM 滑桿
- 同步兩顆風扇選項
- 自動 / 安靜 / 全速快速按鈕
- DMG 拖曳安裝映像
- App icon（風扇＋溫度計）
- 面板內刷新頻率選擇

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
[0.2.0]: https://github.com/boday/fanlite/releases/tag/v0.2.0
[0.3.0]: https://github.com/boday/fanlite/releases/tag/v0.3.0
[0.4.0]: https://github.com/boday/fanlite/releases/tag/v0.4.0
