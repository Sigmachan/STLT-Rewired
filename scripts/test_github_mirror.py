#!/usr/bin/env python3
"""Unit tests for github_mirror URL mapping (Lua logic mirror)."""

from __future__ import annotations

import re
import unittest


def jsdelivr_from_raw(url: str) -> str:
    if "raw.githubusercontent.com/" not in url:
        return ""
    tail = url.split("raw.githubusercontent.com/", 1)[-1].lstrip("/")
    parts = tail.split("/")
    if len(parts) < 4:
        return ""
    owner, repo = parts[0], parts[1]
    rest = parts[2:]
    if len(rest) >= 3 and rest[0] == "refs" and rest[1] in ("heads", "tags"):
        ref, path = rest[2], "/".join(rest[3:])
    else:
        ref, path = rest[0], "/".join(rest[1:])
    if not path:
        return ""
    return f"https://cdn.jsdelivr.net/gh/{owner}/{repo}@{ref}/{path}"


class TestJsDelivr(unittest.TestCase):
    def test_simple_main_path(self):
        url = "https://raw.githubusercontent.com/qwe213312/k25FCdfEOoEJ42S6/main/123_456.manifest"
        self.assertEqual(
            jsdelivr_from_raw(url),
            "https://cdn.jsdelivr.net/gh/qwe213312/k25FCdfEOoEJ42S6@main/123_456.manifest",
        )

    def test_refs_heads(self):
        url = "https://raw.githubusercontent.com/madoiscool/lt_api_links/refs/heads/main/load_free_manifest_apis"
        self.assertEqual(
            jsdelivr_from_raw(url),
            "https://cdn.jsdelivr.net/gh/madoiscool/lt_api_links@main/load_free_manifest_apis",
        )

    def test_non_github(self):
        self.assertEqual(jsdelivr_from_raw("https://example.com/x"), "")


if __name__ == "__main__":
    unittest.main()
