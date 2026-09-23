# Designbrücke · Paper → Flutter

Quelle: Paper-Datei `01M2TRX5GZKAXKTSXK7D34E8AY` (**OpenBand 5 · Designphase 3**). Die aktuelle Richtung ist **G2 · Gerät**, Alternative A mit Messleisten, auf den Seiten **G2 · Gerät · Screens** und **G2 · Gerät · Dunkel**. **Release · Alpin 3** und **Bausteine · Release · Alpin 3** halten die vorherige Release-Stufe fest. Designphase 2 bleibt eingefroren.

## Dateien

| Datei | Inhalt | Herkunft |
| --- | --- | --- |
| `tokens.json` | Die `alp`-Tokenfamilie für G2, hell und dunkel, samt Regeln | Paper `get_tokens`, gefiltert auf `alp` |
| `blocks.json` | Baustein → Dart-Klasse → Datei → verwendende Screens; ausgewählte G2-Screen-IDs sind zusätzlich registriert | Layer-Namen der Bausteine-Seite und G2-Screens |
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

## Gestaltungsregeln · G2

- Nur die `alp`-Tokenfamilie. `alp-page` ist die Seite, `alp-canvas` das erhabene Gehäuse, `alp-well` die Mulde und `alp-inset` eine eingedrückte Fläche auf der Seite. Erhabene Karten und Tasten tragen den Schatten.
- Helvetica Neue auf Apple. Inter ist die Schrift in Tests ohne geladene Helvetica und auf Android.
- Messwerte stehen auf beschrifteten linearen Skalen. Ein persönlicher Normalbereich ist ein graues Band, der heutige Wert ein Zeiger. Orange markiert nur Erholung; die grüne LED markiert eine Live-Verbindung. Andere Daten und Aktionen bleiben grau oder schwarz.
- Die reduzierte App verwendet Push-Navigation und Sheets ohne Tab-Leiste. Der Kopf benennt die aktuelle Seite und ihre Rückkehr; ein Datum ist ein eigener auswählbarer Zustand.
- Fehlende Eingaben erscheinen als `—` oder entfallen. Teilwerte tragen eine Kennzeichnung, bei Ernährung die Anzahl unvollständiger Einträge. Keine `≥`-Präfixe und keine erfundene Balkenlänge für unbekannte Mengen. Fortschritt braucht ein tatsächlich gespeichertes Ziel; ein nicht geladenes Ziel ist kein leeres Ziel.
- Symbole: Lucide 1.33.0 aus dem Asset-Paket, 24-Raster, 2 px Strich. Sport-Piktogramme kommen aus Tabler Icons 3.46.0 (MIT, gleiches Raster); Zuordnung in `../assets/icons/sport/MANIFEST.json`.

## Stand

Am 23. September 2026 ist G2 auf `openband5/g2-design` bis `0bfa61a0` in die reduzierte App übernommen. `blocks.json` führt 59 Bausteine und 38 repräsentative Screens, darunter die registrierten G2-Varianten. `check_design_manifest.py` prüft die Quellenzuordnung, nicht die visuelle Abnahme. `tool/g2_review.py` vergleicht elf G2-Frames je in Hell und Dunkel mit synthetischen Daten. Abweichende Daten und Tage in Paper sind kein Grund, Messwerte zu erfinden.

Der signierte Build `0.9.31+67` wurde auf dem physischen iPhone in die vorhandene App installiert. Die sichtbaren G2-Screens wurden in Dunkel mit echten lokalen Daten geprüft. [Die aktuelle Verifikation](../IMPLEMENTATION_VERIFICATION.md) trennt diese Prüfung von Simulator- und Datenbanknachweisen. Persönliche Screenshots und Datenbankkopien bleiben unter `~/Library/Application Support/OpenBand5Lab/`, außerhalb von Git.

`state_checklist.json` ist die kurze Release-Queue. Die vorherigen Dateien bleiben in `archive/blocks-20260921.json` und `archive/state_checklist-20260921.json` erhalten. Offene Archivnamen sind keine Release-Aufträge; geparkte Funktionen gelten dadurch nicht als implementiert.

### Vorheriger Alpin-3-Checkpoint · 22. September 2026

Pro realem Screen: kanonisch hell/dunkel und nur die nötigen fehlenden/fehlerhaften Zustände. Keine vollständige Variantenmatrix. Native Prüfungen sind während einer Änderung gezielt; am Release-Checkpoint folgen Pro und Mini. Jede neu erzeugte PNG wird visuell geprüft. Abgenommene Einheiten stehen in `../IMPLEMENTATION_VERIFICATION.md`, laufende Arbeit in `../IMPLEMENTATION_PLAN.md`.
