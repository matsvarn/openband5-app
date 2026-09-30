# Designbrücke · Paper → Flutter

Quelle: Paper-Datei `01M2TRX5GZKAXKTSXK7D34E8AY` (**OpenBand 5 · Designphase 3**). Die ersten Seiten sind **Release · Alpin 3** und **Bausteine · Release · Alpin 3**. Die übrigen Seiten sind als Archiv gekennzeichnet. Designphase 2 bleibt eingefroren.

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
- `alp-ink` für Text, Auswahlzustände und die kanonischen primären Aktionen. Karten und Seiten behalten ihre eigenen Flächentoken.
- Metrikfarben (`sleep`, `recovery`, `strain`, `pulse`, `food`) nur auf Daten und ihren `-tint`-Flächen. `alp-action` nur auf Bedienelementen.
- Kein Text wiederholt, was ein Bild auf demselben Screen bereits zeigt. Kopf zeigt `Heute` bzw. `Di, 15. Sep.`, keine Erklärzeile.
- Fehlende Eingaben erscheinen als `—` oder entfallen. Teilwerte tragen eine Kennzeichnung, bei Ernährung die Anzahl unvollständiger Einträge. Keine `≥`-Präfixe und keine erfundene Balkenlänge für unbekannte Mengen. Fortschritt braucht ein tatsächlich gespeichertes Ziel; ein nicht geladenes Ziel ist kein leeres Ziel.
- Symbole: Lucide 1.33.0 aus dem Asset-Paket, 24-Raster, 2 px Strich. Sport-Piktogramme kommen aus Tabler Icons 3.46.0 (MIT, gleiches Raster); Zuordnung in `../assets/icons/sport/MANIFEST.json`.

## Stand

`blocks.json` führt die Bausteine und repräsentativen Screens des reduzierten Releases. `check_design_manifest.py` prüft die Quellenzuordnung, nicht die visuelle Abnahme. `state_checklist.json` ist die kurze Release-Queue. Die vollständigen bisherigen Dateien bleiben unverändert in `archive/blocks-20260921.json` und `archive/state_checklist-20260921.json` erhalten. Offene Archivnamen sind keine Release-Aufträge; geparkte Funktionen gelten dadurch nicht als implementiert.

Pro realem Screen: kanonisch hell/dunkel und nur die nötigen fehlenden/fehlerhaften Zustände. Keine vollständige Variantenmatrix. Native Prüfungen sind während einer Änderung gezielt; am Release-Checkpoint folgen Pro und Mini. Jede neu erzeugte PNG wird visuell geprüft. Abgenommene Einheiten stehen in `../IMPLEMENTATION_VERIFICATION.md`, laufende Arbeit in `../IMPLEMENTATION_PLAN.md`.
