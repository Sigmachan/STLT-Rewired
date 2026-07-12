#!/usr/bin/env python3
"""Apply Rewired branding to locale string values (keys stay for IPC compatibility)."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "backend" / "locales"

# locale code -> replacements for string VALUES (key unchanged)
PATCHES: dict[str, dict[str, str]] = {
    "de": {
        "Add via LuaTools": "Über Rewired hinzufügen",
        "Remove via LuaTools": "Über Rewired entfernen",
        "Welcome to LuaTools": "Willkommen bei Rewired",
        "common.appName": "Rewired",
        "menu.removeLuaTools": "Über Rewired entfernen",
        "menu.title": "Rewired · Menü",
        "settings.generalDescription": "Globale Rewired-Einstellungen",
        "settings.title": "Rewired · Einstellungen",
    },
    "ru": {
        "Add via LuaTools": "Добавить через Rewired",
        "Remove via LuaTools": "Удалить через Rewired",
        "Welcome to LuaTools": "Добро пожаловать в Rewired",
        "common.appName": "Rewired",
        "menu.removeLuaTools": "Удалить через Rewired",
        "menu.title": "Rewired · Меню",
        "settings.generalDescription": "Общие настройки Rewired",
        "settings.title": "Rewired · Настройки",
    },
    "uk": {
        "Add via LuaTools": "Додати через Rewired",
        "Remove via LuaTools": "Видалити через Rewired",
        "Welcome to LuaTools": "Ласкаво просимо до Rewired",
        "common.appName": "Rewired",
        "menu.removeLuaTools": "Видалити через Rewired",
        "menu.title": "Rewired · Меню",
        "settings.generalDescription": "Загальні налаштування Rewired",
        "settings.title": "Rewired · Налаштування",
    },
    "be": {
        "Add via LuaTools": "Дадаць праз Rewired",
        "Remove via LuaTools": "Выдаліць праз Rewired",
        "Welcome to LuaTools": "Сардэчна запрашаем у Rewired",
        "common.appName": "Rewired",
        "menu.removeLuaTools": "Выдаліць праз Rewired",
        "menu.title": "Rewired · Меню",
        "settings.generalDescription": "Агульныя налады Rewired",
        "settings.title": "Rewired · Налады",
    },
}


def main() -> None:
    for code, mapping in PATCHES.items():
        path = ROOT / f"{code}.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        strings = data.setdefault("strings", {})
        for key, value in mapping.items():
            if key in strings:
                strings[key] = value
            else:
                print(f"warn: {code}.json missing key {key!r}")
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"updated {path.name}")


if __name__ == "__main__":
    main()
