# FanLite

<p align="center"><img src="assets/AppIcon-1024.png" width="140" alt="FanLite icon"></p>

[![Version](https://img.shields.io/badge/version-0.4.0-blue)]()
[![Platform](https://img.shields.io/badge/macOS-14%2B%20Apple%20Silicon-black)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()

**免費、開源的 macOS 選單列溫度與風扇工具。**
適合只需要「即時溫度 + 風扇轉速 + 可調刷新頻率」的使用者，不需要訂閱，也不依賴 iStat Menus。

> 本專案與 Bjango／iStat Menus 無任何關聯。

## 功能

- 選單列顯示 CPU 最高溫度與兩顆風扇 RPM
- 控制面板：可拖拉的雙風扇 RPM 滑桿、同步兩顆風扇
- 單獨控制 Fan 0 / Fan 1，或同步控制兩顆
- 風扇模式：`auto`（macOS 控制）、`quiet`、`full`
- **80°C 自動增壓**：80°C → 4,500 RPM、88°C → 5,500 RPM、90°C → 6,000 RPM
- 溫控獨立每 **2 秒**取樣；降階需低於出場門檻並停留 **45 秒**，避免風扇抖動
- **登入時自動啟動**：以 LaunchAgent 註冊，重開機登入後自動接回溫控
- 刷新頻率：**5 / 10 / 30 / 60 秒**，預設 **10 秒**
- 讀取 SMC 不需要 root、不需要常駐 daemon
- 使用 MIT 授權、Apple 公證的 [`smctl`](https://github.com/leaperone/smctl) 作為底層
- 無網路功能、無遙測、無廣告

## 系統需求

- Apple Silicon Mac（M1 以後）
- macOS 14 以上
- 首次自行建置需要 Command Line Tools（`xcode-select --install`）

## 安裝 Release

1. 到 [Releases](https://github.com/boday/fanlite/releases) 下載
   `FanLite-v0.4.0-macos-arm64.dmg`。
2. 打開 DMG，把 `FanLite.app` 拖到 `Applications`。
3. 開啟 FanLite，選單列會出現 `🌡 68°C | 3000/3000 RPM`。
4. 點選單列的 FanLite →「開啟控制面板…」，即可用滑桿調整兩顆風扇。

因為 MVP 使用 ad-hoc 簽章，第一次開啟若被 Gatekeeper 阻擋，請在
「系統設定 → 隱私權與安全性」按「仍要開啟」。

## 從原始碼建置

```bash
git clone https://github.com/boday/fanlite.git
cd fanlite
./scripts/fetch-smctl.sh   # 下載並驗證 smctl v0.2.4
./scripts/build.sh --install
open "$HOME/Applications/FanLite.app"
```

建置產物在 `dist/FanLite.app`。

## 驗證

```bash
./scripts/test.sh
"$HOME/Applications/FanLite.app/Contents/MacOS/FanLite" --policy-test
"$HOME/Applications/FanLite.app/Contents/MacOS/FanLite" --once
"$HOME/Applications/FanLite.app/Contents/MacOS/FanLite" --login-item-status
```

預期輸出：

```text
cpu_max=68.3C fans=3000/3000RPM package=16.3W
PASS: sensor read and CLI output
```

執行日誌：

```bash
tail -f ~/Library/Logs/FanLite.log
```

每次刷新會寫入一行，可用來確認 10 秒間隔：

```text
2026-11-06T09:35:49Z cpu=68°C fans=3000/2988 package=11.6W
2026-11-06T09:35:59Z cpu=63°C fans=3023/3006 package=14.6W
```

## 開機自動啟動

FanLite 從 v0.4.0 起支援登入時自動啟動，使用 per-user LaunchAgent：

```text
~/Library/LaunchAgents/io.github.boday.fanlite.plist
```

- 控制面板：勾選「登入時自動啟動 FanLite」
- 選單列：FanLite →「開機自動啟動」
- 命令列：

```bash
APP="$HOME/Applications/FanLite.app"
"$APP/Contents/MacOS/FanLite" --enable-login-item
"$APP/Contents/MacOS/FanLite" --disable-login-item
"$APP/Contents/MacOS/FanLite" --login-item-status
```

驗證：

```bash
launchctl print gui/$(id -u)/io.github.boday.fanlite
tail -f ~/Library/Logs/FanLite.log
```

開機時間線：`smctld` root daemon 先隨開機啟動（設定 `profile = "auto"`，
登入畫面前交還 macOS）→ 使用者登入 → LaunchAgent 啟動 FanLite →
2 秒內重新套用 3,000 RPM 或依溫度增壓。

> 登入前（FileVault 解鎖畫面）沒有 FanLite 溫控；詳見
> [docs/auto-start.md](docs/auto-start.md)。

## 風扇控制

FanLite 的風扇控制需要 `smctl` 的 root helper。首次使用前執行：

```bash
sudo "$HOME/Applications/FanLite.app/Contents/Resources/bin/smctl" daemon install
```

安裝後可用：

```bash
"$HOME/Applications/FanLite.app/Contents/Resources/bin/smctl" daemon status
"$HOME/Applications/FanLite.app/Contents/Resources/bin/smctl" fan status
```

控制面板中的操作：

- **Fan 0 / Fan 1 滑桿**：放開滑桿即套用該風扇 RPM
- **80°C 自動增壓**：勾選後依溫度自動調整；預設在有 helper 時開啟
- **同步兩顆風扇**：勾選後拖動任一滑桿會同時設定兩顆
- **系統自動**：交還 macOS 控制（可能回到 0 RPM）
- **安靜 / 全速**：使用 `smctl` 內建 profile
- **刷新頻率**：5 / 10 / 30 / 60 秒（只影響 UI，溫控固定每 2 秒）
- **登入時自動啟動 FanLite**：以 LaunchAgent 註冊

### 安全設計

- 風扇控制由 `smctl` 的 root daemon 執行，FanLite 只呼叫已簽章的 CLI。
- `smctl` 具備熱保護：溫度過高會交還 macOS 控制。
- 不安裝 helper 時，FanLite 只讀取感測器，不可能改風扇。
- 不要同時執行 iStat Menus 或其他風扇控制器，避免兩個程式搶 SMC。

## 風扇調配建議

請見 [docs/fan-strategy.md](docs/fan-strategy.md)。重點：日常 3,000 RPM、兩顆同步；
80°C 自動到 4,500 RPM；88°C 5,500 RPM；90°C 6,000 RPM。降階需低於
70/82/85°C 且停留 45 秒，避免反覆升降。

## 專案結構

```text
fanlite/
├── Sources/main.swift        # AppKit 選單列程式
├── Sources/ControlPanel.swift # 雙風扇滑桿與控制面板
├── Sources/ThermalPolicy.swift # 溫控門檻、滯後與 45 秒 dwell
├── Sources/LaunchAtLogin.swift # LaunchAgent 登入自動啟動
├── scripts/
│   ├── fetch-smctl.sh        # 下載 smctl + SHA-256 驗證
│   ├── build.sh              # 建置 .app
│   ├── package.sh            # 產生 release ZIP 與 DMG
│   └── test.sh               # 建置、讀取與政策驗證
├── docs/fan-strategy.md     # 風扇調配建議
├── docs/auto-start.md       # 開機自動啟動策略
├── docs/releases/           # release notes
├── CHANGELOG.md
├── THIRD_PARTY_NOTICES.md
└── LICENSE
```

## 已知限制

- 目前只支援 Apple Silicon；Intel Mac 尚未驗證。
- MVP 使用 ad-hoc 簽章，尚未做 Apple notarization。
- 風扇控制需另外安裝 `smctl` root helper，這是 macOS 對 SMC 寫入的限制。
- 選單列圖示為文字，尚未提供自訂 icon。
- 登入自動啟動只在使用者登入後生效，FileVault 解鎖前沒有 FanLite 溫控。
- 多使用者同時執行 FanLite 會搶 SMC，建議只讓一個使用者啟用。

## Roadmap

- [x] 自訂 App icon
- [ ] Apple notarization
- [x] 登入時自動啟動選項
- [ ] 可選擇顯示的溫度感測器
- [ ] 風扇曲線編輯器
- [ ] 歷史溫度圖表
- [ ] 支援 Intel Mac 的唯讀模式

## 授權

本專案採 MIT License，見 [LICENSE](LICENSE)。
`smctl` 為獨立 MIT 專案，授權與來源見 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
