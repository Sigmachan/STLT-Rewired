#!/usr/bin/env python3
"""Fill ru.json translation missing entries."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ru_p = ROOT / "backend/locales/ru.json"
en_p = ROOT / "backend/locales/en.json"

ru = json.loads(ru_p.read_text(encoding="utf-8"))
en = json.loads(en_p.read_text(encoding="utf-8"))

ru_overrides = {
    "A couple of things to get downloads working:": "Несколько шагов, чтобы загрузки заработали:",
    "Action needed": "Нужно действие",
    "Activate a game and it downloads — no restart needed.": "Активируйте игру — загрузка пойдёт без перезапуска.",
    'Added to disk. If Steam says "No License", restart Steam to finish — the license is granted on the next launch.': (
        "Добавлено на диск. Если Steam пишет «No License» — перезапустите Steam; "
        "лицензия применится при следующем запуске."
    ),
    "Advanced tools": "Расширенные инструменты",
    "Check again": "Проверить снова",
    "Checking setup…": "Проверка настройки…",
    "Could not check setup right now.": "Сейчас не удалось проверить настройку.",
    "Done": "Готово",
    "Download requested": "Загрузка запрошена",
    "Downloading — no restart needed": "Загрузка — перезапуск не нужен",
    "Fixed automatically": "Исправлено автоматически",
    "Hide advanced tools": "Скрыть расширенные инструменты",
    "I can do this for you": "Могу сделать это за вас",
    "Restart Steam to finish": "Перезапустите Steam для завершения",
    "Restarting…": "Перезапуск…",
    "Set it up for me": "Настроить за меня",
    "Setting up & starting download…": "Настройка и запуск загрузки…",
    "Setting up…": "Настройка…",
    "Starting…": "Запуск…",
    "Try download (no restart)": "Попробовать загрузку (без перезапуска)",
    "You're all set": "Всё готово",
    "…": "…",
    "settings.manifestHub.testKey": "Проверить ключ ManifestHub",
    "settings.manifestHub.enterKey": "Сначала введите ключ.",
    "settings.manifestHub.testing": "Проверка…",
    "settings.manifestHub.testFailed": "Проверка не удалась",
    "settings.manifestHub.stats": "Загрузить статистику",
    "settings.manifestHub.statsLoading": "Загрузка статистики…",
    "settings.config.export": "Экспорт конфига",
    "settings.config.import": "Импорт конфига",
    "settings.config.exportSuccess": "Конфиг экспортирован.",
    "settings.config.importSuccess": "Конфиг импортирован.",
    "settings.config.importFailed": "Импорт не удался.",
}

fixed = 0
for k, v in list(ru["strings"].items()):
    if v != "translation missing":
        continue
    if k in ru_overrides:
        ru["strings"][k] = ru_overrides[k]
        fixed += 1
    elif k in en["strings"]:
        ru["strings"][k] = en["strings"][k]
        fixed += 1

ru_p.write_text(json.dumps(ru, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
remaining = sum(1 for v in ru["strings"].values() if v == "translation missing")
print(f"fixed={fixed} remaining={remaining}")
