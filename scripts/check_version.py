#!/usr/bin/env python3
"""版本單一來源防呆檢查：VERSION 必須是唯一版號來源。

檢查項目：
1. VERSION 存在且符合 semantic version。
2. README badge、CHANGELOG 最新條目與 VERSION 一致。
3. build.sh / package.sh / test.sh 不得出現硬編碼舊版號常數。
4. 三支 script 都從 VERSION 讀取（環境變數覆寫除外）。

exit 0 = 全過；任一失敗列印 FAIL 並 exit 1。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION_FILE = ROOT / "VERSION"
SEMVER = re.compile(r"^\d+\.\d+\.\d+$")
SCRIPTS = ["scripts/build.sh", "scripts/package.sh", "scripts/test.sh"]

fails: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"[{'PASS' if ok else 'FAIL'}] {name}{(': ' + detail) if detail else ''}")
    if not ok:
        fails.append(name)


version = (
    VERSION_FILE.read_text(encoding="utf-8").strip() if VERSION_FILE.exists() else ""
)
check("VERSION 存在且為 semantic version", bool(SEMVER.match(version)), repr(version))

readme = (ROOT / "README.md").read_text(encoding="utf-8")
badge = re.search(r"version-(\d+\.\d+\.\d+)-blue", readme)
check(
    "README badge 與 VERSION 一致",
    bool(badge and badge.group(1) == version),
    f"badge={badge.group(1) if badge else 'missing'}",
)

changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
entry = re.search(r"^## \[(\d+\.\d+\.\d+)\]", changelog, re.M)
check(
    "CHANGELOG 最新條目與 VERSION 一致",
    bool(entry and entry.group(1) == version),
    f"changelog={entry.group(1) if entry else 'missing'}",
)

for name in SCRIPTS:
    text = (ROOT / name).read_text(encoding="utf-8")
    hardcoded = re.findall(r"(?<![\w.])0\.4\.0(?![\w.])", text)
    check(f"{name} 無 0.4.0 硬編碼", not hardcoded, f"found={len(hardcoded)}")
    check(f"{name} 從 VERSION 讀取", "VERSION" in text and "cat" in text)

print(f"\ncheck_version: FAIL={len(fails)}")
sys.exit(1 if fails else 0)
