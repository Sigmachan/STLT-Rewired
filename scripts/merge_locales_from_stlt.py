#!/usr/bin/env python3
"""Merge locale strings from local Sigmachan STLT into STLT-Rewired.

Usage:
  python scripts/merge_locales_from_stlt.py
  python scripts/merge_locales_from_stlt.py --stlt F:/STLT --locales uk ru de
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

DEFAULT_STLT = Path(r"F:/STLT")
REWIRED_LOCALES = Path(__file__).resolve().parent.parent / "backend" / "locales"
PLACEHOLDER = "translation missing"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def merge_locale(stlt_path: Path, rewired_path: Path, en_strings: dict[str, str]) -> tuple[int, int]:
    if not stlt_path.exists():
        print(f"  skip {stlt_path.name}: source missing")
        return 0, 0

    src = load_json(stlt_path)
    meta = src.get("_meta") or {"code": stlt_path.stem}
    src_strings = src.get("strings", src)

    existing = load_json(rewired_path) if rewired_path.exists() else {"_meta": meta, "strings": {}}
    out_strings: dict[str, str] = {}

    imported = 0
    for key in en_strings:
        candidate = src_strings.get(key)
        if candidate and candidate != PLACEHOLDER:
            out_strings[key] = candidate
            imported += 1
        else:
            prev = (existing.get("strings") or {}).get(key)
            if prev and prev != PLACEHOLDER:
                out_strings[key] = prev
            else:
                out_strings[key] = PLACEHOLDER

    out = {
        "_meta": {
            **meta,
            "code": stlt_path.stem,
        },
        "strings": out_strings,
    }
    rewired_path.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return imported, len(out_strings)


def main() -> None:
    parser = argparse.ArgumentParser(description="Merge STLT locale files into Rewired")
    parser.add_argument("--stlt", type=Path, default=DEFAULT_STLT, help="Local STLT repo root")
    parser.add_argument(
        "--locales",
        nargs="+",
        default=["uk"],
        help="Locale codes to merge (must exist under backend/locales in STLT)",
    )
    args = parser.parse_args()

    stlt_locales = args.stlt / "backend" / "locales"
    en_path = REWIRED_LOCALES / "en.json"
    if not en_path.exists():
        raise SystemExit(f"Missing {en_path}")
    en_strings = load_json(en_path).get("strings", {})

    print(f"STLT locales: {stlt_locales}")
    print(f"Rewired keys: {len(en_strings)}")
    for code in args.locales:
        imported, total = merge_locale(
            stlt_locales / f"{code}.json",
            REWIRED_LOCALES / f"{code}.json",
            en_strings,
        )
        print(f"  {code}: {imported}/{total} from STLT (kept existing where STLT missing)")


if __name__ == "__main__":
    main()
