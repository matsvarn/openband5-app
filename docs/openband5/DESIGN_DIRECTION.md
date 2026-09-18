# Designrichtung · OpenBand 5

Stand: 17. September 2026 · Designphase 2 · **Design zur Prüfung, keine Implementierungsfreigabe**.

## Gestaltungsregel für alle Bereiche

**Wert → Bild → Handlung.** Die bestätigte Übersicht bestimmt die gesamte Gestaltung: kleine Überschriften, erkennbare Datenbilder, kurze Feldnamen und direkte Vertiefung. Keine erklärende Überschrift über einer selbsterklärenden Aktion. Hinweise stehen am betroffenen Wert oder Eingabefeld; längere Erklärungen gehören in die Methode. Fehler, Einwilligungen und Folgen einer Änderung bleiben ausdrücklich benannt.

Schlaf verwendet Phasen und Zeitfenster, Training Verlauf und Zonen, Ernährung Mengen und Makros. Check-ins verwenden kompakte Symbolskalen; Medikamente eine Terminfolge; Zyklus einen Kalender; Sync ein Band–iPhone-Bild mit bestätigtem Speicherstand. Weiche Linsen, gezeichnete Atemflächen und zurückhaltende Farbakzente geben dem System Persönlichkeit. Dekoration gibt keine Messung vor.

## Empfehlung

**A · Tagesbild** verbindet drei kleine Hauptwerte mit einer knappen täglichen Einordnung. Das Datum öffnet den Kalender; der Feed führt zu Aktivitäten, Journal und weiteren Messwerten. Ruhige Flächen ersetzen die Landschaft hinter Daten. Kleine Linsen und Diagramme tragen die Bildsprache. Dunkel verwendet eigene Graphitflächen und helle Datenfarben.

**B · Messwerte zuerst** zeigt denselben synthetischen Datenstand als drei Zahlenzeilen. A ist die Empfehlung: Schlaf, Erholung und Belastung lassen sich schneller unterscheiden, der erste Bildschirm bleibt dicht und die weiche Bildsprache funktioniert auch in Details. Beide Richtungen sind auf der Review-Seite editierbar; die übrigen Bereiche entwickeln A weiter.

Bevel prägt Dichte, kleine Diagramme, weiche Karten und die schrittweise Vertiefung. WHOOP prägt die nachvollziehbaren Treiber. Eigene Navigation, Texte, Farben, Illustrationen und Datenregeln vermeiden eine Kopie.

## Review in Paper

**[Start hier · aktueller A/B-Vergleich und Review-Weg](https://app.paper.design/file/01M2KDQRH0A9K3N46EWHMBF61D/H-0)**

| Seite | Inhalt und Einstieg |
| --- | --- |
| [Übersicht](https://app.paper.design/file/01M2KDQRH0A9K3N46EWHMBF61D/9-0) | 1V0: Standard; 1Y8: dunkel; 8OM: Scrollfortsetzung; Kalender, vergangene Tage, Anpassung, laufendes Training, Datenzustände |
| [Schlaf](https://app.paper.design/file/01M2KDQRH0A9K3N46EWHMBF61D/A-0) | 22Q: Nacht; 16RN: Detail; JN → L1 → M8 → NG: Korrektur; Phasen, Messwerte, Zeitplanung, Nickerchen und Fehler |
| [Einrichtung](https://app.paper.design/file/01M2KDQRH0A9K3N46EWHMBF61D/B-0) | 2OC: Einstieg; Quellenwahl, optionales Profil, Kopplung, erster Commit, Transferende, erste Nacht |
| [System](https://app.paper.design/file/01M2KDQRH0A9K3N46EWHMBF61D/C-0) | Typografie, Farben, Komponenten, Navigation, Zustände, Widgets, 375-pt-Ansichten und größere Schrift |
| [Gesundheit](https://app.paper.design/file/01M2KDQRH0A9K3N46EWHMBF61D/D-0) | 3LR: Hub; Erholung, Stress, Rhythmus, Historie, Glukose, Gewicht, VO₂max und Labor |
| [Training](https://app.paper.design/file/01M2KDQRH0A9K3N46EWHMBF61D/E-0) | 4GY: Hub; Sportauswahl, Live-Aufzeichnung, Ergebnisse, Belastung, Vorlagen, eigene Übungen und Kraftverlauf |
| [Journal und Ernährung](https://app.paper.design/file/01M2KDQRH0A9K3N46EWHMBF61D/F-0) | 53Y: Journal; 4XB: Ernährung; Check-in, Muster, Lebensmittel, Rezepte, Wasser, Medikamente, Zyklus, Atmen und Coach |
| [Profil, Band und Daten](https://app.paper.design/file/01M2KDQRH0A9K3N46EWHMBF61D/G-0) | 5L1: persönlicher Bereich; Band, Quellen, Health, Im-/Export, Sicherung, Wecker, Mitteilungen und Datenschutz |

**153/153 Bevel-Flows und 709/709 Quellpositionen** wurden nacheinander betrachtet, adaptiert oder begründet nicht übernommen. Der Bestand umfasst **583 iPhone-Ansichten und acht Tafeln** auf neun Seiten. Veraltete Parallelentwürfe wurden entfernt oder an Ort und Stelle ersetzt. [Flow-Review](DESIGN_FLOW_REVIEW.md), [Screeninventar](DESIGN_SCREEN_INVENTORY.json) und [Abdeckungsmatrix](DESIGN_COVERAGE.md) halten Zuordnung und Prüfstand fest.

## Abschluss der visuellen Revision · 17. September

Alle **583 iPhone-Ansichten** wurden auf die neue Gestaltung und knappe Texte abgeglichen; 102 Ansichten erhielten zusätzlich einen gezielten Neuaufbau oder eine neue Datenvisualisierung. Die acht System-/Reviewtafeln sind aktualisiert. Der Wortumfang der Textknoten sank bei gleichem Screenbestand um rund **32 %**; die Zählmethode steht im Inventar. Fehler, Einwilligungen, Quellen und Methoden bleiben erreichbar.

Alle Artboards wurden exportiert und in vollständigen Kontaktbögen bzw. als Tafeln betrachtet; Korrekturen zusätzlich einzeln geprüft. Tastaturblätter, feste Aktionen und der Home-Indikator haben getrennte Ebenen und sichere Abstände. Der abschließende Hashvergleich aller 722 erfassten Engineering-Dateien ergab keine Änderung durch diese Revision.

## Navigation und Tiefe

Vier Tabs: **Übersicht · Gesundheit · Training · Journal**. Ernährung gehört zum Journal; Band, Profil und Einstellungen liegen im persönlichen Bereich. Coach ist optional. Kein eigener Tab für jede Funktion und keine Pflicht zu Konto oder Abo.

Der gewählte Tag bleibt in Tagesansichten erhalten. Eine Nacht gehört zum Aufwachtag. Details kehren zum Ausgangsbereich und dessen Scrollposition zurück. Einträge speichern den ausdrücklich gewählten Tag; ein neues Live-Training beginnt jetzt. Eine laufende Einheit bleibt beim Tabwechsel erreichbar.

Überblick → Wert und Verlauf → Erklärung und Treiber → verwendete Daten und Methode. Umfangreiche Seiten scrollen; die Entwürfe zeigen dazu Fortsetzungen. Formulare, Detailseiten und Live-Aufzeichnungen haben einen eigenen Rahmen mit klarer Rückkehr. Abbrechen, Verwerfen, lokales Speichern und nachfolgende Berechnung sind getrennte Schritte.

## Wiederverwendbares System

| Rolle | Hell | Dunkel |
| --- | --- | --- |
| Hintergrund / Karte | `#F5F6F9` / `#FFFFFF` | `#101318` / `#1C2027` |
| Text / Sekundärtext | `#243149` / `#58657A` | `#F0F2F6` / `#AFB8C8` |
| Aktion / Trennlinie | `#285CCB` / `#E6EAF0` | `#9DBDFA` / `#343B47` |
| Schlaf / Erholung | `#617FCE` / `#388A77` | `#A8BFF0` / `#89B6A5` |
| Belastung / Puls | `#B77E26` / `#B54F72` | `#E3B76C` / `#E597AE` |
| Ernährung / Fett | `#7865AD` | `#C5AEDF` |

Helle Pastelltöne bleiben für Akzente und ergänzende Phasenflächen. Diagrammstriche verwenden die kräftigeren Rollen. Kleine farbige Texte erhalten eigene dunklere Rollen: Schlaf `#4F68AE`, Erholung `#2D7463`, Belastung `#926018`. Makros: Eiweiß rot, Kohlenhydrate gold, Fett violett; immer mit Namen und Zahlen.

**Inter**, Gewichte 400/500/600/700. Hauptkopf 22/28, Detailkopf 18/24, Abschnitt 15/20, Lesetext 14/19, Labels 13/19, Metadaten 12/19, kompakte Ringwerte 25/29, Kartenwerte 27/31, Detailwerte 36–38. Live-Zähler dürfen größer sein. Größere Schrift wächst auf 20/26; dichte Ringe werden durch freie Werte oder gestapelte Gruppen ersetzt. Inhalt darf länger werden.

Außenrand 16, Karteninnenraum 12–14, Gruppengap 12, Kartenradius 20. Abstandsskala 4/8/12/14/16/20/24/32/48. Interaktive Ziele mindestens 44 × 44 pt; die sichtbare Glyphe darf kleiner sein. Sichere Bereiche und untere Inhaltsabstände berücksichtigen Tabbar, Tastatur und laufende Einheit.

Bausteine: Datumskopf, Vier-Tab-Leiste, Dreierüberblick, kleine Einordnung, Messwertkarte, Trend mit Lücken, Phasenbild, Quellenzeile, begründeter Leerzustand, Eingabefeld, Auswahl, Bestätigung, Speicherbeleg und fortsetzbare Live-Einheit. Kreiswerte zentrieren sich als gemeinsamer Textblock über der gesamten Kreisfläche.

Kalender verwenden sieben gleich breite Spalten, mindestens 44 pt hohe Tageszellen und zentrierte Ziffern mit gleicher Zeichenbreite und 20 pt Zeilenhöhe. Auswahl und Datenpunkte verändern die Zahlenposition nicht; Punkte liegen separat unter der Zahl. Der gewählte Zeitraum steht einmal in der Bestätigungsaktion. Im Datumskopf sitzt der Verbindungspunkt am Bandsymbol; Akkuwert und Verbindungszustand bleiben getrennte Informationen. Die Kapsel hat 12 pt Seitenabstand, 8 pt Abstand zwischen Symbol und Wert und mindestens 44 pt Höhe.

**Lucide** liefert die editierbaren SVG-Symbole; Version, ISC/MIT-Lizenzen und Zuordnung liegen unter [assets/icons](assets/icons). Inter ist offen lizenziert. Eigene generierte Rasterbilder beschränken sich auf Landschaft, Beispielmahlzeit und Übungsillustration; UI und Diagramme bleiben separate editierbare Ebenen. [Assetnachweis](assets/README.md).

## Daten und Zustände

Alle Beispiele tragen „Synthetische Daten“. A/B verwenden [denselben Basissnapshot](assets/fixtures/day-summary.json):

- Nacht 14./15. September: 23:10–06:54; **7h44 im Bett, 7h18 Schlaf, 26 Minuten wach**.
- Erholung **74**, HRV **48 ms** gegenüber 40, Ruhepuls **54 /min** gegenüber 56, Atemfrequenz **16 /min**.
- 1.240 Schritte und illustrative Tagesbelastung 1,6 bis 07:42; Akku 64 %.
- Mindestens 620 kcal, 36/80/18 g bekannte Makros und 750 ml Wasser; Kaffee ohne Nährwerte bleibt offen.

**Verbindung, Aktualität, Abdeckung und Messwertbereitschaft sind unabhängig.** 07:42 ist der jüngste gespeicherte Bandzeitpunkt; 09:36 bezeichnet dessen Eingang auf dem iPhone. Eine vollständige Nacht macht nicht automatisch jede Metrik verfügbar. Der Schlafring zeigt die Phasenzusammensetzung der 464 Minuten im Bett: 123 REM, 247 leicht, 68 tief, 26 wach. Innen steht die Schlafdauer 438 Minuten. Das ist kein Schlafscore; die eigene Schlafanteil-Detailansicht zeigt ausdrücklich 94 %. Erholung und Belastung behalten ihre bezeichneten Skalen.

Die Teilnacht hat eine 24-minütige Lücke von 02:10–02:34 und 6h54 beobachteten Schlaf. Unzuverlässige Herzintervalle sind eine eigene Variante. Ein Verbindungsabbruch entfernt keine gespeicherten Werte. Ohne Banddaten bleiben Journal und Ernährung nutzbar. Reifere Historien, zusätzliche Einträge und Änderungsbelege sind ausdrücklich getrennte synthetische Varianten.

**Schlafkorrektur:** 23:25–06:54 → Vorschau 7h29 im Bett → Commit → Neuberechnung → 7h08 Schlaf, 21 Minuten wach. Ein Speicherfehler erhält den Entwurf; ein Berechnungsfehler erhält die gespeicherte Korrektur. Rücknahme stellt das automatische Fenster wieder her.

**Erster Start:** Band/Import/später → überspringbares Profil → Übertragung → erster bestätigter lokaler Abschnitt → nutzbare Übersicht. Der erste Beleg zeigt 16 Minuten von 09:12–09:28. Erst der separate Transferabschluss bestätigt das Ende dieses Laufs. Kein erfundener Prozentfortschritt oder pauschaler Kalibrierungszähler.

## Umsetzung nach Review

[DESIGN_BACKEND.md](DESIGN_BACKEND.md) enthält konkrete Verträge, vorhandene Grundlagen, notwendige Änderungen und Abnahmekriterien B01–B166. Priorität:

1. **Verlässliche Daten:** Quellen und Originale behalten; Commit vor ACK; unabhängige Statusdimensionen; datierte Ergebnisse und fehlende Eingänge.
2. **Sichere Änderungen:** wiederaufnehmbare Entwürfe, stabile IDs, atomare Speicherung, gezielte Rücknahme, Fehler ohne Datenverlust.
3. **Produktbreite:** gemeinsame Messwertdetails; Trainingsvorlagen und Live-Sitzungen; Ernährung und Journal; die vollständigen Medikamenten-, Zyklus-, Atem-, Labor- und Exportwege.
4. **iPhone-Anschluss:** einheitlicher Tageskontext, Deep Links, Health-Provenienz, Widget-Snapshots, Alarmbestätigung, Dynamic Type und native Berechtigungen.

`edge` besitzt App, Bluetooth-Sitzung, lokale Speicherung, Sync-Fortschritt und Navigation. `analytics` besitzt versionierte Berechnungen und Bereitschaftsregeln. `protocol` besitzt Decoder und Bandbefehle. Die gewünschte UX ist das Ziel; heutige Backend-Lücken sind kein Grund für falsche Werte oder wirkungslose Bedienelemente.

## Quellen und Nachweisgrenzen

- [Bevel Home](https://mobbin.com/screens/c33feab6-41f6-475a-b370-caa18c10e204): Datum, kleine Ringe, knappe Einordnung.
- [Bevel langer Feed](https://mobbin.com/screens/45777953-3f7c-40ce-8675-09b3ec5bd8fd) und [fehlende Werte](https://mobbin.com/screens/188be10c-cc97-4b4e-9091-b854089b71ec): Dichte, Fortsetzung und Leerzustände.
- [WHOOP Erholungstreiber](https://mobbin.com/screens/33b30723-adc2-4efa-82d5-6c320624aff3): Eingänge und persönliche Vergleiche.
- [Refero · Gentler Streak](https://refero.design/screens/7ced759c-f065-4dd4-bffe-9f775c05a241): Erklärung am Diagramm. Vollständige Quellen: [Recherche](DESIGN_RESEARCH.md) und [Flowliste](DESIGN_FLOW_REVIEW.json).

Referenzen belegen den betrachteten historischen Katalogstand, nicht die neueste installierte Bevel-App. Die Sichtprüfung umfasst alle behaltenen Artboards, deutsche Texte, Hierarchie, Zentrierung, Datenkonsistenz, Hell/Dunkel, größere Schrift und 393 × 852 sowie 375 × 812 pt. Kontrastproben gelten für die dokumentierten Farbpaare; sie sind keine pauschale Barrierefreiheitszertifizierung.

Paper zeigt editierbare Zustandsansichten. Navigation, Scrollen und Interaktionen sind beschrieben, nicht als lauffähige App verdrahtet. Native Dynamic Type, VoiceOver, Tastatur, echte Bluetooth-Synchronisierung und physiologische Gültigkeit benötigen eigene Implementierungsprüfung. Die synthetische Erholung wurde mit der vorhandenen reinen Dart-Berechnung geprüft; das ist kein Pipeline- oder Hardwarebeweis. **In dieser Phase wurde kein App-Code bearbeitet.**
