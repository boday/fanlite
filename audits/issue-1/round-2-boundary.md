# Round 2 — 異常邊界巡檢（2026-11-24 17:01 CST）

對照 DoD #7–#9 的防呆機制。方法：注入無效持久化資料、移除相依 binary。

## 證據

```text
# 無效曲線（寫入非 JSON 到兩個可能的 defaults domain）
$ defaults write FanLite thermalCurve -string 'not-json'
$ defaults write io.github.boday.fanlite thermalCurve -string 'not-json'
$ "$APP" --curve-status
default                        # 正確回退，未崩潰

# 無效感測器 key
$ defaults write FanLite sensorKey -string 'NO_SUCH_SENSOR'
$ "$APP" --once
cpu_max=56.4C fans=3001/2994RPM package=11.1W sensor=auto
                               # 溫度回退為最高溫，且有明確 fallback 標記

# 移除 bundled smctl + 兩個 fallback 路徑
$ mv /Users/boday/fanlite/bin/smctl /Users/boday/fanlite/bin/smctl.off
$ mv ~/worktrees/fanlite-v050-issue1/bin/smctl .../bin/smctl.off
$ <app-without-bundled-smctl>/Contents/MacOS/FanLite --once
read failed
exit=1                         # 乾淨失敗，非零退出，可供 CI 攔截
# 兩個 smctl 已還原並再次 --once 成功
```

## 附加發現（已修正）

第一版 `--once` 在 sensor key 無效時仍印出原始 key（`sensor=NO_SUCH_SENSOR`），
容易被誤讀為感測器存在。已改為解析成功才印 key，否則印 `auto(fallback)`；
重新建置後驗證回傳 `sensor=auto`。

## 判定

- 三種異常注入皆正確降級，無 crash、無無限迴圈。
- `ThermalCurve.isValid` 同時擋住溫度倒掛與 RPM 遞減；
  `ThermalPolicy(curve:)` 對無效曲線回退預設，雙層防呆。
- 感測器 ring buffer 固定在 `HistoryView.capacity = 60`，超出即 `removeFirst()`，
  記憶體不隨執行時間線性增長。
