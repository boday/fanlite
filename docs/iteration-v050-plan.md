---
tags: [iteration, planning, 5w2h, dod, fanlite]
version: "0.5.0"
status: active
type: planning
---

# FanLite v0.5.0 迭代計畫（Issue #1 四缺口）

> 建立時間：2026-11-24。任務隔離：worktree `fanlite-v050-issue1`、branch `feat/issue-1-v050-iteration`、session `ses_e506f3e1affe0lO3kG6ps9WHwT`。

## 一、5W2H 現況盤點

| 維度 | 現況與問題本質 | 邊界條件／證據 |
|---|---|---|
| **What** | 四個缺口：①零 CI 與零 branch protection；②版本號硬編碼三處；③零 Issue／PR 軌跡；④Roadmap 5 項未完成。 | `.github/workflows` = none；`branches/main/protection` → 404；`build.sh`/`package.sh`/`test.sh` 各含 `0.4.0`；`gh issue list`/`pr list` = 0；README Roadmap 未勾選 5 項。 |
| **Why** | `realivy0730` 已取得 write 邀請（2026-11-24T05:48:34Z），但無任何自動閘門可防止直推；版本散落使「測 A 版、發 B 版」風險真實存在；缺乏軌跡使外部協作者無法接手。 | sibling `boday-kiro-cli`／`boday-codex-cli` 皆有 `main-push-guardrail.yml`；GitHub Free 無法用 server-side ruleset。 |
| **Who** | 執行：OpenCode（本 session）；驗收：需求者／repo owner `boday`；協作者：`realivy0730`（write，待接受）；受影響使用者：FanLite 本機使用者。 | 管理員權限 `viewerPermission: ADMIN`、`viewerCanAdminister: true`。 |
| **When** | 盤點 2026-11-24 16:56 CST；M1 規劃完成即起；M2 兩輪巡檢；M3 第三輪＋release；M4 結案。 | v0.4.0 發佈於 2026-11-06，距今 18 天，功能穩定、無 hotfix 需求。 |
| **Where** | repo：`boday/fanlite`（public）。工作隔離：`/Users/boday/worktrees/fanlite-v050-issue1`。技能沉澱：`~/.kiro/skills/fanlite-iteration/`。 | `~/.kiro` 已由 OpenCode 管理，但技能新增仍需 Issue／diff／測試／備份。 |
| **How** | ①移植 guardrail 並新增可攜式政策測試 CI；②建立 `VERSION` 單一來源，三支 script 統一讀取；③本迭代全程 branch／PR／Issue／audits 軌跡；④Roadmap 可實作項（感測器選擇、風扇曲線、歷史圖表）落地，需憑證或硬體項（notarization、Intel）標記 BLOCKED。 | CI 在 ubuntu-latest 用 swiftc 編譯 `ThermalPolicy` 純邏輯測試；AppKit 相關測試留在 macOS `scripts/test.sh`。 |
| **How much** | 版本 v0.4.0 → v0.5.0（minor：新增功能）。預計新增／修改約 15 檔；DoD 13 項全數通過方可 release。 | 不變更 v0.4.0 Release 資產；不直接在 main 推送。 |

## 二、完整解決方案與流程

### 模組 A — CI guardrail（缺口 1）

1. `.github/workflows/main-push-guardrail.yml`：移植 sibling repo 的直接推送偵測，檢查每次 push 到 main 的 commit 是否有已合併 PR 關聯，違規自動 revert 並開 Issue。
2. `.github/workflows/test.yml`：push／PR 皆執行：
   - `python3 scripts/check_version.py`：VERSION 與 README badge、CHANGELOG 標題、scripts 引用一致，且 script 中不得再出現硬編碼版本常數；
   - `swiftc -O Sources/ThermalPolicy.swift Sources/ThermalPolicyTests.swift Tests/Linux/main.swift -o /tmp/fanlite-policy-test` 並執行；
   - `git diff --check` 與 YAML 語法解析。
3. `Sources/ThermalPolicyTests.swift`：將 `selfTest()` 抽成 extension，讓 macOS App 與 Linux CI 共用同一份測試邏輯（不重複定義）。
4. `Tests/Linux/main.swift`：Linux 進入點，呼叫 `ThermalPolicy.selfTest()`。

### 模組 B — 版本單一化（缺口 2）

1. 新增 `VERSION`（內容 `0.5.0`）。
2. `build.sh`／`package.sh`／`test.sh` 改為 `VERSION="${VERSION:-$(cat "$ROOT/VERSION")}"`（`test.sh` 不再寫死）。
3. `scripts/check_version.py` 為防呆閘門：比對 VERSION、README badge、CHANGELOG 最新條目、安裝後 App 版本（本機 run）。

### 模組 C — Issue／PR 軌跡（缺口 3）

1. 本迭代所有變更走 worktree branch → PR → squash merge（commit 自動帶 `(#N)`）。
2. `audits/issue-1/` 保存三輪巡檢與逐項驗收證據。
3. Issue #1 於規劃、執行、完成三階段即時更新。

### 模組 D — Roadmap 可實作項（缺口 4）

1. **溫度感測器選擇**：`Reading` 增加 `sensors`；選單新增「溫度來源」子選單（自動最高溫＋各感測器），選擇存入 UserDefaults；狀態列與溫控皆使用所選來源。
2. **風扇曲線編輯器**：`ThermalPolicy` 參數化四組進入／退出門檻與 RPM；控制面板提供 4 組溫度／RPM 輸入與「套用曲線」；以 JSON 存 UserDefaults；`--policy-test` 加入自訂曲線邊界測試。
3. **歷史溫度圖表**：控制面板加入 sparkline view， plot 最近 60 筆（2 秒取樣約 2 分鐘）溫度。
4. **BLOCKED（明確揭露）**：Apple notarization 需 Developer ID 與 Apple 帳號憑證；Intel 唯讀模式需 Intel 硬體驗證。兩項寫入 `docs/releases/v0.5.0.md` 的已知限制，不偽稱完成。

### 時程里程碑

| 里程碑 | 內容 | 完成條件 |
|---|---|---|
| M1 | 5W2H／DoD 文件、Issue 更新、worktree 建立 | 本檔與 Issue comment 可讀 |
| M2 | 模組 A/B/C 實作＋第一輪（功能邏輯）與第二輪（異常邊界）巡檢 | CI 本機模擬 PASS、版本檢查 PASS、政策測試 PASS |
| M3 | 模組 D 實作＋第三輪（維運架構）巡檢、逐項驗收 | 13 項 DoD 全數 PASS，證據寫入 audits |
| M4 | PR／merge／v0.5.0 tag／Release／skill 沉澱／Issue 結案 | 遠端 tag 與 Release 讀回成功 |

## 三、驗收指標清單（DoD）

| # | 指標（可量化） | 驗證方式 | 防呆機制 |
|---|---|---|---|
| 1 | `VERSION` 存在且為 `0.5.0` | `cat VERSION` | `check_version.py` 比對失敗即 exit 1 |
| 2 | 三支 script 無 `0.4.0` 字面常數 | `grep -R '0\.4\.0' scripts` → 0 | CI 靜態檢查 |
| 3 | `./scripts/test.sh` 全 PASS（≥22 項政策＋讀取＋login item） | 本機執行 | CI  mirrored 政策測試 |
| 4 | Linux 政策測試可編譯並全 PASS | `swiftc` + run | CI job 必經 |
| 5 | guardrail workflow 存在且含 PR 關聯檢查、自動 revert、開 Issue 三段 | `grep` 三個 step id | YAML 解析＋code review |
| 6 | test workflow 在 push 與 PR 皆觸發 | YAML `on:` 檢查 | CI 實際 run 讀回 |
| 7 | 感測器選擇：傳回 sensor 清單，選擇後狀態列與溫控同步 | CLI `--sensors`／`--once` 輸出 | 無效 key 回退自動 |
| 8 | 自訂曲線：四組閾值可持久化，重啟後讀回一致 | defaults read＋政策測試 | JSON 解析失敗回退預設 |
| 9 | 歷史圖表：60 筆緩衝，超出後 ring buffer 不增長 | 程式碼＋UI 檢查 | 上限常數 |
| 10 | 三輪交叉巡檢皆產出證據檔 | `audits/issue-1/round-*.md` | 缺檔即視為未完成 |
| 11 | 逐項驗收 13/13 PASS | `audits/issue-1/acceptance.md` | 任一 FAIL 不得 release |
| 12 | 文件同步：Issue #1、CHANGELOG、README、v0.5.0 release notes、docs 更新 | `git diff`＋GitHub 讀回 | PR checklist |
| 13 | 技能沉澱：`~/.kiro/skills/fanlite-iteration/SKILL.md` 存在且通過 v3 格式驗證 | `verify-skills-v3.py` | 新增技能需 governance 檢查 |
