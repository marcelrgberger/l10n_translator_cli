# L10n Translator (CLI)

Ein kleines Dart-Kommandozeilenwerkzeug, das Übersetzungen für ARB-Dateien (Flutter/Intl) via OpenAI erzeugt und als
eigene ARB-Dateien pro Zielsprache abspeichert.

## Features

- Liest ein Template-ARB aus einem konfigurierten Verzeichnis.
- Übersetzt nur die eigentlichen String-Werte (keine `@`-Metadaten).
- Bewahrt ICU-Platzhalter wie `{count}`, `{name}`, `{total}` exakt.
- Schreibt pro Ziel-Locale eine eigene ARB-Datei.
- Optionaler Dry-Run, gezielte Auswahl von Locales, wählbares OpenAI-Modell.

## Voraussetzungen

- Dart SDK installiert (2.19+ empfohlen).
- OpenAI API Key als Umgebungsvariable:
    - macOS/Linux: `export OPENAI_API_KEY="sk-..."`
    - Windows (PowerShell): `$Env:OPENAI_API_KEY="sk-..."`
- ARB-Template-Datei mit gültigem JSON.

## Installation

- Abhängigkeiten auflösen:
    - `dart pub get`
- Optional: Binärdatei bauen:
    - `dart compile exe bin/<entrypoint>.dart -o build/l10n-translator`

Hinweis: Der Einstiegspunkt liegt im `bin/`-Verzeichnis. Ersetze `<entrypoint>.dart` durch den tatsächlichen Dateinamen.

## Konfiguration (l10n.yaml)

Lege eine `l10n.yaml` im Projekt an, zum Beispiel:

```yaml```
yaml arb-dir: lib/l10n # Verzeichnis mit ARB-Dateien template-arb-file: app_de.arb # Template-ARB (Quellsprache)
output-localization-file: app_localizations.dart # wird hier nicht geändert, aber häufig in Flutter-Setups vorhanden
locales: en, fr, es # Zielsprachen (Komma-getrennt)

```

- `arb-dir`: Ordner mit den ARB-Dateien.
- `template-arb-file`: Das Quell-Template (z. B. `app_de.arb`).
- `output-localization-file`: Wird von diesem Tool nicht beschrieben, bleibt aber für Flutter-Tooling üblich.
- `locales`: Liste der Ziel-Locales als kommagetrennter String. Kann per CLI überschrieben werden.

## ARB-Anforderungen

- Übersetzbare Einträge sind reine String-Werte. ARB-Metadaten wie Schlüssel, die mit `@` beginnen, werden nicht übersetzt.
- Platzhalter im ICU-Format (z. B. `{name}`, `{count}`) müssen im Template korrekt enthalten sein und werden 1:1 übernommen.
- Emojis, Auslassungspunkte (…) sowie Zeilenumbrüche (`\n`) bleiben erhalten.

## Verwendung

Allgemein:
- `dart run bin/<entrypoint>.dart [Optionen]`

Optionen:
- `-c, --config <pfad>`: Pfad zu `l10n.yaml` (Standard: `l10n.yaml`)
- `--source-locale <code>`: Quellsprache des Templates (Standard: `de`)
- `--model <name>`: OpenAI-Modell (Standard: `gpt-4o-mini`)
- `--dry-run`: Nichts schreiben, nur anzeigen
- `--only <locale>`: Nur diese Ziel-Locales übersetzen; kann mehrfach angegeben werden (überschreibt `locales` aus `l10n.yaml`)

Beispiele:
- Standardlauf mit `l10n.yaml`:
  - `dart run bin/<entrypoint>.dart`
- Nur Englisch und Französisch:
  - `dart run bin/<entrypoint>.dart --only en --only fr`
- Dry-Run (zeigt, was geschrieben würde):
  - `dart run bin/<entrypoint>.dart --dry-run`
- Abweichende Config-Datei und Modell:
  - `dart run bin/<entrypoint>.dart -c config/l10n.yaml --model gpt-4o-mini`

## Ausgabe

- Für jede Ziel-Locale wird aus dem Template-Dateinamen ein entsprechender Zielname abgeleitet, z. B.:
  - Template `app_de.arb` → Ziel `app_en.arb`, `app_fr.arb`, …
- Das Feld `@@locale` wird im Ergebnis auf die Ziel-Locale gesetzt.
- Bei `--dry-run` werden keine Dateien geschrieben.

## Fehlersuche

- "Fehlende Umgebungsvariable OPENAI_API_KEY.": Setze den API Key in deiner Shell-Umgebung.
- "l10n.yaml nicht gefunden" oder "ARB-Verzeichnis nicht gefunden": Pfade in `--config` und `l10n.yaml` prüfen.
- HTTP-Fehler von OpenAI (4xx/5xx): API Key, Modellname, Kontingent/Rate-Limits, Netzwerk prüfen.
- "Platzhalter-Mismatch": Stelle sicher, dass Platzhalter in allen Strings korrekt sind und in der Übersetzung nicht verändert werden.

## Hinweise zu Datenschutz und Kosten

- Inhalte der ARB-Strings werden an die OpenAI-API gesendet. Prüfe interne Richtlinien und entferne sensible Daten.
- Je nach Modell und Datenmenge können Kosten entstehen.

## Lizenz

Füge hier die passende Lizenz-Information ein  MIT, Apache-2.0