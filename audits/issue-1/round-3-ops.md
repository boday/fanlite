# Round 3 — 維運架構巡檢（2026-11-24 17:01–17:02 CST）

對照 DoD #4–#6、#10–#13。方法：Release 打包／掛載、CI 本機模擬、實機安裝與 launchd 讀回。

## 證據

```text
$ ./scripts/package.sh
built: .../dist/FanLite.app
package: .../FanLite-v0.5.0-macos-arm64.zip
package: .../FanLite-v0.5.0-macos-arm64.dmg

$ (cd dist && shasum -a 256 -c *.sha256)
FanLite-v0.5.0-macos-arm64.dmg: OK
FanLite-v0.5.0-macos-arm64.zip: OK

$ hdiutil attach dist/FanLite-v0.5.0-macos-arm64.dmg -nobrowse -readonly
mount=/Volumes/FanLite
Applications symlink OK
CFBundleShortVersionString: 0.5.0
$ <DMG app>/FanLite --policy-test | tail -n 1
ALL POLICY TESTS PASS
$ <DMG app>/FanLite --sensors | wc -l
38

# CI 本機模擬（與 test.yml 相同步驟）
$ python3 scripts/check_version.py | tail -n 1
check_version: FAIL=0
$ swiftc ... && /tmp/fanlite-policy-test | tail -n 1
ALL POLICY TESTS PASS
$ python3 -c "import yaml; ..."
YAML OK
$ git diff --check
git diff --check OK
$ grep -c 'id: detect\|id: revert\|File issue' .github/workflows/main-push-guardrail.yml
3

# 實機安裝 v0.5.0 並由 launchd 啟動
$ ditto <DMG>/FanLite.app ~/Applications/FanLite.app
$ launchctl kickstart -k gui/501/io.github.boday.fanlite
state = not running / job state = spawn failed      <-- 發現問題
$ codesign -vvv --deep --strict ~/Applications/FanLite.app
valid on disk / satisfies its Designated Requirement
$ launchctl bootout gui/501/io.github.boday.fanlite
$ launchctl bootstrap gui/501 ~/Library/LaunchAgents/io.github.boday.fanlite.plist
state = running
program = /Users/boday/Applications/FanLite.app/Contents/MacOS/FanLite
runs = 1
pid = 2423
$ tail -n 3 ~/Library/Logs/FanLite.log
... cpu=53°C sensor=最高溫 fans=3013/3020 package=13.0W
... thermal=67.5C target=3000
```

## 根因與處置

`spawn failed` 不是簽章或程式碼問題：codesign strict 驗證 PASS，binary 直接執行成功。
根因是 **在 launchd job 仍 loaded 時以 ditto 替換 App bundle，job 快取的 cdhash 與新執行檔不符**。
處置：升級流程必須 `bootout` → 替換 → `bootstrap`，不能只靠 `kickstart -k`。
此知識已寫入 `docs/auto-start.md` 與技能 `~/.kiro/skills/fanlite-iteration/`。

## 補充：真實負載

24 個 `yes` 滿載程序下，90 秒內最高約 72.4°C，未達 80°C 增壓點；
本次不宣稱「真實負載觸發增壓」。80／88／90°C 門檻由 29 項政策測試驗證。
v0.4.0 時期的 20 程序實測增壓／回退紀錄仍保留於
`docs/releases/v0.4.0.md`，未受本次重構影響。
