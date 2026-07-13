#!/usr/bin/env python3
"""Fill uk.json translation missing entries from ua overrides, ru, then en."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
uk_p = ROOT / "backend/locales/uk.json"
ru_p = ROOT / "backend/locales/ru.json"
en_p = ROOT / "backend/locales/en.json"

uk = json.loads(uk_p.read_text(encoding="utf-8"))
ru = json.loads(ru_p.read_text(encoding="utf-8"))
en = json.loads(en_p.read_text(encoding="utf-8"))

ua = {
    "A couple of things to get downloads working:": "Кілька речей, щоб завантаження працювали:",
    "Action needed": "Потрібна дія",
    "Activate a game and it downloads — no restart needed.": "Активуйте гру — завантажиться без перезапуску.",
    'Added to disk. If Steam says "No License", restart Steam to finish — the license is granted on the next launch.': (
        "Додано на диск. Якщо Steam пише «No License» — перезапустіть Steam; "
        "ліцензія застосується при наступному запуску."
    ),
    "Check again": "Перевірити знову",
    "Checking setup…": "Перевірка налаштувань…",
    "Could not check setup right now.": "Зараз не вдалося перевірити налаштування.",
    "Done": "Готово",
    "Download requested": "Завантаження запитано",
    "Downloading — no restart needed": "Завантаження — перезапуск не потрібен",
    "Fixed automatically": "Виправлено автоматично",
    "Hide advanced tools": "Сховати розширені інструменти",
    "I can do this for you": "Можу зробити це за вас",
    "Restart Steam to finish": "Перезапустіть Steam для завершення",
    "Restarting…": "Перезапуск…",
    "Set it up for me": "Налаштувати за мене",
    "Setting up & starting download…": "Налаштування та запуск завантаження…",
    "Setting up…": "Налаштування…",
    "Starting…": "Запуск…",
    "You're all set": "Усе готово",
    "days left": "днів залишилось",
    "…": "…",
    "settings.fastDownload.description": "Автоматично обирати перше доступне джерело під час додавання гри.",
    "settings.fastDownload.label": "Швидке завантаження",
    "settings.morrenusApiKey.description": "API-ключ ManifestHub (колишній Morrenus). Отримайте на {link}",
    "settings.morrenusApiKey.label": "Ключ API ManifestHub",
    "settings.morrenusApiKey.placeholder": "Введіть ключ API ManifestHub",
}

fixed = 0
for k, v in list(uk["strings"].items()):
    if v != "translation missing":
        continue
    if k in ua:
        uk["strings"][k] = ua[k]
        fixed += 1
    elif k in ru["strings"] and ru["strings"][k] != "translation missing":
        uk["strings"][k] = ru["strings"][k]
        fixed += 1
    elif k in en["strings"]:
        uk["strings"][k] = en["strings"][k]
        fixed += 1

uk_p.write_text(json.dumps(uk, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
remaining = sum(1 for v in uk["strings"].values() if v == "translation missing")
print(f"fixed={fixed} remaining={remaining}")
