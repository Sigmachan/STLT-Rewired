#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEBKIT = ROOT / ".millennium" / "Dist" / "webkit.js"
LUATOOLS = ROOT / "public" / "luatools.js"

START = "try{(0,eval)("
END = ")}catch(err){console.error(\"[LuaTools] embedded webkit bootstrap failed\",err)}"
SOURCE_URL = "\n//# sourceURL=luatools-embedded.js\n"


def main() -> None:
    webkit = WEBKIT.read_text(encoding="utf-8")
    luatools = LUATOOLS.read_text(encoding="utf-8") + SOURCE_URL

    start = webkit.find(START)
    if start == -1:
        raise SystemExit(f"Cannot find LuaTools embedded bootstrap marker in {WEBKIT}")
    payload_start = start + len(START)
    payload_end = webkit.find(END, payload_start)
    if payload_end == -1:
        raise SystemExit(f"Cannot find LuaTools embedded bootstrap end marker in {WEBKIT}")

    updated = webkit[:payload_start] + json.dumps(luatools) + webkit[payload_end:]
    WEBKIT.write_text(updated, encoding="utf-8")
    print(f"Embedded {LUATOOLS.relative_to(ROOT)} into {WEBKIT.relative_to(ROOT)} ({len(luatools)} bytes)")


if __name__ == "__main__":
    main()
