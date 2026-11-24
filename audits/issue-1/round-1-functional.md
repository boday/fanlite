# Round 1 — 功能邏輯巡檢（2026-11-24 17:00 CST）

對照 DoD #1–#9。方法：本機 `swiftc` 無 AppKit 編譯、App CLI、版本防呆、DMG 實掛。

## 證據

```text
$ swiftc -O Sources/ThermalPolicy.swift Sources/ThermalPolicyTests.swift Tests/Linux/main.swift -o /tmp/fanlite-policy-test
compile_exit=0
$ /tmp/fanlite-policy-test | tail -n 12
PASS custom 74.9 normal: got 2500, expected 2500
PASS custom 75 warm: got 4000, expected 4000
PASS custom 85 hot: got 5000, expected 5000
PASS custom 95 critical: got 5800, expected 5800
PASS custom dwell 5s blocks exit: got 5800, expected 5800
PASS custom dwell 11s -> hot: got 5000, expected 5000
PASS invalid curve falls back: 80 warm: got 4500, expected 4500
ALL POLICY TESTS PASS          # 共 29 項

$ APP=dist/FanLite.app/Contents/MacOS/FanLite
$ "$APP" --sensors | head -n 8
TC10 TC 42.7 TC10
TC11 TC 43.5 TC11
...
sensor_count=38

$ "$APP" --once
cpu_max=64.7C fans=2983/2994RPM package=12.1W sensor=auto

$ "$APP" --curve-status
default

$ "$APP" --login-item-status | head -n 1
disabled

$ python3 scripts/check_version.py | tail -n 1
check_version: FAIL=0

$ ./scripts/test.sh | tail -n 6
[PASS] scripts/test.sh 從 VERSION 讀取
check_version: FAIL=0
PASS: version single-source guard
PASS: sensor enumeration (38 sensors)
PASS: curve status (default)
exit=0
```

## 判定

- 政策測試由 22 項擴充至 29 項，新增自訂曲線與非法曲線回退，全數 PASS。
- Linux 模式不需 AppKit 即可編譯執行，符合 CI 可攜性要求。
- 38 個感測器可列舉，`--once` 輸出含 sensor 欄位且維持既有解析格式。
- 版本防呆同時檢查 VERSION／README／CHANGELOG／三支 script，FAIL=0。
- 發現並修正：`--once` 新增欄位後 `test.sh` 的字尾 glob 比對失敗，已改為 `*"W"*`。
- 發現並修正：`--curve-status` 對無效 JSON 應回報 `default`，已加入 `curve.isValid` 檢查。
