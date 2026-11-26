#!/usr/bin/env python3
"""Structure check for Stiže: keeps the codebase from silently swelling.

Zero dependencies (stdlib only), runs in CI and locally:

    python3 tool/structure/check.py            # report findings
    python3 tool/structure/check.py --strict   # exit 1 on any new finding
    python3 tool/structure/check.py --update-baseline

Checks (each finding has a short code, like a linter):

  big-file        a source file over the line limit. Files that were already
                  over it are recorded in baseline.json with their size; they
                  may shrink but not grow (a ratchet), new files may not cross.
  dead-file       a Dart file nothing reaches from main.dart (conditional
                  imports included).
  dead-widget     a public Dart class only its own file mentions.
  dead-export     a backend export nothing else imports or uses.
  unused-string   an l10n key (app_en.arb) no Dart code reads.
  duplicate       the same 12+ normalised lines in two places: a pattern that
                  should be one shared function or component.

Findings in baseline.json are known debt: reported as a total, not failed.
The point is direction: every change should leave the numbers equal or lower.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASELINE = Path(__file__).with_name("baseline.json")

MAX_LINES = 500
DUP_WINDOW = 12

APP_LIB = ROOT / "app" / "lib"
BACKEND_SRC = ROOT / "backend" / "src"
BACKEND_TEST = ROOT / "backend" / "test"
APP_TEST = ROOT / "app" / "test"

SKIP_PARTS = ("/l10n/", ".g.dart", ".freezed.dart")


def rel(p: Path) -> str:
    return p.relative_to(ROOT).as_posix()


def sources() -> list[Path]:
    files = list(APP_LIB.rglob("*.dart")) + list(BACKEND_SRC.rglob("*.ts"))
    return sorted(f for f in files if not any(s in f.as_posix() for s in SKIP_PARTS))


def line_count(p: Path) -> int:
    return sum(1 for _ in p.open(encoding="utf-8"))


# ---- big-file ---------------------------------------------------------------

def big_files() -> dict[str, int]:
    return {rel(f): n for f in sources() if (n := line_count(f)) > MAX_LINES}


# ---- dead-file (Dart reachability) -----------------------------------------

_DART_DIRECTIVE = re.compile(r"^\s*(?:import|export|part)\s+'([^']+)'([^;]*);", re.M | re.S)
_CONDITIONAL = re.compile(r"if\s*\([^)]*\)\s*'([^']+)'")


def _resolve_dart(src_file: Path, target: str) -> Path | None:
    if target.startswith("dart:"):
        return None
    if target.startswith("package:"):
        if not target.startswith("package:stize/"):
            return None
        return APP_LIB / target[len("package:stize/"):]
    return (src_file.parent / target).resolve()


def dead_dart_files() -> list[str]:
    files = {f.resolve() for f in APP_LIB.rglob("*.dart")}
    edges: dict[Path, list[Path]] = {}
    for f in files:
        text = f.read_text(encoding="utf-8")
        out = []
        for m in _DART_DIRECTIVE.finditer(text):
            targets = [m.group(1)] + _CONDITIONAL.findall(m.group(2))
            for t in targets:
                p = _resolve_dart(f, t)
                if p is not None:
                    out.append(p.resolve())
        edges[f] = out
    seen: set[Path] = set()
    stack = [(APP_LIB / "main.dart").resolve()]
    while stack:
        f = stack.pop()
        if f in seen or f not in files:
            continue
        seen.add(f)
        stack.extend(edges.get(f, []))
    return sorted(rel(f) for f in files - seen if "/l10n/" not in f.as_posix())


# ---- dead-widget -------------------------------------------------------------

_DART_CLASS = re.compile(r"^(?:abstract\s+|final\s+|sealed\s+|base\s+)*(?:class|enum|mixin)\s+([A-Z]\w*)", re.M)


def dead_dart_classes() -> list[str]:
    files = [f for f in APP_LIB.rglob("*.dart") if "/l10n/" not in f.as_posix()]
    texts = {f: f.read_text(encoding="utf-8") for f in files}
    out = []
    for f, text in texts.items():
        for name in _DART_CLASS.findall(text):
            word = re.compile(rf"\b{name}\b")
            if any(word.search(t) for g, t in texts.items() if g != f):
                continue
            own = len(word.findall(text))
            # Declaration + const constructor and nothing else: never used.
            # State classes are reached through createState().
            if own <= 2 and not name.endswith("State"):
                out.append(f"{rel(f)}:{name}")
    return sorted(out)


# ---- dead-export (backend) ---------------------------------------------------

_TS_EXPORT = re.compile(
    r"^export\s+(?:async\s+)?(?:function|const|let|class|interface|type|enum)\s+(\w+)", re.M
)


def dead_ts_exports() -> list[str]:
    src = sorted(BACKEND_SRC.rglob("*.ts"))
    texts = {f: f.read_text(encoding="utf-8") for f in src}
    tests = "\n".join(f.read_text(encoding="utf-8") for f in BACKEND_TEST.rglob("*.ts")) if BACKEND_TEST.exists() else ""
    out = []
    for f, text in texts.items():
        if f.name.endswith(".d.ts"):
            continue
        for name in _TS_EXPORT.findall(text):
            word = re.compile(rf"\b{name}\b")
            used_elsewhere = any(word.search(t) for g, t in texts.items() if g != f)
            if used_elsewhere:
                continue
            # Used inside its own file only: the export keyword is noise but the
            # code is alive. Flag only when the name appears once (the export).
            if len(word.findall(text)) > 1:
                continue
            tag = " (tests only)" if word.search(tests) else ""
            out.append(f"{rel(f)}:{name}{tag}")
    return sorted(out)


# ---- unused-string -------------------------------------------------------------

def unused_strings() -> list[str]:
    arb = APP_LIB / "l10n" / "app_en.arb"
    if not arb.exists():
        return []
    keys = [k for k in json.loads(arb.read_text(encoding="utf-8")) if not k.startswith("@")]
    code = "\n".join(
        f.read_text(encoding="utf-8") for f in APP_LIB.rglob("*.dart") if "/l10n/" not in f.as_posix()
    )
    return sorted(k for k in keys if not re.search(rf"\.{k}\b", code))


# ---- duplicate -------------------------------------------------------------------

_TRIVIAL = re.compile(r"^[\s{}()\[\],;]*$|^\s*(//|///|\*|import |export |part )")


def duplicates() -> list[str]:
    windows: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for f in sources():
        lines = f.read_text(encoding="utf-8").splitlines()
        norm = [(i + 1, re.sub(r"\s+", " ", l.strip())) for i, l in enumerate(lines)]
        norm = [(n, l) for n, l in norm if not _TRIVIAL.match(l)]
        for i in range(len(norm) - DUP_WINDOW + 1):
            chunk = "\n".join(l for _, l in norm[i : i + DUP_WINDOW])
            h = hashlib.sha1(chunk.encode()).hexdigest()
            windows[h].append((rel(f), norm[i][0]))
    # Collapse overlapping windows into one finding per pair of files/regions.
    found: dict[tuple[str, str], tuple[int, int]] = {}
    for locs in windows.values():
        if len(locs) < 2:
            continue
        a, b = locs[0], locs[1]
        if a[0] == b[0] and abs(a[1] - b[1]) < DUP_WINDOW:
            continue
        key = (a[0], b[0])
        if key not in found:
            found[key] = (a[1], b[1])
    return sorted(f"{a}:{la} = {b}:{lb}" for (a, b), (la, lb) in found.items())


# ---- driver ------------------------------------------------------------------------

def collect() -> dict:
    return {
        "big-file": big_files(),
        "dead-file": dead_dart_files(),
        "dead-widget": dead_dart_classes(),
        "dead-export": dead_ts_exports(),
        "unused-string": unused_strings(),
        "duplicate": duplicates(),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true", help="exit 1 on new findings")
    ap.add_argument("--update-baseline", action="store_true")
    args = ap.parse_args()

    now = collect()
    if args.update_baseline:
        BASELINE.write_text(json.dumps(now, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"baseline written: {rel(BASELINE)}")
        return 0

    base = json.loads(BASELINE.read_text(encoding="utf-8")) if BASELINE.exists() else {}
    new_findings = 0
    for code, items in now.items():
        known = base.get(code, {} if code == "big-file" else [])
        if code == "big-file":
            fresh = [
                f"{f} {n} lines (limit {MAX_LINES}" + (f", was {known[f]})" if f in known else ")")
                for f, n in items.items()
                if f not in known or n > known[f]
            ]
            debt = len(items)
        else:
            fresh = [i for i in items if i not in known]
            debt = len(items)
        for f in fresh:
            print(f"::warning::{code}: {f}" if not args.strict else f"error {code}: {f}")
        new_findings += len(fresh)
        print(f"{code}: {debt} total, {len(fresh)} new")

    total_lines = sum(line_count(f) for f in sources())
    print(f"source lines (app/lib + backend/src, no l10n): {total_lines}")
    if new_findings:
        print(f"{new_findings} new finding(s): fix them or, if deliberate, run --update-baseline")
    return 1 if (args.strict and new_findings) else 0


if __name__ == "__main__":
    sys.exit(main())
