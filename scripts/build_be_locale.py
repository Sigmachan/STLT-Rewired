#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCALES = ROOT / "backend" / "locales"

BE = {
    "Add via LuaTools": "Дадаць праз LuaTools",
    "Remove via LuaTools": "Выдаліць праз LuaTools",
    "Advanced": "Дадаткова",
    "Advanced tools": "Дадатковыя інструменты",
    "Settings": "Налады",
    "Cancel": "Скасаваць",
    "Close": "Зачыніць",
    "Confirm": "Пацвердзіць",
    "Hide": "Схаваць",
    "Back": "Назад",
    "Apply": "Ужыць",
    "Restart Steam": "Перазапусціць Steam",
    "Restart Steam now?": "Перазапусціць Steam зараз?",
    "Restart Steam to finish": "Перазапусціць Steam, каб завяршыць",
    "Restarting…": "Перазапусціць…",
    "Checking availability…": "Праверка даступнасці…",
    "Checking…": "Праверка…",
    "Downloading…": "Спампоўка…",
    "Downloading from {api}…": "Спампоўка з {api}…",
    "Available": "Даступна",
    "Needs key": "Патрэбны ключ",
    "Not found": "Не знайдена",
    "Found": "Знайдена",
    "Failed": "Памылка",
    "Failed: {error}": "Памылка: {error}",
    "Game Added!": "Гульня дададзена!",
    "Game added!": "Гульня дададзена!",
    "Select Download Source": "Выберыце крыніцу спампоўкі",
    "The game has been added successfully.": "Гульня паспяхова дададзена.",
    "Welcome to LuaTools": "Сардэчна запрашаем у LuaTools",
    "You're all set": "Усё гатова",
    "Check for updates": "Праверыць абнаўленні",
    "Join the Discord!": "Далучайцеся да Discord!",
    "Fixes Menu": "Меню выпраўленняў",
    "Manage Game": "Кіраванне гульняй",
    "Proceed": "Працягнуць",
    "Skipped": "Прапущана",
    "Starting…": "Запуск…",
    "Working…": "Працуем…",
    "Waiting…": "Чаканне…",
    "Done": "Гатова",
    "Unknown Game": "Невядомая гульня",
    "Unknown error": "Невядомая памылка",
    "common.appName": "LuaTools",
    "common.alert.ok": "ОК",
    "menu.settings": "Налады",
    "menu.title": "LuaTools · Меню",
    "menu.removeLuaTools": "Выдаліць праз LuaTools",
    "menu.remove.confirm": "Выдаліць праз LuaTools для гэтай гульні?",
    "menu.remove.success": "LuaTools выдалены для гэтай гульні.",
    "menu.remove.failure": "Не ўдалося выдаліць LuaTools.",
    "settings.title": "LuaTools · Налады",
    "settings.language.label": "Мова",
    "settings.language.description": "Выберыце мову інтэрфейсу LuaTools.",
    "settings.language.option.en": "Англійская",
    "settings.language.option.de": "Немецкая",
    "settings.language.option.ru": "Руская",
    "settings.language.option.uk": "Украінская",
    "settings.language.option.be": "Беларуская",
    "settings.useSteamLanguage.label": "Выкарыстоўваць мову Steam",
    "settings.useSteamLanguage.description": "Выкарыстоўваць мову кліента Steam замест налады LuaTools.",
    "settings.useSteamLanguage.yes": "Так",
    "settings.useSteamLanguage.no": "Не",
    "settings.save": "Захаваць налады",
    "settings.saveSuccess": "Налады паспяхова захаваны.",
    "settings.theme.label": "Тэма",
    "settings.fastDownload.label": "Хуткая спампоўка",
    "bigpicture.mouseTip": "Рэжым мышы ў Steam: Guide + правы стік, націск — RB",
}


def main() -> None:
    en = json.loads((LOCALES / "en.json").read_text(encoding="utf-8"))
    ru = json.loads((LOCALES / "ru.json").read_text(encoding="utf-8"))
    uk = json.loads((LOCALES / "uk.json").read_text(encoding="utf-8"))

    def pick(key: str) -> str:
        if key in BE:
            return BE[key]
        uv = uk["strings"].get(key)
        if uv and uv != "translation missing":
            return uv
        rv = ru["strings"].get(key)
        if rv and rv != "translation missing":
            return rv
        return "translation missing"

    out = {
        "_meta": {
            "code": "be",
            "name": "Belarusian",
            "nativeName": "Беларуская",
            "credits": "",
        },
        "strings": {key: pick(key) for key in en["strings"]},
    }
    path = LOCALES / "be.json"
    path.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    translated = sum(1 for v in out["strings"].values() if v != "translation missing")
    print(f"Wrote {path.name}: {translated}/{len(out['strings'])} translated")


if __name__ == "__main__":
    main()
