# Designbrücke · Paper → Flutter

Quelle: Paper-Datei `01M2TRX5GZKAXKTSXK7D34E8AY` (**OpenBand 5 · Designphase 3**), Seite **A00b · Bausteine · Alpin**. Designphase 2 bleibt als eingefrorene Referenz bestehen.

## Dateien

| Datei | Inhalt | Herkunft |
| --- | --- | --- |
| `tokens.json` | Die `alp`-Tokenfamilie (Farben hell/dunkel, Schriftgrößen, Abstände, Radien, Schriften) plus Regeln | Paper `get_tokens`, gefiltert auf `alp` |
| `blocks.json` | Baustein → Dart-Klasse → Datei → verwendende Screens | Layer-Namen der Bausteine-Seite |
| `../assets/icons/lucide/` | Lucide 1.33.0 SVGs, identisch mit `lucide_icons_flutter 3.1.17` | [MANIFEST.json](../assets/icons/lucide/MANIFEST.json) |
| `lib/openband/alp_tokens.dart` | Generiert aus `tokens.json` | `tool/gen_alp_tokens.py` |

## Regel: Baustein ist kanonisch

Ein Baustein existiert genau einmal auf der Bausteine-Seite. Sein Layer-Name ist der Dart-Klassenname (`OBMetricCard`); Varianten hängen mit Punkt an (`OBSetRow.done`) und werden zu Enum oder benanntem Konstruktor. Screens enthalten Klone.

Ablauf bei einer Designänderung:

1. Baustein auf der Bausteine-Seite ändern.
2. Widget in `edge/lib/openband/` anpassen (Ziel-Datei steht in `blocks.json`).
3. Betroffene Screens in Paper aus dem Baustein neu ableiten (`usedIn` in `blocks.json` sagt welche).

Screens sind Spezifikation für Komposition, Inhalt und Zustände. Für das Aussehen eines Bausteins gilt nur der Bausteine-Knoten.

## Befehle

```bash
python3 tool/gen_alp_tokens.py        # schreibt lib/openband/alp_tokens.dart
python3 tool/check_design_manifest.py # prüft blocks.json
~/.local/share/flutter/3.41.6/bin/flutter analyze --no-pub lib/openband/alp_tokens.dart
```

Nach einem Token-Export aus Paper: `tokens.json` ersetzen, `source.tokensContentHash` übernehmen, Generator laufen lassen. Ein Diff in `alp_tokens.dart` zeigt genau, welche Werte sich geändert haben.

## Gestaltungsregeln

- Nur die `alp`-Tokenfamilie. `alp-well` ist die Seitenfläche, `#FFFFFF` die Karte. Keine Schatten auf Karten, keine Verläufe.
- `alp-ink` nur für Text und gewählte Segmente, nie als Fläche.
- Metrikfarben (`sleep`, `recovery`, `strain`, `pulse`, `food`) nur auf Daten und ihren `-tint`-Flächen. `alp-action` nur auf Bedienelementen.
- Kein Text wiederholt, was ein Bild auf demselben Screen bereits zeigt. Kopf zeigt `Heute` bzw. `Di, 15. Sep.`, keine Erklärzeile.
- Fehlende Eingaben erscheinen als `—` oder entfallen. Untergrenzen werden nicht mit `≥` markiert; der kcal-Balken zeigt ein gestricheltes Segment für Einträge ohne Nährwerte.
- Symbole: Lucide 1.33.0 aus dem Asset-Paket, 24-Raster, 2 px Strich. Sport-Piktogramme folgen als eigener Satz im selben Raster.

## Stand

`blocks.json` listet 44 Bausteine und 8 neu aufgebaute Screens (Übersicht ×2, Gesundheit, Training, Journal, Schlaf, Kraft live, Ernährung Tag). Offene Bausteine stehen unter `openBlocks`. Kein bestehendes Widget wurde in dieser Phase verändert; `alp_tokens.dart` ist additiv.
