#!/usr/bin/env python3
"""Fill be.json and de.json translation missing entries."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

DE_OVERRIDES = {
    "A couple of things to get downloads working:": "Ein paar Schritte, damit Downloads funktionieren:",
    "Action needed": "Aktion erforderlich",
    "Activate a game and it downloads — no restart needed.": "Spiel aktivieren — Download ohne Neustart.",
    'Added to disk. If Steam says "No License", restart Steam to finish — the license is granted on the next launch.': (
        "Auf die Festplatte gelegt. Wenn Steam „No License“ meldet, Steam neu starten — "
        "die Lizenz gilt beim nächsten Start."
    ),
    "Advanced tools": "Erweiterte Tools",
    "Check again": "Erneut prüfen",
    "Checking setup…": "Einrichtung wird geprüft…",
    "Could not check setup right now.": "Einrichtung konnte gerade nicht geprüft werden.",
    "Done": "Fertig",
    "Download requested": "Download angefordert",
    "Downloading — no restart needed": "Download läuft — kein Neustart nötig",
    "Fixed automatically": "Automatisch behoben",
    "Hide advanced tools": "Erweiterte Tools ausblenden",
    "I can do this for you": "Das kann ich für dich erledigen",
    "Restart Steam to finish": "Steam neu starten zum Abschließen",
    "Restarting…": "Neustart…",
    "Set it up for me": "Für mich einrichten",
    "Setting up & starting download…": "Einrichtung und Download-Start…",
    "Setting up…": "Einrichtung…",
    "Starting…": "Start…",
    "Try download (no restart)": "Download versuchen (ohne Neustart)",
    "You're all set": "Alles bereit",
    "…": "…",
}

BE_OVERRIDES = {
    "A couple of things to get downloads working:": "Некалькі крокаў, каб загрузкі працавалі:",
    "Action needed": "Патрэбна дзеянне",
    "Activate a game and it downloads — no restart needed.": "Актывуйце гульню — загрузка без перазапуску.",
    'Added to disk. If Steam says "No License", restart Steam to finish — the license is granted on the next launch.': (
        "Дададзена на дыск. Калі Steam паказвае «No License» — перазапусціце Steam; "
        "ліцэнзія ўступіць у сілу пры наступным запуску."
    ),
    "Advanced tools": "Пашыраныя інструменты",
    "Check again": "Праверыць зноў",
    "Checking setup…": "Праверка наладак…",
    "Could not check setup right now.": "Зараз не ўдалося праверыць налады.",
    "Done": "Гатова",
    "Download requested": "Загрузка запытана",
    "Downloading — no restart needed": "Загрузка — перазапуск не патрэбны",
    "Fixed automatically": "Выпраўлена аўтаматычна",
    "Hide advanced tools": "Схаваць пашыраныя інструменты",
    "I can do this for you": "Магу зрабіць гэта за вас",
    "Restart Steam to finish": "Перазапусціце Steam для завяршэння",
    "Restarting…": "Перазапуск…",
    "Set it up for me": "Наладзіць за мяне",
    "Setting up & starting download…": "Налада і запуск загрузкі…",
    "Setting up…": "Налада…",
    "Starting…": "Запуск…",
    "Try download (no restart)": "Паспрабаваць загрузку (без перазапуску)",
    "You're all set": "Усё гатова",
    "…": "…",
}

# fix typo in BE key
BE_OVERRIDES["I can do this for you"] = "Магу зрабіць гэта за вас"


def fill(path: Path, overrides: dict, fallback_path: Path | None = None) -> int:
    data = json.loads(path.read_text(encoding="utf-8"))
    fallback = {}
    if fallback_path and fallback_path.exists():
        fallback = json.loads(fallback_path.read_text(encoding="utf-8")).get("strings", {})
    fixed = 0
    for k, v in list(data["strings"].items()):
        if v != "translation missing":
            continue
        if k in overrides:
            data["strings"][k] = overrides[k]
            fixed += 1
        elif k in fallback and fallback[k] != "translation missing":
            data["strings"][k] = fallback[k]
            fixed += 1
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    remaining = sum(1 for v in data["strings"].values() if v == "translation missing")
    print(f"{path.name}: fixed={fixed} remaining={remaining}")
    return fixed


if __name__ == "__main__":
    ru = ROOT / "backend/locales/ru.json"
    fill(ROOT / "backend/locales/de.json", DE_OVERRIDES, ru)
    fill(ROOT / "backend/locales/be.json", BE_OVERRIDES, ru)
