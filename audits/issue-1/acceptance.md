# Issue #1 — 逐項驗收表（DoD 13/13）

日期：2026-11-24。任何一項 FAIL 即不得發版。完整命令輸出見 `round-1-functional.md`、`round-2-boundary.md`、`round-3-ops.md`。

| # | 指標 | 結果 | 證據 |
|---|---|---|---|
| 1 | `VERSION` 存在且為 `0.5.0` | **PASS** | `cat VERSION` → `0.5.0`；`check_version.py` 第一項 PASS |
| 2 | 三支 script 無 `0.4.0` 字面常數 | **PASS** | `check_version.py` 三行 `無 0.4.0 硬編碼: found=0` |
| 3 | `./scripts/test.sh` 全 PASS | **PASS** | 29 項政策 PASS、sensor read、login item、version guard、`PASS: sensor enumeration (38 sensors)`、`PASS: curve status (default)`，`exit=0` |
| 4 | Linux 政策測試可編譯並全 PASS | **PASS** | `swiftc -O Sources/ThermalPolicy.swift Sources/ThermalPolicyTests.swift Tests/Linux/main.swift` compile_exit=0；`ALL POLICY TESTS PASS` |
| 5 | guardrail 含 PR 關聯檢查／自動 revert／開 Issue | **PASS** | `grep -c 'id: detect\|id: revert\|File issue'` → 3；YAML 解析 OK |
| 6 | test workflow 在 push 與 PR 皆觸發 | **PASS** | `.github/workflows/test.yml` 的 `on:` 同時含 `push.branches:[main]` 與 `pull_request`；YAML OK |
| 7 | 感測器選擇：38 個 sensor，無效 key 回退 | **PASS** | `--sensors` 輸出 38 行；`--once` 注入無效 key → `sensor=auto`，溫度取最高溫；選單 delegate 與 UserDefaults 持久化已實作 |
| 8 | 自訂曲線持久化與防呆 | **PASS** | `ThermalCurve.isValid` + initializer 回退；無效 JSON → `--curve-status` 回 `default`；29 項測試含 `custom 75 warm`、`invalid curve falls back` |
| 9 | 歷史圖表 60 筆 ring buffer | **PASS** | `HistoryView.capacity = 60`，`append` 超過即 `removeFirst()`；控制面板每 2 秒 refresh 寫入 |
| 10 | 三輪交叉巡檢證據檔 | **PASS** | `audits/issue-1/round-1-functional.md`、`round-2-boundary.md`、`round-3-ops.md` 皆存在且含命令輸出 |
| 11 | 逐項驗收 13/13 PASS | **PASS** | 本表 13 列全 PASS；無 FAIL、無 BLOCK（BLOCKED 項目已於 DoD 外單獨揭露） |
| 12 | 文件同步：Issue／CHANGELOG／README／release notes／docs／QMD | **PASS** | Issue #1 三階段 comment；`CHANGELOG.md` 0.5.0 條目；README badge／功能／Roadmap／已知限制更新；`docs/iteration-v050-plan.md`、`docs/releases/v0.5.0.md`、`docs/auto-start.md` 更新；QMD update／embed／search 輸出存於 `audits/issue-1/qmd-index.txt` |
| 13 | 技能沉澱於 `.kiro/skills` 且格式驗證 | **PASS** | `~/.kiro/skills/fanlite-iteration/SKILL.md`（94 行，frontmatter 完整）；`verify-skills-v3.py` 對該技能全 PASS（全體 42 技能中唯一 FAIL 為既有 `answer-me-with-html` 的觸發描述，非本次新增） |

## 額外驗證（非 DoD，但已執行）

- Release DMG／ZIP SHA-256：`OK`；DMG 可掛載、含 `/Applications` 捷徑、App 版本 `0.5.0`、政策測試 PASS、38 sensors。
- 實機安裝後 launchd：`state = running`、`runs = 1`、`pid = 2423`；日誌含 `thermal=67.5C target=3000`。
- 真實負載 24 個 `yes`：90 秒最高約 72.4°C，未達 80°C，**不宣稱真實增壓驗證**；閾值由 29 項政策測試覆蓋。

## 殘留風險（如實揭露）

1. `boday/boday-opencode` 工作區有非本次任務的 uncommitted 變更（policy schema 遷移），且 governance 因既有 `~/.kiro/skills/answer-me-with-html` 符號連結 FAIL。新技能 `fanlite-iteration` 尚未寫入該 repo 的 `skills-policy.json` allowlist；需待該 in-flight 任務結束後由負責 session 補宣告（`expectedGlobalCount` 40 → 41）並 sync，避免覆蓋他人工作。
2. Apple notarization 需 Developer ID 與 Apple 帳號；Intel 唯讀模式需 Intel 硬體，兩項維持 BLOCKED，已寫入 release notes。
3. v0.4.0 之前的 5 個 commit 未走 PR（當時尚無 guardrail），workflow 啟用後才強制；歷史紀錄不追溯改寫。
