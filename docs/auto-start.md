# 開機自動啟動策略

> 適用 FanLite v0.4.0 以上。

## 結論

FanLite 從 v0.4.0 起支援「登入時自動啟動」，採 **per-user LaunchAgent**：

```text
~/Library/LaunchAgents/io.github.boday.fanlite.plist
```

- 啟動時機是**使用者登入 GUI 後**，不是開機即執行。
- 不需要 Apple Developer ID，也不需要把 App 放到 `/Applications`。
- 可用 `launchctl` 直接驗證，適合 ad-hoc 簽章的 FanLite。
- 控制面板與選單都有開關；預設為**關閉**，由使用者明確啟用。

## 為什麼不用 SMAppService

`SMAppService.mainApp` 是 macOS 13 以後的原生登入項目 API，適合已完成
Developer ID 簽章與公證的 App。FanLite 目前是 ad-hoc 簽章、安裝在
`~/Applications`，用 LaunchAgent 的行為最確定、也最容易除錯。

未來若完成 Developer ID 簽章與 Apple 公證，可以再遷移到 SMAppService，
讓 FanLite 出現在「系統設定 → 一般 → 登入項目」。

## 開機到風扇控制的時間線

1. **開機**：`launchd` 啟動 root LaunchDaemon
   `/Library/LaunchDaemons/one.leaper.smctl.daemon.plist`
   （`RunAtLoad = true`、`KeepAlive = true`）。
2. **登入畫面前**：`smctld` 讀取 `/etc/smctl/config.toml`。本機已將
   `[fan] profile` 設為 `"auto"`，所以此時風扇先交還 macOS 控制，
   不會在登入畫面全速運轉。

   > 這是一次性的系統設定，不是 FanLite 每次啟動都會改寫。若你的
   > `smctld` 曾被設成 `full`，請執行一次
   > `smctl fan profile auto`，再讓 FanLite 套用日常轉速。
3. **使用者登入**：`launchd` 讀取
   `~/Library/LaunchAgents/io.github.boday.fanlite.plist`，啟動 FanLite。
4. **登入後 2 秒內**：FanLite 讀取 CPU 最高溫；若「80°C 自動增壓」開啟，
   立即套用 3,000 RPM，或依溫度套用 4,500 / 5,500 / 6,000 RPM。
5. **持續控制**：溫控每 2 秒取樣一次；降階需低於出場門檻並停留 45 秒，
   避免風扇反覆升降。

## 使用方式

### 圖形介面

- 控制面板：勾選「登入時自動啟動 FanLite」。
- 選單列：FanLite →「開機自動啟動」。

### 命令列

```bash
APP="$HOME/Applications/FanLite.app"

# 啟用
"$APP/Contents/MacOS/FanLite" --enable-login-item

# 停用
"$APP/Contents/MacOS/FanLite" --disable-login-item

# 查詢（第一行 enabled/disabled，第二行 plist 路徑）
"$APP/Contents/MacOS/FanLite" --login-item-status
```

## 驗證方式

```bash
plutil -p ~/Library/LaunchAgents/io.github.boday.fanlite.plist
launchctl print gui/$(id -u)/io.github.boday.fanlite
```

`launchctl print` 應顯示：

```text
state = running
pid = <PID>
runs = <次數>
```

日誌：

```bash
tail -f ~/Library/Logs/FanLite.log
```

溫控轉折會單獨寫入：

```text
2026-11-06T14:26:20Z thermal=80.8C target=4500
2026-11-06T14:28:20Z thermal=67.9C target=3000
```

## 實測紀錄

- 以 `launchctl bootstrap gui/501 ~/Library/LaunchAgents/io.github.boday.fanlite.plist`
  模擬登入：`state = running`，PID 由 launchd 接管（`ppid = 1`）。
- `launchctl kickstart -k`：`runs` 由 1 增加到 2，PID 更新，App 重新啟動。
- 停用：plist 移除、`launchctl bootout` 後無 FanLite 行程。
- 重新啟用：plist 重建、`plutil -lint` 通過、再次 bootstrap 成功。

> 未實際執行整機重開機（會中斷目前工作階段）；上述測試使用與登入相同的
> launchd bootstrap 機制。`smctld` 的 `RunAtLoad` / `KeepAlive` 已由
> `/Library/LaunchDaemons/one.leaper.smctl.daemon.plist` 確認。

## 限制與注意事項

- **只在使用者登入後生效**：FileVault 解鎖前、登入畫面沒有 FanLite 溫控。
- **多使用者**：每個使用者有各自的 LaunchAgent；FanLite 會搶 SMC，
  建議只讓一個使用者啟用。
- **App 搬移**：plist 記錄目前執行檔絕對路徑；搬移 App 後需重新勾選。
- **未簽章/公證**：首次開啟仍可能被 Gatekeeper 阻擋，需手動放行一次。
- **未安裝 smctl helper**：登入後只會監看溫度，不會控制風扇。
- **關閉自動啟動**：取消勾選，或執行
  `launchctl bootout gui/$(id -u)/io.github.boday.fanlite` 後刪除 plist。
