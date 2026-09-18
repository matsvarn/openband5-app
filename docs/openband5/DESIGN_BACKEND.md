# Umsetzung nach Designreview

Stand: 16. September 2026 · **Anforderungen aus dem abgeschlossenen Designreview der Quellen**, keine implementierten Zusagen. Substanzielle Änderungen sind für das gewünschte Produkt erlaubt. Die Grenzen bleiben: keine erfundenen Messwerte, Quellen erhalten, lokal speichern vor Bluetooth-ACK. Neue Berechnungen gehören in `analytics`, Daten und Abläufe in `edge`, Protokolländerungen in `protocol`.

## Reihenfolge für die Implementierung

Die Nummern B01–B162 sind Quellen- und Entscheidungsreferenzen, keine Reihenfolge für 162 unabhängige Projekte. Gemeinsame Verträge zuerst umsetzen, danach die dazugehörigen Produktwege.

| Priorität | Ergebnis | Zugehörige Anforderungen |
| --- | --- | --- |
| P0 · Datenbestand | Decoderkorrektheit, erhaltene Originale, Commit vor ACK, wiederaufnehmbare Übertragung und unabhängige Zustände | B01, B04, B53, B61, B146, B155, B160 |
| P0 · Änderungen | Ein Commit pro bestätigter Operation; stabile IDs; Entwurf und bisheriges Ergebnis bei Fehler behalten; Neuberechnung getrennt | B05–B07, B19, B31, B138, B149, B155–B159 |
| P1 · Messwerte | Datum, Quelle, Qualität, Basis, Methode und Refusal aus einem Ergebnisvertrag; keine parallelen Score-Wahrheiten | B41, B43, B117–B119, B135–B137, B139–B142, B147–B152 |
| P1 · Navigation | Vier Bereiche, lokaler Tageskontext, Ursprung/Rückkehr, laufende Einheit, bekannte und verlorene Deep-Link-Ziele | B03, B25, B120, B132, B134, B138, B145, B153, B154, B161 |
| P1 · Produktwege | Ernährung/Rezepte, Journal/Muster, Vorlagen/Krafttraining, Medikamente, Zyklus, Atmen und Labor | B05–B40, B65, B92–B114, B121–B130, B154–B159 |
| P1 · iPhone | Health-Provenienz, Zubehörzugriff, Weckerbestätigung, Freigaben, Theme und native Bedienhilfen | B02, B42/B144, B45/B131, B134, B152, B153, B160, B161 |
| P2 · Optionale Dienste | Coach/Fotoanbieter, freiwillige externe Lebensmittelsuche, geprüfte Problemberichte | B15, B37, B68, B124, B128/B129 |

**Eigentümer:** `edge` hält Bluetooth-Sitzung, Speicherung, gespeicherten Frontier, Jobs, Drafts, Quellenwahl und Router. `analytics` hält reine, versionierte Berechnungen und deren Bereitschaft. `protocol` dekodiert und bildet Bandbefehle ab. Keine Datenbank- oder UI-Zuständigkeit in `protocol`.

**Vor Umsetzung gezielt reparieren:** Live-Abschluss darf bei fehlgeschlagenem Speichern den Entwurf nicht löschen (B138); HRR muss das dokumentierte Nachbelastungsfenster nutzen (B19); Import-/Neuauswertungsfehler dürfen nicht als null Ergebnisse durchgehen (B53/B61); Schlafbedarf darf keine falsche Datumsgrundlage verwenden (B136/B137); ein freier Wochentag darf keinen alten Wecker aktiv lassen (B45/B131); Coach-Löschen darf Fehler nicht verschlucken und auf 30 Einträge begrenzen (B68); Intents dürfen unbekannte Frische nicht als aktuell zeigen (B134); importiertes Gewicht braucht die tatsächliche Herkunft (B152). OFF-Zugriff bleibt ausdrücklich freiwillig (B15); doppelte Journal-Auswertungswege werden vereinheitlicht (B93).

**Verbindliche spätere Nachweise:** lokale Vertrags-/Fehlertests, native iPhone-Bedienung, reale Bluetooth-Wiederaufnahme, gesicherte Wiederherstellung und physiologische Evaluation getrennt berichten. Paper ersetzt diese Nachweise nicht.

## B01 · Wiederaufnehmbare Einrichtung

**Aus Flow 001.** Ein lokaler Einrichtungszustand hält Schwerpunkt, gewählten Quellenweg (Band/Import/später), Profildraft und zuletzt bestätigten Schritt. Zurück und erneutes Öffnen behalten gültige Eingaben. Ein gewähltes Band ist ein gekoppeltes Zubehör, kein Beweis für eine Verbindung oder gespeicherte Aufzeichnungen.

Der Speicherbeleg kommt aus der bestätigten lokalen Transaktion: Zeitfenster, gespeicherte Dauer, Zeitpunkt des Commits und laufender/beendeter Transfer getrennt. Der erste Beleg schließt die Einrichtung ab; weitere Synchronisierung läuft als sichtbarer App-Zustand. Nie ein animierter Fortschrittswert ohne bekannte Gesamtmenge. Ein Neustart zwischen Commit und ACK darf weder Daten löschen noch einen zweiten Einrichtungslauf erzwingen.

**Abnahme:** Abbruch vor Bandwahl, gekoppelt ohne Verbindung, Empfang ohne Commit, erster Commit, Unterbrechung, Relaunch, bestätigtes Übertragungsende und Auswertung noch offen führen jeweils zum richtigen gespeicherten Zustand. 16 Minuten im Beleg beweisen nur 09:12–09:28, keine vollständige Nacht.

## B02 · Profil überspringen und gezielt ergänzen

**Aus Flow 001.** Einrichtung und Übersicht funktionieren ohne Profildaten. „Später ergänzen“ speichert einen unbekannten Profilzustand; es werden keine physiologischen Ersatzwerte eingesetzt. Explizites „Keine Angabe“ und ein noch unbeantwortetes Feld bleiben intern unterscheidbar, falls späteres Nachfragen davon abhängt. Eine benötigte Berechnung erklärt den konkreten fehlenden Eingang an ihrer Detailansicht.

Vorhandene Profil-/Health-Import-Funktionen weiterverwenden. Import nur nach Auswahl, Vorschau mit Quelle, keine stillen Überschreibungen; Speichern atomar, danach betroffene abgeleitete Tage neu berechnen. Zurück aus Datumsauswahl verändert den Profildraft nicht. Ein Fehler lässt Eingaben erhalten.

**Abnahme:** Ohne Geschlechtsangabe, Geburtsdatum, Größe oder Gewicht in die Übersicht gelangen; betroffene Werte bleiben fehlend. Ein später ergänztes Datum ändert keine gespeicherten Rohdaten. Bereits manuell gesetzte Angaben werden erst nach Bestätigung ersetzt.

## B03 · Persönliche Startansicht

**Aus Flow 001.** Optionaler Schwerpunkt `sleep | fitness | patterns | balanced` bestimmt nur die anfängliche Kartenreihenfolge. Die Standardansicht ist sofort nutzbar. Nutzeränderungen erhalten eine eigene geordnete Kartenliste und dürfen bei erneutem Öffnen oder späterer Profiländerung nicht überschrieben werden. Messwerte, Schwellwerte und Qualitätsgrenzen bleiben davon unabhängig.

**Abnahme:** Gleiche synthetische Daten erzeugen in allen Schwerpunkten gleiche Werte. Zurück/Abbrechen speichert keine neue Auswahl. Fehlt ein Kartentyp nach einer Version, bleiben alle weiterhin bekannten Karten in Nutzerreihenfolge erhalten.

## B04 · Erste Nacht und Bereitschaft

**Aus Flow 001.** Der erste Tag zeigt gespeicherte Abschnitte, nächste sinnvolle Schritte und unabhängige Voraussetzungen je Metrik. Für Schlaf zählt eine verwertbare Nacht; Erholung braucht verwendbare Eingänge und deren persönliche Basis. Der erste Tag zeigt keinen pauschalen 0/14-Kalibrierungszähler. Ein späterer Fortschritt muss aus tatsächlich geeigneten Baseline-Samples pro Eingang abgeleitet werden, nicht aus Kalendertagen seit Installation.

Ein gemeinsames Readiness-Modell liefert `available | processing | insufficient_history | insufficient_coverage | unreliable_input | unsupported`, Grund, Quellenfenster und erlaubte nächste Aktion. Verbindung, jüngster gespeicherter Zeitstempel und Abdeckung bleiben eigene Felder. Eine neue Nacht darf alte brauchbare Ergebnisse mit Datum weiter anzeigen, ohne sie als heutige Werte auszugeben.

**Abnahme:** Mit ersten 16 Minuten sind Schlaf/Erholung offen; mit einer verwertbaren Nacht kann Schlaf erscheinen; Erholung bleibt bei fehlender Basis offen. Schlechte Intervalle ändern den Bereitschaftsgrund. Ein Import kann vorhandene geeignete Historie liefern.

## B05 · Mahlzeit als Entwurf, Vorschau und atomarer Speicherlauf

**Aus Flow 003.** Einstieg aus Übersicht/Journal/Ernährung mit festem lokalen Datum. Freitext kann zunächst lokale Lebensmittel vorschlagen; ein Vorschlag ist kein gespeicherter Verzehr. `FoodDraft` hält stabile Draft-ID, Datum, optionale Uhrzeit, Beschreibung, geordnete Kandidaten, Portionsmenge, Herkunft jedes Nährwerts und Auflösungsstatus. Lokale Treffer werden mit ihrer Quelle gezeigt; unbekannte Werte bleiben leer. Ein optionaler externer Resolver wäre ein eigener, explizit aktivierter Datenweg, kein stiller Coach-Aufruf.

Eine Vorschau erlaubt mehrere Einträge, Mengenänderung, Entfernen und Ergänzen. Bestätigen schreibt alle Einträge in einer Transaktion mit stabilen IDs; wiederholtes Bestätigen oder ein Retry darf nicht duplizieren. Ein Fehler lässt den Draft erhalten und öffnet keinen Erfolgszustand. Abbruch ohne Änderungen schließt; mit Änderungen stehen Weiterbearbeiten und Verwerfen zur Wahl. Datum und Uhrzeit gehören zum Draft und springen nach Mitternacht nicht auf heute.

`NutritionDay` summiert nur gespeicherte Einträge. Bekannte kcal plus unbekannter Kaffee ergeben **≥620 kcal**, nicht 620 als vollständige Tagesmenge. Der Draft selbst enthält 450 + 170 = 620 kcal; die bekannten Makros 36/80/18 g sind unabhängig eingetragene, gerundete Angaben, keine Rückrechnung aus kcal. Leere Nährstoffe und bewusst eingetragene 0 sind verschieden. Mengenbegriffe brauchen eine definierte Bezugsportion; ohne Umrechnung wird kein Grammwert erfunden.

**Abnahme:** Nur Kaffee ohne Nährwerte → Tagesenergie offen; Draft noch ohne Einfluss; zwei bestätigte Einträge → Tagesenergie ≥620. Retry erzeugt genau zwei IDs. Historisches Datum, App-Neustart, fehlende Quelle, Abbruch und Schreibfehler behalten eine überprüfbare Herkunft und den richtigen Tag. Der Ergebniszustand kehrt zum Ausgangsbereich zurück und bestätigt erst den lokalen Commit.

## B06 · Portionen ohne veraltete Summen ändern

**Aus Flow 004.** Dezimale Mengen mit deutscher Kommaeingabe, definierter Referenzportion und optionalen sicheren Umrechnungen. Der Entwurf berechnet alle bekannten Nährstoffe aus unveränderten Basiswerten; wiederholtes Ändern darf keine Rundungsdrift erzeugen. 1,5 × 450 kcal = 675 kcal; plus Joghurt 170 kcal ergibt 845 kcal, Makros 47/110/25 g. Speichern in der Portionsansicht ändert nur den Draft; der Tag ändert sich erst beim Bestätigen der gesamten Mahlzeit.

Leere, negative und null Portionen sind keine Löschaktion: Eingabe erklären, Übernehmen deaktivieren, letzten gültigen Draft behalten. Bei unbekannter Bezugsportion nur die bekannte Einheit anbieten. Rückkehr oder Tastaturschließen übernimmt keine ungültige Eingabe. Die Vorschau und der Footer verwenden dieselbe abgeleitete Summe; eine lokal geänderte Einzelportion darf nicht neben einer alten Gesamtsumme stehen.

## B07 · Entwurf entfernen, gespeicherten Eintrag löschen

**Aus Flow 005.** Entfernen im Draft schreibt nichts in die Tagesdatenbank. Eine kleine Rückgängig-Aktion stellt denselben Kandidaten mit Menge, Quelle und Listenposition wieder her. Alle Draft-Summen ändern sich gleichzeitig. Wird der letzte Kandidat entfernt, erscheint ein leerer Entwurf mit „Lebensmittel hinzufügen“; Speichern bleibt deaktiviert.

Ein gespeicherter Eintrag braucht eine benannte Bestätigung mit Lebensmittel und Tag. Löschen betrifft die konkrete Entry-ID, nicht die Lebensmitteldefinition, Rezeptvorlage oder andere Verzehrtage. Bei Fehler bleibt der Eintrag sichtbar und wiederholbar löschbar; kein Erfolgshinweis vor Commit. Herkunft und Datum bestimmen die Rückkehr. Für Draft-Undo reicht lokaler Zustand; dafür ist kein allgemeines Änderungsjournal nötig.

## B08 · Rezepte und nachvollziehbare Zutaten

**Aus Flow 006.** Lebensmittel, Rezeptdefinition und gegessener Eintrag sind verschiedene Objekte. Ein Rezept enthält geordnete Zutaten mit stabilen Definition-IDs, Menge/Einheit und einer bekannten Bezugsportion. Der Entwurf summiert bekannte Nährstoffe; unbekannte Bestandteile erzeugen eine gekennzeichnete Teilsumme. Manuell eingetragene Gesamtwerte bleiben ein eigener Modus, ohne erfundene Zutatenliste.

Bearbeiten im Mahlzeitendraft betrifft zunächst dessen Snapshot. Eine ausdrücklich gespeicherte Rezeptvorlage erhält eine neue Version; bereits gespeicherte Verzehrtage werden dadurch nicht rückwirkend verändert. Der Zutateneditor kehrt zum Rezeptdraft, dieser zum Mahlzeitendraft zurück. Abbruch lässt den jeweils übergeordneten Zustand unverändert.

**Synthetisches separates Rezeptbeispiel:** Beeren-Skyr-Bowl, 1 Schüssel: Haferflocken 60 g / 230 kcal, Skyr 150 g / 95 kcal, Beeren 100 g / 45 kcal, Mandeln 13 g / 80 kcal = 450 kcal. Makros aus den synthetischen Zutatenangaben: 29/52/11 g. Dieses Rezept ist ein ungespeicherter Entwurf und verändert das Tagesbeispiel mit Haferfrühstück 450 kcal und Joghurt 170 kcal nicht.

**Abnahme:** Zutaten- und Portionsänderungen aktualisieren dieselben Summen; fehlender Nährstoff bleibt offen; Definition bearbeiten verändert keinen historischen Entry-Snapshot; Zurück/Verwerfen und Speichern sind getrennte Aktionen.

## B09 · Zutatenmenge und Einheiten

**Aus Flow 007.** Der gemeinsame Mengeneditor aus B06 wird auch für eine einzelne Rezeptzutat verwendet. Nur fachlich bekannte Einheiten anbieten: Gramm aus einer Massenreferenz; ml nur mit Volumenreferenz; Stück nur mit definierter Stückgröße. Keine implizite Umrechnung von ml in g. Der eingegebene Zahlenwert und die Einheit bilden zusammen eine Menge; beim Einheitenwechsel die äquivalente Menge erhalten, soweit die Umrechnung bekannt ist.

Die Vorschau zeigt die betroffene Zutat, nicht unbemerkt die Gesamtportion. 60 → 90 g Haferflocken ergeben 230 → 345 kcal; Rezeptgesamtwert 450 → 565 kcal, Makros 29/52/11 → 33/70/13 g. Dafür enthält die synthetische Haferreferenz bei 60 g genau 8/36/4 g Makros. Rundung nur für die Anzeige. Übernehmen kehrt zum Rezeptdraft zurück; kein Tages-Commit. Leere/negative Eingabe bleibt korrigierbar, Übernehmen deaktiviert.

## B10 · Zutaten suchen und gesammelt übernehmen

**Aus Flow 008.** Ein wiederverwendbarer Lebensmittelpicker bekommt ein explizites Ziel: Mahlzeitendraft oder Rezeptdraft. Mehrfachauswahl wird lokal gehalten und zeigt Menge/Einheit im Auswahlbereich. Hinzufügen übernimmt einmal atomar in den Zielentwurf; Zurück verwirft nur die Pickerauswahl. Ein zweiter Tipp auf ein ausgewähltes Ergebnis entfernt die Auswahl, statt dieselbe Zutat heimlich zu duplizieren. Bewusste doppelte Rezeptpositionen sind später im Editor möglich.

Lokale Suche, Barcode und manuelles Anlegen führen in denselben Picker-Vertrag. Treffer zeigen tatsächliche Herkunft; kein blaues Qualitätssiegel ohne überprüfte Definition. Neue unbekannte Lebensmittel dürfen mit Name und Menge hinzugefügt werden; unvollständige Summen bleiben kenntlich. Ein leeres Suchergebnis bietet Anlegen und einen expliziten Onlineweg. Externe Provider und Lizenzen werden vor Implementierung gewählt, nicht aus dem Bevel-Screenshot abgeleitet.

**Abnahme:** Banane 100 g / 90 kcal / 1/20/0 g wird dem separaten Rezeptbeispiel hinzugefügt: 540 kcal und 30/72/11 g. Auswahl ohne Bestätigung ändert den Rezeptdraft nicht. Verlassen, erneutes Öffnen und Fehler duplizieren keine Auswahl. Lange Listen scrollen über einer festen Bestätigungsleiste; Tastatur verkleinert die Inhaltsfläche.

## B11 · Sammlung und Favoriten

**Aus Flow 009.** Merken speichert eine lokale Definition oder Rezeptversion, keinen Verzehreintrag. Bei einem neuen Rezept wird der gültige Rezeptdraft als Vorlage gespeichert; bei einer bestehenden Definition toggelt Merken nur deren Favoritenstatus. Die Sammlung enthält Suche und Filter für Lebensmittel/Rezepte. Entfernen aus der Sammlung löscht keine historischen Einträge und keine Zutaten fremder Rezepte.

„Zur Mahlzeit hinzufügen“ erzeugt eine Kopie mit definierter Portion im geöffneten Mahlzeitendraft; außerhalb eines Drafts fragt der gemeinsame Einstieg nach dem Tag. Favoritenaktionen sind idempotent und erhalten bei Schreibfehler ihren letzten bestätigten Zustand. Kein Mengen- oder Kalorienanstieg allein durch Merken.

Gespeicherte Rezeptdetails öffnen für Zutaten-/Portionsänderungen wieder einen separaten Bearbeitungsentwurf. Erst dessen explizites Speichern erzeugt eine neue Rezeptversion. Die Sammlung bleibt beim Öffnen und Schließen unverändert.

## B12 · Nährwertübersicht je Nährstoff

**Aus Flow 010.** Die Summe im Mahlzeitendraft öffnet eine kompakte Nährwertübersicht. Energie/Makros, weitere Angaben und Herkunft verwenden dieselbe Aggregation wie die Vorschau. Für jeden Nährstoff separat liefern: bekannte Summe, Anzahl bekannter/beabsichtigt null/fehlender Einträge, Einheit und Quellen. Ein vollständig bekannter Energiewert erlaubt keine Aussage über Ballaststoffe oder Mikronährstoffe.

Das Beispiel zeigt für zwei ungespeicherte Einträge 620 kcal und 36/80/18 g; Zucker ≥8 g stammt nur aus dem Joghurt, das Frühstück hat keinen Zuckerwert. Ballaststoffe, gesättigte Fette und Salz fehlen bei beiden. Fehlend wird als „Offen“ gezeigt; eine bekannte 0 bleibt 0. Bei einem unbekannten Teil ist die bekannte Summe eine Untergrenze, kein vollständiger Wert. Der reine Kaffee des gespeicherten Tages gehört nicht in diese Draft-Summe.

Bestehende `NutrientTotal`-Semantik wiederverwenden und um zählbare Herkunft/Abdeckung ergänzen. Einheitenkonvertierung explizit; Salz und Natrium nur mit benannter fachlicher Umrechnung, nicht als identisches Feld. Keine neue Nährwertbewertung oder erfundener Nutrition Score.

## B13 · Fotos als lokale Einträge, optionale Vorschläge

**Aus Flow 011.** Der iOS-Fotopicker übergibt nur ausgewählte Bilder; kein pauschaler Mediathekzugriff. Ein lokaler Fotoentwurf kann ohne Nährwerte gespeichert werden. Anhänge haben lokale IDs, Original/Thumbnail, Datum und zugeordneten Draft/Entry. Beim Entfernen Referenzen beachten, nicht blind ein gemeinsam verwendetes Original löschen.

Optionale Fotovorschläge sind ein eigener, expliziter Auftrag an den konfigurierten KI-Anbieter. Vor Versand nennt die Aktion die Datenweitergabe; Kostenmodell gehört zum Anbieter-Setup. Ohne Einrichtung bleiben lokales Foto, manuelle Angaben und Suche nutzbar. Keine Accountpflicht. Ein bildfähiger Providervertrag, Größenbegrenzung, sichere Schlüsselablage und Fehlerübersetzung sind neue Arbeit; bestehender Textcoach allein genügt nicht.

`FoodResolutionJob` hält Draft-ID, Version, Status (`queued/running/ready/failed/cancelled`), Anhänge und Kandidaten. Hintergrund/Relaunch verlieren keinen Entwurf. Abbrechen verhindert spätere automatische Übernahme; verspätete Ergebnisse dürfen keine inzwischen bearbeitete Draft-Version überschreiben. Keine Prozentanzeige ohne bekannte Gesamtarbeit. Bereit/Fehler erscheint am selben Entwurf; keine automatische Tagesbuchung.

Erkannte Lebensmittel sind Vorschläge. Unbekannte Menge bleibt offen. Im gezeigten Fall wird Haferbowl vorgeschlagen; der Nutzer kann bewusst die eigene Haferfrühstück-Definition 450 kcal je Schüssel wählen und die Portion bestätigen. Nur dann gelten deren hinterlegte Nährwerte. Ein Foto allein erzeugt weder Gramm noch kcal. Falls später Schätzwerte angeboten werden, brauchen sie einen eigenen Herkunfts-/Unsicherheitsstatus bis in Tagesaggregation und Verlauf; sie dürfen nie als deklarierte Werte erscheinen.

**Abnahme:** Keine Einrichtung, Einzelfoto, mehrere Fotos, Upload-/Providerfehler, offline, Abbruch, Relaunch, verspätetes Ergebnis, eigenes Lebensmittel ausgewählt, unbekannte Portion und nur Foto gespeichert. Gewählter Tag bleibt beim Wechsel in den Hintergrund erhalten. Die ursprüngliche Bowl-Illustration wurde in Flow 031 durch ein originales synthetisches Beispielfoto ersetzt; siehe assets/GENERATED_ASSETS.md. Kein Nutzerfoto oder Bevel-Asset.

## B14 · Kamera und Etiketterfassung

**Aus Flow 012.** Ein eigener Kameraeinstieg bündelt Foto, Etikett und Barcode. Aufnahme ist zunächst ein lokaler Draft-Anhang und führt zur Vorschau aus B13; Auslösen speichert noch keinen Verzehr. Fotoauswahl und manuelle Eingabe bleiben gleichwertige Auswege. Kamera erst beim Öffnen der Funktion anfragen; bei dauerhafter Ablehnung „Einstellungen öffnen“ statt erneut eine aussichtslose Systemabfrage auszulösen.

Etikettmodus ist eine zusätzliche eigene Produktentscheidung: OCR auf dem Gerät liest Nährwertfelder mit Bezugsmenge und Einheiten. Ein Feld bleibt ein zu prüfender Kandidat, wenn Zahl, Komma oder Einheit unsicher ist. Ein Foto einer Mahlzeit ist keine Nährwerttabelle. Etikettvorschau muss insbesondere je 100 g / je Portion trennen, und Originalausschnitt zur Korrektur behalten. Providerfreie lokale OCR und ein Review-Modell sind neue Integrationsarbeit; konkrete iOS-/Flutter-Brücke wird nach Designreview gewählt.

**Abnahme:** Erstfreigabe, dauerhafte Ablehnung, eingeschränkte Kamera, App im Hintergrund, Bild verworfen, Wiederaufnahme, Orientierung, Mediathek mit einzelnem Bildzugriff; kein Upload durch Auslösen. Zoomstufen nur anbieten, wenn das Gerät sie unterstützt. Der gewählte Tag kommt aus dem Draft, nicht aus der Aufnahme-Uhrzeit.

Die Etikettansicht zeigt ein synthetisches Beispiel: je 100 g Haferflocken 383 kcal, Protein 13,3 g, Kohlenhydrate 60 g, Fett 6,7 g. OCR liefert beim Fett zunächst „6,?“ als unsicheren Text. Bis Korrektur oder bewusstem Offenlassen ist Übernehmen deaktiviert. Ein bewusst ausgelassener Wert bleibt `null`, kein geschätztes 6,0. Die vier Angaben sind ein separates OCR-Beispiel; gerundete Referenzwerte dürfen bestehende Rezept-Snapshots nicht automatisch ersetzen.

## B15 · Barcode-Suche mit Quelle und prüfbarer Portion

**Aus Flow 013.** `off_lookup.dart` und `nutrition_store.dart` bieten bereits Cache, Portionsskalierung und `ok/notFound/flagged/unreachable/refused`. Diese Zustände wiederverwenden. Zahlen aus der Produktdatenbank sind deklarierte Fremdangaben, keine Messwerte. Bestehende Plausibilitätsprüfung und Null-Semantik erhalten; verworfene Werte bleiben offen. Produktdaten, Cache-Datum, ursprüngliche Quelle und Nutzerkorrekturen müssen in Details nachvollziehbar bleiben.

**Bewusste Designänderung:** Der aktuelle Getter nutzt nach geladenen Preferences Default `true`. Der Entwurf wählt bei der ersten nicht lokal auflösbaren Suche ausdrücklich zwischen einmaliger Onlineabfrage, gemerkter Erlaubnis und lokalem Weg. Bestehendes explizites Opt-out erhalten. Neueinstellungen/Altinstallationen brauchen einen klaren Migrationsentscheid; eine fehlende Preference ist keine dokumentierte aktive Zustimmung. Keine neue Einwilligungsabfrage bei jedem Scan, sobald die Wahl gespeichert ist.

Kamera und manuelle Codeeingabe liefern denselben validierten Produktschlüssel. Wiederholte Kameraframes lösen keinen zweiten Lookup aus. Ein Ergebnis wird erst mit gewählter Portion in den Draft übernommen. Synthetisches Beispiel: Code 2000000000015, Joghurt 85 kcal sowie 7/10/2 g je 100 g → bei 200 g 170 kcal und 14/20/4 g, Ballaststoffe unbekannt. Es fand keine echte Produktabfrage statt. Für diesen unabhängigen Beispielpfad ist die Herkunft Datenbank; der Tagesfixture-Joghurt bleibt manuell eingetragen.

Keinen parallelen Multi-Scan-Modus übernehmen: ein Produkt führt direkt zur Prüfung, danach kann ein weiteres in denselben Mahlzeitendraft. Das hält Portion/Quelle je Produkt eindeutig. Bei unbekanntem Code Etikett und manuelles Anlegen anbieten; bei Netzwerkfehler Retry; bei Qualitätsfehler Original nicht als nullwertiges Produkt übernehmen. QR-Inhalte sind keine Produktcodes und öffnen keine beliebigen Links.

[Offizielle OFF-Lizenzübersicht](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorials/license-be-on-the-legal-side/): Datenbank ODbL, Einzelinhalte DbCL, Produktbilder CC BY-SA. Quellen-/Lizenzhinweis sichtbar an übernommenen Werten und erreichbar aus Aggregaten; bei Export Herkunft/Lizenz erhalten. Hier werden keine fremden Produktbilder verwendet. Beim späteren Provider-/Datenbankumbau Weitergabe- und Kombinationsbedingungen erneut konkret prüfen.

## B16 · Suche mit stabiler Auswahl und sichtbarer Herkunft

**Aus Flow 014.** Lebensmittelpicker aus B10 erhält die Mahlzeit als Ziel. Auswahl über mehrere Suchbegriffe bleibt erhalten; stabile IDs verhindern Duplikate und falsche Markierungen bei gleichnamigen Produkten. Treffer zeigen die tatsächlich verwendete Portion und Quelle. „Prüfen“ führt erst in den Mahlzeitendraft, nicht direkt in den Tag. Zuletzt verwendet wird aus Entry-Zeitpunkten abgeleitet, Sammlung aus Favoriten; bestehende alphabetische food_def-Suche darf nicht als Recency ausgegeben werden.

Lokale Suche funktioniert offline. Ein eigener Online-Einstieg ergänzt einen `FoodCatalog.search`-Vertrag mit Abbruch, Pagination, Query-Version und Quellen-/Einheitenprüfung. Der Entwurf nutzt Open Food Facts als benannte Produktquelle; dessen konkreten Suchendpunkt, Lastgrenzen und Caching vor Umsetzung an aktueller offizieller Dokumentation festlegen. Keine private Lebensmittelsammlung an den Dienst übertragen. Eine Barcode-Erlaubnis deckt Suchtexte nicht automatisch ab: der erste Online-Suchschritt benennt Suchbegriff und IP als übermittelte Daten; danach gilt die gespeicherte Auswahl für diesen Weg.

Late Antworten dürfen aktuelle Suchtreffer nicht überschreiben. Kein Treffer, offline und Providerfehler sind verschiedene Zustände. Ergebnisse bleiben bearbeitbare Fremdangaben mit Lizenzhinweis; unbekannte Nährwerte bleiben offen. Der Zugriff auf Datenbanktreffer ist kein Verifiziert-Siegel. Externe Quelle vor Draftübernahme nach denselben Datenregeln wie Barcode prüfen. Änderungen am Produktkatalog dürfen historische Verzehreinträge nicht rückwirkend ändern.

## B17 · Verständliche Nährstofferklärungen

**Aus Flow 015.** Gemeinsame Erkläransicht aus Nährwertübersicht, Nährstoffdetail und Zielbearbeitung. Reihenfolge/Farben bleiben Protein, Kohlenhydrate, Fett. Keine personalisierte Empfehlung und kein neuer Zielalgorithmus durch diesen Hilfetext. [DGE: Energie](https://www.dge.de/wissenschaft/referenzwerte/energie/) und [DGE: FAQ Energiezufuhr](https://www.dge.de/gesunde-ernaehrung/faq/energiezufuhr/) stützen die allgemeinen Faktoren 4/4/9 kcal je Gramm (geprüft 16.09.2026).

Im synthetischen Draft ergeben 36/80/18 g rechnerisch 626 kcal; die eigenen Lebensmitteleinträge nennen zusammen 620 kcal. Beides darf mit Herkunft erhalten bleiben; eine UI darf die deklarierte Energie nicht still durch eine Makrorechnung ersetzen. Faktoren dienen der Erklärung und vorhandenen Plausibilitätsprüfung, nicht der Ergänzung fehlender Nährstofffelder. Redaktionelle Inhalte und Quellen als versionierte, lokalisierte Ressource bündeln; keine KI-Antwort für diesen stabilen Grundtext nötig.

## B18 · Lokales Profil statt Kontoverwaltung

**Aus Flow 016.** Das Bevel-Konto mit Anmeldung/Abmelden/Konto löschen wird nicht übernommen. OpenBand hat einen lokalen Profilbereich mit Band, persönlichen Angaben, Zielen, optionalem Anbieter und Datenverwaltung. Daten löschen ist ein separater, eindeutig benannter Daten-Flow, kein fingiertes Konto-Löschen. Bandverbindung, Akku und jüngster lokaler Speicherstand bleiben getrennte Aussagen.

Den vorhandenen `PersonalProfile`-Vertrag mit echtem `birth_date` und datiertem `forDate` verwenden. Alter nicht unabhängig speichern oder aus einem früheren Alter ein Geburtsdatum erfinden. Das zusätzliche Profilbeispiel enthält 18.02.2000, 180 cm und 75,0 kg; die Angaben sind synthetisch und freiwillig. Für Berechnungskoeffizienten „Keine Angabe“ ist tatsächlich fehlend; keine stillen männlichen oder gemittelten Ersatzwerte. Die gegenwärtige workoutSex-Abbildung kennt einen Mittelwertpfad; fehlende Eingänge müssen vor dessen Verwendung korrekt abgefangen werden.

Editor mit eigenem Draft, explizitem Speichern, Abbrechen und bestätigtem Import aus Apple Health. Historische Neuberechnung nach geänderten Berechnungsangaben getrennt vom erfolgreichen Profil-Commit zeigen; Rohdaten nicht überschreiben. Fehler bewahrt Eingaben. Ein Profil, das alle benötigten Werte nur für einzelne Metriken hat, darf deren Ergebnisse nicht durch ein pauschales isComplete-Gate verlieren. Bestehende aktuelle Profilarbeit wurde gelesen, nicht geändert.

„Deine Ziele“ ist der gemeinsame Zugang zu unabhängig verwalteten Zielbereichen. Nur eingerichtete Zieltypen erscheinen mit einem Wert; ohne Ziel zeigt der jeweilige Bereich eine Einrichtungsaktion. Die Detailverträge werden in den jeweiligen Ernährungs-/Schlaf-/Trainingsflows festgelegt, nicht durch den Profil-Hub impliziert. Ein vollständiger zentraler Zielvertrag wird vor Designabschluss gegen diese Flows abgeglichen.

## B19 · Aktivitätsdetails mit belastbaren Quellen

**Aus Flow 017.** Aktivität öffnet als eigener Detail-Stack ohne untere Hauptnavigation; Zurück erhält Tag, Filter und Scrollposition des Herkunftsbereichs. Erster Bildschirm: Route/Distanz, Aktivzeit, Tempo, geschätzte Energie und Einheitsbelastung, kompakte Einordnung und Puls. Weiter scrollen zu Abschnitten, Puls nach Ende, Quellen, persönlicher Anstrengung, Notiz, Bearbeiten und Teilen. Karte ist nur vorhanden, wenn eine Route existiert; eine manuell erfasste Einheit bleibt ohne erfundene Messwerte nutzbar. Bevel dient der Informationsdichte und gestuften Vertiefung als Referenz, nicht als Quelle für Scores oder Assets.

**Vorhanden:** `getWorkout` liefert Pulsstatistik und Abdeckung, `getWorkoutRoute` Route/Abschnitte, `manual_session.dart` Einheits-TRIMP, Belastung und Energie, `sessions.zone_min` Zonen, `strength_set` Sätze. Die vorhandene Pulsdarstellung kennt Null-Lücken. Quellen wurden gelesen, nicht geändert.

**Notwendige Verträge:**

- Dauer eindeutig modellieren: Zeit zwischen Start/Ende, pausierte Intervalle, Aktivzeit, GPS-Bewegungszeit sind verschieden. Live-Pausen werden aktuell nicht vollständig in der gespeicherten Sitzung erhalten; `stopWorkout` und gespeicherte Dauer dürfen nicht einen pausebereinigten Live-Wert still ersetzen. Pulsabwesenheit ist keine Pause.
- Dauerhafte Detail-Snapshots mit Algorithmusversion, Eingängen, Quellen, Einheit und Bereitschaft je Ergebnis. `workout_split` wird beim Rescore geschrieben, aber die aktuelle Routenansicht berechnet aus Rohpunkten; nach deren Aufbewahrungsfrist müssen gespeicherte Abschnitte/Route weiter korrekt lesbar sein. Keine Historie, die nach wenigen Tagen scheinbar kürzer wird.
- Zonen dokumentieren Grenzquelle: Karvonen, beobachtete oder geschätzte HFmax; aktuelle Grenzen nicht auf ungeprüft alte Zonenzeit schreiben. Das Beispiel nutzt Tanaka, 26 Jahre, 189,8/min → Anzeige 190. Der strengere Filter für globale 28-Tage-Zonen ist kein Grund, eine als geschätzt bezeichnete Einzelsitzung zu verstecken.
- Einheitsbelastung ist 0–21 und von Tages-TRIMP, Tagesbelastung und langfristigen Trainingswerten getrennt. Kein Bevel-„Cardio impact“ aus einer frei gewählten Differenz, keine automatische Übertrainingsnote. Eigenes Skalenmodell in Hilfe erklären. Geschätzte Energie als Schätzung für die gesamte Einheit, nicht als gemessene oder ausschließlich aktive kcal benennen.
- Ergebnisbereitschaft getrennt von Quellenabdeckung. Im Teilbeispiel fehlen 07:14–07:18, 21/25 Minuten Puls; Route/Tempo bleiben vollständig. Pulsgraph unterbricht sichtbar. Belastung/Energie bleiben in diesem Beispiel offen, statt den vollständigen Zahlenwert zu behalten. Konkrete Qualitätsregeln müssen pro Algorithmus benannt werden; 84 % allein ist weder ein allgemeiner Erfolg noch ein allgemeiner Fehler.
- Puls nach Ende: vorhandenes `ana.hrRecovery` nimmt das Maximum der letzten 30 Sekunden und Median um den Zeitpunkt ±3 Sekunden; die gespeicherte `recovery_curve` nutzt dagegen Median der letzten 15 Sekunden und ±7 Sekunden danach. Diese unterschiedlichen Ausgangswerte nicht zu einer scheinbar einheitlichen 60-/120-Sekunden-Kurve zusammensetzen. Gemeinsamen versionierten Vertrag für Ausgangswert, 60/120 Sekunden, Zeitgewichtung, Lückenprüfung und gespeicherten Nachlauf schaffen. Unvollständiger Nachlauf bleibt separat offen. Keine Fitnessnote aus einer einzelnen Messung.
- Krafttraining: Arbeits- und Aufwärmsätze, Wiederholungen, Last und RPE als eigene Eingaben. Volumen nur aus bekannten Lasten; Eigengewicht ist keine Last von 0 kg. Muskelzuordnung aus Übungskatalog wäre eine Kataloginformation, keine gemessene Muskelbelastung. Keine Prozent-Heatmap. Im Beispiel 3×8×60 + 3×8×40 + 3×10×30 = 3.300 kg, neun Arbeitssätze. Satz-RPE und Anstrengung der ganzen Einheit sind verschiedene Angaben.
- RPE/Notiz/Bearbeiten wirken über eigene Entwürfe; keine automatische Neuberechnung aus einer geänderten Notiz. Teilen öffnet eine prüfbare Vorschau; Route und Profilangaben standardmäßig nicht in einem exportierten Bild. Details zu Edit-/Share-/Save-Flows folgen deren Katalogreview.

**Zahlenprüfung:** [Synthetische Lauf-Fixture](assets/fixtures/run-detail.json), mit den vorhandenen reinen Dart-Algorithmen berechnet: 5 km / 25 Minuten, Ø142,1967/min, Maximum162/min, Zonen 0/6/15/4/0 Minuten, TRIMP37,0474, Belastung5,8716, Energie327,2537 kcal. HRR60=20 und HRR120=32/min mit demselben Ausgangswert143/min. Abschnitte 4:55/5:10/5:05/4:58/4:52 summieren exakt25:00, Spanne18Sekunden. Vollständiges synthetisches Profil männlich, 18.02.2000, 180cm, 75kg. Die Variante „Gewicht fehlt“ lässt nur davon abhängige Ergebnisse offen. Reine Zahlenprüfung ist keine App-, Bluetooth-, Hardware- oder physiologische Validierung.

**Darstellung geprüft:** editierbare Paper-Details mit echten Lucide-SVGs, eigene schematische Route, echte Fixture-Minutenwerte statt dekorativer Kurve; Light/Dark, 393×852 sowie 375×812 mit größerer Schrift und umgebrochenen Kennzahlen. Langer Inhalt scrollt; ein eigener Fortsetzungsentwurf zeigt die darunter liegenden Aktionen. Kein App-Code wurde implementiert.

## B20 · Trainingsverlauf, Zeitraum und Filter

**Aus Flow 018.** Die Referenz zeigt Fitness-Übersicht, kumulierten Zeitvergleich und eine chronologische Aktivitätenliste. OpenBand verwendet eine gemeinsame Verlaufsseite: 7/30/90 Tage oder Jahr, klar benannter Zeitraum, Aktivitätsfilter, Tagesbalken und die zugehörigen Einheiten. Der Filter ändert Zahlen, Diagramm und Liste gemeinsam; er tauscht nicht den Diagrammtyp. Ein leerer Zeitraum bietet Rückkehr zum aktuellen Zeitraum und Nachtragen. Zurück aus einer Einheit stellt Datum, Filter und Scrollposition wieder her.

Der vorhandene `getWorkouts(range)` bezieht sich auf `DateTime.now()`, summiert Minuten/Kalorien mit Null→0 und schließt live aus. Für Datumsauswahl und Vergleiche braucht es explizite lokale Kalendergrenzen, Zeitzone, Aktivitätsfilter und getrennte Ergebnisse für Liste/Aggregation. Zeitumstellung und Einheiten über Mitternacht beachten: Gesamtzeit ohne Doppelzählung nach Tagesüberschneidung aufteilen, Sitzung in der Liste einmal unter ihrem Starttag. Vorheriger Zeitraum hat dieselbe Kalenderlänge; Zukunft endet am gewählten Vergleichszeitpunkt, kein voller vergangener Tag gegen einen angefangenen heutigen.

Minuten aus bekannten abgeschlossenen Sitzungen sind etwas anderes als Pulserfassung. Unbekannte Dauer macht eine Summe unvollständig und wird nicht 0; fehlende Kalorien führen zu einer gekennzeichneten Teilsumme, auch wenn alle Dauern bekannt sind. Doppelte Imports brauchen stabile Quellenidentität, manuelle und erkannte überlappende Einheiten einen nachvollziehbaren Abgleich. Eine leere lokale Liste ist keine bewiesene Trainingspause. Spätere Imports dürfen Summen ändern; Datenstand und Herkunft bleiben einsehbar.

Synthetischer Zeitraum 9.–15.09.2026: Radfahren am 12.09. 32 Minuten, Kraft am 13.09. 45 Minuten, Lauf am 14.09. 25 Minuten = 102 Minuten in drei Einheiten. Tagesbalken [0,0,0,32,45,25,0] zeigen gespeicherte Zeit. Vergleich 2.–8.09.: zwei Rad-/Krafteinheiten mit 35 und 43 Minuten = 78; Differenz +24 Minuten. Kein Lauf im Vergleichszeitraum. Das Label „Letzte 7 Tage“ ersetzt die irreführende Kalenderwoche auf dem Training-Hub. Der Lauf-Herzgraph dort verwendet dieselben Minutenwerte wie das Detail.

**Abnahme:** Alle/Einzelaktivität/Weitere, leere Auswahl, früherer Zeitraum, aktueller Teilzeitraum, DST, Mitternacht, fehlende Dauer/Energie, laufende Einheit ausgeschlossen, Importduplikat und Rückkehr aus Details. Paperviews Alle/Laufen/leer sowie der angepasste Training-Hub in Light/Dark wurden visuell geprüft; kein Repository-Umbau umgesetzt.

## B21 · Neues Rezept als Vorlage anlegen

**Aus Flow 019.** Die Sammlung öffnet einen eigenen Rezeptentwurf mit Name, Portionszahl und Zutaten für das ganze Rezept. Mehrfachsuche, Mengeneditor und Importprüfung aus B08–B16 werden wiederverwendet. Speichern braucht einen Namen, mindestens eine Zutat und eine positive Portionszahl; unbekannte Nährwerte dürfen unbekannt bleiben. Nach lokal bestätigtem Commit erscheint die Sammlung mit dem neuen Rezept. Kein Tages- oder Mahlzeiteneintrag wird dabei erzeugt.

Gesamtzutaten, fertige Portionszahl und optional gewogenes fertiges Gesamtgewicht sind getrennte Angaben. Kochverlust/-wasser darf nicht aus der Rohzutatenmasse erfunden werden. Grammportionen sind nur mit bekanntem fertigem Gewicht berechenbar; ansonsten bleibt die benannte Portion verfügbar. Ändern der Portionszahl verändert den Nährwert pro Portion, nicht heimlich die Zutatenmengen. „Rezept skalieren“ wäre eine gesonderte bewusste Aktion. Vergangene Verzehr-Snapshots bleiben gemäß B08 unverändert.

Synthetischer neuer Entwurf: 120 g Hafer 460 kcal + 300 g Skyr 190 + 200 g Beeren 90 + 26 g Mandeln 160 = 900 kcal. Zwei Portionen ergeben jeweils 450 kcal und 29/52/11 g. Fertiges Gesamtgewicht ist bewusst unbekannt; die Summe der Rohmassen 646 g wird nicht automatisch zur Portionsbasis. Derselbe Nährwert pro Portion entspricht dem bereits verwendeten separaten Rezeptbeispiel, nicht einem zusätzlich gespeicherten Tagesverzehr.

Name/Portionen/Zutaten bleiben bei lokalem Schreibfehler und App-Unterbrechung als Draft erhalten. Wiederholen desselben Speicherauftrags erzeugt keine zweite Definition. Zurück mit Änderungen verwendet die gemeinsame Entwurf-verwerfen-Abfrage; ohne Änderungen direkt zurück. „Abbrechen“ löscht keine bereits gespeicherte Rezeptversion.

**Prüfung:** Sechs Quellpositionen vollständig angesehen; Paper zeigt leer/deaktiviert, ausgefülltes Rezept, lokalen Erfolg in der Sammlung und Speicherfehler mit erhaltenen Eingaben. Bestehende Zutatenpicker/-mengenansichten ergänzen den Ablauf. Neue Rezeptobjekte und Persistenz bleiben Implementierungsarbeit.

## B22 · Bandwecker und schneller Abend-Einstieg

**Aus Flow 020.** Vier Quellpositionen zeigen Bevel-Weckereinstellungen, Erklärung mehrerer Alarmarten, Apple-Watch-Einstieg und eine Kurzbefehle-Verknüpfung. OpenBand übernimmt den schnellen Einstieg, jedoch keinen Apple-Watch-Flow und keine unbewiesene schlafphasenabhängige Weckfunktion. Die eigene Ansicht zeigt die nächste geplante Uhrzeit, deren konkrete Bandbestätigung und darunter den Wochenplan. Nur der nächste Termin liegt als Wecker auf dem Band; wiederkehrende Wochentage müssen über die bestehende Planlogik nachgestellt werden. Eine Testvibration beweist keinen künftigen Termin.

Vorhandene Quellen: `state/alarm_schedule.dart` berechnet nächste Kalendertermine und setzt den nächsten Bandwecker; `ui2/profile/alarm.dart` hat none/pending/confirmed/unknown; `AppState.setScheduleDay` speichert lokal und überträgt bei Verbindung. Der Kommentar der View behauptet teilweise pauschale Offlinefehler, die aktuelle Methode erlaubt jedoch lokale Planänderungen. Der Entwurf folgt dem tatsächlichen Verhalten: lokaler Plan gespeichert und auf Band bestätigt sind getrennte Zustände. Bei Trennung bleibt der lokale Plan bearbeitbar; der nächste nicht bestätigte Termin bietet Verbinden/Prüfen, ohne Erfolg zu suggerieren. Bestätigungen müssen zum Ziel-Epoch und Band gehören; Relaunch, verspätete Events und zwischenzeitlich geänderte Ziele korrekt behandeln. Zeitzonenwechsel/DST aus Kalenderarithmetik weiter prüfen.

Neue native Integration: App Intent „Wecker öffnen“ öffnet diesen Stack mit geladenem lokalen Plan und aktueller Bestätigung; kein eigener zweiter Alarm-Writer. [Apple: App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts) beschreibt automatisch verfügbare App-Aktionen sowie ShortcutsLink/ShortcutsUIButton zum App-Bereich in Kurzbefehle; [HIG](https://developer.apple.com/design/human-interface-guidelines/app-shortcuts) beschreibt Siri/Spotlight/weitere Einstiegspunkte. Quellen geprüft 16.09.2026. Flutter braucht eine native iOS-Brücke und eindeutiges Routing bei Kaltstart. Im gelesenen iOS-Runner ist diese Integration noch nicht vorhanden.

Die eigene Einrichtungsseite führt in den Systembereich von Kurzbefehle. Weitere iPhone-Aktionen setzt der Nutzer dort zusammen; OpenBand behauptet weder Fokusänderung noch erfolgreiche Installation einer Routine allein durch Rückkehr aus der System-App. Ohne native Verfügbarkeit wird die Einrichtung nicht als ausführbare Aktion angeboten; Wecker direkt öffnen bleibt möglich. Kein fremdes Kurzbefehle-Paket importiert, kein Bevel-Asset übernommen. Die konkrete Systemdarstellung muss beim späteren iPhone-Build geprüft werden.

**Prüfung:** Bestätigter Wecker, getrenntes Band ohne Bestätigung und Kurzbefehle-Hilfe in Paper neu gestaltet und visuell geprüft. Keine Bandbefehle, Alarmänderungen oder App-Intent-Ausführung vorgenommen. Wochenplanbearbeitung/Deaktivierung wird im eigenständigen Alarm-Flow weiter vertieft.

## B23 · Trainingsvorlagen als eigene Pläne

**Aus Flow 021.** Die Referenz zeigt Einstieg über Vorlagen, leeren Editor und einen gefüllten Plan mit Übungs-/Satzfeldern. OpenBand ersetzt die bisherige reine Übungsnamensliste durch echte geplante Sätze. Die eigene Ansicht nutzt kompakte Felder für Gesamtgewicht und Wiederholungen, zusammenklappbare Übungen und eine feste Speicheraktion. Zeitbasierte Übungen behalten Sekunden statt fingierter Wiederholungen. Name und mindestens eine Übung sind nötig; vollständig ausgefüllte Lasten sind keine Voraussetzung für eine Vorlage.

Neu nötig: versionierte lokale `WorkoutTemplate` mit geordneter Übungsliste, stabilen Exercise-IDs, geplanten Set-IDs, Set-Typ, Wiederholungs- oder Zeitvorgabe, optionaler Last, Pause und Notiz. `strength_set` speichert gegenwärtig ausgeführte Sätze; `exercise_def` ist angelegt, aber noch kein vollständiger benutzter Katalog. Geplante Zeilen gehören nicht in diese Sitzungstabelle. Beim Start entsteht ein eigenständiger Session-Snapshot; erst das Bestätigen eines Satzes macht ihn zu einem ausgeführten Satz. Änderungen an Vorlage oder Übungskatalog dürfen keine bereits gespeicherte Einheit ändern.

Synthetischer Plan Ganzkörper A: Bankdrücken 3×8×40 kg, Rudern 3×10×30 kg, Kniebeuge 3×8×60 kg, Plank 3×45 Sekunden = vier Übungen, zwölf geplante Arbeitssätze. Dies ist ein zukünftiger Plan, kein vierter Datensatz im historischen Drei-Übungen-Krafttraining aus B19. Gewichtsangabe zunächst Gesamtgewicht; Langhantel-/Scheibenhilfe folgt Flow 022. Aufwärmen, Supersätze und Reihenfolge bekommen eindeutige Typen statt Textpräfixe; ihre tatsächlichen Interaktionen werden in den passenden folgenden Referenzflows gestaltet.

Vorlagenbearbeitung verwendet einen wiederaufnehmbaren Draft, atomisches Speichern, Rückkehr zum Vorlagenkontext und gemeinsame Verwerfen-Abfrage. Speicherfehler behält alle Felder; Wiederholen aktualisiert dieselbe Vorlagen-ID/Version statt ein Duplikat anzulegen. Entfernen einer Vorlage löscht keine aufgezeichneten Sätze. Such-/Übungspicker erhält den Ziel-Draft und übernimmt erst nach Bestätigung. Noch nicht beobachtete Picker-/Save-/Superset-Details sind durch diesen Review nicht abgeschlossen.

**Prüfung:** Alle drei Quellpositionen angesehen; Paper-Editor ersetzt, leerer Zustand und Scrollfortsetzung gebaut. Gewichts-/Wiederholungsfelder sind in festen Spalten ausgerichtet, vollständige Vorlage scrollt oberhalb der festen Speicherleiste. Keine neuen App-Tabellen oder Algorithmen implementiert.

## B24 · Eigene Stangen und verfügbare Gewichte

**Aus Flow 022.** Sechs Quellpositionen zeigen Geräteauswahl beim Vorlagengenerator, verfügbare Stangen/Scheiben, Hinzufügen-Menü, Zahlentastatur und die gespeicherte neue Stange. OpenBand bietet eigene Ausstattung im Trainings-/Vorlagenbereich mit eindeutigem Leergewicht je Stange. Eine Gerätekonfiguration ist kein ausgeführter Satz und ändert keine gespeicherte Last. Das Anlegen einer Stange setzt auch nicht automatisch deren Gewicht als Satzgesamtgewicht.

Neues lokales Equipment-Modell: stabile ID, Gerätename, Gerätetyp, Stangenleergewicht, Einheit, verfügbare Scheibengewichte und jeweilige Stückzahl. kg/lb erhalten den physikalischen Wert beim Umschalten; Kommaeingabe akzeptieren, Anzeige erst am Rand runden. Gewicht muss endlich und positiv sein; unbekannt bleibt unbekannt, kein pauschales 20-kg-Default. Gewicht geführter Geräte aus der Geräteangabe, nicht aus dem Aussehen schätzen. `ExerciseDef.step` ist bislang nur ein fester Eingabeschritt; er ist weder Inventar noch Beweis für eine ladbare Kombination.

Die eigene Gerätegrafik ist schematisch und zeigt keine Gewichtsempfehlung. Synthetischer Bestand: Stangen 20/15 kg, neu „Kurze Stange“ mit 7 kg; Scheiben je zweimal 1,25/2,5/5/10/20 kg. Ein späterer Scheibenrechner muss Gesamtlast, Stange und Last pro Seite sichtbar trennen sowie Stückzahlen und erreichbare Kombinationen berücksichtigen. Er darf einen angefragten Wert nicht heimlich auf den nächstmöglichen Wert runden. Der direkte Gesamtgewichtsweg bleibt für jedes Gerät erhalten.

Speichern/Abbruch/Fehler verwenden denselben lokalen Draft-Vertrag wie Vorlagen. Gelöschte oder umbenannte Geräte bleiben in historischen Satz-Snapshots nachvollziehbar. Vorlagengenerierung, eigene Übung und Satzeditor referenzieren dieselben Geräte-IDs, ohne einen zweiten Gerätebestand anzulegen. Details der Generierung werden erst nach ihrem eigenen Quellflow entschieden.

**Prüfung:** Alle sechs Quellen angesehen. Paper zeigt Ausgangsliste, Eingabe mit Dezimaltastatur und gespeicherte Stange. Texte, Einheiten, Tastaturabstand und Rückkehr geprüft; tatsächliche iOS-Tastatur/Umrechnung/Persistenz sind nicht implementiert.

## B25 · Eigene Karten in der Übersicht

**Aus Flow 023.** Die Referenz zeigt Bearbeitungsmodus, Katalog mit Vorschauen, eine Cardio-Load-Erklärung und die hinzugefügte Karte vor dem finalen Speichern. OpenBand verwendet denselben verständlichen Entwurfsablauf: Übersicht anpassen → Karte mit den Daten des gewählten Tages ansehen → hinzufügen → gesamten Entwurf speichern. Die Standardansicht bleibt sofort nutzbar. Tagesdatum, Bandzugang, drei Hauptwerte und kurzer täglicher Einblick bleiben als Orientierung bestehen; die darunterliegenden Bereiche sind wählbar. Ausblenden entfernt weder Messdaten noch Zugänge im zugehörigen Hauptbereich.

B03 erweitern: versionierte geordnete Karten-IDs, sichtbare Karten, optionale Konfiguration je Kartentyp, separat gespeicherter Bearbeitungsentwurf. Keine doppelte Karte durch wiederholtes Hinzufügen. Ein Katalog zeigt nur noch nicht eingeblendete Kartentypen; ein Detail erklärt Inhalt/Zeitraum vor Übernahme. Speichern ist atomar; Abbrechen/Zurück mit Änderungen verwirft nach gemeinsamer Abfrage. „Standard wiederherstellen“ ändert zunächst den Entwurf, nicht direkt die gespeicherte Übersicht. Datenzustände verwenden B04 und bleiben unabhängig vom Layout.

Ein neues Layout gilt für andere Tage und beide Erscheinungsbilder. Jeder Inhalt erhält weiterhin seinen Zeitraum: Nacht 14./15., Tageswerte bis 07:42, Trainingsumfang 9.–15. September. Die konkrete hinzugefügte Karte zeigt 102 Minuten / drei Einheiten / +24 zum vorherigen Sieben-Tage-Fenster aus B20, mit tatsächlichen Tagesbalken. Kein Bevel-Cardio-Load-Score oder Übertrainingslabel wird übernommen. Alte Karten-IDs migrieren ohne Verlust der weiterhin bekannten Nutzerreihenfolge; neue Kartentypen nicht ungefragt nach oben schieben.

**Harmonisierter Datenstand:** [Gemeinsame synthetische Tages-Fixture](assets/fixtures/day-summary.json). Der reguläre Überblick zeigt jetzt berechenbare Erholung 74 und HRV 48 statt des bisherigen unzuverlässigen-Intervall-Falls. Die reine Dart-Auswertung wurde erneut ausgeführt: 74,062276 bei Confidence 0,75 aus HRV/RHR/Atemfrequenz; Temperatur fehlt. Kleine Puls-/HRV-Kurven verwenden die letzten sieben Baseline-Samples plus heute. Der Intervallfehler bleibt eine eigene Variante. Vier kompakte Tageswerte und Ernährung/Wasser passen oberhalb des Aktivitätsbereichs; alle weiteren Bereiche sind über Scrollen erreichbar.

**Prüfung:** Vier Quellpositionen vollständig angesehen. Editor, Vorschau, hinzugefügter Draft und gespeicherte Übersicht gestaltet. Hauptübersicht/Scrollfortsetzung und Dark-Variante aktualisiert; Ringtext, kleine Diagramme, Ebenen der Statusleiste und feste Navigation visuell geprüft. Die bestehende App hat noch keinen solchen Karten-Draft-Vertrag. Frühere Teil-/Fehler-/Großschriftvarianten werden im abschließenden vollständigen Screen-Abgleich an dieses gemeinsame Layout angeglichen; dieser Flow allein behauptet keinen fertigen Gesamtstand.

## B26 · Eigene Übungen mit eindeutiger Erfassung

**Aus Flow 024.** Neun Quellpositionen zeigen Bibliothek, eigene Übung, Name, Geräteauswahl, Wiederholungen/Zeit, primäre/sekundäre Muskelgruppen und Rückkehr zur Bibliothek. OpenBand ergänzt insbesondere die fehlende Bedeutung der Gewichtseingabe: Kurzhantelpaar, Gewicht je Hantel und Wiederholungen je Seite müssen vor dem ersten Satz verständlich sein. Muskelgruppen bleiben optional und dienen Filtern, nicht einer gemessenen Belastungsverteilung. Eine Übung braucht Name und bewusst gewählte Geräteart; „Andere / ohne Zuordnung“ ist ein gültiger expliziter Wert.

Die bisherige konstante `exerciseLibrary`/`exerciseByKey` muss mit lokalen versionierten Definitionen zusammengeführt werden; die bereits vorhandene `exercise_def`-Tabelle allein reicht nicht. Benötigt werden stabile ID, Name, Quelle, Gerätetyp/-referenz, Wiederholungs- oder Zeitmodus, Lastbasis (insgesamt, je Gerät, Eigengewicht, Unterstützung), Anzahl der Geräte und Bedeutung der Wiederholungszahl. Historische Logs behalten einen passenden Definition-Snapshot. Gleichnamige Definitionen nicht anhand ihres Namens zusammenführen; eine umbenannte Übung behält ihre ID.

Synthetisches Beispiel: Kurzhantel-Curl, zwei Hanteln, 10 kg je Hantel und 8 Wiederholungen je Seite. Die Normalisierung ergibt 20 kg gemeinsame äußere Last × 8 = 160 kg Volumen; nicht nochmals für zwei Seiten verdoppeln. Bei einseitigem Training oder ungleichen Wiederholungen müssen die Seiten getrennt erfassbar sein. Haltezeit ist kein Wiederholungswert. Eigengewicht, Zusatzlast und Assistenz unterscheiden; fehlende äußere Last ist kein 0-kg-Training. Alte Sätze mit unbekannter Lastbasis nicht rückwirkend als „je Hantel“ interpretieren.

Speichern erzeugt eine Definition in der Bibliothek. Das anschließende Plus wählt sie für den geöffneten Vorlagen-/Live-Draft; erst dessen Hinzufügen übernimmt sie dort. Zurück erhält Suchbegriff, Filter und bestehende Auswahl. Bearbeitungsfehler erhält den Draft. Der bestehende `strength_set.load_kg`-Weg braucht die normalisierte Last plus nachvollziehbare ursprüngliche Eingabe/Basis; Auswertungen und Exporte müssen diese Semantik gemeinsam verwenden.

**Prüfung:** Alle neun Quellen angesehen. Paper zeigt unvollständiges Formular, vollständig konfigurierte Übung, Geräteauswahl und Rückkehr zur Bibliothek. Name/Gerät/Modus und optionale Gruppen sind nachvollziehbar; 44-pt-Ziele und Bildschirmhöhe geprüft. Die Bibliotheksauswahl ist nach dem Speichern weiterhin leer, damit kein Satz oder Vorlageneintrag unbemerkt entsteht. Übungspicker, Löschen und Eingaben im Training werden in ihren eigenen späteren Flows weiterentwickelt.

## B27 · Eigene Lebensmittel und Nährwertbasis

**Aus Flow 025.** Vier Quellpositionen zeigen Sammlung, leere Definition, ausgefüllte Nährwerte und gespeichertes Lebensmittel. Die Referenz enthält widersprüchliche Beispielwerte; OpenBand übernimmt den kompakten Formularaufbau mit ausdrücklich sichtbarer Nährwertbasis und einer Korrekturansicht. Anlegen speichert nur die Definition. Eine übliche Portion hilft beim späteren Eintragen und erzeugt noch keinen Ernährungseintrag.

`nutrition_store.dart` hat bereits `food_def` mit Angaben je 100 g, optionalen Nährwerten und Quellenfeld. `putFoodDef` ersetzt derzeit per Schlüssel und setzt `created_at` neu. Eigene Definitionen brauchen stabile IDs, getrennte externe Barcodes, Erstellungs-/Änderungszeit und eine Version; gespeicherte Einträge behalten ihren damaligen Nährwert-Snapshot. Angaben je 100 ml oder je Portion benötigen eine explizite Basis mit Menge/Einheit. Keine implizite Umrechnung von ml in g ohne bekannte Dichte. Der bestehende Konsum-Editor bleibt ein anderer Vorgang.

Name und positive endliche Basis sind nötig; unbekannte Nährwerte bleiben null. Explizite 0 bleibt ein bekannter Nullwert. Dezimalkomma, Einheiten und optionale übliche Portion werden validiert. Grobe Widersprüche erscheinen direkt an den betroffenen Feldern, ohne Werte aus einer Formel zu überschreiben. Rundungen und unterschiedliche Energiebeiträge erlauben Abweichungen: 85 kcal bei 7 g Protein, 10 g Kohlenhydraten und 2 g Fett sind kein Fehler; 20 g Fett allein entsprechen ungefähr 180 kcal und passen nicht zu 85 kcal. Die Person korrigiert einen Wert oder lässt ihn unbekannt. Salz in g und Natrium in mg sind verschiedene Angaben; der vorhandene Natrium-Speicher braucht eine eindeutige Konvertierung/Quellenbasis, keine bloße Umbenennung.

Synthetisches Lebensmittel Joghurt: je 100 g 85 kcal, 7 g Protein, 10 g Kohlenhydrate, 2 g Fett, 4 g Zucker. Übliche Portion 200 g ergibt 170 kcal / 14 / 20 / 4 g und 8 g Zucker. Weitere Nährwerte offen. Sammlung nennt die angezeigte Portion, damit gespeicherte Basis und Portionsenergie nicht widersprüchlich wirken. Fehler erhält den Draft; Wiederholen schreibt dieselbe Definition. Änderungen dürfen keine alten Tageswerte rückwirkend verändern.

**Prüfung:** Alle vier Quellen und fünf eigene Paper-Zustände angesehen: leer, ausgefüllt, Konflikt, weitere Nährwerte und Rückkehr zur Sammlung. Neue Felder, Provenienz, unbekannte Werte und Speicherung sind Designverträge; nicht in der App implementiert.

## B28 · Einzelnen Nährstoff ergänzen

**Aus Flow 026.** Sieben Quellen zeigen Nährstoffdetail, Mengenänderung, Zeitpicker und gespeicherten Beitrag. OpenBand erlaubt einen eigenständigen Beitrag ohne fingiertes Lebensmittel. Menge, Datum und Uhrzeit stehen vor dem Speichern zusammen; die Detailansicht nennt danach jede Quelle. Ohne eigenes Ziel wird kein Restwert oder Zielring erfunden.

Die nullable Spalten von `food_entry` können Teilwerte tragen. Ergänzen braucht jedoch einen ausdrücklichen Eintragstyp `nutrient_only`, stabile ID, Nährstoff-ID, Originaleinheit, normalisierten Wert, Zeitpunkt mit Zeitzone und Herkunft. Ein Zusatz ist keine weitere vollständig erfasste Mahlzeit. Tagesvollständigkeit darf durch ihn weder auf vollständig springen noch für fremde Nährstoffe künstlich sinken; Nährstoff-Abdeckung und Ernährungstagebuch-Abdeckung getrennt auswerten. Nur explizit angegebene Werte summieren, aus Fett/Protein keine Energie stillschweigend ergänzen. Negative Einträge sind kein Korrekturweg: bestehende Einträge bearbeiten/löschen. Wiederholtes Speichern nach Fehler muss denselben Beitrag treffen.

Synthetische Variante: 14 g aus Haferfrühstück + 4 g aus Joghurt + 5 g eigener Beitrag um 07:35 = mindestens 23 g Fett. Kaffee bleibt offen. Die bekannten 620 kcal ändern sich nicht. Diese Variante ist ein expliziter Nachher-Zustand gegenüber der gemeinsamen Tages-Fixture mit mindestens 18 g Fett. Zurück aus dem Zeitpicker übernimmt nur den Draft; erst „5 g Fett eintragen“ persistiert. Bearbeiten führt in denselben Editor mit vorhandener ID; Löschen nutzt den gemeinsamen Bestätigungs-/Rückgängig-Vertrag. Datumswechsel, Mitternacht und Sommerzeit erhalten die ursprüngliche lokale Zuordnung.

**Prüfung:** Alle sieben Quellen angesehen; eigene Mengeneingabe, 24-Stunden-Zeitpicker und gespeichertes Detail visuell geprüft. Native iOS-Picker, Persistenz und Aggregationsänderung sind nicht implementiert.

## B29 · Eigene Journalfragen

**Aus Flow 027.** Fünf Quellen zeigen anpassbares Journal, eigene Bezeichnung/Symbol, Tages-/Nachtzuordnung, Anheften und gespeicherte Definition. OpenBand verwendet lizenzierte Lucide-Symbole und eine Vorschau. Die neue Frage ist nach dem Hinzufügen sichtbar, aber unbeantwortet. Ein Sichtbarkeitsschalter ist kein Ja/Nein-Eintrag. Eigene Fragen sind über Journal → Anpassen erreichbar; Bearbeiten und tägliches Antworten bleiben getrennte Wege.

`JournalFieldSpec` und der vorhandene eigene Feldeditor unterstützen Rating, Menge und Dauer; das ältere Tag-Set beschreibt nur Anwesenheit. Für Ja/Nein/Offen ist ein ausdrücklicher boolescher Antworttyp nötig: eine fehlende Tag-ID ist kein Nein. Definitionen brauchen stabile, vom Namen unabhängige ID, lokalisierten Namen, Symbol-ID, Antworttyp, optionale Einheit/Schrittweite, Tagesbereich, Reihenfolge, angeheftet und sichtbar. Vorhandene Custom-Keys und Historie erhalten; umbenennen darf keinen neuen Verlauf erzeugen. Ändert sich die Bedeutung/Einheit, eine neue Definition anlegen oder eine überprüfbare Migration verlangen, keine stille Neudeutung alter Zahlen.

„Abends“ ist eine Gruppierung im Journal des ausgewählten Kalendertages. Nachts beantwortete Fragen erhalten eine sichtbare Tageszuordnung; keine automatische Verschiebung auf den Beginn einer Schlafepisode. Als erledigt markierte Definitionen und tatsächlich beantwortete Tage bleiben getrennt. Ausblenden erhält Antworten, Exporte und Verlauf. Löschen einer Definition mit Historie braucht die gemeinsame Löschentscheidung; Anheften ist nur Reihenfolge. Der Symbolpicker ändert nur den Definitionsentwurf, Hinzufügen speichert atomar. Leerer Name deaktiviert Speichern, Namenskonflikte werden ohne Überschreiben behandelt.

**Prüfung:** Alle fünf Quellen angesehen. Definition, Symbolpicker und angepasste Sammlung in Paper visuell geprüft; Ja/Nein/Offen verwendet das vorhandene Tagesantwortmuster. Die boolesche Speichersemantik und Definitionsmetadaten sind noch umzusetzen.

## B30 · Eigene Energie- und Makroziele

**Aus Flow 028.** Sechs Quellen zeigen Zielliste, Profilbestätigung, TDEE-Laden, Prozent-/Grammbearbeitung und gespeicherte Ziele. OpenBand übernimmt die kompakte Bearbeitung und den nachvollziehbaren Zielvergleich. Eigene Ziele sind direkt erreichbar, ohne Profil- oder Health-Zwang. Die Referenz erlaubt keinen Rückschluss auf die Gültigkeit ihres TDEE-Modells. Ein automatischer Ernährungsplan wird aus diesem Flow deshalb nicht zugesagt; eine spätere Bedarfsschätzung braucht einen eigenen fachlich geprüften Vertrag mit Herkunft, Datenfenster und Unsicherheit.

Neu nötig: versionierte lokale Zielperiode mit Beginn als lokalem Datum, optionalem Energieziel und einzeln optionalen Makro-/Nährstoffzielen. Keine entsprechende persistente Ernährungsvorgabe im vorhandenen Store gefunden. Erstellen/Bearbeiten hat einen separaten Draft. Historische Tage verwenden ihre damalige Zielperiode, spätere Änderungen keine rückwirkende Umdeutung. Entfernung eines Ziels entfernt keinen Ernährungseintrag. Fehlendes Ziel ist nicht 0. Positive endliche Zahlen und Dezimalkomma; leere optionale Felder bleiben unset.

Gramm- und Prozentmodus erhalten dieselbe zugrunde liegende Vorgabe ohne wiederholte Rundungsverluste. Prozentmodus braucht ein bekanntes Energieziel und eine explizite Verteilung mit insgesamt 100 %. Grammziele dürfen auch einzeln bestehen. Bei vollständig gesetzten Makros wird die näherungsweise 4/4/9-Energie angezeigt; Abweichung vom Energieziel nicht durch stille Anpassung beheben. Ein bewusstes Ausgleichen müsste eine Vorschau anbieten und gesperrte Werte respektieren. Synthetisches, selbst gewähltes Beispiel: 2.000 kcal, Protein 125 g / 25 %, Kohlenhydrate 240 g / 48 %, Fett 60 g / 27 %; Summe 2.000 kcal.

Der Tagesvergleich verwendet B28/B27-Abdeckung: mindestens 620 kcal, 36/80/18 g aus der gemeinsamen Tages-Fixture. Fehlende Angaben erhalten ≥; keine exakten Restmengen oder grünes „Ziel erreicht“ aus einem unvollständigen Tag. Zielbalken deckeln die Zeichnung bei 100 %, nennen aber die tatsächliche Menge; Über-/Unterschreitung wird nicht moralisch bewertet. Weitere Nährstoffe und Obergrenzen werden in ihren eigenen Referenzflows entwickelt.

**Prüfung:** Alle sechs Quellen angesehen; alte Zielansicht ersetzt. Ausgangszustand, Gramm, Prozent und gespeicherter Vergleich visuell geprüft. 4/4/9-Beispiel und Balkenbreiten stimmen. Keine automatische Bedarfsschätzung, Health-Schreiboperation oder App-Zielpersistenz implementiert.

## B31 · Schlaf manuell ergänzen

**Aus Flow 029.** Drei Quellen zeigen die Schlafzeitliste, Start-/Endeingabe und eine Liste mit Nickerchen. Die Uhrzeiten zwischen den Quellpositionen passen nicht durchgehend zusammen; sie belegen den Ablauf, keine zusammenhängende Beispieldatentransaktion. OpenBand bietet Hauptschlaf/Nickerchen, beide Datumsangaben und Zeitzone gemeinsam. Ein Zeitfenster ist zunächst eine eigene Angabe, keine gemessene Schlafdauer und kein Satz neuer Schlafphasen.

Bestehende `sleep_override` (eine Hauptnacht pro day_id) und `sleep_nap` (Liste, Schlüssel day_id/start_ts) weiterverwenden beziehungsweise gezielt erweitern. `setSleepOverride`, `putNapEdit` und anschließende Neuberechnung bestehen bereits. Bei Änderung der Nap-Startzeit darf der alte Primärschlüssel keinen zweiten Eintrag hinterlassen: stabile Edit-ID oder atomare Entfernung/Neuanlage. Session-Quelle, ursprüngliche lokale Zeitzone, ausgewählter Tag, eingegebene Grenzen und Detektorbestand getrennt halten. Ergänzen einer zweiten Hauptnacht darf keine vorhandene unbemerkt ersetzen.

Validierung vor Commit: Ende nach Beginn als tatsächlicher Zeitpunkt, keine unbeabsichtigten Zukunftszeiten, explizite Nacht über Mitternacht, Sommerzeitlücke/-dopplung und Überschneidung mit bestehenden Haupt-/Nap-Sitzungen. Bei Überschneidung Zeiten korrigieren oder vorhandene Sitzung öffnen; nicht doppelt zählen, automatisch vereinigen oder still überschreiben. Das Zurückkehren erhält den manuellen Draft. Rohaufzeichnungen bleiben bestehen; manuelle Abwahl unterdrückt nur die entsprechende Erkennung.

Synthetischer Eintrag: 14. September 14:10–14:35, 25 Minuten, Berlin. Er bleibt getrennt von Hauptnacht 14./15. September 23:10–06:54 mit 7h18 Schlaf und 7h44 im Bett. Der Konfliktfall 23:30–00:10 überlappt die Hauptnacht. Ein vorhandener manueller Schlaf-/Nap-Eintrag kann die dafür vorgesehene Schlafbedarfsauswertung beeinflussen, aber keine HRV, Schlafphasen oder Erholung erzeugen. Speicherbeleg und Neuberechnung sind getrennte Zustände; ein Ableitungsfehler hebt einen erfolgreichen Commit nicht auf. Den vorhandenen nur geloggten Rechenfehler zu einem sichtbaren wiederholbaren Ergebnis machen.

**Prüfung:** Alle drei Quellen angesehen. Eingabe, Überschneidung und vollständig überarbeitete Schlafzeitenliste visuell geprüft. Bestehende Tabellen/Schreib- und Rechenwege gelesen; kein neuer Schlafalgorithmus und keine Hardwareprüfung.

## B32 · Schnelle Nährstoffeinträge

**Aus Flow 030.** Drei Quellen zeigen Nährstoffdetail ohne Beiträge, eine feste Mengenaktion und danach den gespeicherten Beitrag. OpenBand verwendet denselben Einzelbeitragsvertrag wie B28 mit einer eigenen, konfigurierten Schnellmenge. Die Vorgabe ist kein Ernährungsziel und keine Empfehlung. Nach Commit erscheint Rückgängig für genau diesen Eintrag; die Detailquelle bleibt länger editierbar.

Pro Nährstoff optionale eigene Schnellmenge/Einheit speichern. Die Aktion nennt den konkreten Wert; sie schreibt den tatsächlich aktuellen Zeitpunkt mit Zeitzone, nicht einen zuletzt geöffneten historischen Pickerwert. Auf einem vergangenen Tag muss der Zeitpunkt vorher bestätigt werden. Jede absichtliche erneute Betätigung ist ein neuer Beitrag; technische Wiederholung derselben laufenden Operation ist idempotent. Kurz sperren während Commit, bei Fehler keinen Erfolg/Undo zeigen. Rückgängig entfernt exakt die zugehörige Entry-ID und berechnet sichtbare Summen neu.

Synthetisches Beispiel um 07:40: 5 g Ballaststoffe als eigene Schnellmenge. Vorher offen, nachher mindestens 5 g; Haferfrühstück/Joghurt/Kaffee besitzen in dieser Fixture keine bestätigten Ballaststoffangaben. Aus „kein Wert“ wird kein 0-g-Start. Makros und Energie ändern sich nicht. Der vorhandene Ernährungsspeicher kann Ballaststoffe tragen; zusätzliche Nährstoffarten brauchen einen getypten Katalog mit Einheit und eindeutiger Quellzuordnung, nicht ad hoc neue UI-Spalten.

**Prüfung:** Alle drei Quellen und zwei eigene Paper-Zustände angesehen. Mengen-/Zeitänderung führt zum bereits geprüften Editor B28. Speicherung, Undo und Preset-Konfiguration sind noch umzusetzen.

## B33 · Einem gespeicherten Essen ein Foto hinzufügen

**Aus Flow 031.** Drei Quellen zeigen gespeicherten Eintrag ohne Foto, Fotoaktion im Menü und Eintrag mit Bild. OpenBand macht den leeren Fotoplatz direkt bedienbar; der kompakte Nährwertblock und die Details bleiben stabil. Der Quellenpicker bietet gezielte Fotoauswahl oder Kamera. Ein Anhang löst keine Bildauswertung aus und ändert keine Nährwerte.

B13-Anhänge um Verknüpfung mit einem vorhandenen Entry erweitern: stabiler Attachment-Key, lokales Original und Thumbnail, Entry-ID, Reihenfolge und optionale Bildbeschreibung. Pickerabbruch verändert nichts. Erst erfolgreiches lokales Kopieren plus Referenz-Commit gilt als hinzugefügt; ein Fehler erhält den bestehenden Eintrag/Anhang. Nur die gewählten Fotos importieren, keine vollständige Mediathekberechtigung verlangen. Kamera verwendet B14. Zugriff auf ein Cloud-Foto kann noch laden/fehlschlagen, obwohl der Picker schon geschlossen ist; bestehende Werte bleiben bedienbar.

Das Foto öffnet eine Bildansicht mit Ersetzen/Entfernen. Entfernen löscht die Referenz, nicht den Ernährungseintrag; physische Datei erst löschen, wenn keine andere Referenz sie benötigt. Backups/Export/Löschung müssen Anhänge ausdrücklich behandeln. Auswahl als Rezeptbild ist eine eigene Kopier-/Verknüpfungsentscheidung, nicht Nebenwirkung eines Eintragsfotos. Ein manuell bestätigter Nährwert behält seine Quelle und wird durch Fotoanhang nicht zu `FoodSource.photo` umklassifiziert.

Synthetischer Eintrag Haferfrühstück: 450 kcal, 22 g Protein, 60 g Kohlenhydrate, 14 g Fett, eine Schüssel, 15. September 07:00. Das neue Bild belegt diese Mengen nicht. Originales synthetisches Foto mit eingebautem imagegen erstellt; Datei/Prompt/Herkunft in [GENERATED_ASSETS.md](assets/GENERATED_ASSETS.md). Keine Bevel-Bilder in die Produktgestaltung übernommen. Die früheren schematischen Bowl-Platzhalter in Import, Verarbeitung, Ergebnis, Fehler und Kamera wurden ebenfalls ersetzt.

**Prüfung:** Alle drei Quellen und eigener Vorher-/Quellenpicker-/Nachher-Zustand angesehen; aktualisierte fünf Fotozustände visuell geprüft. Die Paper-Bildfüllung ist austauschbar, UI und Texte bleiben native editierbare Knoten. Kein Upload, Bilderkennungsaufruf oder App-Anhangsspeicher implementiert.

### Ergänzung zu B21 · Flow 032, ältere Rezeptanlage

Alle drei Positionen des älteren Flows wurden separat angesehen. Name, Portionen, Zutaten und Speichern sind vollständig im aktuellen Editor K7E/K97 enthalten. Es entsteht kein zweiter Legacy-Editor. Die Referenz zeigt bei leerem Rezept 0 kcal; OpenBand lässt die Summe bis zu bekannten Zutaten offen. Zutatenmengen gelten für das gesamte Rezept, Ergebniswerte sind je Portion. Die im alten Menü erwähnte Rezeptimport-Aktion wird im eigenen Flow 091 geprüft; sie ist hier keine belegte Importfunktion. Aktueller leerer und gefüllter Paper-Editor erneut visuell geprüft. B21/B08/B09/B10 bleiben der gemeinsame Backendvertrag.

## B34 · Vorhandene Journalfragen einblenden

**Aus Flow 033.** Sechs Quellen zeigen Journal, Anpassungsmenü, Katalog mit Kategorien, Aktivieren vorhandener Fragen und die neue unbeantwortete Zeile. OpenBand führt Journal → Anpassen direkt zu Suche/Kategorien. Sichtbarkeit wird lokal je Feld gespeichert; neue Fragen erhalten weder automatische Ja-Antworten noch rückwirkende Nein-Werte. „Fertig“ schließt die Einstellungen. Bei einem Schreibfehler bleibt der vorherige Schalterstand mit erneutem Versuch erhalten.

Vorhandene `kJournalFields` und eigene Definitionen aus B29 bilden einen gemeinsamen Katalog. Sichtbarkeit, Reihenfolge und Anheften sind getrennt von Antworten. Kategorien sind Navigation, keine zweite Datenhaltung. Doppelte Definitionen durch Sprach-/Namenswechsel vermeiden, stabile IDs verwenden. Antworten eines ausgeblendeten Felds bleiben in Export und Verlauf. Eine bekannte eingetragene 0 bei Koffein/Dauer ist etwas anderes als unbeantwortet.

Automatische Fragen brauchen zusätzlich Quelle, Schwelle/Zeitraum und messwertspezifische Bereitschaft. Ein unvollständig erfasster Tag darf zum Beispiel „Bewegungsziel nicht erreicht“ nicht allein aus fehlenden Minuten ableiten. Änderungen eines Nutzerziels verändern keine historische Antwort unbemerkt. Automatische Schlussfolgerung und eigener Bericht bleiben getrennte Quellen; kein Übernehmen proprietärer Bevel-Scores oder Schwellen aus dem Katalog. Als neues Beispiel ist „Bildschirm vor dem Schlafen“ eine manuell eingegebene Dauer, keine behauptete iOS-Nutzungsmessung.

**Prüfung:** Alle sechs Quellen angesehen; Katalog und neue unbeantwortete Journalzeile in Paper geprüft. Eigene Fragen/Symbole verwenden B29, die Tagesantwort verwendet den bestehenden Ja/Nein/Offen-Editor. Kein neues Tracking oder Journal-Speicher implementiert.

## B35 · Weitere Nährstofffelder auswählen

**Aus Flow 034.** Sechs Quellen zeigen Lebensmitteleditor, lange vorhandene Nährwertliste, Such-/Auswahlkatalog, zusätzliche Felder und Rückkehr zum Zutatenkontext. OpenBand öffnet aus „Weitere Nährwerte“ einen gemeinsamen Katalog mit Suche und Kategorien. Bereits vorhandene Felder sind erkennbar; neue Auswahl erhält zunächst unbekannte Werte. Übernehmen führt in den übergeordneten Lebensmitteldraft, nicht direkt in einen gegessenen Eintrag.

Den begrenzten festen Satz von `food_def`-/`food_entry`-Spalten zu einer gemeinsamen getypten Nährstoffsammlung erweitern: stabile Nutrient-ID, kanonische Einheit, Originalwert/-einheit, Bezugsmenge, Herkunft und bekannter/unbekannter Zustand pro Wert. Katalog dient Lebensmitteldefinitionen, Entry-Snapshots, Einzelbeiträgen und Zielen. Vorhandene Spalten verlustfrei migrieren; keine zweite konkurrierende Summe. mg/µg/g sicher normalisieren, Salz/Natrium und fachlich unterschiedliche Vitaminformen nicht anhand ähnlicher Namen zusammenfassen. Einheiten nur umrechnen, wenn die Definition das tatsächlich erlaubt.

Felder auswählen ist noch keine Aussage über deren Menge. Ein neues Feld startet mit null, kein automatisch eingetragenes 0. Entfernen eines Felds mit eingegebenem Wert braucht eine klare Entscheidung; bloßes Einklappen darf keinen Wert löschen. Mehrfachauswahl ist dedupliziert, Suche erhält den Draft. Die Liste scrollt bei Tastatur/großer Schrift über einer zugänglichen Übernehmen-Aktion. Beim Speichern gilt die B27-Versionierung: bestehende Verzehr-Snapshots bleiben unverändert. Bearbeiten einer Zutat trifft deren gewählten Draft-Kontext; keine globale Änderung ohne ausdrücklich gewählte Definitionsbearbeitung.

Synthetische Ergänzung am Joghurt: Magnesium 12 mg und Zink 0,5 mg je 100 g; bei 200 g wären es 24 mg und 1 mg. Zucker bleibt 4 g je 100 g, alle anderen offenen Zusatzfelder bleiben unbekannt. Keine Menge aus dem Foto abgeleitet. Die Variante ist ein neuer Definitionsentwurf, noch keine Änderung der Tages-Fixture.

**Prüfung:** Alle sechs Quellen angesehen. Gemeinsame weitere-Nährwerte-Ansicht um Katalogzugang erweitert; Auswahl, zusätzliche Werte und Rückkehr in den Definitionsdraft visuell geprüft. Kein Katalog oder Datenbankschema implementiert.

## B36 · Übungen aus der Bibliothek hinzufügen

**Aus Flow 035.** Sechs Quellen zeigen Vorlageneditor, Hinzufügen-Menü, Bibliothek, gefilterte Suche, ausgewählte Variante und Rückkehr zur Vorlage. OpenBand trennt Übungsdetails vom Auswahl-Plus und nennt Geräte-/Wiederholungsbasis direkt im Treffer. Die Auswahl bleibt bis zum Bestätigen lokal. Der Picker erhält den Zielkontext Vorlage oder laufende Einheit; eine Auswahl darf nicht gleichzeitig beides ändern.

B23/B26 um gemeinsamen Übungspicker erweitern: Suche über übersetzte Bezeichnungen/Aliasse, Muskel-/Gerätefilter, stabile IDs und Varianten. Gerätevariante ist Teil der Definition, keine Dekoration. Auswahl bleibt bei Filtern und Detailansicht erhalten, Anzahl immer sichtbar. Schon im Plan vorhandene Übungen kennzeichnen; erneute Position nur bewusst hinzufügen, keine stillen Duplikate durch Doppeltippen. Ein leerer Treffer bietet eigene Definition an; nach deren Speichern zum gleichen Such-/Auswahlkontext zurückkehren. Vorhandene konstante `exerciseLibrary` reicht als Grundlage, muss aber die eigene Registry und Varianten aus B26 erhalten.

Neue Übungen erzeugen geplante, noch nicht ausgeführte Satzzeilen. Beispiel: Ganzkörper A hat zunächst vier Übungen/zwölf geplante Sätze; Ausfallschritte mit Eigengewicht kommt mit einer leeren Satzvorgabe hinzu → fünf Übungen/dreizehn geplante Sätze. Keine automatisch erfundenen Wiederholungen oder 0-kg-Last. Bei Start eines Trainings zählt nur eine bestätigte Ausführung. Eingabebasis „je Seite“ gilt auch in späteren Auswertungen. Bestätigen der Pickerauswahl ändert zunächst den Vorlagendraft, Speichern der Vorlage ist ein eigener Commit.

Foto-/Beschreibungserkennung ist im Quellmenü sichtbar, wird aber in den eigenen entsprechenden Flows geprüft. Übungsdetails brauchen Name, Geräteart, Erfassungsbasis und optionale eigene Notiz; Anleitungsgrafiken/-videos nur aus geklärten Lizenzen oder eigener Produktion, keine übernommenen Bevel-Assets.

**Prüfung:** Alle sechs Quellen und vier eigene Zustände angesehen: Suche, Auswahl, keine Treffer, hinzugefügte geplante Übung. Feste Aktion, 44-pt-Auswahl-/Infoflächen und Home-Indikator geprüft. Vorlagen-/Satzpersistenz nicht implementiert.

## B37 · Übungen aus Planfoto oder Bildvorschlag

**Aus Flow 036.** Drei Quellen zeigen Fotoaktion, laufende Erkennung im Vorlageneditor und eingefügte Übung mit Sätzen. Was genau im kleinen Quellfoto steht, ist nicht lesbar; daraus wird keine Erkennungsgenauigkeit abgeleitet. OpenBand bietet lokalen Textimport für fotografierte Pläne und einen getrennten optionalen Auftrag an einen eingerichteten Bildanbieter. Alle Ergebnisse gehen vor Übernahme in eine prüfbare Vorschau.

Neue Import-Pipeline: lokal gehaltenes Foto/Thumbnail → OCR-Text mit Ausschnitt und Erkennungssicherheit → Kandidaten für Übungs-ID/Gerät, Satztyp, Wiederholungen/Dauer und Lastbasis → vom Nutzer bestätigte geplante Sets. Originaltext und Bild bleiben zur Prüfung erreichbar; die Bildansicht kann natives Quick Look verwenden. Keine Last, Anzahl oder Gerätevariante aus unsicherem Text erfinden. Dezimalkomma, kg/lb, x/×, Zeitformat, je-Seite-Angaben und Reihenfolge erhalten. Unzugeordnete Übung führt zum Picker/eigener Definition und blockiert nur diese Position. Quelle ist ein Importvorschlag, kein ausgeführter Satz.

Ein Auftrag besitzt eigene Job-/Draft-ID und ausgewählten Zielentwurf. Zurück/Background verliert den Draft nicht. Ergebnis kommt als „bereit zum Prüfen“ zurück; nach Verwerfen oder Wechsel der Vorlage darf es nicht in einen anderen Plan hineinlaufen. Abbrechen invalidiert späte Ergebnisse. Lokale Speicherung des Fotos, OCR/Providerfehler und spätere Übernahme sind getrennte Zustände. Ein erneuter Versuch ersetzt das Kandidatenergebnis desselben Auftrags, kein doppeltes Hinzufügen. Fremde Fotoerkennung nutzt den konfigurierten bildfähigen Providervertrag aus B13 mit ausdrücklich gezeigter Weitergabe, kein automatischer Cloud-Fallback für erfolglose OCR.

Synthetischer sichtbarer Quelltext: „Ausfallschritte · Eigengewicht · 3 × 10 Wiederholungen je Seite“. Vorschau zeigt drei geplante Zeilen. Nach bestätigter Übernahme hätte Ganzkörper A fünf Übungen/fünfzehn geplante Sätze; bestehende zwölf bleiben erhalten. Diese Variante unterscheidet sich vom manuell hinzugefügten leeren Einzelsatz in B36. Die gezeigte Dateikachel steht für ein synthetisches Auswahlbeispiel, kein tatsächlich ausgewertetes Nutzerbild. Foto allein erzeugt keine Übungsleistung, Trainingsempfehlung oder verlässliche Technikprüfung.

**Prüfung:** Alle drei Quellen und eigene Auswahl-, Verarbeitungs-, Ergebnis- und Kein-Text-Zustände angesehen. 44-pt-Zugang zum Original und klarer Draft-Commit. Bestehender Textcoach/Übungskatalog stellen diese Bild-/OCR-Pipeline noch nicht bereit; keine Erkennung implementiert oder vermessen.

## B38 · Übungen bei Vorschlägen ausschließen

**Aus Flow 037.** Sechs Quellen zeigen Generator, erweiterte Vorgaben, leere Ausschlüsse, Bibliothek, Mehrfachauswahl und Ausschlussliste vor Speichern. OpenBand nutzt den gemeinsamen Picker in einem ausdrücklichen Ausschlussmodus. Ausgeschlossen wird die genannte Gerätevariante; andere Varianten sind nicht stillschweigend mitgemeint. Die Vorgaben gelten nur für neue Vorschläge, nicht für historische Sätze oder bestehende Vorlagen.

Neues lokales Modell für Trainingsvorgaben: stabile Version, Erfahrung/Schwerpunkt als optionale eigene Angaben, Ausstattung aus B24 und ausgeschlossene Exercise-IDs aus B26. Innerer Picker verändert den Vorgabendraft; erst „Vorgaben speichern“ persistiert atomar. Ausschluss entfernen gibt die Variante für neue Vorschläge frei. Umbenennen der Übung erhält den Ausschluss; unbekannte/entfernte IDs nicht durch Namensähnlichkeit auf eine andere Übung umhängen. Eigene manuelle Auswahl bleibt möglich und nennt den aktiven Ausschluss, bevor die Person ihn bewusst übergeht.

Ein künftiger Generator muss die Ausschlüsse nach jedem Vorschlag server-/modellunabhängig prüfen, ebenso verfügbare Geräte. Reicht der Kandidatenraum nicht, die widersprüchlichen Vorgaben nennen und zur Anpassung führen; keine stille Lockerung und keine erfundene Ersatzübung. Medizinische Kontraindikationen oder sichere Belastbarkeit werden aus dieser Präferenz nicht abgeleitet. Die im Quellflow aktivierten Vorgaben für Muskelversagen/Dropsets werden nicht pauschal als Anfängerstandard übernommen. Die vollständige Generierung wird erst in ihrem eigenen späteren Flow entschieden.

Synthetische Präferenz: Ausfallschritte mit Eigengewicht ausschließen; Hantelvarianten bleiben separat auswählbar. Erfahrung/Schwerpunkt noch offen. Das ist eine eigene Vorschlagskonfiguration und ändert den manuellen Beispielplan nicht. Speicherfehler erhält den Draft; erneuter Versuch ersetzt dieselbe Version. Beim Abbrechen bleiben die bisherigen gespeicherten Vorgaben gültig.

**Prüfung:** Alle sechs Quellen und Picker, Vorgabendraft sowie gespeicherte Rückmeldung angesehen. Gemeinsame Geräte-/Übungsreferenzen dokumentiert. Im gelesenen Trainings-/Coachpfad kein entsprechender Generator-Ausschlussvertrag vorhanden; noch umzusetzen.

## B39 · Weitere Nährstoffziele hinzufügen

**Aus Flow 038.** Fünf Quellen zeigen Zielübersicht, durchsuchbaren Katalog mit Kategorien, Aktivieren und neue Zielkarten. OpenBand verlangt nach der Auswahl einen selbst gewählten Wert; Einschalten eines Nährstoffs übernimmt keine unbemerkte Standardmenge. Zielwert und Obergrenze sind unterschiedliche Bedeutungen und bleiben auch im Tagesvergleich benannt.

B30-Zielperioden und B35-Nährstoffkatalog gemeinsam nutzen. Ein Ziel hat Nutrient-ID, Vergleichsart, Menge, Einheit und Gültigkeitsbeginn; keine separate Liste freier Textnamen. Bereits vorhandenes Ziel öffnet Bearbeiten statt ein Duplikat anzulegen. Katalogauswahl allein speichert nichts. Ein Mengenwechsel erhält die tatsächlich äquivalente Einheit; keine Mischung von mg und g. Eigene Obergrenze bedeutet weder medizinischer Grenzwert noch garantierte Sicherheit. Widersprüchliche Mindest-/Höchstwerte desselben Zeitraums müssen vor Speichern geklärt werden.

Tagesvergleich respektiert bekannte, teilweise und fehlende Werte. Bei null kein 0-%-Balken und keine exakte Restmenge. Bei Teilsumme ≥ bleibt mindestens die bekannte Menge sichtbar; eine unterschrittene Obergrenze lässt sich aus einem unvollständigen Tag nicht bestätigen. Der synthetische Zielwert 25 g Ballaststoffe ist frei gewählt und keine Empfehlung. In der gemeinsamen Tages-Fixture fehlen die Ballaststoffangaben: Karte bleibt „Offen“. Der separate Schnelllog-Nachher-Fall aus B32 hätte mindestens 5 g, ist hier aber nicht stillschweigend bereits ausgeführt.

**Prüfung:** Alle fünf Quellen und eigene Auswahl, Zieleingabe sowie gespeicherte Offen-Karte angesehen. Bestehende Makroziele bleiben unverändert; Zieländerungen gehören nicht in den Lebensmitteldefinitionsspeicher. Keine Zielpersistenz oder ernährungsmedizinische Berechnung implementiert.

## B40 · Satzgewicht und gezielte Übernahme

**Aus Flow 039.** Vier Quellen zeigen Vorlageneditor, kg/lb-Eingabe, Auswahl für weitere Sätze und übernommene Last. OpenBand nennt die Bezugsgröße direkt am Feld: Bankdrücken als Gesamtgewicht, Kurzhantelübungen entsprechend B26 je Hantel. „Auch für Satz 2 und 3“ beschreibt den tatsächlichen Umfang; die Option ist zunächst aus.

B23/B26 um einen gemeinsamen Lasteingabevertrag ergänzen. Dezimalkomma akzeptieren, ursprüngliche Eingabeeinheit behalten und physisch äquivalent zwischen kg/lb umrechnen; keine wiederholte Rundungsdrift. Leeres Gewicht bleibt unbekannt. Eigengewicht oder Unterstützung sind Lastarten, keine ersatzweise eingetragene Null. Gewichtsangaben brauchen eine explizite Gesamt-/je-Gerät-Basis. Die bestätigte Eingabe ändert zunächst nur den aufrufenden Entwurf; sie bestätigt keinen ausgeführten Satz und speichert keine Vorlage automatisch.

Mehrfachübernahme betrifft ausschließlich die ausdrücklich genannten folgenden geplanten Sätze dieser Übungsposition. Keine anderen Übungen, historischen Einheiten oder bereits bestätigten Sätze ändern. In laufendem Training bleibt die verfügbare Zielmenge sichtbar; Änderungen bestätigter Sätze erfordern deren eigene Bearbeitung. Zwischen Öffnen und Übernehmen geänderte Zielpositionen neu abgleichen. Abbrechen erhält alle bisherigen Werte, erneutes Übernehmen erzeugt keine neuen Sets.

Synthetischer Fall: Bankdrücken wird von 40 auf 42,5 kg geändert. Bei aktiver Option erhalten genau Satz 1–3 je 42,5 kg und weiterhin je acht geplante Wiederholungen. Die geplanten 1.020 kg sind keine ausgeführte Trainingsleistung. Die bestehende `strength_set`-Speicherung ersetzt den noch fehlenden Vorlagendraft-/Massenänderungsvertrag nicht.

**Prüfung:** Alle vier Quellen sowie Einzel-/Mehrfachauswahl und Ergebnis in Paper angesehen. Symmetrischer Dialogkopf mit 44-pt-Aktionsflächen, Dezimaltastatur und ausdrücklich genannte Lastbasis geprüft. Keine Lastpersistenz implementiert.

## B41 · Durchsuchbarer Werte- und Bereichskatalog

**Aus Flow 040.** Zwei Quellen zeigen den Einstieg nach dem Home-Verlauf und einen Katalog mit sechs Bereichen sowie aktuellen Werten und kleinen Trends. OpenBand erhält „Alle Werte ansehen“ am Ende der Übersicht und denselben Katalog aus Gesundheit. Sechs Bereichsziele führen zu Schlaf, Erholung, Belastung, Stress, Ernährung und Rhythmus. Darunter stehen Messwerte nach Themen; das führt zu vorhandenen Detailzielen und erzeugt keine weitere Tab-Leiste.

Ein gemeinsamer MetricDescriptor-Katalog bündelt stabile ID, deutsche Bezeichnung/Suchaliasse, Einheit, Zeitbasis, Quell-/Bereitschaftsregeln, Darstellungsformat und Detailroute. Zusammen mit B25 für wählbare Startkarten verwenden; Darstellungspräferenz ist nicht Messwertverfügbarkeit. Suche filtert Bereiche und Werte, behält das ausgewählte lokale Datum und zeigt bei keinem Treffer eine leere Ergebnisliste mit Suchfeld. Verfügbare Werte, fehlende Sensorwerte und noch nicht berechenbare Ergebnisse bleiben voneinander unterscheidbar. Der Katalog entfernt fehlende Werte nicht stillschweigend.

Kleine Verläufe verwenden dieselben Tagesaggregate, Vergleichsintervalle und Datenlücken wie die Detailansicht. Wertebezug immer sichtbar: Nacht, heute bis 07:42, eigener Eintrag oder expliziter Zeitraum. „Energie“ bezeichnet hier eingetragene Nahrungsenergie, keinen erfundenen Körperakku. Synthetische Tagesdaten bleiben unverändert; Ernährung ≥620 kcal, Temperatur und Stress offen. Ein Wechsel aus dem Katalog merkt sich Suchtext/Scrollposition; Zurück kehrt zum tatsächlichen Ursprung zurück. Oberkategorien müssen nicht als persistierte Datensätze existieren.

**Prüfung:** Beide Quellen, neuer Katalog mit Fortsetzung sowie Einstieg am Ende der Übersicht in Paper angesehen. 393 × 852, kompakte aktuelle Werte und offene Zustände geprüft. Routing/Registry sind Implementierungsbedarf.

## B42 · Darstellung, Hintergrund und Systemschrift

**Aus Flow 041.** Alle vier Quellen zeigen Einstellungen, drei Farbschemata, zwei Hintergrundvarianten sowie eigene Widget-/App-Icon-Auswahl. OpenBand übernimmt die verständlichen visuellen Vorschauen. Standard ist „iPhone“, optional Hell oder Dunkel. Die endgültige Entscheidung B144 verwendet keinen separaten Hintergrundschalter: ein ruhiger Kopf je Hell/Dunkel. Messkarten bleiben deckend. Widgets folgen demselben Farbschema. Eine zusätzliche Galerie dekorativer App-Icons und separate Widget-Themen sind bewusst nicht Teil dieses Produkts.

`ThemeController` in `lib/theme/theme_controller.dart` persistiert `system/light/dark`, berücksichtigt OS-Helligkeit vor dem ersten Frame und aktualisiert Systemleisten bereits. Diesen Eigentümer beibehalten. `WidgetService.setThemeDark` spiegelt den effektiven Modus schon best-effort ins App Group Storage. Neu sind die abgestimmten Dawn-/Dusk-Designwerte auf Flutter, Widgets, Live Activity und allen nativen Übergängen. Die Darstellung ändert keine Messdaten. Im Systemmodus auch einen Helligkeitswechsel im Hintergrund beim Wiederöffnen richtig auflösen. Persistenzfehler dürfen nicht stillschweigend dauerhafte Speicherung behaupten; Auswahl zunächst sichtbar halten und erneutes Speichern anbieten.

Textgröße bleibt systemgesteuert, ohne einen konkurrierenden App-Schieberegler. Keine globale Textskalierungsbegrenzung. Größere Schrift erzeugt höhere Zeilen/Karten und bei Bedarf vertikale Anordnung. Die Hinweise für Textgröße/Widgets sind reine Information ohne funktionslose Chevron-Aktion. VoiceOver benennt Vorschauoptionen und Auswahlzustand; Farbunterschiede allein reichen nicht. „Bewegung reduzieren“ unterdrückt Theme-Übergänge und dekorative Animationen; Transparenzreduktion ersetzt weiche Überlagerungen durch solide Flächen. Symbolfarbschema und nativer Statusbalken bleiben zum gerenderten Hintergrund passend.

**Prüfung:** Vier Quellpositionen und eigene helle/dunkle Darstellung sowie 375 × 812 mit vergrößerten 17/24-Texten angesehen. Alle Auswahlkarten und Beschriftungen bleiben sichtbar, Home-Indikator auf 375 pt mittig. Das ist Layoutprüfung in Paper, kein iPhone-/VoiceOver-Lauf. Die umfassende Prüfung aller übrigen Ansichten ist in B162 dokumentiert.

## B43 · Gesundheit, Basiswerte und optionale Körpermessungen

**Aus Flow 042.** Drei Quellen zeigen Home und zwei Biology-Ausschnitte mit VO₂max, HRV-/Ruhepulsbasis, Gewicht und Körperzusammensetzung. Die Aufnahmen haben unterschiedliche Zahlen und werden nicht als lückenloser Verlauf derselben Person behandelt. OpenBand entwickelt Gesundheit als lesbaren Datenbereich: heutige Einordnung und kompakte Messkarten, danach persönliche Basis, optionale Körperwerte, Rhythmus, Rückblick und Quellen. Der schmale Kopfverlauf ersetzt die alte Landschaft dieser Ansichten, auch in Dunkel. Kein eigener fünfter Biology-Tab.

Aktueller Wert und Basis erhalten getrennte Felder/Zeiträume. Synthetisch: heute Ruhepuls 54 und HRV 48; Median der 14 vorausgehenden Nächte 56 /min und 40 ms. Zeitraum 1.–14. September, ohne die ausgewählte Nacht. Die kleinen Tagesverläufe sind acht einzelne Nachtwerte, keine scheinbar gemessene Basisentwicklung. Der Schlafvergleich nutzt die sieben vorausgehenden Nächte aus der gemeinsamen Fixture. Rückblick und Baseline benötigen denselben datierten Aggregatvertrag und explizite Mindestabdeckung; keine ungeprüfte Einstufung in „gesund/schlecht“ nach Populationsgrenzen. Die Methode erklärt Median, Zeitraum, Einschluss und Lücken.

`journal_fields.dart` enthält `weight_kg` und `weightTrendEwma`; `health_profile_import.dart` liest Gewicht/Größe in das Profil. Die heutige skalare Profilangabe 75 kg besitzt in der Design-Fixture kein Messdatum. Sie wird deshalb klar als Profilangabe gezeigt und nicht rückwirkend als Messpunkt erfunden. Erweiterung zu zeitbezogenen Körpermessungen: stabile ID, Zeitpunkt/Zeitzone, Typ, kanonische Einheit, Originalwert/-einheit, Quelle/externes Sample-ID, optional Methode/Notiz und Korrekturhistorie. Profilwert und beobachtete Serie bleiben verschieden. Gesundheit darf das Profil nicht durch einen älteren Import überschreiben. Gewichtsverläufe behalten sichtbare Lücken und benennen Glättung.

Neu vorgesehen sind freiwillige eigene/importierte Körperfett- und VO₂max-Messwerte. Diese Produktentscheidung erweitert die frühere enge Kommentierung im Journal ausdrücklich, erzeugt aber keine Schätzung aus unbekannten WHOOP-Signalen. Kein Körperalter oder fettfreie Masse ohne eigenen, nachvollziehbaren Eingangsvertrag. Körperfett braucht Messmethode, VO₂max Quelle und Test-/Schätzmethode; Methodenwechsel dürfen nicht als Körperveränderung ausgegeben werden. Das aktuelle WHOOP-Band liefert dafür im geprüften Pfad keinen verifizierten Vertrag. Health-Import braucht typspezifische Berechtigung, Quellenpriorität, Deduplizierung, gelöschte Samples und Aktualisierung; bestehender einmaliger Profilimport reicht nicht. Bei verweigerten/leer zurückgegebenen Daten keine positive Autorisierungsbehauptung. Eigene Einträge bleiben ohne Health-Verbindung möglich.

Die neuen Körperwerte öffnen den gemeinsamen Messwerteditor mit Typ, Einheit, Datum und Quelle; erst dort wird gespeichert. Leerzustand bietet Eintragen oder Health-Anbindung. Keine automatisch gesetzten Gewichtsziele, täglichen Aufforderungen oder farbliche Bewertung einer Gewichtsänderung. Auswirkungen geänderter Profileingänge auf Kalorien/Belastung werden nach Version und Gültigkeitszeitpunkt nachvollziehbar neu berechnet, nicht stillschweigend auf die gesamte Vergangenheit angewandt.

**Prüfung:** Alle drei Quellen, Gesundheit/Scrollfortsetzung, Dunkel und Körperwerte-Einstieg angesehen. Basis und Tageswerte mit der gemeinsamen Fixture abgeglichen. Körperdatenimport, neue Messwerttypen und langfristige Vergleiche sind Designanforderungen, nicht implementierte oder physiologisch evaluierte Funktionen.

## B44 · Berechnungsmethoden und veränderbare Vorgaben

**Aus Flow 043.** Drei Quellen zeigen Customization und Berechnungsoptionen für HRV/Ruhepuls, Messfenster, Temperatur, Sauerstoff, Atmung, Kalorien und manuelles Schlafzusammenführen. OpenBand trennt eigene Vorgaben (Profil, Herzfrequenzbereiche, Schlafziel) von Erklärungen der tatsächlich angewandten Methode. Es gibt keinen Methodenumschalter, dessen Alternativen ungeprüft dieselbe Bedeutung vortäuschen. Datenquellen bleiben ein eigenes, erreichbar verknüpftes Thema.

`onehz_pipeline.dart` berechnet den RMSSD-Hauptwert primär als Mittel geeigneter bereinigter Fünf-Minuten-Fenster der Schlafsitzung; vorhandene Fallbacks sind robuster Nachtwert und Ganzfensterwert. Erholung liest dagegen `sleepSessionRmssd`. Das Ergebnis muss deshalb die tatsächlich angewandte Methode samt Fallback, Fenster, Abdeckung und Version mitführen: Kartenwert und Erholungseingang dürfen sich nicht unbemerkt unterscheiden. Ein einheitlicher Snapshot aus Hauptwert, Detail und Bereitschaft ist nötig. Bereits vorhandene Refusal-Gründe bleiben verbindlich; Gen5-Beispielwerte in Paper sind ausdrücklich synthetisch und kein Sensor-Nachweis.

Ruhepuls verwendet im gelesenen Pfad `low30Mean` nur aus tatsächlich erkanntem Schlaf; die Erklärung darf daraus weder niedrigsten Einzelwert noch Tagesruhepuls machen. Der HRV-Erklärpfad nennt RMSSD und lässt SDNN getrennt. Keine automatische Konvertierung oder SDNN-Fallback in eine RMSSD-Basis. Vergleichswerte müssen zu Verfahren, Einheit und Sensorquelle passen. Temperatur bleibt bei fehlender Kalibrierung ohne absolute °C-Aussage; die relative Sauerstoffauswertung bleibt ohne erfundene SpO₂-Prozentzahl. Diese Methoden sind Detailinformationen, keine scheinbar aktivierbaren Sensoren.

Jedes Ergebnis braucht verwendete Quelldatensätze/Zeiten, Methodenversion, Profilversion, Ausschlüsse und Bereitschaft. Neue Einstellungen bekommen Gültigkeitszeitpunkt und ausdrücklich genannten Neuberechnungsumfang. Vor einer rückwirkenden Änderung werden betroffene Tage und abhängige Werte genannt; Schreiben der Einstellung, Neuberechnung und Fehlerzustand sind getrennt. Letzte gültige Ergebnisse bleiben mit altem Methodenstand lesbar, bis Ersatz vollständig gespeichert ist. Eine fehlgeschlagene Neuberechnung darf weder gespeicherte Eingaben löschen noch einen Mischstand als aktuell ausgeben. Die existierende `PersonalProfile.forDate` löst Alter datumsbezogen auf; Gewicht/andere Profileingänge brauchen zusätzlich die in B43 beschriebene Änderungshistorie.

**Prüfung:** Drei Quellen sowie Berechnungsübersicht und HRV-Erklärung in Paper angesehen. Die entscheidenden aktuellen Methoden-/Fallbackpfade direkt gelesen; keine Analysealgorithmen geändert. Schlafziel-/Zonenbearbeitung werden in ihren eigenen Flows weiter konkretisiert.

## B45 · Eigenes Schlafziel und datengestützter Vorschlag

**Aus Flow 044.** Sechs Quellen zeigen Zielübersicht, Wahl manuell/automatisch, Analyse und zu wenig Daten. Bevel nennt im abgebildeten Fall 90 Tage. Diese Schwelle wird nicht als wissenschaftlich begründete OpenBand-Regel übernommen. OpenBand zeigt die bekannte Bereitschaft bereits vor dem Start. Ein eigenes Ziel ist freiwillig; fehlende Zielberechnung blockiert weder Schlafansicht noch Einrichtung. Der synthetische manuelle Entwurf 8h 00 ist eine eigene Wahl, kein voreingestellter Bedarf.

Neues `SleepGoal`-Modell: `none`, eigener Wert oder bestätigter Vorschlag mit Methode/Version, Gültigkeitsnacht, Originalwahl und Änderungsverlauf. Dauer in Minuten, kein Uhrzeit-/Zeitzonenwert. UI-Schritte 15 Minuten, genaue Eingabe möglich. Das Ziel bezieht sich ausdrücklich auf Schlafzeit, nicht Bettzeit. Speichern ist atomar; Abbrechen bewahrt die vorherige Wahl. Entfernen setzt die künftige Zielperiode auf keine Vorgabe und entfernt keine vergangenen Ziele, Nächte oder Erholungswerte. Beispiel: eigenes Ziel ab Nacht 15./16. September. Die letzte Nacht 14./15. wird nicht rückwirkend danach bewertet. Bei Import/Datumswechsel gilt die zur Nacht passende Zielversion.

Vorhandene Grundlage: `crossday_pipeline.dart` verwendet `sleepDebt` und leitet daraus Schlafbedarf-/Zeitvorschläge ab. `analytics/.../human/sleep_regularity.dart` beschreibt den Basiswert ausdrücklich als 75. Perzentil unbeeinflusster Nächte, nicht als gemessenen optimalen Schlafbedarf. Mindestens drei jüngere Nächte und eine freie Nacht reichen im aktuellen Rechenpfad für eine Zahl; daraus folgt keine ausreichende wissenschaftliche Grundlage für ein persönliches Ziel. Zudem klassifiziert der aktuelle Aufrufer freie Tage über `_isFreeDay` statt bestätigte Nächte ohne Wecker. Diese Annahme muss vor einem Zielvorschlag durch ausdrückliche Angaben beziehungsweise geeignete, geprüfte Kriterien ersetzt werden. Wochenenden sind nicht automatisch unbeeinflusste Nächte.

Eine automatische Zielmethode benötigt getrennte Produkt-/Algorithmusarbeit: Eignung der Nächte, Schlafgelegenheit, belastbare Zieldefinition, Mindestumfang und physiologische Evaluation. Bis dahin bleibt die Option als erklärter offener Vorschlag erreichbar und bietet manuelle Wahl. Keine scheinbare Analyse trotz schon bekannter fehlender Voraussetzung. Sobald eine geprüfte Methode vorliegt: Berechnung mit stabiler Auftrags-ID, Abbruch/Fehler/Wiederaufnahme, Ergebnisvorschau mit Datengrundlage und erst nach ausdrücklicher Übernahme neues Ziel. Kein nächtliches stilles Überschreiben einer eigenen Wahl. Der übliche Schlafbereich 6h15–6h42 aus sieben Nächten ist eine Beobachtung und wird niemals ersatzweise zum Bedarf erklärt.

**Prüfung:** Alle sechs Quellen sowie Methodenwahl, eigene Eingabe, offener Vorschlag und gespeichertes Ziel in Paper angesehen. Bereitschaft bewusst vor statt nach einer wirkungslosen Animation. Vorhandenen Schlafbedarfspfad und seine Eingangsannahmen gelesen; keine neue Methode oder Zielpersistenz implementiert.

## B46 · Antwortstil des optionalen Coachs

**Aus Flow 045.** Fünf Quellen zeigen Chatverlauf, Personalisierung, Tonvorschau, geänderte Auswahl und Speicherung. OpenBand verwendet drei ausdrücklich benannte Stile Warm/Sachlich/Direkt statt eines unklar kontinuierlichen Sliders. Vorschauen zeigen dieselben Zahlen und Datengrenzen. Sie sind lokal hinterlegte synthetische Beispiele, keine kostenpflichtigen Modellanfragen. Standard Sachlich, Detailtiefe zunächst Kurz; Umfang wird im eigenen Flow behandelt.

Neue lokale `CoachPresentationPreferences` mit stabiler Stil-/Umfangskennung und Version. Beim Öffnen gespeicherten Stand in einen Entwurf kopieren; bei unveränderter Auswahl Speichern deaktiviert. Speichern ändert nur kommende Antworten, nicht bestehende Nachrichten. Abbrechen stellt den gespeicherten Stand wieder her. Persistenzfehler lässt Auswahl offen und bietet Wiederholen; keine Erfolgsmeldung vor bestätigtem Speichern. Präferenzen gelten pro lokalem Profil und über Providerwechsel hinweg, solange der Nutzer sie nicht zurücksetzt.

`coach_prompt.dart` hat derzeit einen festen STYLE-Abschnitt; `AiPrefs` steuert Briefing-/Journalzeiten, nicht Antwortstil. Präsentationsvorgaben separat an den bestehenden Promptvertrag anschließen. Sie stehen unter den Regeln für abgefragte Zahlen, fehlende Daten, Quellen, zulässige Themen und explizite Bestätigung von Schreibvorschlägen. „Direkt“ erlaubt keine Druck-/Schuldsprache, „Warm“ keine erfundene positive Interpretation oder Gewissheit. Die gleiche Grundregel gilt für erzeugte Briefings, deren fachlicher Scorebezug bereits in `briefing_engine.dart` abgesichert wird. Aktuelle Daten weiterhin im jeweiligen Turn lesen; Stil oder gemerkte Vorlieben ersetzen keine Messwertabfrage.

Die neue Coach-Anpassung bleibt aus Profil und Chat erreichbar und verlinkt Verbindung/Freigaben sowie bestätigte gemerkte Angaben. Sie aktiviert weder einen Anbieter noch Datenaustausch. Die bestehende Trennung zwischen Providerkonfiguration, Zugangsschlüssel und optionalen Briefings bleibt erhalten.

**Prüfung:** Alle fünf Quellen und eigene Einstellungs-, unveränderte/änderbare Vorschau- und Speicherzustände angesehen. Konstante Beispielzahlen, 44-pt-Stilauswahl und deaktivierter unveränderter Speicherknopf geprüft. Keine Modellanfrage ausgeführt und keine Coach-Präferenz implementiert.

## B47 · Gemerkte Angaben mit Ablaufdatum

**Aus Flow 046.** Fünf Quellen zeigen Personalisierung, gespeicherte Angaben, Kontextmenü, Datumsauswahl und aktualisierte Gültigkeit. OpenBand verwendet bestätigte eigene Aussagen mit sichtbarer Herkunft und Gültigkeit. Synthetisch: „Unter der Woche trainiere ich lieber morgens.“ Der Ablauf ist einschließlich 30. September in der gewählten Zeitzone; ab 1. Oktober ist die Angabe nicht mehr aktiv. Diese Gestaltung verarbeitet keine echten persönlichen Angaben.

Neue lokale `CoachMemory`-Speicherung neben dem bestehenden Chatverlauf: stabile ID, bestätigter Text, Kategorie, Herkunfts-/Nachrichtenreferenz, Bestätigungszeit, optionaler letzter Gültigkeitstag plus IANA-Zeitzone, Versionsnummer und Widerruf. `coach_engine.dart` persistiert bereits Transkript und Modellhistorie, enthält aber keinen gleichwertigen Memory-/Ablaufvertrag. Ein erkanntes Detail bleibt ein Vorschlag bis zur ausdrücklichen Bestätigung. Keine Diagnose, aktuelle Messung oder Berechtigung aus einem Merkeintrag ableiten. Messwerte werden weiterhin aktuell abgefragt.

Aktivitätsprüfung bei jeder Kontextzusammenstellung, nicht erst durch einen Background-Job. Ein Gültigkeitstag endet am Beginn des Folgetags in der gespeicherten Zone; DST mit Kalenderarithmetik auflösen. Ablauf sortiert die Angabe in „Abgelaufen“, ohne automatische Wiederaktivierung bei erneutem Öffnen oder Wiederherstellen eines Chats. Kein Datumswechsel durch Reisen. Verlängerung/Änderung hat einen neuen bewussten Commit. Speicherfehler erhält den Entwurf. Aktiv-/Abgelaufen-Zahlen beziehen sich auf genau dieselbe Filterregel wie die dem Modell übergebenen Angaben.

Abgelaufene oder widerrufene Angaben dürfen auch über generierte Zusammenfassungen nicht wieder als aktuelle Vorliebe in neue Anfragen gelangen. Alte Nachrichten bleiben erhalten, wie im Ablaufeditor erklärt; die App kann einen bereits gesendeten Kontext nicht beim Anbieter zurückholen. Beim Fortsetzen alter Chats kennt der Coach die aktuelle Gültigkeit und behandelt alte Aussagen entsprechend, statt sie ungeprüft zu erneuern. Kontextdaten als Daten mit Herkunft/Status übergeben, nicht als neue Systemanweisung. „Vergessen“ widerruft den Merkeintrag; das Löschen des ursprünglichen Chats ist eine separate Funktion. Die exakte Löschgestaltung folgt im entsprechenden Flow.

**Prüfung:** Alle fünf Quellen sowie eigene Liste, Aktionsmenü, Datumseingabe und aktualisierte Liste angesehen. Einheitliche Merkkarten, feste Datumsspalten und klare inklusive Gültigkeit. Neue Memory-Persistenz, Ablauf- und Kontextfilter sind Implementierungsbedarf; keine echte Coach-Erinnerung gespeichert.

## B48 · Bestehendes Nährstoffziel ändern

**Aus Flow 047.** Vier Quellen zeigen Nährstoffkatalog, Ziel-/Schnelllog-Vorgaben, geänderte Menge und aktiviertes Ziel. OpenBand verwendet denselben Zieleingabevertrag wie B30/B39. Zielwert, Obergrenze und Schnelllog-Menge sind getrennte Einstellungen. Die Quellformulierung für Zucker als zu erreichende/überschreitende Menge wird nicht übernommen; es gibt keine pauschale Empfehlung aus dieser Referenz.

Synthetische Änderung: bereits aktives Ballaststoffziel 25 → 30 g pro Tag ab 15. September; Schnelllog bleibt 5 g. Der Editor zeigt den bisherigen Wert und den Gültigkeitsbeginn. Kein Ernährungseintrag wird durch das Ändern des Ziels erzeugt. Fehlende Tagesangaben bleiben „Offen“, ohne 0-%-Fortschritt. Die bestehende Zielperiode wird ab dem gewählten Tag atomar ersetzt/versioniert; frühere Tage behalten ihre Vorgaben. Unveränderte Eingabe deaktiviert Speichern. Zieleingabe aus einem bisher inaktiven Katalogeintrag benennt vor dem Commit ausdrücklich, dass damit ein Ziel aktiviert wird.

Schnelllog-Vorgaben gehören zu Eingabepräferenzen je Nährstoff-ID/Einheit, nicht zur Zielperiode. Das Öffnen einer Zahlenwahl erzeugt einen Unterentwurf; erst Rückkehr und Speichern übernimmt das Ziel. Speicherfehler erhält beides. B30/B39 liefern Historie, Einheiten und fehlende-Werte-Regeln.

**Prüfung:** Vier Quellen sowie geänderter Editor und gespeicherte Offen-Karte angesehen. Den gemeinsamen Editor auch für die frühere Neuanlage auf ein kompakteres, erkennbar editierbares Mengenfeld umgestellt. Keine Ziel-/Presetpersistenz implementiert.

## B49 · Satzart ändern

**Aus Flow 048.** Drei Quellen zeigen Vorlage, Satzartmenü und geänderten Satz. OpenBand öffnet die Auswahl am Satzkennzeichen und nennt Übung, Position und geplante Ausführung. Nach dem Wechsel ist der Aufwärmsatz durch Symbol und ausgeschriebene Zählung erkennbar. Zwölf geplante Sätze bleiben zwölf; nicht alle sind danach Arbeitssätze. Last und Wiederholungen werden durch den Typwechsel nicht automatisch geändert.

B23/B26 ergänzen: Satzart, geplante Intensitätsabsicht, tatsächlich bestätigter Abschluss und Reduktionssatz-Gruppe brauchen unterscheidbare Felder. `strength_set` enthält derzeit nur Übung, Reihenfolge, Wiederholungen, Last, RPE, Halte-/Pausenzeit, Zeitpunkt und Notiz. Ein geplantes Muskelversagen bestätigt kein erreichtes Muskelversagen; eine Warm-up-Markierung entfernt keine tatsächliche Belastung. Reduktionsabschnitte benötigen stabile Gruppierung/Reihenfolge und eigene Last-/Wiederholungswerte, damit Volumen nicht doppelt zählt. Abwärmen bleibt eine explizite Satzart. Historische Einträge ohne Typ bleiben unklassifiziert, statt rückwirkend als bestätigte Arbeitssätze zu gelten.

Vorlagenwechsel bleibt im Entwurf bis „Vorlage speichern“. Änderung eines ausgeführten Satzes verwendet dessen eigenen Korrekturpfad und berechnet betroffene Auswertungen neu. Arbeits-/Aufwärmsatz-Zahlen und Bestleistungsregeln müssen ihre Einschlussregeln offenlegen. Synthetisch: Bankdrücken Satz 1 wird Aufwärmen, zwei weitere bleiben Arbeitssätze; 40 kg und acht Wiederholungen je Satz unverändert. Keine automatische Empfehlung für Lastreduktion oder Training bis zum Versagen.

**Prüfung:** Alle drei Quellen und eigenes Kontextmenü sowie geänderte Vorlage angesehen. 44-pt-Ziele, sichtbarer Typ und unveränderte Mengen geprüft; aktuelle Strength-Tabelle gelesen. Noch keine Satzartpersistenz implementiert.

## B50 · Eigener Aktivitätsstatus und zeitweise Pause

**Aus Flow 049.** Acht Quellen zeigen Home, Einführung, vier Statusoptionen, Zeitraumwahl und aktualisiertes Home. OpenBand führt direkt zur Auswahl aus „Dein Bereich“. Ohne eigene Angabe wird kein Gesundheits-/Aktivitätsstatus behauptet. Auswahl: Keine Angabe, Trainingspause, Ich bin krank, Ich bin verletzt. Ein aktiver Status erscheint als kleine Zeile nach den Hauptwerten im Home; keine zusätzliche permanente Zeile im Normalfall. Die Aufzeichnung und gemessene Belastung bleiben sichtbar.

Neuer lokaler, versionierter Statuszeitraum mit eigener Angabe, Beginn, optionalem Endtag und Zeitzone. Tagesende ist der Beginn des Folgetags in dieser Zone; Reise/DST und Neustart deterministisch auflösen. Innerer Datumspicker ändert nur den Statusentwurf, „Status speichern“ den Bestand. Heute/7 Tage zeigen vor dem Commit das konkrete Datum. „Bis ich es ändere“ hat kein verstecktes Ablaufdatum. Historische Tage zeigen den damals gültigen Kontext, nicht den heutigen Status. Journal-Tag, automatischer Auffälligkeitsdetektor und selbst gemeldeter Status sind drei unterschiedliche Datenquellen und ersetzen einander nicht.

Trainingspause unterdrückt Trainings-/Schritteaufforderungen bis zum ausdrücklich gewählten Ende, danach gelten die vorherigen Benachrichtigungspräferenzen. Gesundheitsspezifische Angaben unterdrücken automatische Trainingsvorschläge; nach deren Ablauf zuerst eine ruhige Rückfrage im Feed, keine unterstellte Genesung und kein direktes Wiederaufnehmen intensiver Vorschläge. Die Mitteilungsplanung muss bestehende geplante Impulse entsprechend abmelden und beim Senden nochmals den Status prüfen. Medikamenten-, Bandakku- und Speicherhinweise bleiben nach ihrer eigenen Einstellung erhalten. Coach/Briefing erhält den datierten Selbstbericht mit Herkunft, ohne daraus eine Diagnose abzuleiten.

Keine automatische Umschreibung von Erholung, Belastung, Schlaf oder historischen Bestleistungen; keine Graufärbung, die einen gemessenen Wert verschwinden lässt. Manuell gestartetes Training bleibt möglich. Laufendes Training wird durch einen Statuswechsel nicht beendet. Keine stillen Baseline-Ausschlüsse oder erfundene Null-Trainingslast. Ein optionaler Ausschluss aus einer späteren Analyse muss gesondert sichtbar begründet sein.

**Prüfung:** Acht Quellen, eigene Status-/Zeitraumwahl, Profileinstieg und Home mit Pause angesehen. Gemeinsame Tageszahlen bleiben 7h18/74/1,6. Aktuelle Pfade haben Auffälligkeitsdetektoren, aber keinen gleichwertigen selbst gemeldeten Statuszeitraum; Persistenz und Benachrichtigungsanbindung sind neu zu bauen.

## B51 · Alkohol-Schnelllog mit definierter Portion

**Aus Flow 050.** Drei Quellen zeigen Alkoholansicht und Änderung einer voreingestellten „Drink“-Menge. OpenBand definiert die Portion über Getränk, Volumen und Alkoholgehalt. Synthetische Änderung: Wein von 125 auf 150 ml bei 12 Vol. %. Ungefähr 14 g Alkohol ist eine gerundete Mengenrechnung, keine Aussage über ein sicheres Maß. Zum Mengenvergleich: [NIAAA beschreibt 5 US fl oz Wein bei etwa 12 % als ungefähr 14 g reinen Alkohol](https://rethinkingdrinking.niaaa.nih.gov/how-much-too-much/whats-standard-drink); der [Getränkerechner](https://rethinkingdrinking.niaaa.nih.gov/tools/calculators/alcohol-drink-size-calculator) unterscheidet Portionsvolumen und Alkoholgehalt. OpenBand verwendet keine undeklarierte nationale Standardglas-Definition.

Der bisherige Journalvertrag `alcohol_units` besitzt nur unspezifizierte „units“ mit Zeitschlüssel. Ergänzung: Getränkevorlage mit Volumen/Einheit, Vol.-%-Angabe, daraus nachvollziehbar abgeleiteter Alkoholmenge und Versionsstand. Ein tatsächlicher Eintrag kopiert diese Angaben einschließlich Zeitpunkt und Berechnungsbasis. Historische unbekannte Einheiten nicht pauschal in Gramm umrechnen. Fehlender Alkoholgehalt lässt die Alkoholmenge offen; kein Standardwert aus dem Getränkenamen. Volumen- und Prozentfelder prüfen finite Werte, Einheiten und gültigen Prozentbereich, ohne „gesundes“ Limit zu erfinden.

Vorlage speichern legt ausschließlich eine Eingabepräferenz an. „150 ml jetzt eintragen“ ist die ausdrückliche separate Journalaktion für den sichtbaren Zeitpunkt heute 09:41; danach Beleg und Rückgängig. Bei historischen Tagen Uhrzeit wählen, nicht die aktuelle Tageszeit unterschieben. „Andere Menge“ öffnet den Mengen-/Zeitentwurf. Wiederholter Speicherversuch nach unklarer Rückmeldung darf denselben Eintrag nicht verdoppeln. „Abends“ sortiert den Eintrag im Journal, ersetzt aber niemals seine tatsächliche Uhrzeit. Fehlender Tageseintrag bleibt offen, nicht null Gramm.

**Prüfung:** Alle drei Quellen und eigener Vorlage-/gespeicherter Leerzustand angesehen. Eigene Portion und Vergleichsgröße über Primärquelle geprüft; bestehende unspezifizierte Einheit im Code gelesen. Keine Dosis eingetragen und kein Backend erweitert.

## B52 · Zeitbasierte Übungsvorgaben bearbeiten

**Aus Flow 051.** Vier Quellen zeigen Satzeditor, Dauer-/Wiederholungswahl und auf mehrere Sätze übertragene Eingabe. OpenBand nutzt dieselbe ausdrücklich genannte Übernahmemenge wie B40. Für die zeitbasierte Plank-Vorlage wird die Dauer mit getrennten Minuten-/Sekundenspalten gewählt; 1:00 bedeutet 60 Sekunden. Eine Wiederholungszahl wird weder daraus geschätzt noch gleichzeitig als zweiter Wert erzeugt.

B23/B26 um einen eindeutig typisierten Leistungswert pro geplanter Satzposition ergänzen: Wiederholungen oder Dauer in ganzzahligen Sekunden; Eigengewicht/Lastbasis und Pausendauer bleiben unabhängige Felder. Die Erfassungsart folgt der ausgewählten Übungsdefinition. Bei Übungen mit zulässigen Alternativen wird sie ausdrücklich gewechselt; ungespeicherte alte Eingabe bleibt beim Umschalten im Entwurf erhalten, der Commit enthält aber genau die gewählte Art. Bereits gespeicherte andersartige Werte werden nicht numerisch umgedeutet. Fehlende Vorgabe ist null, keine Dauer null und keine Wiederholungszahl null.

Synthetisch: Plank Satz 1 von 45 auf 60 Sekunden, nach bewusster Auswahl auch Satz 2/3. Die drei Pausen bleiben 60 Sekunden. Der Zeitdialog ändert direkt den zugehörigen Vorlagendraft; „Fertig“ schließt die Übungsdetails. Erst die übergeordnete Vorlagen-Speicherung persistiert die Vorgaben. Keine ausgeführten Sätze oder echte Trainingsminuten entstehen. Zeitgeber und tatsächliche Haltezeit einer laufenden Einheit verwenden den separaten Live-Vertrag, nie die Planzeit als absolvierte Zeit. Doppeltippen/erneute Dialogbestätigung erzeugt keine weiteren Sätze.

**Prüfung:** Vier Quellen, eigener Dialog und geänderte Plank-Vorlage mit drei 1:00-Zeilen angesehen. Spalten, Minuten/Sekunden und unveränderte Pausen geprüft. `strength_set.hold_sec/reps/rest_sec` vorhanden; typisierte Entwürfe und atomare Mehrfachänderung fehlen noch.

## B53 · Quellhistorie nachladen, Speicherung getrennt halten

**Aus Flow 052.** Sechs Quellen zeigen Ladefenster von einem auf zwei Jahre und gespeicherte Einstellung. OpenBand macht daraus einen ausdrücklichen Nachladeauftrag mit Quelle, Datentyp und Zeitraum. Aktuelles Beispiel: Apple-Health-Trainings 15.09.2024–15.09.2026. Ein kleineres Fenster löscht nichts. Originaldaten-Aufbewahrung, Bandübertragung, Dateiimport und Health-Historie sind getrennte Ziele im überarbeiteten Datenbereich.

`HealthWorkoutImport.sync` liest derzeit auf Apple fest 90 Tage, auf Android 30. Es fängt Lesefehler ab und liefert wie bei einem leeren Ergebnis einen Nullbefund zurück; das reicht für die neuen Zustände nicht. Benötigt werden expliziter Auftrag/Zeitraum, stabile Job-ID, abschnittsweise Cursor, datentypspezifischer Fortschritt, beständige Commit-Belege, Abbruch/Pause/Neustart und getypte lesbar-unbekannt/leeres-Ergebnis/temporärer-Fehler-Zustände. Keine positive Leseberechtigung aus einem leeren HealthKit-Ergebnis ableiten. Bestehende UUID-Deduplizierung und Lösch-Tombstones erhalten, Fortschrittszahlen erst nach Commit zählen. Nach Fortsetzen nur offene Abschnitte prüfen; erneute Ausgabe derselben Quelle aktualisiert denselben Eintrag.

Synthetisch sind vor Unterbrechung neun neue und drei bereits vorhandene Trainings erfasst; geprüft bis 31. März 2025. In den restlichen Abschnitten kommen keine weiteren hinzu. „Abfrage abgeschlossen“ besagt nur, dass der angeforderte Zeitraum abgefragt wurde, nicht dass die Quelle lückenlos gemessen hat. Die aktuelle Beispielwoche und Tageswerte werden dadurch nicht verändert. Auswertung kann nach gespeichertem Import noch laufen oder fehlschlagen und hat einen eigenen Status. Band bleibt unabhängig verbunden mit gespeicherten Daten bis 07:42. „Später fortsetzen“ beendet den aktuellen Importversuch mit dauerhaftem Cursor.

Die Profilübernahme liest auf Apple ein Jahr, um sehr alte Körperwerte nicht als aktuellen Profileingang zu verwenden. Historische Körpermessungen aus B43 dürfen einen aktuellen Profilwert nicht durch einen älteren Wert ersetzen. Quellen-/Typrechte und Berechnungsfenster bleiben unabhängig. Ein zwei Jahre langes Health-Fenster verspricht keinen ebenso langen WHOOP-Gerätepuffer. Fehlende Band-Rohdaten können nur aus tatsächlich verfügbaren Quellen oder einer Sicherung wiederhergestellt werden.

Im aktuellen Decoder-/Derivationspfad existieren `rawRetentionDays = 3`, ein begrenzter Haltezeitraum und ausgedünnte unbekannte Frames im `raw_archive`. Der Tabellenname ist kein Beleg für vollständige Langzeit-Rohdaten. Die für OpenBand vorgesehene Originaldaten-Aufbewahrung muss deshalb separat als belastbares Archiv-/Exportkonzept umgesetzt werden; dieser Bildschirm verändert keine Aufbewahrungs- oder Löschregeln. Commit-before-ACK, Gerätezuordnung und unabhängige Quelldaten bleiben erhalten. Keine Firmware-/R22-/Force-trim-Aktion gehört zum Historienladen.

**Prüfung:** Alle sechs Quellen sowie Datenhub, Zeitraumauswahl, Unterbrechung und Importbeleg angesehen. Aktuelle Health-Fenster, Fehlerverhalten und Rohdaten-Aufbewahrung direkt gelesen. Kein Health-/Bluetooth-Aufruf ausgeführt; die Zahlen sind synthetische Zustandsbeispiele.

## B54 · Ein gemeinsamer Tag und ehrliche Kalenderzeichen

**Aus Flow 053.** Vier Quellen zeigen Kalender, Messwertwechsel und einen vergangenen Home-Tag. OpenBand nutzt einen gemeinsamen Tageskontext für Übersicht, Gesundheit, Training und Journal. Der Kalender bietet Schlaf/Erholung/Belastung als Vorschau, einen Monats-/Jahressprung und „Zu heute“. Der volle Punkt bedeutet ausschließlich: ein Wert dieser Metrik liegt vor. Er behauptet weder lückenlose Erfassung noch Verbindung oder Aktualität. Ein leerer Punkt steht für einen vergangenen Tag ohne Ergebnis dieser Metrik; zukünftige Tage werden nicht als fehlende Messungen dargestellt.

Bestehender `ui2/app_shell.dart` hält den gewählten Bereich, aber keinen gemeinsamen Tageskontext. Die Umsetzung braucht einen datierten Kontext mit Kalenderdatum und zugehöriger Auswertungszeitzone, einen queryfähigen Ergebnisindex pro Metrik sowie Weitergabe an Detailrouten, Rücknavigation und Tagebuchentwürfe. Die Auswahl gilt erst nach „Tag ansehen“; Abbrechen erhält den bisherigen Tag. Ein Monats-/Messwertwechsel allein ändert den Tageskontext nicht. Tagesgrenzen über Kalenderdaten berechnen, nicht pauschal 24 Stunden abziehen. Nächte werden über ihr Aufwachdatum zugeordnet und mit beiden Daten beschriftet.

Historischer Tagesinhalt darf weder heutige Werte noch heutige Gesundheitsangaben übernehmen. Geräteverbindung und letzte Speicherung sind dagegen Live-Zustand und werden ausdrücklich als heute bezeichnet. Ein neu gestartetes Live-Training beginnt jetzt; ein historischer Trainingseintrag öffnet einen datierten manuellen Entwurf. Abgelaufene Jobs dürfen beim raschen Datumswechsel nicht Ergebnisse für den falschen Tag anzeigen. Detailzurück erhält Tag, Scrollposition und angewählten Messwert. „Zu heute“ wird beim lokalen Datumswechsel neu aufgelöst; ein bewusst gewählter alter Tag springt nicht um Mitternacht weg.

Synthetischer 14. September: 7h02 Schlaf, Ruhepuls 56/min, HRV 40 ms, Lauf 5 km/25 min mit Einheitsbelastung 5,9. Für diesen Tagesausschnitt sind keine gespeicherten Tageswerte für Erholung/Belastung definiert; sie bleiben offen. Die Einheitsbelastung wird nicht als Tagesgesamtwert ausgegeben. Der Schlafkreis zeigt hier nur den vorhandenen Schlafwert, keinen erfundenen Ziel- oder Effizienzanteil. Leerer Vergleichstag ist der 20. August, außerhalb der definierten September-Baseline. Eigene Einträge sind dort weiterhin möglich; Quellenhistorie kann nur verfügbare Daten nachliefern.

**Prüfung:** Alle vier Quellen und eigene Kalender-/historische-/leere Tagesansichten angesehen. Kalenderwochentage, ausgewählter Montag 14.9., heutigen Dienstag 15.9., verfügbare Schlafwerte 8.–15.9. und 44-pt-Datumsziele geprüft. Kalenderüberlauf behoben. Kein Routing oder Persistenzcode geändert.

## B55 · Diagrammzeitraum, Aggregation und Enddatum

**Aus Flow 054.** Sechs Quellen zeigen kurzen/jährlichen Verlauf, Kalender-Enddatum und neu verankerten Zeitraum. OpenBand übernimmt die direkt am Diagramm angeordneten Perioden und einen separaten Endtag. Die Ruhepulsansicht demonstriert 7 Tage und 30 Tage; „Jahr“ wird nach Kalendermonaten zusammengefasst. Die Datumauswahl dieser Analyse verändert nur deren Enddatum, nicht still den gemeinsamen Home-Tag aus B54.

Benötigt wird eine gemeinsame Bereichsabfrage mit Metrik, Endtag, Zeitzone, Fensterdefinition, Aggregationsfunktion, vorhandenen/erwarteten Tagen, Quellen und Algorithmusversion. 30 Tage umfassen den Endtag und 29 vorherige Kalendertage. Ein Jahr umfasst zwölf Kalendermonate bis zum Endtag; weder 365 Tage noch ein Schaltjahr still gleichsetzen. Zurück/Vor schiebt um genau ein Fenster, nicht um die Zahl vorhandener Werte. Zukunft begrenzen. Ein neuer Endtag bleibt bis zur Bestätigung Entwurf. Abbrechen stellt das vorherige Diagramm einschließlich Auswahl wieder her.

Wertüberschrift benennt „Durchschnitt“, „Summe“, „Median“ oder eine ausgewählte Nacht ausdrücklich. Ruhepuls verwendet einen gleichgewichteten Durchschnitt der vorhandenen Nachtwerte; fehlende Nächte sind keine Nullwerte. 30-Tage-Beispiel 17.8.–15.9.: 15 gespeicherte Nachtwerte ergeben 55,866…/min, angezeigt 55,9/min. Die ersten 15 Tage bleiben leer; keine Interpolation über diese Lücke. „15 von 30 Nächten“ ist Ergebnisverfügbarkeit, keine Aussage über die Zeitabdeckung innerhalb der Nächte. Tages- und Monatswerte benötigen beim Tippen einen zugänglichen Textbeleg samt Datum, Einheit, Anzahl und Quelle. Persönlicher Vergleichsbereich nur bei gültiger eigener Referenz, nie aus dem sichtbaren Diagrammfenster improvisieren.

Jahresbalken/-punkte tragen pro Monat die Anzahl vorhandener Nächte. Eine Auswahl zeigt deren Monatsdurchschnitt; die übergeordnete Jahreszahl wird über Nächte gewichtet, nicht als ungewichtetes Mittel der Monatsmittel. Belastung und Schlaf werden nicht automatisch nach derselben Regel summiert. B01/B44 definieren Metrik und Methode; deren Semantik bleibt beim Zeitraumwechsel erhalten. Kein automatisches Nachladen externer Quelldaten beim bloßen Diagrammwechsel; B53 ist eine eigene Aktion.

**Prüfung:** Alle sechs Quellen, bestehender 7-Tage-Verlauf, neue 30-Tage-Ansicht und eigener Endtag-Picker angesehen. Achsen, leere Hälfte, 15/30-Nenner, rechnerischer Durchschnitt und verfügbare Fläche oberhalb der Tabbar geprüft. Bestehende Detailkopf-Zielfläche auf 44 pt korrigiert. Neue Bereichsabfrage noch nicht implementiert.

## B56 · Einheiten je Größenart, konsistente Vorschau

**Aus Flow 055.** Fünf Quellen zeigen Einheiteneinstellungen und Wechsel von km auf mi. OpenBand bietet einzelne Größenarten statt eines gekoppelten Länderprofils. Die Entfernungsauswahl zeigt vor dem Commit denselben Lauf als 3,11 mi und 8:03 min/mi; 5,00 km, 25 Minuten und alle gespeicherten Quelldaten bleiben dieselbe Messung. Der direkte Button „Meilen verwenden“ speichert diese einzelne Präferenz, Zurück verwirft sie. Keine zweite, versteckte Gesamt-Speicherung auf der Elternseite.

`UnitsController` speichert heute ein lokales `UnitSystem` und besitzt bereits die Umrechnung 1609,344 m/mi, Pace-/Geschwindigkeitsformatierung sowie kg/lb und cm/in. Erweiterung: unabhängige typisierte Präferenzen für Entfernung, Größe, Gewicht, Temperatur, Energie, Wasservolumen und Glukose. Bestehendes Metric/Imperial einmalig in entsprechende Ausgangswerte migrieren; unbekannte neue Größen erhalten einen dokumentierten Standard. Energie aus Ernährung und Aktivität verwendet dieselbe Anzeigeeinheit. Auswahl ist ausdrücklich nur eine Anzeige-/Eingabepräferenz und erzeugt keine Glukose- oder Temperaturdaten.

Quellenwerte mit Einheit und Präzision erhalten; kanonische Rechengrößen nicht durch gerundete Displaywerte überschreiben. Eingabeentwürfe halten die bei Beginn gewählte Einheit; ein externer Einstellungswechsel interpretiert eingegebenes „5“ nicht neu. Deutsche Dezimalkommas, Einheiten, Ganz-/Dezimalwerte und fehlende Werte zentral formatieren/prüfen. Wiederholtes Öffnen/Speichern unveränderter Profile darf keine Rundungsdrift verursachen. Persistenzfehler bleibt sichtbar und setzt die Auswahl nicht als erfolgreich gespeichert voraus.

Entfernung steuert Distanz, Pace und Geschwindigkeit zusammen, einschließlich Live-Training, Detail, Kartenmaßstab und Teilendarstellung. Streckenabschnitte brauchen eine explizite Strategie: originale 1-km-Runden als solche beschriften oder neue Meilenabschnitte aus vorhandener Zeit-/Distanzserie berechnen. Bestehende fünf Kilometerzeiten nicht als fünf Meilen ausgeben. Bei unzureichender Serie bleiben Originalabschnitte erhalten. Originalexporte behalten Quelleneinheiten; menschenlesbare Exporte nennen die gewählte Anzeigeeinheit und Methode.

**Prüfung:** Alle fünf Quellen, überarbeitete Einstellungen, Einheitenliste, Vorschau und gespeicherte Meilenauswahl angesehen. Umrechnungsbasis direkt im bestehenden Controller geprüft: 5000/1609,344 = 3,10685… mi; 1500/(5000/1609,344) = 482,8032 s/mi. Keine Messungen oder App-Einstellungen geändert.

## B57 · Journalfrage anordnen, Ereigniszeit nicht umdeuten

**Aus Flow 056.** Vier Quellen wechseln eine Lesefrage zwischen Tages-/Nachtabschnitt. OpenBand nennt dies ausdrücklich „Anordnung“: Im Tagesverlauf oder Abendlicher Check-in. Der synthetische Wechsel betrifft die eigene Frage „Abends gelesen“ aus B29. Ihr Name, Tag, Ja/Nein/Offen-Antwort und vorhandene Ereigniszeiten bleiben unverändert. Der gespeicherte Journalzustand zeigt die neue Position mit weiterhin offener Antwort.

B29/B34 um eine unabhängige Anzeigegruppe und stabile Sortierposition je Feld erweitern. `JournalFieldSpec.hasTime` bezeichnet heute, ob eine echte Uhrzeit zum Messwert gehört; es darf nicht als Anzeigegruppe wiederverwendet werden. Der Zeitpunkt einer Alkohol-/Koffeinangabe bleibt ein datiertes Ereignis. Bei täglichen Ja/Nein-Fragen bleibt der Tag die Zuordnung, eine Gruppenwahl erzeugt keine künstliche Uhrzeit. Frühere Analysen oder Nächte werden durch Umordnen nicht neu zugeordnet.

Die Auswahl wird als lokale, beständige Darstellungspräferenz gespeichert. Der Dialog besitzt einen Entwurf; Zurück verwirft, Speichern übernimmt atomar. Die Frage kann nur in einer Gruppe stehen, nicht als zwei unabhängige Felder dupliziert werden. Ausblenden und Löschen sind andere Aktionen; gespeicherte Antworten bleiben erhalten. Bei gleichzeitig geänderten Fragen stabilen Feldschlüssel verwenden, nicht den sichtbaren Namen als Identität.

Eine Gruppenwahl aktiviert keine neue Mitteilung. Wenn eine bereits erlaubte Check-in-Erinnerung ihre Fragen aus dieser Gruppe bezieht, den Inhalt beim Senden aus der aktuellen Auswahl aufbauen; das Zeitfenster der Mitteilung selbst bleibt eine gesonderte Präferenz. Bei Tageswechsel und Reise gilt weiterhin die dokumentierte Tages-/Zeitzonenzuordnung. Sichtbare Bezeichnung „Abends gelesen“ beschreibt die eigene Frage, nicht einen vom System gesetzten Erfassungszeitpunkt.

**Prüfung:** Alle vier Quellen und eigene Auswahl-/gespeicherte Journalansicht angesehen. Ja/Nein/Offen bleibt unverändert; keine zusätzlichen Daten oder Rückdatierung. Aktueller Feldvertrag gelesen, kein Backend geändert.

## B58 · Beobachten, Zielwert und eigene Obergrenze

**Aus Flow 057.** Sechs Quellen wechseln die Ernährungsabsicht zwischen Ziel, Limit und keiner Orientierung. OpenBand übernimmt die explizite Wahl, aber keine pauschalen Referenzempfehlungen aus dem Vorbild. Drei Zustände: Nur beobachten, Zielwert, Obergrenze. Ein eigener Vergleichswert ist ein datierter Nutzerwert; kein automatisch als passend behaupteter Bedarf. Beispiel: selbst gewählte Gesamtzuckergrenze 30 g ab 15.9. als separate synthetische Variante.

B08/B30/B39/B48 um eine diskriminierte Zielart erweitern: Beobachten ohne aktive Menge oder Ziel/Obergrenze mit Wert, Einheit, Größenart und Gültigkeitszeitraum. Vorherige Mengen dürfen im Entwurf beim Umschalten erhalten bleiben; ein Beobachten-Commit enthält keinen aktiven Grenzwert. Speichern einer Darstellungsabsicht löscht keine Nährstoffeinträge und erzeugt keine Einnahme. Zurück verwirft den Entwurf. Frühere Tage werden nicht still gegen die neue Grenze bewertet.

Gesamtzucker, zugesetzter Zucker und freier Zucker sind getrennte Größen mit eigener Herkunft. Eine Produktangabe „davon Zucker“ darf nicht als zugesetzter/freier Zucker behandelt werden. Vorschläge und automatische Voreinstellungen für Grenzen sind nicht Teil dieses Entwurfs. Der Import und eigene Produkte müssen unbekannte Nährwerte von bestätigten Nullen unterscheiden.

Bei unvollständigem Tag ist die Summe eine bekannte Untergrenze: Joghurt 200 g enthält im synthetischen Beispiel 8 g, beim Haferfrühstück fehlt die Angabe. Anzeige ≥8 g, offene Bewertung und direkter Einstieg zur fehlenden Angabe. Kein „22 g übrig“, kein erfolgreicher grüner Tagesstatus. Eine nachweislich über der Grenze liegende bekannte Teilmenge kann bereits als Überschreitung benannt werden; eine bekannte Teilmenge unter der Grenze beweist keine Unterschreitung. Bei vollständigen Angaben bleibt „zu deiner eigenen Grenze“ die Bezugsgröße, kein Sicherheitsversprechen. Fortschrittsbalken ist neutral und zeigt nur die bekannte Menge.

**Prüfung:** Sechs Quellen, eigene Absichtsauswahl und gespeicherte Teilmenge mit Beiträgen angesehen. Eigenes Limit, ≥8 g, fehlender Beitrag, Originaleinträge und zeitliche Gültigkeit getrennt. Bestehende Verträge aus B08/B39 bleiben die Grundlage; diese Erweiterung wurde nicht implementiert.

## B59 · Zonenmethode mit Eingängen, Vorschau und Versionsstand

**Aus Flow 058.** Vier Quellen zeigen Zonen nach Maximalpuls sowie Wechsel zu Pulsreserve. OpenBand bietet Automatisch, Maximalpuls, Pulsreserve und eigene Grenzen. Methode, Eingangswerte, Herkunft und resultierende fünf Bereiche stehen vor dem Speichern fest. Eine eigene Zahl wird ausdrücklich als eigene Angabe beschriftet, nicht als Bandmessung. Die angebotene Leistungsdiagnostik-/Schwellenpuls-Methode des Vorbilds wird nicht als weitere unbestimmte Formel übernommen: Solche getesteten Grenzen können zunächst als eigene Bereiche hinterlegt werden. Ein späterer Schwellenpulsmodus benötigt Sportart, benanntes Zonenschema und datierten Testvertrag.

Aktueller Code ist weiter als ein reines Altersmodell: `trainingZones` in `edge/lib/compute/hr_max.dart` verwendet eine geeignete beobachtete Obergrenze und, falls vorhanden, die Ruhepulsbasis für Karvonen. Die automatische Obergrenze ist mindestens die Altersschätzung; ein nur niedrig beobachteter Trainingspuls beweist kein persönliches Maximum. `reserveZones` verlangt derzeit mindestens 14 gültige Tageswerte im vorgesehenen 28-Tage-Verlauf und verwendet deren Median. Die Tanaka-Schätzung wird aktuell bewusst nicht als vermeintlich beidseitig gemessene Pulsreserve ausgegeben. Diese Regeln sind Methodeneigenschaften und müssen in der Erklärung mit Herkunft erscheinen.

Neuer Vertrag: explizit gewählte Methode plus typisierte Eingänge, Quellen und Zeitpunkt, Zustandsstatus bereit/fehlender Eingang/ungültige Grenzen sowie Ergebnisversion. Automatik und eigene Vorgabe sind unterschiedliche Autoritäten; ein bewusst eingetragenes Maximum nicht still wieder durch das Altersmaximum ersetzen. Eine eigene Angabe ist damit nicht automatisch physiologisch validiert. Eigene Zonengrenzen müssen vollständig, endlich, streng aufsteigend und ohne Lücken/Überlappungen sein. Keine „Fettverbrennungs-“ oder Schwellenbehauptung aus Modellprozenten.

Basisscreen bleibt beim gemeinsamen Beispiel: 26 Jahre, Tanaka 189,8/min, gerundet 190/min; ganzzahlige Zuordnung 95–113 / 114–132 / 133–151 / 152–170 / ab 171. Eigene Varianten-Vorschau: Maximum 195/min und Basis 56/min aus 1.–14.9.; `56 + p × (195−56)` ergibt die ungerundeten Untergrenzen 125,5 / 139,4 / 153,3 / 167,2 / 181,1. Ganzzahlige Anzeige 126–139 / 140–153 / 154–167 / 168–181 / ab 182. Zuordnung rechnet mit ungerundeten Grenzen; Anzeige und Klassifikation müssen dieselben Intervallregeln beschreiben. Messwerte unter Zone 1 und fehlende Zeit bleiben eigene Größen, keine sechste Trainingszone.

Bei nur fünf gültigen Nächten bleibt die neue Methode ungespeichert und die bisherige aktiv. Verfügbarkeit wird beim Speichern erneut geprüft; eine Vorschau kann während neuer Daten veralten. Eingänge für eine laufende Einheit am Start fixieren. Neue Präferenz gilt ab dem sichtbaren Zeitpunkt, hier 15.9.09:41; abgeschlossene Einheiten behalten ihre Methodenversion. Eine spätere historische Neuberechnung ist eine separate überprüfbare Aktion und bewahrt Originalwerte/Quelle. Tages-, Live- und Detailauswertung müssen dieselbe gespeicherte Grundlage lesen. TRIMP, Belastung und Kalorien wechseln nicht beiläufig zusammen mit Anzeigezonen; deren eigene Methode bleibt sichtbar und versioniert.

**Prüfung:** Alle vier Quellen, überarbeiteter Basisscreen, Auswahl, Vorschau, gespeicherte Variante und fehlende Basis angesehen. Grenzen anhand der bestehenden Formeln geprüft. Aktuelle automatische Auswahl und Mindesthistorie direkt gelesen. Keine Profileinstellung geändert, keine physiologische Validierung und keine Neuberechnung ausgeführt.

## B60 · Kontextueller Coach, nachprüfbare Antworten und bestätigte Änderungen

**Aus Flow 059.** Sechs Quellen zeigen Einstieg aus Home, vorgeschlagene Fragen, Anfrage, Verarbeitung und längere Antwort. OpenBand übernimmt den schnellen Einstieg, verwendet jedoch eine ruhige deckende Lesefläche. Ein kompakter Kopf hält gewählten Tag und Datenstand fest. Vorschläge öffnen eine echte Anfrage; kein künstliches „Nachdenken“-Protokoll. Tatsächliche Datenabfrage und Antwortstatus dürfen angezeigt werden. Antworten verbinden kurze Prosa mit wiederverwendbaren Wert-/Diagrammbausteinen und einer datierten Quellenansicht. Der Composer bleibt über Tastatur und sicherem Bereich erreichbar; leerer Text kann nicht gesendet werden.

Überarbeitete Wege: Einstieg → Anfrage in Arbeit → Antwort → verwendete Daten → ursprünglicher Detailkontext; nicht erreichbares Modell → Wiederholen/Verbindung prüfen; bewusst anhalten → Frage bleibt; fehlende VO₂max → Messwertquelle öffnen; eigene Notiz als Vorschlag → bearbeiten/bestätigen/verwerfen → lokaler Speicherbeleg mit Journalziel und Rücknahme. „Schließen“ verliert weder Verlauf noch Eingabe. Bei neuer Frage wird die aktuelle Auswahl erfasst; bestehende Nachrichten behalten ihre ursprünglichen Daten-Snapshots. Wechsel des ausgewählten Tages ändert keine bereits erzeugte Antwort.

### Bestehendes Fundament und neue Verträge

`CoachEngine` besitzt bereits lesende Werkzeuge, Diagramme, `ActionRequest`, Bestätigungs-Callback und persistierten Gesprächsverlauf. `CoachActions` validiert Schreibargumente und schreibt oder wirft einen Fehler. Diese Grenzen erhalten. Neu nötig: stabile Gesprächs-/Nachrichten-/Auftrags-IDs, datierte Kontext-Snapshots, maschinenlesbare Belegreferenzen pro Antwort, getypte Arbeits-/Fehler-/Abbruchzustände, Abbruchsignal über HTTP/Toolschleife und Wiederaufnahme ohne doppelte User-Nachricht. Der aktuelle `send`-Loop hat maximal zehn Iterationen und ruft `_chat`; das ist noch kein Nachweis für abbrechbares Token-Streaming. Ein gestoppter Teiltext bleibt ausdrücklich unvollständig und wird nicht als fertige Antwort zitiert. Keine Anzeige verborgener Modellgedanken; Fortschritt beschreibt ausgeführte Datenzugriffe.

„Erneut versuchen“ startet einen neuen Leseversuch für dieselbe Frage, mit sichtbarem Datenstand. Bereits bestätigte Schreibaktionen werden vorher über ihre stabile Aktions-ID abgeglichen und nicht erneut ausgeführt. Eine Schreibaktion trägt genaue Werte, Datum/Zeit/Zeitzone und Zielobjekt; der sichtbare bestätigte Entwurf ist der auszuführende Inhalt. Eigene Änderungen im Vorschlag brauchen erneute Validierung. Abbruch vor Bestätigung schreibt nichts; nach bereits erfolgtem Commit bleibt der echte Speicherbeleg sichtbar. Rücknahme betrifft genau die gespeicherte Version; bei späterer Änderung zuerst den Konflikt zeigen. Die synthetische Notiz „Ich bin ausgeruht.“ ist ein Selbstbericht um 09:41, keine aus Messwerten abgeleitete Behauptung. Neue Varianten ändern nicht die Basisfixture.

Die Quellenansicht listet tatsächlich gelesene/übermittelte Eingänge und Vergleichsfenster samt Berechnungsstand; sie ist kein generischer Datenkatalog. Hier: 7h18, üblicher Schlafbereich 6h15–6h42, Ruhepuls 54 gegen 56, HRV 48 gegen 40 und Erholung 74. Der Erholungswert verweist seinerseits auf B01/B44 und seine vollständige Methode. Ein später neu berechneter Wert ersetzt nicht rückwirkend den Antwortbeleg. Charts behalten echte Lücken und dieselbe Definition wie die Fachansicht. B46-Stil und B47-bestätigte Erinnerung verändern weder Tatsachen noch Einwilligungs-/Schreibgrenzen.

### Einrichtung und Verarbeitung

Der eigene Modellserver im Heimnetz und ein externer Anbieter sind getrennte Wege. „Im Heimnetz“ bedeutet ausdrücklich nicht „auf diesem iPhone“. Bestehende `CoachConfig`-Verbindung, Modell und sicherer Schlüsselspeicher weiterverwenden; gesperrter/nicht lesbarer Schlüssel bleibt ein anderer Zustand als nicht eingerichtet. Verbindungsprüfung verwendet neutrale synthetische Inhalte, keine Gesundheitsdaten. Serveradresse, Modell, erfolgreicher Test und ausdrücklich gewählte Verwendung bilden einen Commit. Erreichbarkeit, Textantwort, unterstützte Datenwerkzeuge und Bildfähigkeit separat prüfen. Das Netzwerkbeispiel unterstützt keine Fotos; Kamera/Fotoeintrag darf deshalb weiterhin manuell verwendet werden.

Cloud-Einrichtung benötigt vor der ersten Datenanfrage eine gespeicherte Freigabe pro Anbieter/Modellkonfiguration: Schlaf/Messwerte, Training, Journal/Ernährung, bewusst ausgewählte Fotos. Die gezeigte Variante erlaubt nur die ersten beiden Gruppen. Eingegebene Nachrichten und gesendeter Gesprächsverlauf werden als Übermittlung gesondert benannt. Lesewerkzeuge müssen diese Freigabe serverunabhängig erzwingen, einschließlich abgeleiteter SQL-Abfragen, Anhänge und Kontextgedächtnis. Nicht freigegebene Daten werden nicht erst gelesen und dann aus der Anzeige ausgeblendet. Erweiterung des Umfangs erfordert eine ausdrückliche Wahl; Anbieterwechsel sendet keinen alten Verlauf automatisch. Bestehende Übermittlungen können lokal nicht zurückgeholt werden.

Bei verweigertem iOS-Netzwerkzugriff führt „Verbindung prüfen“ zu Erklärung und System-Einstellungen; bei Serverfehler zu erneutem neutralem Test; bei ungültigem Schlüssel zum Zugangsfeld; bei fehlender Modellfähigkeit zur Modellauswahl. Keiner dieser Fälle aktiviert still einen anderen Anbieter. Modellzugang kann Kosten des gewählten Anbieters verursachen; die übrige App bleibt ohne Coach nutzbar. Quellenansicht benennt den tatsächlichen Verarbeitungsort und Datenumfang. Kein echtes Modell verbunden, kein Schlüssel gespeichert und keine Gesundheitsdaten übertragen.

**Prüfung:** Alle sechs Quellen; eigener Einstieg, Arbeitszustand, kurze Antwort, Quellen, Verbindungsfehler, fehlender Messwert, Änderungsvorschlag, Speicherbeleg und Einrichtung visuell angesehen. Lesbare 17/24-Prosa, kontrollierte Kartendichte, 44-pt-Aktionen, deaktiviertes leeres Senden und feste Eingabe geprüft. Neue Lucide-Originale `arrow-up`, `message-circle`, `copy` samt bestehender Lizenz ergänzt (81 SVGs). App-Code unverändert; echte Anfrage-/Abbruch-/Schreibprüfung folgt erst in der Implementierung.

## B61 · Datenpflege ohne unsichtbaren Verlust

**Aus Flow 060.** Zwei Quellen zeigen „Clear cache & reload all data“ und die zurückgekehrte Home-Ansicht. OpenBand trennt diese Sammelaktion: Anzeige neu laden, Werte neu auswerten und weitere Quelldaten übernehmen. Die ersten beiden verwenden den lokalen Bestand; nur die dritte Aktion führt zu B53/Band/Dateiimport. Keine davon löscht Originaldaten, eigene Eingaben oder Korrekturen.

Anzeige-Neuladen invalidiert ausschließlich rekonstruierbare Ansichts-/Diagrammcaches, liest den zuletzt gespeicherten Bestand erneut und bestätigt „Anzeige aktualisiert“. Laufende Übertragung, Eingabeentwürfe, Datenbank, Ergebnisse, Quellenarchiv und Sitzungen bleiben erhalten. Ein Cache darf nur dann gelöscht werden, wenn seine Herkunft aus beständigen Daten und seine vollständige Rekonstruktion definiert sind. Ein generisches „alles löschen und herunterladen“ passt nicht zur lokal gespeicherten Produktbasis.

Vor einer Neuauswertung Zeitraum und erforderliche Quellen prüfen; Nächte umfassen den vorherigen Abend, Referenzmetriken die benötigten historischen Eingänge. Ein vorhandener Ergebnisdatensatz beweist nicht, dass seine Originale noch vorhanden sind. Das Beispiel für den 1. September besitzt historische Ergebnisse, aber keine wiederverwendbaren Originale; die neue Berechnung bleibt gesperrt. Der bestehende Stand bleibt sichtbar, und nur eine tatsächlich geeignete Sicherung kann weitere Originale bereitstellen. Es wird kein vollständiger Bestand vom Band oder Health versprochen.

`AppState.reanalyzeAll()` führt derzeit einen erzwungenen Durchlauf aus, meldet Tagesfortschritt, liefert bei bereits laufender Analyse oder Fehler aber ebenfalls 0 zurück. Die UI meldet anschließend die Anzahl ohne entsprechende Unterscheidung. Neuer Vertrag muss Vorprüfung, job-ID, betroffene Tage/Quellen-/Methodenversion, laufend/pausiert/fehlende Quelle/Fehler/abgeschlossen und tatsächliche Commit-Belege unterscheiden. Jede Tagesauswertung wird erst atomar veröffentlicht, wenn sie vollständig bereitsteht. Ein bisheriger Wert darf als vorheriger Stand weiter sichtbar sein. Bei Neustart Arbeit fortsetzen/erneut ausführen, ohne doppelte Ergebnisse und ohne bisherige Werte vorzeitig zu löschen.

Die Nachberechnung ist kein Bluetooth-Sync: Im Abschluss bleibt das Band verbunden, seine neueste Aufzeichnung aber weiterhin 07:42. Beispiel 15. September wird erneut ausgewertet und gespeichert, 7h18 und Erholung 74 bleiben unverändert. „Abgeschlossen“ bestätigt hier einen wirklich gespeicherten Tag, nicht eine bloß gestartete Schleife. Bei Unterbrechung 0/1 erneuert, alte Werte erhalten. Änderungen an der Methode oder an Korrekturen werden mit alter/neuer Version nachvollziehbar; bei zwischenzeitlich neuer Quelle nicht einen veralteten Snapshot als neuesten Stand publizieren.

**Prüfung:** Beide Quellen und eigene Datenpflege, Vorprüfung, Abschluss, fehlende Originale, Unterbrechung sowie Anzeige-Beleg angesehen. Aktueller Reanalyse-/Fehlervertrag und Quellenabhängigkeit direkt gelesen. Keine Daten neu berechnet oder gelöscht.

## B62 · Optionale Glukosequelle mit eigenem Datenstand

**Aus Flow 061.** Acht Quellen zeigen Ernährungseinstieg, Sensorwahl, Health/Hersteller-Verbindung und Hersteller-Login. OpenBand verwendet als konkreten ersten Weg Apple Health. Es gibt bereits `ImportedMeasurementImporter` mit `BLOOD_GLUCOSE` und quellengestützten importierten Messungen. Die Quelle wird im Werte-Katalog angeboten und bleibt optional. Keine unbewiesene Liste direkt unterstützter Sensoren, kein Login mit Herstellerpasswort und keine pauschale Verzögerung aus dem Vorbild. Direkte Herstellerwege benötigen separat belegte API-/Lizenz-/Regionsverfügbarkeit, sichere Autorisierung und eigene Vertragsprüfung.

[Apples Glukosetyp](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/bloodglucose) enthält diskrete Werte; mg/dL und mmol/L sind zu berücksichtigen. [HealthKit-Lesezugriff](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data) kann pro Typ angefragt und zeitlich begrenzt sein. Ein leeres Leseergebnis erlaubt keine Aussage, ob die Person den Zugriff verweigert hat. Daher heißt der eigene Leerzustand „Noch keine Werte lesbar“, mit Prüfung von Quelle/Freigabe und erneutem Lesen. Eine positiv bekannte zeitliche Begrenzung wird angezeigt und bei der Abfrage berücksichtigt; SDK-/OS-Verfügbarkeit der betreffenden API muss bei der Umsetzung geprüft werden. Das gilt zusätzlich für das zweijährige Wunschfenster aus B53.

Bestehender Import fragt Blutdruck, Glukose und Körpertemperatur zusammen an, liest auf Apple ein Jahr und gibt bei leerem Bestand, Sperre und Fehler jeweils 0 zurück. Für den neuen Weg den angefragten Typ einschränken, gestellte Anfrage von tatsächlich gelesenen Daten trennen und typisierte Lese-/Speicherbelege einführen. Quell-ID/Revision, originale Einheit, Messzeit/Zeitzone, Importzeit, letzte Abfrage und Menge gespeicherter Werte erhalten. Quelle unbekannt bleibt unbekannt; ein Platzhalter ist kein nachgewiesenes Gerät. Nicht aus einem Appnamen auf ein zugelassenes Sensorgerät schließen.

Die derzeitige `rowsFrom`-Prüfung nimmt für Plausibilitätsgrenzen die kanonische Plug-in-Einheit an und speichert zugleich `p.unit.name`. Vor Implementierung an der tatsächlichen Grenze verifizieren und nötigenfalls explizit normalisieren: niemals mmol/L-Zahlen gegen mg/dL-Grenzen prüfen. Nicht endliche Werte und Einheitenfehler mit lesbarem Importbefund behandeln. Bestehende UUID-Deduplizierung behalten; Änderungen und Löschungen der Quelle müssen nachvollziehbar abgeglichen werden. Anzeigeeinheit kommt aus B56, Rohwert und Quelleneinheit bleiben erhalten.

Synthetische separate Fixture `assets/fixtures/glucose-source.json`: elf Messwerte zwischen 07:00 und 08:00, zwei fehlende Positionen, letzter Wert 5,2 mmol/l um 08:00, Import 09:40, letzte Abfrage 09:41. Keine Verbindung über die Lücke von 07:20 bis zum nächsten Wert 07:35. „Elf Werte“ ist eine Datensatzanzahl, keine bestätigte lückenlose Sensorabdeckung. Die Werte stehen neben WHOOP-Daten und werden nicht aus ihnen abgeleitet. Keine automatische Ernährungsnote oder behauptete Mahlzeitenursache aus einer solchen kurzen Folge; keine Dosierungsempfehlung und kein Live-Sensorstatus.

Gezeichnete Zustände: optionale Einführung → typbezogene Zugriffsanfrage → Lesen → gespeicherter Verlauf; leeres Ergebnis; Health vorübergehend nicht lesbar mit erhaltenem letzten Wert; Quellen-/Zeitdetails und Erklärung/Einheit. Die Herkunftsseite trennt letzte Messung, Import und Abfrage. „Automatisch nachlesen an“ ist die eigene Einstellung, kein Beweis einer Health-Freigabe oder Herstellerverbindung. Hintergrund-Abfragen sind best effort; UI-Alter läuft anhand der Messzeit weiter. Vorhandene Werte bleiben bei Sperre/Fehler erhalten und werden nicht als frisch umetikettiert. Trennen wird in Flow 071 separat überprüft.

**Prüfung:** Alle acht Quellen und eigene Einführungs-, Anfrage-, Lese-, Leer-, Verlaufs-, Unterbrechungs-, Quellen- und Erklärungszustände angesehen. Diagramm mit echter Lücke, elf Punkten und getrennter Frische geprüft. Aktuellen Importcode und Apple-Primärdokumentation gelesen. Keine Health-Abfrage oder Sensorverbindung ausgeführt; die Glukosefixture ist eine eigenständige synthetische Erweiterung.

## B63 · Apple Health verwalten: Lesen und Schreiben getrennt

**Aus Flow 062.** Drei Quellen zeigen Wahl von Health als Glukoseweg, fehlgeschlagenes Lesen und die Verwaltung einer Verbindung. OpenBand übernimmt eine eigene Verwaltungsseite, verwendet aber die tatsächlichen Quellen-/Zeitangaben aus B62 statt einer festen Herstellerverzögerung. Nach einem leeren Ergebnis kann die gewünschte Übernahme eingeschaltet sein, ohne dass Datenzugriff nachgewiesen ist. „Freigabe prüfen“, erneutes Lesen und Beenden der Übernahme haben getrennte Ziele.

Der überarbeitete Health-Hub führt zu Trainingshistorie B53, Körperwerten B43, Glukose B62 und weiteren Messungen. Profilbefüllung aus Health bleibt ein prüfbarer Profilentwurf, keine unsichtbare Überschreibung einer neueren Angabe. Der bisherige isolierte Ruhepuls-Startwert wird nicht als fertige nächtliche WHOOP-Basis vermarktet. Historische fremde Messungen behalten Quelle und Methode; SDNN und RMSSD werden nicht in eine gemeinsame Basis gemischt. Die bestehende `PhoneImport`-Ansicht beschreibt ihren RHR-Seed selbst als derzeit nicht ausgewertete Vergleichsbasis; neue Produktflächen sollen keinen Nutzen behaupten, der daraus noch nicht entsteht.

Eine separate Aktion wählt Daten für die Weitergabe an Health. Die gezeichnete Auswahl umfasst Schlaf/Phasen und Trainings; Puls/Ruhepuls/Atemfrequenz sowie Schritte bleiben aus. Nach dem nativen Dialog können Schreibrechte teilweise erteilt sein: Beispielsbild Schlaf erlaubt, Trainings nicht erlaubt, noch keine Ergebnisse tatsächlich exportiert. Schreibfreigabe ist kein Übertragungsbeleg. Standard ist nur neue Ergebnisse ab dem bestätigten Aktivierungszeitpunkt; historische Weitergabe benötigt eine eigene Auswahl mit Umfang und Duplikatprüfung. Lesen aktiviert niemals Schreiben.

[Apples Autorisierung](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data) trennt angefragte Datentypen und Zugriffsrichtungen; [authorizationStatus](https://developer.apple.com/documentation/healthkit/hkhealthstore/authorizationstatus(for:)) darf nicht als Lesestatus missverstanden werden. Die nativen Dialoge werden vom jeweiligen iOS erzeugt; App-Vorschau und Rückkehrzustände sind die eigenen Paper-Flächen. Eine zeitliche Lesebeschränkung muss zusätzlich sichtbar berücksichtigt werden, soweit API/OS sie positiv identifizieren können. Kein nachgebauter Appdialog darf einen tatsächlich angezeigten iOS-Freigabedialog ersetzen.

Bestehende Health-Import-/Exportmodule wiederverwenden und um typisierte gewünschte Auswahl, nachweisbaren Schreibstatus, tatsächlichen Exportauftrag und quittierte Datensätze erweitern. Datentypen strikt abbilden: echte SDNN-Werte dürfen als SDNN exportiert werden, RMSSD nicht unter derselben Bezeichnung; relative Temperaturabweichung ist keine absolute Körpertemperatur. Unbereite Metriken und fehlende Zeitabschnitte nicht als Nullwerte exportieren. Eigene Writes anhand stabiler Herkunft/IDs wiedererkennen; importierte Fremddaten nicht erneut als OpenBand-Messung zurückschreiben. Wiederholen und Korrektur/Neuberechnung müssen eigene vorherige Exporte gezielt aktualisieren und fremde Daten erhalten. Bestehende Export-Ledger-/Epoch-/Löschlogik vor der UI-Anbindung prüfen.

Neue Einstellungen benötigen je Typ aktiv ab, Pause, ausstehend, gespeichert, verweigert und Fehler; tatsächlicher Exportfortschritt bleibt von der nächtlichen Berechnung und Bluetooth-Speicherung unabhängig. Ein externer Widerruf stoppt weitere Writes, entfernt aber keine bereits exportierten Health-Daten. Genau diese Unterschiede gehören in Quellen-/Datenstandansicht, nicht in einen einzigen grünen „verbunden“-Schalter.

**Prüfung:** Alle drei Quellen; Glukoseverwaltung, überarbeiteter Health-Hub, Schreibauswahl und teilweise Schreibfreigabe visuell geprüft. Aktuelle Importpfade und Exporttyp-Liste gelesen; Apple-Primärquelle herangezogen. Kein nativer Berechtigungsdialog und keine Health-Schreibaktion ausgeführt.

## B64 · Coach-Antwort kopieren

**Aus Flow 063.** Zwei Quellen zeigen eine kleine Kopieraktion unter der Antwort und einen bestätigenden Hinweis. OpenBand hält die 44-pt-Aktion am Antwortblock, ersetzt nach erfolgreichem Schreiben das Symbol durch einen Haken und meldet „Antwort kopiert“. Kein zusätzlicher Bestätigungsdialog. Auswahl einzelner Textstellen bleibt über die native Textauswahl möglich.

Kopiert werden lesbarer Antworttext, dargestellte Kennzahlen, Bezugsdatum und tatsächlicher Datenstand. Keine unsichtbaren Werkzeugabfragen, Zugangsdaten, fremden Gesprächsteile oder behaupteten öffentlichen Quellenlinks. Diagramme erhalten eine beschriftete Textzusammenfassung; Werte nicht aus Pixeln extrahieren. Synthetische Beispiele behalten ihre Kennzeichnung. Zwischenablage erst auf bewusste Aktion beschreiben; Erfolg erst nach erfolgreichem Plattformaufruf, bei Fehler Aktion erhalten und Wiederholen anbieten. Wiederholtes Kopieren ändert keine Gesundheitsdaten. Bestehende Coach-Textdarstellung benötigt Textauswahl und zugängliche Aktionen; derzeit ist kein entsprechender Clipboard-Aufruf im Coach-Pfad vorhanden.

**Prüfung:** Beide Quellen und eigener Kopierbeleg angesehen. Antwort bleibt lesbar und Eingabe erreichbar. Keine echte Zwischenablage beschrieben.

## B65 · Eine Übungsdefinition als Ausgangspunkt

**Aus Flow 064.** Vier Quellen zeigen die optionale Übernahme einer vorhandenen Übung in ein eigenes Formular. OpenBand bietet eine Einzelauswahl mit Suche, übernommene Felder im editierbaren Entwurf und einen getrennten Speicherbeleg. Beispiel „Curl · neutraler Griff“ übernimmt Kurzhantelpaar, Wiederholungen je Seite und Gewicht je Hantel. Das Hinzufügen zur Trainingsvorlage ist eine zweite Handlung.

Der sichtbare `ExerciseDef`-Katalog enthält Schlüssel, Label, Muskelanteile und Gewichtsschritt. Die bereits vorhandene Tabelle `exercise_def` enthält zudem Gerät, unilateral und custom. Diesen vorhandenen Speicher mit B26/B36 zu versionierten Definitionen mit stabiler neuer ID und `copiedFrom` weiterentwickeln. Kopieren übernimmt Metadaten, keine absolvierten Sätze, Bestleistungen, Verlauf, laufenden Timer oder geplanten Gewichte. Eigene Muskelgruppen sind Filterangaben, keine gemessene Belastung. Die Ausgangsdefinition bleibt unverändert, spätere Katalogänderungen überschreiben die Kopie nicht. Abbruch verwirft nur den Entwurf; Validierungs-/Speicherfehler erhalten Felder. Nach Doppeltippen/Neustart genau eine eigene Definition, Rückkehr zum ursprünglichen Auswahlkontext ohne automatischen Trainings-Commit. Identische sichtbare Namen dürfen durch Herkunft unterschieden werden; neue ID nicht aus Namen ableiten.

**Prüfung:** Alle vier Quellen, eigener Picker, bearbeitbare Kopie und gespeicherte Definition angesehen. Katalogmodell gelesen. Keine Übung im Appbestand angelegt.

## B66 · Supersätze und Zirkel als geplante Reihenfolge

**Aus Flow 065.** Fünf Quellen zeigen das Übungsmenü, Mehrfachauswahl und verbundene Übungskarten. OpenBand gruppiert A1/A2 in einer gemeinsamen Karte mit ausgeschriebener Reihenfolge und Rundenpause. Das vermeidet die Verwechslung von Satzpause und Gruppenpause. Beispiel Ganzkörper A: Bankdrücken 3 × 8 × 40 kg und Rudern 3 × 10 × 30 kg in drei Runden, danach 90 Sekunden Pause; Kniebeuge und Plank bleiben einzeln. Zwölf geplante Sätze bleiben zwölf, durch Gruppieren entsteht kein absolviertes Volumen.

Vorlagen benötigen stabile Gruppen-ID, geordnete Mitglieder, Round-/Set-Zuordnung und explizite Ruhephase. Ab zwei Mitgliedern aktiv, ab drei Bezeichnung Zirkel. Ungleiche Satzzahlen müssen vor Bestätigung sichtbar bleiben: zusätzliche Sätze einzeln am Ende oder bewusst angeglichene Planung, kein stilles Löschen. Übungen dürfen nicht gleichzeitig mehreren Gruppen angehören. Auflösen erhält Übungen, Satzvorgaben und Reihenfolge; Entfernen auf ein Mitglied löst die Gruppe auf. Aufwärmsätze B49 bleiben außerhalb der Arbeitsrunden, sofern nicht ausdrücklich gruppiert. Jede Veränderung gilt zuerst dem Vorlagenentwurf, Speichern veröffentlicht eine neue Version.

`strength_set` besitzt heute Sequenz, Übung, Satzindex, Wiederholungen, Gewicht, Halte-/Pausenzeit und Zeitstempel, aber keine Gruppen-/Runden-ID. Bestehende `exercise_def`-Tabelle enthält bereits Gerät, unilateral und custom; B65 soll diese weiterentwickeln, keinen zweiten Katalogspeicher daneben anlegen. Laufendes Training benötigt eine eingefrorene Vorlagenversion sowie tatsächliche Satz-ID, Runde und Übungsreihenfolge. Speichern/Unterbrechen/Neustart darf keine geplanten Sätze als ausgeführt markieren. Resttimer anhand gespeicherter Zeitpunkte wiederherstellen; Auslassen/Zurückgehen verändert nur offene Planung. Analyse zählt jeden tatsächlich abgeschlossenen Satz einmal. Historische Gruppierung ist Darstellung, keine neue physiologische Belastungsmetrik.

**Prüfung:** Alle fünf Quellen und eigene Auswahl/gruppierte Vorlage angesehen; aktuelle Satz- und Übungstabellen gelesen. Die Live-Navigation durch Runden wird mit den späteren Trainingsflows zusammen geprüft.

## B67 · Anpassungen finden, ohne zweite Einstellungen zu erzeugen

**Aus Flow 066.** Zwei Quellen zeigen den Einstellungen-Einstieg und den umfangreichen Anpassungs-Hub. OpenBand bündelt hier Übersichtskarten, eigene Ziele, Einheiten, Berechnungen, Journal, Training und Coach. Darstellung bleibt eine direkte globale Einstellung. Quellen, Übernahmezeitraum, Sicherungen und Datenpflege bleiben im Datenbereich. Kontextaktionen im jeweiligen Bereich führen zum selben Editor mit Rücksprung, nicht zu einer zweiten unabhängigen Einstellung.

Die bereits entworfenen B30/B39/B45/B48/B54–B60 bilden die Zielseiten. Einstellungen brauchen einen gemeinsamen typisierten Bestand, Versions-/Gültigkeitsdatum bei Methoden und Zielen, und getrennten Entwurf/Commit. Änderung einer Einheit ist sofortige Darstellung; Änderung einer Berechnung kann ausdrücklich eine neue Auswertung erfordern. Nicht alle Einstellungen in einen ungeprüften Map-Reset zusammenfassen. Der gemeinsame ausgewählte Tag B54 bleibt beim Öffnen/Schließen erhalten. Suche kann diese stabilen Routen später auffinden, ohne neue Inhaltskopien anzulegen.

**Prüfung:** Beide Quellen und eigener Hub angesehen; bestehender Einstellungen-Einstieg auf „Anpassen“ aktualisiert. Keine App-Einstellung verändert.

## B68 · Coach-Gespräch gezielt löschen

**Aus Flow 067.** Drei Quellen zeigen Verlauf, Gesprächsmenü und reduzierte Liste. OpenBand hat eine sichtbare 44-pt-Menüaktion je Gespräch mit Umbenennen/Löschen. Der Löschschritt nennt das konkrete Gespräch und den lokalen Umfang; nach bestätigter Speicherung kehrt die Liste ohne diesen Eintrag zurück. Gemerkte Angaben B47 und bestätigte Journal-Schreibaktionen B60 sind eigene Daten und bleiben bestehen. Ein Link führt anschließend zu den gemerkten Angaben. Extern bereits gesendete Daten werden nicht als mitgelöscht dargestellt.

`CoachEngine.deleteSession` löscht Datei und Index getrennt und verschluckt Fehler; `persist` und Indexpflege tun das ebenso. Für diesen Ablauf bestätigtes Ergebnis und atomare bzw. wiederaufnehmbare lokale Änderung einführen. Laufende Antwort vor Löschung dieses Gesprächs stoppen; Generation/Session-ID verhindert spätes Wiederanlegen durch einen alten Request. Bestätigte Einträge nicht aus dem Gespräch mitlöschen, offene Aktionsvorschläge dagegen nach Löschung nicht mehr ausführen. Bei Dateifehler bleibt das Gespräch mit erneutem Versuch sichtbar; fehlende Datei plus vorhandener Index wird gezielt bereinigt. Keine Erfolgsmeldung bei unbestätigtem Löschen.

Leere Liste führt zu „Neues Gespräch“, kein Zwang zur Einrichtung eines anderen Anbieters. Bestehende Begrenzung auf 30 Sessions verwirft heute alte Dateien automatisch; diese versteckte Aufbewahrungspolitik passt nicht zu einem verlässlichen Verlauf. Dauerhafte Aufbewahrung oder eine ausdrücklich sichtbare Nutzerwahl festlegen, Speicherbedarf anzeigen, keine stille Löschung unter einem neuen Design. Gesprächstitel lokal editierbar; historische Quellenstände bleiben erhalten.

**Prüfung:** Alle drei Quellen, eigene Verlaufsliste, Bestätigung und reduzierter Verlauf angesehen; Persistenz-/Löschcode gelesen. Keine echten Gespräche gelöscht.

## B69 · Eigene Übungen ausblenden, Trainings erhalten

**Aus Flow 068.** Fünf Quellen führen von Bibliothek über Übungsdetails und Bearbeitung zur Löschbestätigung. Die Quelle verspricht, aufgezeichnete Daten zu behalten. OpenBand nennt die entsprechende reversible Handlung präziser „Archivieren“ und zeigt anschließend die archivierte Definition mit „Wieder einblenden“. Dafür ist kein zusätzlicher Bestätigungsdialog nötig. Die Wahl bleibt im Übungsdetail auffindbar; bestehende Bibliothek erhält den Filter „Archiviert“.

`exercise_def` um Archivierungszeit und Definitionversion ergänzen. Stabile Referenzen aus Vorlagen und abgeschlossenen Sätzen behalten ihre lesbare Definition. Neue Auswahlen blenden archivierte Einträge standardmäßig aus; bestehende Vorlagen zeigen das Archivkennzeichen und erlauben bewusstes Weiterverwenden oder Ersetzen. Archivieren ist kein Löschen eines Trainings und kein Zusammenführen ähnlich benannter Übungen. Wiederherstellung ist idempotent. Aktives Training verwendet seinen Snapshot und wird nicht während eines Satzes verändert. Bei Speicherfehler bleibt der bisherige Status mit erneutem Versuch, kein verschwindender Listeneintrag. Endgültiges Entfernen einzelner historischer Gesundheitsdaten ist ein anderer, ausdrücklich benannter Datenvorgang.

**Prüfung:** Alle fünf Quellen und eigener Verwaltungs-/Archivzustand angesehen. Keine Definition oder Trainingshistorie gelöscht.

## B70 · Lokale Daten entfernen statt erfundenem Kontolöschen

**Aus Flow 069.** Drei Quellen zeigen Kontodetails, endgültige Kontolöschung und Rückkehr zum Einstieg. OpenBand hat kein notwendiges Konto. Der eigene Weg heißt „Lokale Daten entfernen“ und nennt den konkreten Umfang: Datenbank, Originale innerhalb des App-Speichers, Auswertungen, eigene Einträge, Fotos, Gesprächsdateien, Profil, Einstellungen, Modellzugänge und Kopplungsinformationen. Apple Health, extern gespeicherte Sicherungen, private Laborarchive außerhalb der App und bereits übermittelte Anbieterdaten bleiben gesondert. Kein Firmware-Reset, kein Force-Trim und keine behauptete Cloud-Kontolöschung.

Umfang prüfen → optional geeignete Sicherung erstellen → konkrete irreversible Aktion bestätigen → bestätigtes Ergebnis oder verbleibender Fehler. Die Rückkehr zum Einstieg ist erst nach vollständigem Abschluss zulässig. Der gezeigte Fehlerfall hat die Datenbank bereits entfernt, aber einen nicht erreichbaren Schlüsselspeicher; App bleibt für neue Übertragungen gesperrt, Entsperren und Abschließen sind der klare nächste Schritt. Keine Darstellung als vollständig zurückgesetzt und keine sichere Wiederherstellbarkeit vom Band versprechen. Externe Sicherung vor der Löschung muss abgeschlossen und auffindbar sein, nicht nur ein gestarteter Share-Dialog.

Aktuell stoppt `AppState.resetAllData` Telemetrie/Health-Uploader, leert alle SQLite-Nutzertabellen, entfernt Mitteilungen/Widget-Kopie, Schlüssel und Preferences und trennt zuletzt das Band. Schlüssel-/Preferencefehler werden lediglich geloggt. Zusätzlich alle aktiven BLE-/Import-/Analyse-/Coach-/Backup-Schreiber zunächst kontrolliert stoppen und durch eine persistente Reset-Generation am Wiederanlegen hindern. Dateien außerhalb SQLite, Bildcache, Gesprächsindex und lokale Quellenarchive ausdrücklich erfassen. Ein App-Neustart setzt den Löschvorgang fort, statt noch vorhandene Reste wieder als Profil zu laden. Teilergebnis pro Speicherbereich quittieren; Schlüssel löschen vor erfolgreichem Abschluss nachweisen. Bestehende vollständige Tabelleniteration beibehalten, keine vergessensanfällige kurze Löschliste.

Health-Export-Ledger und App-eigene Health-Daten sind getrennt. Die hier gezeichnete Aktion entfernt Health-Daten ausdrücklich nicht; vorhandene eigenen Exporte müssen bei späterem Wiederimport/Wiederherstellen anhand dauerhafter Herkunft deduplizierbar bleiben. Nach Löschen kein automatisches Neuimportieren, Neu-Pairing oder Senden. Neuer Einstieg und Wiederherstellung sind bewusste nächste Handlungen. Lab-Daten und Repository-Fixtures gehören nicht zum App-Reset.

**Prüfung:** Drei Quellen; eigene Umfangsseite, Bestätigung, unvollständiger Abschluss und Erfolg angesehen. Aktuelle Reset-Reihenfolge und Tabellenlöschung direkt gelesen. Keine Daten oder Zugänge tatsächlich entfernt.

## B71 · Einen Alkoholeintrag entfernen

**Aus Flow 070.** Drei Quellen zeigen Tagesliste, Eintragsdetail und leeren Tag mit expliziter Kein-Alkohol-Aktion. OpenBand übernimmt die wichtige Unterscheidung: Löschen des letzten Eintrags ergibt „Noch keine Angabe“, nicht 0 g. „Keinen Alkohol bestätigen“ ist eine eigene bewusste Tagesangabe. Der entfernte Eintrag lässt sich unmittelbar rückgängig machen; Schnellvorschlag B51 bleibt bestehen.

Separater synthetischer Ablauf: 14. September, 20:15, Wein 150 ml bei 12 Vol.-%, rund 14 g Alkohol. Dieser Eintrag erweitert nur die Löschvariante, nicht die Basisfixture des 15. September. Konkrete Eintrags-ID/Revision löschen, keine Tages-Summe als Stellvertreter. Vorhandenes Journalfeld `alcohol_units` allein ersetzt keine Liste mit Menge, Volumenprozent, Zeitpunkt und Herkunft. Eine einheitliche Alkoholmenge braucht definierte Umrechnung und Herkunft; Anzeige nicht zwischen undokumentierten „Drinks“ und Gramm wechseln.

Nach Commit Tagesaggregation, Journalstatus und spätere Zusammenhänge invalidieren. Unbekannt/ausdrücklich kein Alkohol/positive Einträge getrennt modellieren. Widersprüchliche neue Einträge nach bestätigtem Nulltag heben die Nullangabe nachvollziehbar auf. Rückgängig stellt denselben Eintrag zum ursprünglichen Tag und Zeitpunkt wieder her; parallel bearbeitete Einträge nicht überschreiben, doppelte Wiederherstellung verhindern. Löschfehler hält den Eintrag sichtbar. Bei bereits für eine Erkenntnis verwendeter Datenrevision deren Aktualisierung kenntlich machen, keine unveränderte alte Aussage als aktuell belassen.

**Prüfung:** Alle drei Quellen, eigener Eintragsdetail- und Leerzustand angesehen. Kein echter Konsumeintrag verändert.

## B72 · Glukoseübernahme ausschalten

**Aus Flow 071.** Drei Quellen zeigen CGM-Verwaltung und Rückkehr zum Verbindungsangebot nach Trennen. Beim eigenen Health-Weg wird keine physische Sensorverbindung behauptet. „Übernahme beenden“ schaltet neue Glukoseabfragen in OpenBand aus, erhält die elf gespeicherten Werte aus B62 und nennt weiterhin die letzte echte Messung um 08:00. „Wieder aktivieren“ führt über Quellen-/Zugriffsprüfung zurück, ohne Duplikate nachzuladen.

Eigene Aktivierungsabsicht, laufender Abfrageauftrag und Systemfreigabe sind getrennte Zustände. Abschalten persistieren, noch laufende Ergebnisse anhand einer Job-/Konfigurationsgeneration nicht nachträglich als frisch übernehmen. Bereits dauerhaft gespeicherte Ergebnisse erhalten; offene Cursor nur nach bestätigtem Commit fortschreiben. Ein gezielter Stopp betrifft Glukose, nicht Trainings-, Körperwert- oder andere Health-Importe. HealthKit-Freigaben können im System geändert werden und werden durch diese Appwahl nicht als widerrufen dargestellt. Frühere Daten löschen ist eine separate Auswahl mit konkretem Zeitraum/Quelle und verbleibender Health-Quelle; Wiederaktivierung darf eine bewusste Löschung nicht sofort ungesehen rückgängig machen.

**Prüfung:** Alle drei Quellen sowie abgeschalteter eigener Zustand angesehen; Verwaltungs-Einstieg X4T-0 aus B63 weiterverwendet. Keine Health-Einstellung tatsächlich geändert.

## B73 · Trainingsvorlage duplizieren

**Aus Flow 072.** Drei Quellen zeigen Vorlagenliste, Kontextmenü und zweite Vorlage mit Kopie-Suffix. OpenBand erzeugt eine sofort gespeicherte eigenständige Kopie und bietet danach Bearbeiten an. Original und Kopie bleiben in der Liste unterscheidbar; kein Training startet und kein Satz wird ausgeführt. Beispiel kopiert die Grundvorlage Ganzkörper A mit vier Übungen und zwölf geplanten Sätzen, nicht die getrennte Supersatz-Variante B66.

Vorlagen-ID, Gruppen-IDs, geplante Satz-IDs und Draft-ID neu vergeben; Definitionen aus dem Übungskatalog dürfen referenziert bleiben. Kopierte Reihenfolge, Lastbasis, Satztypen, Zeitvorgaben, Pausen und Notizen als Snapshot einer Quellversion erhalten. Duplizieren nie auf eine flache Liste von Anzeigenamen reduzieren. Eine stabile Auftrags-ID verhindert zwei Kopien nach Doppeltippen/Retry, ein bewusst zweiter Auftrag darf eine weitere Kopie erzeugen. Fehlgeschlagene Speicherung belässt die Originalliste und bietet erneut an; „Kopie erstellt“ erst nach Commit. Namen wie Kopie 2 unterscheiden sichtbare Varianten, sind aber keine Identität. Archivieren einer Vorlage ist getrennt vom Archivieren ihrer Übungen und erhält abgeschlossene Session-Snapshots.

**Prüfung:** Alle drei Quellen und eigene Vorlagenaktionen/Kopienliste angesehen. Kein Trainingsplan in der App gespeichert.

## B74 · Übersicht anordnen und zurücksetzen

**Aus Flow 073.** Drei Quellen zeigen den langen Home-Verlauf, Bearbeitungsmodus mit Karten und Reset. B25 deckt Hinzufügen und Speicherung bereits ab. Die vorhandenen OpenBand-Editoren wurden um eindeutige Kartenmenüs ergänzt: Verschieben per Drag sowie alternativ eine Position nach oben/unten, Ausblenden und Rückkehr zum Entwurf. Beispiel verschiebt Journal direkt vor Stress. Tagesdatum, Verbindung, drei Hauptwerte und kurzer Einblick bleiben der feste Kopf; umfangreiche Bereiche darunter scrollen weiter.

Geordnete stabile IDs statt Index als Kartenidentität speichern. Zugängliche Aktionen müssen gleichwertig zu Drag funktionieren und die neue Position ankündigen; am ersten/letzten beweglichen Platz jeweilige Richtung deaktivieren. Ausblenden löscht keine Daten. Standard wiederherstellen ist eine Änderung im aktuellen Entwurf und wird erst durch Speichern gültig. Zurück/Abbrechen mit Änderungen verwendet den gemeinsamen Verwerfen-Dialog; Speicherfehler erhält Reihenfolge. Ein Konfigurationsschema migriert alte bekannte Karten ohne stilles Zurücksetzen. Fehlende Quellen verändern die angeordnete Karte in einen ehrlichen Datenzustand und entfernen sie nicht unerwartet aus dem Layout. Dieselbe Reihenfolge gilt für Light/Dark und größere Schrift, wobei die Kartengröße mitwächst.

**Prüfung:** Alle drei Quellen, bestehender Editor, neues Kartenmenü und verschobener Entwurf angesehen. 44-pt-Rückweg korrigiert; Hinzufügen-Variante auf dieselben Menüaktionen aktualisiert. Keine App-Konfiguration geändert.

## B75 · Lebensmittelsymbole ohne fremde Bildrechte

**Aus Flow 074.** Vier Quellen zeigen Lebensmittelbearbeitung, Kategorien mit Bildsymbolen und ein geändertes Symbol. OpenBand verwendet beschriftete Lucide-Symbole in derselben lizenzierten Bibliothek wie die Navigation; keine aus Bevel kopierten Lebensmittelbilder oder proprietären Emoji-Bitmaps. Milchprodukte, Getreide, Obst, Gemüse, Ei, Fisch, Fleisch, Gericht und Allgemein sind direkt auswählbar. Kleine Fotos bleiben der separate eigene Foto-Weg B33.

Für ein bereits gespeichertes eigenes Lebensmittel speichert „Symbol speichern“ nur den Symbolschlüssel und zeigt den bestätigten Detailstand. In einem noch ungespeicherten Lebensmittelentwurf lautet die Aktion dagegen „Übernehmen“ und kehrt in denselben Entwurf zurück; dessen Speichern bleibt nötig. Picker-Abbruch erhält die vorige Wahl. Definierte allowlist statt beliebigem SVG/HTML, übersetzte Suchbegriffe und zugänglicher ausgewählter Zustand. Unbekannter Schlüssel erhält das allgemeine Bestecksymbol. Metadatenänderung verändert weder Nährstoffrevision noch Mengen, Rezeptbestandteile oder aufgezeichneten Verzehr. Historische Darstellungen dürfen das aktuelle Symbol verwenden; numerische Snapshots bleiben unverändert.

Synthetisch: bereits vorhandener Joghurt erhält das Milchprodukte-Symbol; weiterhin 85 kcal, 7 g Eiweiß, 10 g Kohlenhydrate und 2 g Fett je 100 g. Sechs offizielle Lucide-SVGs `milk`, `apple`, `egg`, `fish`, `beef`, `soup` auf demselben dokumentierten Commit ergänzt, jetzt 87 Icons; bestehende ISC-/MIT-Hinweise gelten weiter. Keine neue App-Abhängigkeit.

**Prüfung:** Alle vier Quellen, Symbolraster und gespeicherter Detailstand angesehen; Quellenassets und Lizenzbezug dokumentiert. Kein echtes Lebensmittel geändert.

## B76 · Energieziel ändern mit sichtbarer Rechenregel

**Aus Flow 075.** Sechs Quellen zeigen vorhandenes Ziel, Gramm/Prozent, Energieeingabe und aktualisierte Makros. OpenBand verwendet die bereits gestalteten B30-Editoren. Bei Prozentmodus bleibt die Verteilung beim Ändern der Energie gleich, die Grammwerte werden nachvollziehbar neu berechnet. Im Gramm-Modus bleiben die eingegebenen Grammwerte stehen; eine abweichende Energiesumme wird sichtbar und erst durch eine explizite Wahl angeglichen. Keine still gewählten gesperrten Makros oder erfundene Bedarfsschätzung.

Separater synthetischer Änderungsfall: 2.000 → 2.100 kcal ab 16. September, Anteile Eiweiß 25 %, Kohlenhydrate 48 %, Fett 27 %. Kanonische Werte 131,25 g / 252 g / 63 g bei 4/4/9 kcal pro Gramm. Anzeige rundet Eiweiß auf 131,3 g, speichert aber nicht den gerundeten Anzeigenwert zurück. Für den 15. September bleibt die bisherige Vorgabe erhalten. Ein Wechsel g/% ohne Bearbeitung darf keine Rundungskaskade auslösen; Dezimalkomma, Wertebereich und 100-%-Summe am Eingaberand prüfen. Native Zahleneingabe mit erreichbarem Fertig/Abbrechen, Feldwert bleibt bei Tastaturwechsel erhalten.

Ziele versioniert nach lokalem Gültigkeitstag speichern. Bestehende bzw. zukünftige Änderung für denselben Tag gezielt bearbeiten statt unbestimmte konkurrierende Ziele. Ziel beenden erzeugt einen neuen Zeitraum ohne Ziel, frühere Tagesansichten behalten ihre damals gültige Vorgabe. Fehlende Ernährungsangaben erlauben keinen sicheren Restbudgetwert; B30s ≥-Fortschritt bleibt gültig. Das vorhandene Ziel und die neue Auswahl sind eigene Angaben, keine medizinische Empfehlung oder durch Bandmessung bestätigter Tagesbedarf.

**Prüfung:** Alle sechs Quellen, bestehender Gramm-/Prozenteditor und neue Änderungs-/Gültigkeitsansicht angesehen. Beispielarithmetik geprüft. Keine tatsächlichen Ernährungsziele verändert.

## B77 · Ein Training persönlich benennen

**Aus Flow 076.** Vier Quellen zeigen Aktivitätsmenü, Titel im Bearbeitungsmodus mit Tastatur und unveränderte Kennzahlen nach Umbenennen. OpenBand führt einen kurzen eigenen Titel ein, Beispiel „Runde am Morgen“ für den Lauf vom 14. September, 07:05. Ein Editorschritt zeigt die betroffene Einheit, erreichbare Speichern-/Abbrechen-Aktionen und das 80-Zeichen-Limit. Der bestehende Detailkopf wurde auf einen 44-pt-Rückweg korrigiert; die gespeicherte Variante behält Route, 5 km, 25 Minuten und dieselben Pulswerte.

Benutzerdefinierter Titel ist eine Metadatenkorrektur zur stabilen Session-ID, unabhängig von Aktivitätstyp, Quelltitel und Messwerten. Import/Sync darf ihn nicht wieder überschreiben. Leerraum trimmen; vollständig leerer Titel bedeutet die ausdrücklich angebotene Rückkehr zum automatischen Namen, kein namenloser Listeneintrag. UTF-8-Nutzereingabe korrekt begrenzen, keine abgeschnittenen Grapheme. Bei Fehler bleibt der Draft, erneuter Save ersetzt dieselbe Korrektur. Suche, Tagesverlauf, Trainingsliste und Teilen verwenden den gespeicherten Anzeigenamen; Detail und Export behalten tatsächlichen Aktivitätstyp und Herkunft. Keine Neuberechnung der Belastung nur wegen einer Titeländerung. Bestehender startWorkout-Titelparameter ist noch kein nachträglicher revisionssicherer Umbenennungsvertrag.

**Prüfung:** Alle vier Quellen, eigener Titelentwurf und unverändertes Laufdetail mit gespeichertem Namen angesehen. Kein Training im Appbestand geändert.

## B78 · Schnellmenge ändern ist noch kein Eintrag

**Aus Flow 077.** Drei Quellen zeigen die Änderung eines Nährstoff-Schnellwerts und anschließend die neue Beschriftung der Eintragsaktion. OpenBand verwendet Ballaststoffe statt eines unkritisch übernommenen Cholesterinziels. Die eigene Schnellmenge ändert sich 5 → 10 g; das unabhängig selbst gewählte Tagesziel bleibt 30 g und die heutige erfasste Menge bleibt offen. Erst „10 g jetzt eintragen“ erzeugt einen neuen eigenen Eintrag mit Datum/Zeit und Beleg.

Schnellmenge als typisierte Einstellung pro Nährstoff mit kanonischer Einheit speichern. Sie ist weder ein Ziel noch eine Obergrenze noch Konsum. Wiederholter Save ändert dieselbe Einstellung, kein Journalereignis. Einheitenwechsel nutzt die gleiche physische Menge; ungültige, nicht endliche oder nicht positive Schnellmengen verhindern den Commit und erhalten den Entwurf. Fehlende bestehende Nährstoffangaben bleiben unbekannt; der zukünftige eigene 10-g-Eintrag könnte nur eine bekannte Mindestmenge herstellen. Vorhandene Lebensmittelwerte nicht zusätzlich als separaten Schnell-Eintrag duplizieren. Ein Tap erzeugt genau einen Eintrag, versehentliches Doppeltippen wird verhindert; Rückgängig bezieht sich auf dessen ID. Bei historischem ausgewählten Tag muss der Zeitpunkt ausdrücklich zu diesem Tag gewählt werden, statt heutigen Zeitpunkt und altes Datum zu mischen.

**Prüfung:** Alle drei Quellen und eigene Bearbeitungs-/Rückkehransicht angesehen. Kein Nährstoffeintrag erzeugt.

## B79 · Mitteilungen nach Freigabe und Kategorie steuern

**Aus Flow 078.** Drei Quellen zeigen globales Erlauben und einzelne Kategorien. OpenBand trennt noch nicht angefragt, im System erlaubt, dort ausgeschaltet und eigene Kategorien. Der native iPhone-Dialog folgt erst der bewussten Erlauben-Aktion. Die Rückkehr liest den Systemstatus erneut; ein gespeicherter Wunschschalter ist kein Zustellnachweis. Kategorien: Band/Wecker, Auswertungen, erkannte Trainings und freiwillige Erinnerungen. Journal, Trinken, Bewegung, Schlafenszeit, Medikamente und eigenes Schritteziel bleiben einzeln konfigurierbar.

Bestehende NotificationService/NotificationPrefs verwenden lokale und geplante Mitteilungen, keine FCM-/APNs-Infrastruktur. Vorhandene zentrale Zulassungs-/Planungsregeln und stabile IDs behalten, neue UI daran anschließen statt einen zweiten Scheduler anzulegen. Appkategorie, OS-Autorisierung, Fokus, Vorschau und tatsächlich noch geplante Jobs separat anzeigen. Status vollständig erlaubt/provisional/denied/notDetermined über die tatsächlichen Plattform-APIs abbilden; keine Vermutung aus dem Ausbleiben eines Hinweises. System-Aus bietet Einstellungen statt wiederholtem Berechtigungsdialog. Bei fehlender OS-Freigabe bleiben App-Hinweise im Verlauf.

Das Beispiel aktiviert nach Freigabe Band/Wecker und Trainingsprüfung; neue Auswertungs- und Erinnerungsarten bleiben aus. Eigene Uhrzeiten/Intervalle werden erst nach ausdrücklicher Auswahl geplant. Bestehende 22:00–07:00-App-Ruhezeit mit sichtbarer Weckerstatus-Ausnahme darstellen. Diese Ausnahme umgeht keinen iOS-Fokus und beansprucht keine Critical-Alerts-Berechtigung. Bandwecker ist separat bestätigt/geplant, ein iPhone-Hinweis ersetzt ihn nicht. Kalenderbasierte DST-sichere Planung aus NotificationService weiterverwenden; Zeitzonenwechsel, ruhige Stunden und bereits erledigte Journal-/Medikamentenaktionen müssen verbleibende Slots neu abgleichen. Erledigte oder bewusst ausgelassene Einnahmen nicht erneut erinnern.

Auswertungsmitteilungen setzen belastbare aktuelle Ergebnisse voraus: fehlende Eingänge führen zu fehlender Bereitschaft, nicht zu einem niedrigen Gesundheitsscore. Nicht evaluierte Krankheit-/Rhythmus-/Temperaturalarm-Annahmen aus bestehenden Kategorien sind kein Freibrief für entsprechende Produktversprechen. Neue Begründung je Kategorie und methodische Freigabe nötig; Standardvorschau enthält keine sensiblen Zahlen. Ein Tip öffnet den richtigen Tag und die konkrete Meldung/Quelle, auch nach Neustart; entfernte Daten zeigen einen verständlichen nicht mehr verfügbaren Zustand. Abschalten storniert bereits geplante passende Jobs. Keine nachträgliche Flut alter Benachrichtigungen nach Wiederfreigabe.

**Prüfung:** Drei Quellen; eigener Einstieg, erlaubter/abgelehnter Zustand, Erinnerungskatalog und Ruhezeit angesehen. Vorhandene Preferences-/Schedulerregeln direkt gelesen. Keine echte OS-Freigabe oder Erinnerung angelegt; Hintergrundzustellung bleibt physisch zu prüfen.

## B80 · Übungsdetails mit eigener Illustration und klarer Erfassung

**Aus Flow 079.** Drei Quellen zeigen Bibliotheksdetail, Geräte-/Muskelzuordnung und Anleitung mit Illustration. OpenBand verwendet eine eigene Geräteillustration für Bankdrücken, beschriftete Bibliotheksangaben und den eigenen letzten Satzbestand. Eine separate Erfassungsansicht erklärt Gesamtlast und Wiederholungen mit konkretem Rechenbeispiel. Eine anatomische Heatmap wird nicht als gemessene Muskelbelastung ausgegeben. Technische Bewegungsvideos oder Trainingsanweisungen brauchen eigens lizenzierte, fachlich geprüfte Inhalte; ein generiertes Gerätebild ersetzt diese Prüfung nicht.

Synthetisch: Bankdrücken aus der Einheit vom 13. September, 3 × 8 × 40 kg = 960 kg eingegebenes Volumen. Gesamtgewicht enthält Stange und Scheiben. Die Bibliotheksgruppen Brust, Trizeps und Schultern sind Metadaten. Niedrige Zahl abgeschlossener Einheiten darf keinen Fortschritt oder Bestleistungs-Trend vortäuschen. Der Verlauf führt zu den tatsächlichen Satz-Snapshots und ihrer Quellen-/Lastbasis. Eigene Übungen dürfen ohne Illustration bestehen; bewusst gestalteter Geräteplatzhalter bleibt von einem vorhandenen Originalbild unterscheidbar.

Definition braucht Asset-ID, Lizenz-/Erstellungsnachweis, Alternativtext, Darstellungsversion und ggf. Sprachversion des fachlich geprüften Texts. Asset darf nicht als Herkunft einer Messung erscheinen. Auswahl aus der Bibliothek kehrt mit derselben Exercise-ID in den bestehenden Vorlagen-/Sitzungsentwurf zurück, ohne selbst einen Satz oder eine Vorlage zu speichern. Lastbasis aus B26/B40 muss überall dieselbe sein; „je Hantel“ bei einer anderen Übung nicht in die Langhantelbeschreibung übernehmen. Erfassungsanleitung und tatsächliche Übungstechnik sind getrennte Inhalte.

**Prüfung:** Alle drei Quellen, eigene Detailansicht mit Originalillustration und Erfassungsanleitung angesehen. Generiertes Gerätebild visuell geprüft und samt Herkunft unter `assets/bench-press-illustration-v1.png` gespeichert. Rechenbeispiel und letzter Satzbestand stimmen mit B20 überein. Kein anatomisches Modell und keine Übungstechnik validiert; entsprechende spätere Inhalte benötigen eigene Prüfung.

## B81 · Trainingsverlauf nach Kennzahl filtern

**Aus Flow 080.** Vier Quellen zeigen Aktivitätsverlauf mit Dauer, Distanz und Höhengewinn. OpenBand behält Zeitraum und Aktivitätsauswahl beim Kennzahlwechsel. Dauer der synthetischen Woche 9.–15. September: 102 Minuten aus drei gespeicherten Einheiten. Distanz ist nur für den Lauf mit 5 km bekannt; beim 32-Minuten-Radfahren fehlt sie, Krafttraining ist für Distanz nicht anwendbar. Deshalb ≥5,00 km und „1 von 2 passenden Einheiten“, keine vollständige 5-km-Wochensumme. Höhengewinn ist für dieses Beispiel nicht verfügbar.

Aggregationen müssen anwendbar, vorhanden, fehlend, unzuverlässig und ausgeschlossene Duplikate unterscheiden. Prozent/Anzahl der Abdeckung bezieht sich auf passende Einheiten, nicht alle Zeilen. Anzeige von ≥ ist nur eine bekannte Teilsumme nichtnegativer Werte, keine Schätzung des Fehlenden. Tage ohne gespeicherte Einheit sind kein Nachweis, dass die Person nicht trainiert hat. Chart zeigt bekannte Mengen; unbekannte Strecken erhalten einen Textmarker, keinen erfundenen Balkenwert. Ein Tages-/Wochenvergleich darf nur als vergleichbare Summe behauptet werden, wenn beide Quellenbestände dieselbe Einschlussregel und hinreichenden Umfang haben. Ohne Vergleichsbestand kein ausgedachtes Plus/Minus.

Dauer eindeutig als gespeicherte aktive bzw. Gesamtdauer benennen, Pausen nicht unbemerkt zwischen Ansichten wechseln. Höhengewinn erfordert Qualitäts-/Glättungsregeln und Quelle; vorhandene GPS-Punkte allein reichen nicht. Distanz und Tempo verwenden B56s Einheiten. Listen und Diagramme stammen aus derselben stabilen Ergebnisrevision, Filter nicht nur kosmetisch auf Diagramm anwenden. Bei fehlenden Werten bleibt der Wechsel zu Dauer und zu Quelldetails möglich. Änderungen der Auswahl sind Darstellung, keine Neuberechnung oder Mutation der Sessions.

**Prüfung:** Alle vier Quellen und eigene Kennzahlwahl, Distanz-Teilsumme und fehlender Höhenstand angesehen. Die fehlende Strecke erhält ein Fragezeichen statt einer quantitativ missverständlichen Balkenhöhe. Dauer-/Distanz-Einschluss und Einheitenzahl an der gemeinsamen Fixture geprüft; kein tatsächlicher Verlauf geändert.

## B82 · Trainingszonen nach Aktivität vergleichen

**Aus Flow 081.** Fünf Quellen zeigen Cardio-Fokus, Aktivitätsfilter und geänderte Verteilung. OpenBand übersetzt das in nachvollziehbare „Trainingszonen“ statt ungeprüfter Aerobic-Dominanz-/Übertrainingslabels. Zeitraum und Sportart filtern denselben Bestand. Die vollständige synthetische Lauf-Einheit hat 0/6/15/4/0 Minuten in Zone 1–5, also 60 % der 25 erfassten Minuten in Zone 3. Bei allen drei Wocheneinheiten bleibt dieser bekannte Bestand gleich, aber 77 von 102 Minuten besitzen in dieser Fixture keine Zonenwerte. Nach Filter Laufen sind 1/1 Einheiten und 25/25 Minuten abgedeckt.

Aggregation gewichtet gültige Sekunden, nicht den Mittelwert von Prozentwerten verschieden langer Sessions. Unterhalb Zone 1 bleibt ein eigener gültiger Bereich, fehlender/unzuverlässiger Puls ein anderer; Summe darf beides nicht verschwinden lassen. Nenner für Prozentwerte steht direkt am Chart. Unterschiedliche Zonenmethoden/Versionen können nicht still aggregiert werden. Entweder vergleichbare gespeicherte Methode gruppieren oder alle erforderlichen Originale mit ausdrücklich gewählter gemeinsamer Methode neu auswerten; B59s zukünftige manuelle Änderung verändert nicht automatisch alte Trainings. Ohne verwertbaren Puls zeigt der gewählte Sport einen erklärten Leerzustand mit Quellenweg, nicht fünf Nullzonen.

Die Standard-Laufbasis bleibt die Altersschätzung Maximalpuls 190 und die tatsächliche Trainingsdauer aus B19. Keine physiologisch gemessenen Schwellen oder Trainingsqualität aus den Bevel-Begriffen ableiten. Herzfrequenzabdeckung, Ausschlussgründe und beteiligte Einheiten bleiben erreichbar. Trainingsart aus gespeicherter Session verwenden; bloßes Umbenennen B77 ändert den Filter nicht. Filterzustand gehört zur Ansicht und bleibt beim Öffnen einer Einheit erhalten.

**Prüfung:** Alle fünf Quellen, eigene Gesamtverteilung, Sportauswahl und Laufverteilung angesehen. Minutensummen/Prozentwert mit der vorhandenen Lauf-Fixture abgeglichen. Keine neue Belastungsformel implementiert.

## B83 · Übungsfilter

Muskelgruppen und Geräte als stabile IDs: innerhalb einer Gruppe ODER, zwischen Gruppen und Suchtext UND. Primär-/Sekundärmuskeln explizit definieren. Auswahl bleibt unabhängig vom Suchergebnis erhalten; Zähler benennt verdeckte Auswahl. Leere Ergebnismenge bietet Filter zurücksetzen und eigene Übung. Zurück verwirft nur unbestätigte Filter. Bestehende exercise_def-Metadaten erweitern, keinen zweiten Katalog aufbauen. UI-Entwurf 82 mit 2 Muskeln/2 Geräten; ausgewählter Ausfallschritt bleibt außerhalb erhalten.

## B84 · Gemerkte Angaben filtern

Themenfilter und Aktiv/Abgelaufen-Status sind reine Listenzustände. Count bezieht sich auf sichtbare und gesamte aktive Angaben; Filter beeinflusst Coach-Kontext nicht. Themen als editierbare Kategorien, Inhalt bleibt ausdrücklich bestätigt; keine automatische sensible Kategorie aus Messwerten. Bereits definierte Ablauf-/Löschregeln B47 unverändert.

## B85 · Training als scrollbarer Überblick

Training 4GY → 10ME ist eine fortlaufende Seite mit gemeinsamem Zeitraum. Tageszellen öffnen die Liste dieses Tages; Trainingszonen → ZV6; Pulserholung → IXD; letzte Einheit → 4UY; Kraft → J51/DG0; Vorlagen → DDO. Hauptmuskelgruppen-Zuordnung pro abgeschlossenen Satz verhindert Doppelzählung. Volumen 3.300 kg = Beine 1.440 + Brust 960 + Rücken 900, neun Sätze am 13.09.; Templates zählen nicht. Eigene Maße für gehaltene Sekunden und Eigengewicht. Trainingszonen 60 % bezieht sich auf 15/25 bekannte Minuten, nicht auf alle 102 Minuten. Langfristige Belastung benötigt versionierte Methode, ausreichende Historie und sichtbare Tagesabdeckung; kein Übertraining-Urteil aus kurzem Verlauf. Konfiguration der Trainingskarten mit gleichem Reihenfolge-/Sichtbarkeitsmodell wie Übersicht, ohne Datenausschluss.

## B86 · Nährwerte nachvollziehen

Flow 85 übernimmt beitragsbezogene Erklärung, aber keinen proprietären Food-Quality-Score. Originalenergie und Makros getrennt speichern; Portion und Basis pro 100 g normalisieren, null erhalten. Für 200 g Joghurt: 170 kcal, 14 g Eiweiß, 20 g Kohlenhydrate, 4 g Fett, 8 g Gesamtzucker. Energiebalken aus 56/80/36 kcal = rund 33/46/21 %, keine Bewertung und kein Tagesziel. Added sugar bleibt unbekannt; nie aus Gesamtzucker ableiten. Lebensmittelquelle/Version und manuelle Bearbeitung nachvollziehbar. Möglicher künftiger Qualitätsscore braucht separat geprüfte Methodik, Eingangsabdeckung und verständliche Beiträge; der jetzige Entwurf setzt ihn nicht voraus. Einstieg aus gespeicherter Lebensmittelportion, Info öffnet 10VS.

## B87 · Geführte Trainingsvorlagen

Neue Designfunktion: lokaler, versionierter Vorlagen-Generator mit getrenntem InputDraft/Proposal/SavedTemplate. Wünsche experience/goal/duration/focus, Geräte inkl. verfügbarer Lasten und Ausschluss-IDs. Bereits definierte Geräteverwaltung und Bibliothek wiederverwenden. Kuratierte und fachlich geprüfte Vorschlagsregeln vor Umsetzung festlegen; keine ausgedachten Gewichte oder Intensitäts-Scores. Rückwärtsnavigation bewahrt Eingaben; Schließen bietet Entwurf behalten/verwerfen. Abbruch beendet Job; späte Antworten dürfen keinen Draft überschreiben. Fehler hält Eingaben, Retry erzeugt keine Vorlage doppelt. Ergebnis ist editierbar und wird erst mit Speichern atomar persistiert, mit Herkunft und Regelversion. Vorlagen-ID und Job-ID trennen. Freitext-Wunsch kann später denselben typisierten Proposal-Vertrag über optionalen Coach verwenden, mit dessen bestehender Netzwerkeinwilligung; geführter Weg braucht kein Konto/Cloud. Synthetic: Ganzkörper-Vorschlag mit 4 Übungen/12 Sätzen, alle Lasten null, ca.45 Min. als Schätzung; kein erfasstes Training, kein Tagesdaten-Effekt. Editor nutzt DDO/KWG mit leeren Lasten; vorhandene Ganzkörper A bleibt separat. Auswahl-Screens 118D/119Y/11BJ/11DB; Fokus eigene Auswahl nutzt Muskelgruppen-Komponente mit Ganzkörper-Exklusivität.

## B88 · Quellen gezielt ausschließen

Berechtigung/Import und Nutzungsregel strikt trennen. Pro Messgröße und stabiler SourceIdentity allow/exclude speichern, Originalwerte behalten; die Regel gilt auch für neu importierte Werte derselben Quelle. UI zeigt Quelle, Übernahmeweg, Messzeit und Anzahl. Ausschluss ist weder Löschung noch Importstopp. Vorschau nennt betroffene Ansichten/Ableitungen; revisionsgebundene Neuberechnung mit altem Ergebnis bis neuem Commit, Fehler/Abbruch kein falscher Erfolg. Wiederherstellen reversibel, Prioritäts-/Dedupe-Regeln für überlappende Quellen deterministisch. In diesem Glukose-Variantenflow B62: einzige Quelle mit 11 Werten ausschließen → keine aktive Glukosequelle; Datenbestand und Health-Übernahme bleiben unverändert. Keine Nullkurve. Ausschlussdialog aus Messwert-Quellen und Profil → Daten → Datenquellen erreichbar.

## B89 · Gesprächsverlauf und Rückkehr

Gesprächsmenü führt zu lokalem Verlauf, neuem Gespräch, bestätigten Angaben und Modell/Freigaben. Einträge öffnen gespeicherte Antworten ohne Modellaufruf; Datenstand und Quellen bleiben an die damalige Antwort gebunden. Neue Frage verwendet explizit gewählten Tageskontext, nicht unbemerkt den heute verbundenen Bandstand. Leerer Verlauf mit eigener CTA. Fortsetzen rekonstruiert Session-ID und Kontext; Menü/Löschen B68, keine stille 30-Gespräche-Löschung. Retentionkonzept vor Umsetzung ausdrücklich wählen. Offline-Lesen darf möglich bleiben, auch wenn das Modell nicht erreichbar ist.

## B90 · Home als kompakter, vollständiger Tagesfeed

Canonical 1V0/1Y8 + Scrollfortsetzung 8OM. Datum öffnet Kalender, Band-Akku öffnet Verbindung, Datenstand/Nacht erfasst öffnet Coverage. Ringe: Schlaf zeigt Phasenanteile der Bettzeit und innen die Schlafdauer (B163); Erholung 74/100, Belastung 1,6/21. Kein rückwirkender Vergleich gegen erst ab 15./16. gültiges Schlafziel. Ring und tägliche Einordnung öffnen Details; Einordnung mindestens44 pt. Vier Messwertkarten, Ernährung/Wasser und weiter unten Aktivitäten, Stressbereitschaft, Journal, Tagesverlauf, Anpassen und alle Messgrößen. Stress/Energie nur als versionierte, nachvollziehbare Ergebnisse; keine imitierte Energy-Bank-Prozentzahl aus ungeprüfter Methode. Vier Tabs bleiben stabil, Erfassung per Journal-Plus oder jeweiligem Bereich. Datumskontext wird an alle Eintragsentwürfe weitergegeben, Tagesabschluss und neue Daten dürfen nicht historische Screens umdatieren. Aktives Training erscheint oberhalb Navigation und bleibt bei Tabwechsel/Scroll erreichbar; Abbruch/Stop nur in Trainingsansicht. Variante11QX: Start15.09.09:30, Uhr09:41, 11 Minuten laufend, Puls offen; Tageswerte bleiben gespeicherter Stand07:42. Doppelstart verhindern, Session persistent wieder aufnehmen; noch nicht als abgeschlossene Einheit zählen. UI-Änderungen in Dark synchronisiert, Fußabdruck-Icons aus Lucide. Alle Status-/Großschriftvarianten werden im abschließenden Gesamtinventar an diese Canonical-Struktur abgeglichen.

## B91 · Gerätespezifische Erfassungshilfe

An jedem Last-/Wiederholungsfeld eine passende Hilfe aus versionierter ExerciseDefinition anbieten. Langhantel = Gesamtgewicht, zwei Kurzhanteln = je Hantel plus Anzahl und Wiederholungsbasis, Maschine = angezeigte Last und Geräteidentität. Beispiel Curl10 kg je Hantel ×2 ×8 =160 kg; links/rechts bei ungleicher Ausführung getrennte Logs. Keine doppelte Seitenmultiplikation. Maschinenwerte nur innerhalb passender Definition vergleichen, kein vorgetäuschter mechanischer Kraftwert. B26/B40-Normalisierung ist Voraussetzung. Hilfen sind statische Erklärungen und speichern keine Sätze; normale Rückkehr erhält Eingabedraft. Die Volumenfixture3.300 kg verwendet Langhantel-Rudern mit30 kg Gesamtlast, nicht das Kurzhantel-Beispiel.

## B92 · Rezept aus Text oder Foto übernehmen

Neuer Importweg speist den bestehenden RecipeDraft (B08/B21), kein eigener Rezeptdatenspeicher. Text/Foto lokal halten, OCR und Parser liefern Rohtextabschnitt, Menge, Originaleinheit, Portionszahl und Kandidaten. Lokale Zuordnung zuerst; optionaler Netzwerkdienst benötigt sichtbare Freigabe. Keine Zwischenablage lesen, bevor der Nutzer Einfügen auslöst. Leerer Text deaktiviert Erkennen, Kamera verweigert bietet Foto/Text. Nicht zugeordnete Mandeln26g bleiben als solche sichtbar und über den Lebensmittelpicker zuordenbar; unbekannte Nährstoffe sind null und partielle Summen entsprechend gekennzeichnet. Ein Rezept darf unvollständig gespeichert werden, aber die UI darf keine Vollständigkeit behaupten. Nach Prüfung normaler EditorK97 → atomarer Recipe-Save → SammlungKD3; FehlerKFJ erhält Draft. Abbruch/Retry revidiert nur Importjob, nie bestehende Verzehrtage. Fixture: Beeren-Skyr-Bowl2Portionen,120gHafer/300gSkyr/200gBeeren/26gMandeln =900kcal gesamt/450 jePortion; Makros58/104/22 gesamt. Fertiges Gewicht bleibt optional, nicht automatisch aus roher Summe646g behaupten. Foto-Metadaten/Quelle separat, keine fremde Seite als Rezeptautorität ausführen.

## B93 · Journal-Muster mit belegbarer Datengrundlage

Live-Quellprüfung: analytics/lib/src/onehz/human/associations.dart hat scanAssociations mit zeitlicher Zuordnung, Wochentagsanpassung, Block-Permutation, Mehrfachtestkorrektur, Redundanzprüfung und standardmäßig84 passenden Tagen. edge/lib/data/local_repository_impl.dart:getJournalInsights verwendet noch separate journalCorrelations/numericJournalInsights, gibt nur gefilterte Ergebnisse zurück und trägt helped-Semantik. Vor UI-Umsetzung zu einem typisierten Scan-Ergebnis konsolidieren: not_ready(reason/counts), ready_no_finding und ready_findings; Abwesenheit nie als Nein, explizite Ja/Nein-Antworten versionieren. Bereitschaft per Paar/Zeitraum und Methodenversion liefern, keine feste Fünf-Ja/Fünf-Nein-Freischaltung aus der Inspiration übernehmen. Nicht automatisch Kausalität, Effektversprechen oder Handlungsratschlag formulieren. Eigene Werte und Bandwerte nach lokalen Tag-/Nachtlabels sowie Zeitzone verbinden. Tatsächliche Quelle und Datenrevision behalten; nach Korrektur atomar neu rechnen. Nutzung des Codepfads ist keine physiologische Validierung.

Designwerte wurden mit dem vorhandenen Dart-Code berechnet: assets/fixtures/journal-insight.json und journal-insight-no-finding.json. Separate künstliche120-Tage-Reihen19.05.–15.09., kein Ersatz für die Tagesfixture. Positiv:119 Paare,55Ja/64Nein, Median429/398min, Kontrast31min, rho0,829013/q0,001. Negativ:119Paare, q0,557, kein meaningful finding. Keine Signifikanzbehauptung über echte Nutzer. Algorithmusdatei SHA256 61316061cc0b5b7045b21acfd145b0302ee4d6f69c3021ee20eb37faaa14fd9d. Standardparameter, seed92; Generator lief nur als Design-Nachrechnung in /tmp. Basisbeispiel hat keine passende Journal-Folgenacht-Serie und bleibt offen. Tage-Liste12GR paginiert denselben Scan-Snapshot, Filter Alle/Ja/Nein ändert nicht nachträglich die publizierte Statistik. Methodenansicht passt Counts/Ergebnis an den aufrufenden Zustand an.

## B94 · Journal als kompakte Tagesübersicht

53Y und12P1 sind zwei Scrollpositionen desselben Tages. Datum/Woche wählen Journaldate unabhängig von Live-Verbindung; Muster→129V, Menü→12SZ. Check-in verdichtet zu drei klaren Eingängen, Getränke/Ernährung direkt sichtbar. Wasser+250ml ist ein ausdrücklicher Einzel-Commit mit lokalem Zeitpunkt/Tag und Rückgängig; wiederholter Retry darf nicht doppeln. Koffein-Menge des vorhandenen Kaffees bleibt unbekannt, Alkohol ohne Antwort bleibt offen. Gewohnheiten verwenden Ja/Nein/Offen-Vertrag, ohne fiktive9-von14-Historie. Kalendermarker zeigen tatsächliche Eintragszustände, nicht Bandabdeckung; im Basisbeispiel nur15.09. mit eigenen Einträgen. Auto-Beobachtungen sind separate Read-only-Werte mit Quelle/Zeitstand, nicht selbst bestätigte Antworten. Eine frei definierte automatische Schwelle benötigt Feld/Schwelle/Zeitraum/Coverage und Regelversion; fehlende Daten nie als Nein. Nachts beantwortete Gewohnheiten müssen ausdrücklich einer Nacht oder dem Vortag zugeordnet sein. Tagesabschluss prüft offene Fragen, setzt nicht alles auf Nein. Keine ungefragte Vortagskopie. Journal-Reihenfolge/Gruppen/Schnellmengen nutzen bestehende Designverträge, Erinnerungen optional. Bekannte Tageswerte bleiben750ml/≥620kcal, kein neuer Verzehr durch reine Navigation.

## B95 · Eigene Koffeinmenge und Lebensmittelquelle

JournalField caffeine_mg existiert als Tagesdosis mit einem atMinuteOfDay, max1000 und step25. Mehrere Einnahmen benötigen echten zeitgestempelten Entry-Vertrag statt Überschreiben eines Tageswerts. Mg-Eingabe mit Dezimalkomma, keyboard/Stepper, Einheit sichtbar; keine aus Tassenzahl erfundene Dosis und keine stillen Clamps bei Überschreitung. Gesamteintrag oder verknüpfter Food-Entry klar unterscheiden: eigene90mg09:41 ist zusätzlicher Beitrag, Kaffee ergänzen ändert vorhandene Quellen-ID ohne Doppelzählung. Legacy-Tagesangaben behalten Herkunft und aggregierte Bedeutung; nicht künstlich in Einzelereignisse zerlegen. Unbekannte Kaffee-Dosis → offener Tageswert, nach neuer eigener Angabe ≥90mg. Energie≥620kcal und Wasser750ml bleiben unverändert. Bekannte Null ist eigene bestätigte Antwort, keine fehlende Eingabe. Speichern atomar mit stabilerID, Rückgängig entfernt nur neuen Beitrag; Datum/Zeit im selben Editor. Betrag leer/negativ verhindert Speichern, Daten bleiben im Draft. EigenesPreset getrennt von Verzehr und jederzeit änderbar.

## B96 · Gespeicherter Verzehr mit Herkunft und offenen Angaben

Log-Detail ist ein Snapshot des tatsächlich gespeicherten Eintrags, kein aktueller Katalogwert. Name/Portion/Energie/Makros/Quelle und Datum sichtbar; Teilwerte bleiben offen. Joghurt200g =170kcal/14gEiweiß/20gKH/4gFett, Nährwerterklärung→10SP; Hafer450/22/60/14 ohne erfundene Zutaten; Rezept-Zutaten nur bei echter Rezeptdefinition. Eintrag bearbeiten öffnet Entry-Draft, Sammlung merken erzeugt eigenständige Definition, Foto verändert keine Zahlen. Kaffee mit Milch bleibt vorhandener Eintrag mit unbekannten Energie-/Koffeinwerten, Ergänzen ändert dessen ID. Nie zusätzlich eine neue Mahlzeit speichern, wenn nur ein fehlendes Feld ergänzt wird. Herkunft zeigt verwendete Katalog-/Definitionsversion und Originaleinheit; alte Einträge nicht nachträglich durch Katalogupdates ändern. Menü-Löschen nutzt B07 mit passender Entry-ID und Rückgängig, Rezeptdefinition/Sammlung bleibt bestehen. Deutsche Makrobezeichnung Eiweiß wird final global vereinheitlicht.

## B97 · Stimmung als eigene Momentaufnahme

Bestehende mood/energy/sleep_quality-Felder sind Ratings1–5. Neuer MoodEntry mit ID, local timestamp+timezone, value1–5, optionalen Gefühl-IDs/Kontext-IDs/Notiz und Revision erlaubt mehrere Momente, ohne alte zu überschreiben. Initiale Auswahl ist null, nicht3/Neutral. Speichern benötigt bewusste Wahl; Textlabels und Screenreader-Werte ergänzen die lizenzierten Lucide-Gesichter. Gemischte Gefühle erlaubt, keine pauschale positiv/negativ-Zwangszuordnung; Kontext ist eigene Zuordnung, keine nachgewiesene Ursache. Hauptjournal zeigt letzten Moment mit Zeit. Analysen brauchen explizite Auswahlregel/Zeitschnitt und dürfen ordinale Ratings nicht ungefragt mitteln oder die Stimmung nach einer Nacht dieser Nacht als Ursache zuweisen. Vorhandener gemeinsamer Check-in57I bleibt optionaler Tageseditor; muss denselben Entry-Vertrag verwenden statt parallel einen widersprüchlichen Tageswert zu pflegen. Variante13GM:15.09.09:41 Gut4/5, ruhig+zufrieden, KontextSchlaf; Energie/Schlafgefühl bleiben unberührt. Kein Tagesscore/keine gemessene Erholung daraus. Fehler erhält Draft, Undo entfernt nur neuen Moment; weitere Einträge beginnen wieder ohne Auswahl. Icon-Bestand auf88 offizielle SVGs erweitert.

## B98 · Aktivitäten nachtragen und Überschneidungen prüfen

**Aus Flow 097.** Ein eigener Nachtrag speichert Aktivitätsart, Start/Ende mit Zeitzone, optionale Distanz, Energie und subjektive Anstrengung als getrennte Angaben mit Herkunft. Puls, Route, Zonen und physiologische Belastung bleiben ohne Messquelle offen. Eine Pace aus eigener Distanz und Dauer trägt diese Herkunft; subjektive Anstrengung 3/10 ist kein Belastungsscore. Vorhandene Workout-Speicherung erweitern; dieselbe stabile Draft-ID verhindert Doppelanlage bei Retry.

**Separate synthetische Variante:** Spaziergang am 15. September, 09:00–09:25, eigene 2,00 km → 12:30 /km; Anstrengung 3/10. Nach lokalem Commit enthält diese Variante vier Einheiten und 127 Minuten in der Woche. Die Basisszene mit drei Einheiten und 102 Minuten bleibt unverändert.

Vor Commit zeitliche Überschneidungen anhand gespeicherter Einheiten prüfen. Die alternative Konfliktszene vom 14. September 07:05–07:30 zeigt den vorhandenen 5-km-Lauf: vorhandene Einheit öffnen oder Zeitraum ändern, kein stilles Überschreiben oder doppeltes Zählen. Ein ausdrücklich gewünschter paralleler Nachtrag braucht eine begründete Zusammenführung der Tagesaggregate. Bei Schreibfehler bleiben Draft und Ausgangskontext erhalten. Historische Zeitzonen, Nachtwechsel, ungültige Dauer, fehlende Distanz und erneutes Öffnen prüfen.

## B99 · Alkohol: Getränkemenge statt unklarer Drinks

**Aus Flow 098.** Die Oberfläche erfasst Volumen und % vol oder ausdrücklich Gramm Alkohol; eine landesabhängige Drink-Einheit ist nicht die interne Basis. B51 liefert nur die Vorbelegung, keinen Verzehr. Eigene zeitgestempelte Intake-IDs, lokale Tageszuordnung und Herkunft der Alkoholberechnung ergänzen den Journalvertrag. 150 ml × 0,12 × 0,789 g/ml = 14,202 g, Anzeige rund 14 g. Eingaben mit deutschem Komma, positive Menge, % vol im gültigen Bereich; unbekannter Gehalt ergibt unbekannte Alkoholmenge, keine Null.

Offen, ausdrücklich kein Alkohol und vorhandene Getränke sind getrennte Zustände. Ein neuer Eintrag bei einer bestehenden Kein-Alkohol-Antwort verlangt Bestätigung zum Ersetzen dieser Antwort; die letzte Löschung setzt nicht automatisch eine Nullantwort. Keine automatische kcal-/Wasserbuchung ohne eigene erklärte Produktregel. Die synthetische 09:41-Variante ist separat vom 14.-September-Wein und vom unveränderten Basistag. Commit/Fehler/Retry und Rückkehr ins gewählte Journal-Datum folgen B95/B98.

## B100 · Wasser als einzelne Einträge

**Aus Flow 099.** Gemeinsames zeitgestempeltes Intake-Modell mit Wasser in ml. Schnellzugabe speichert die sichtbare Menge am gewählten Tag und bietet Rückgängig; eigene Menge öffnet einen Draft mit Einheit und Uhrzeit. Kein Hochzählen eines einzigen Tagesfelds ohne einzelne korrigierbare Einträge. Fehlende Menge bleibt offen. Vorhandene ältere Tagessummen werden als Altbestand mit fehlenden Einzelzeiten erhalten, nicht in erfundene Getränke zerlegt.

**Separate synthetische Variante:** bestehende 750 ml + 350 ml um 09:41 = 1.100 ml. Eine Fehlbuchung wird über ihre Entry-ID bearbeitet oder gelöscht. Wiederholte Bestätigung derselben Draft-ID dupliziert nichts; zwei bewusste Schnellzugaben bleiben zwei Einträge. Ohne eigenes Ziel wird kein erfundener Bedarfsring gezeichnet; Lebensmittelwasser und Alkohol/Kaffee werden nicht still mitgerechnet. Bei Schreibfehler bleibt der alte bestätigte Tageswert sichtbar. Eingaben: deutsches Komma, positive Menge, Zeitpunkt/Zeitzone, Abbruch, Mitternacht und historische Tage.

## B101 · Start ohne Anmeldung

**Aus Flow 100.** Bevel zeigt Apple-/E-Mail-Anmeldung, Linkversand und Rückkehr zur Übersicht. OpenBand braucht für lokale Aufzeichnung und Auswertung keine Identität. Der Start bietet Band verbinden, vorhandene Daten importieren und später verbinden; vorhandene lokale Daten öffnen direkt die Übersicht. Keine E-Mail, kein Apple-Login und kein Konto werden allein für diese Abläufe eingeführt.

B01 bleibt der wiederaufnehmbare Einrichtungsvertrag. Ein künftiger optionaler Netzwerkdienst erhält eine eigene, explizite Einrichtung im betroffenen Bereich und blockiert nie den lokalen Start. Import ist ein Datenweg, keine Anmeldung; keine implizite Cloud-Wiederherstellung versprechen. Die Willkommensvorschau ist synthetisch und braucht keine vorhandenen persönlichen Daten.

## B102 · Kein Abmelden für ein lokales Profil

**Aus Flow 101.** Bevel trennt Abmelden und Konto löschen. OpenBand hat kein allgemeines Konto und daher keinen Abmelden-Knopf. Profil, Bandverbindung, optionale Modellzugänge und lokale Daten sind voneinander unabhängig. Band trennen beendet keine Datenverfügbarkeit; einen Modellzugang entfernen beendet nur dessen Nutzung. Lokale Daten entfernen bleibt der konkret benannte, geprüfte B70-Ablauf mit Exportmöglichkeit und Teilfehlerzustand.

Kein generischer Logout darf als Abkürzung für Datenlöschung, Bluetooth-Trennung oder Schlüsselentfernung verwendet werden. Die bestehende Profilansicht und Löschvorschau erfüllen diese Trennung; kein zusätzliches Kontomodell erforderlich.

## B103 · Makroverteilung mit bekannter Datenbasis

**Aus Flow 102.** Makrogramm, daraus berechnete Energieanteile und separat eingetragene kcal sind eigene Größen. Die Basisszene hat bekannte 36 g Eiweiß, 80 g Kohlenhydrate und 18 g Fett plus einen unbekannten Kaffee-Eintrag: 144/320/162 kcal = 626 kcal aus Makros; Anteile gerundet 23/51/26 %. Die unabhängig gespeicherten Energieangaben bleiben 620 kcal. Kein Rückrechnen oder Überschreiben zur kosmetischen Gleichheit. Rundung erst in der Anzeige.

Verläufe enthalten Datum, bekannte Summen, Zahl vollständiger/unvollständiger Einträge und explizite fehlende Tage. Keine Einträge sind keine 0-g-Tage. Für 9.–15. September existiert im Beispiel nur ein teilweise erfasster Tag; deshalb keine vollständige Wochenmittelzahl. Mittel/Summen müssen Nenner, Erfassungsbasis und unvollständige Tage sichtbar machen. Anteile eines Null-/unbekannten Gesamtwerts bleiben offen; ein bekanntes Null-Makro ist zulässig. B05/B06 liefern Entry-Snapshots und Portionsrechnung.

Makrodetail verlinkt den zugehörigen Nährstoffverlauf und die betroffenen Einträge; Fehlende Angaben ergänzen öffnet den unvollständigen Kaffee. Gemeinsame Datumsauswahl und Zeitraumsteuerung verwenden dieselben gefilterten Daten. Der Prozentbalken bewertet weder Lebensmittelauswahl noch Gesundheit.

## B104 · Kein Abonnement und keine künstlichen Funktionssperren

**Aus Flow 103.** Die Quellansichten verwalten Bevel Pro und führen zur Aboänderung. OpenBand bleibt entsprechend Produktauftrag abonnementfrei. Kein eigener Paywall-, Probeabo-, Restore-Purchase- oder Entitlement-Ablauf; keine Sperre historischer lokaler Daten oder verfügbarer Auswertungen hinter einem Pro-Status.

Optionale externe Modell-/Lebensmitteldienste können eigene Kosten haben. Deren Einrichtung nennt den gewählten Anbieter und dessen Datenweg; sie ist kein OpenBand-Abo. Fehlende Datenqualität und fehlende optionale Quellen bleiben fachliche Bereitschaftsgründe, keine Kaufaufforderungen. Einstellungen und lokaler Coach-Weg bleiben ohne Upsell.

## B105 · Sammlung, Favoriten und erneutes Eintragen

**Aus Flow 104.** Vier Filter: Zuletzt aus gespeicherten Verzehr-Snapshots, Favoriten als explizite eigene Auswahl, Rezepte und eigene Lebensmittel als Definitionen. Favoriten sind kein weiterer Verzehr und keine automatische Empfehlung. Definition-ID plus Version, Favoritstatus und Archivierung getrennt vom historischen Entry. Erneutes Eintragen öffnet zuerst Menge, gewählten Tag und optional Uhrzeit.

**Bestand geprüft:** nutrition_store.dart hat food_def und recent(); recent gruppiert aktuell nach label und wählt MAX(id). Das genügt nicht für gleichnamige unterschiedliche Produkte oder verlässliche zeitliche Reihenfolge. Auf stabile Definition-/Snapshotidentität und actual created_at/at_ts umstellen; keine zwei Produkte wegen gleicher Beschriftung zusammenführen. Favoritpersistenz ergänzen; keine parallele zweite Lebensmitteldatenbank. Historische unbekannte Nährwerte bleiben beim Wiederverwenden unbekannt, bis ausdrücklich ergänzt.

Sammlungssuche arbeitet im gewählten Filter und hat leere Treffer mit klarer Neuanlage; Suchzustand und Filter bei Detailrückkehr behalten. Recipe-/Food-Erfolg führt zur passenden gefilterten Sammlung. Die separate Favoritenvariante merkt Haferfrühstück (450 kcal, 22/60/14 g je Portion); Rezept 450 kcal, 29/52/11 g bleibt eigenständig. Die neu gestalteten GXG/KD3/MSF ersetzen ihre alten Sammlungsinhalte. Keine Änderung der Basistageswerte.

## B106 · Nickerchen mit eigener Herkunft

**Aus Flow 105.** Ein Nickerchen ist eine eigene Schlafsession mit Art, lokaler Zeitspanne, Quelle und optional zugeordneten Messdaten. Die Detailansicht darf eine eigene Zeitangabe nicht als gemessene Schlafdauer oder Schlafphasen ausgeben. Vorhandene manuelle Schlafzeit aus B31 wiederverwenden; Session-ID für Bearbeiten/Entfernen, bestätigte lokale Transaktion, keine Löschung von Rohdaten.

**Synthetische bestehende Variante:** 14. September 14:10–14:35, 25 Minuten eigenes Zeitfenster, Puls und Phasen offen. Nacht 14./15. bleibt 7h18 Schlaf in 7h44 im Bett. Bei später passenden Messdaten Quelle, Verknüpfung und berechnete Dauer getrennt erhalten; gemessene Segmente dürfen die eigene Angabe nicht still überschreiben. Überschneidungen werden in der Schlafkorrektur aufgelöst.

Kein pauschales +25 Minuten auf eine Schlafbank oder auf den Hauptschlaf. Eine künftige Bedarfs-/Schuldenberechnung müsste versioniert festlegen, wie Nickerchen einfließen, und ihre Eingänge zeigen. Löschen kehrt zur Sessionliste zurück, bei Fehler bleibt der Eintrag sichtbar; der Bestätigungsdialog benennt genau den eigenen Eintrag.

## B107 · Energiebilanz aus kompatiblen Tageswerten

**Aus Flow 106.** Zufuhr minus Gesamtverbrauch nur für denselben lokalen Zeitraum und brauchbare Eingänge. Zielkalorien sind kein Verbrauch. Partielle Morgenwerte und offene Lebensmittel erzeugen keine abgeschlossene Defizit-/Überschussdiagnose. Im Basistag bleibt die Bilanz offen (≥620 kcal, Verbrauchsergebnis fehlt); spätere bekannte Eingänge ändern sie nachvollziehbar.

**Bestand geprüft:** DerivationEngine.wakeDayEnergy berechnet aktive, basale und gesamte Energie gemeinsam; Calories.dailyEnergy verlangt Profilanker, Maximal- und Ruhepuls. Diesen gemeinsamen Vertrag weiterverwenden, keine zweite TDEE-Berechnung in der UI. Gesamt = basal + aktiv, Trainingskalorien niemals noch einmal addieren. Zeitabdeckung, Eingangsquelle, Gerätefamilie, Profilversion und Schätzmethode mit dem Ergebnis transportieren. Grundumsatzmodell füllt keine unbekannte Aktivität mit scheinbar gemessener Energie.

**Separates reines Darstellungsschema, kein ausgeführter Algorithmustest:** 13. September, vollständige eigene Zufuhr 1.900 kcal, verfügbarer geschätzter 24-Stunden-Gesamtverbrauch 2.300 kcal, Differenz −400 kcal. Diese Werte sind illustrativ und kein Nachweis physiologischer Genauigkeit oder verfügbarer Sensordaten. Der Basistag und andere 13.-September-Trainingsdaten werden dadurch nicht verändert. Vor Implementierung verfügbare/teilweise/fehlende Zeiträume, doppelte Aktivitäten, Zeitzonenwechsel und externe Quellen nach denselben Regeln auswerten. Wochenmittel nennen gültige Tage statt Lücken als Null zu zählen.

## B108 · Ernährungsbereich als durchgehender Tagesablauf

**Aus Flow 107.** Ernährung ist eine Detailstrecke aus Übersicht oder Journal, mit Zurück zum Ursprung, auswählbarem Datum und Bereichsmenü. Stabile vier Tabs gehören zu den Hauptbereichen; diese tiefere Strecke hat eine klare Zurücknavigation. Oberer Bereich: bekannte kcal/Makros, gezielter Hinweis auf fehlende Angaben, Beschreiben/Foto/Suchen, Mahlzeiten und Sammlung. Der Inhalt scrollt weiter zu Makros, Energiebilanz, Woche, eigenen Zielen und Tagesabschluss. Kein abgeschnittener Endpunkt nach dem ersten Bildschirm.

4XB und FR6 sind neu aufgebaut; FR6 zeigt nur einen zusätzlichen bestätigten Speicherbeleg. Beide enthalten auch die Inhalte unterhalb des sichtbaren Ausschnitts. 154L zeigt deren Fortsetzung. 51R ersetzt die nicht belegte alte Beispielwoche: 9.–15. September nur ein Tag mit Einträgen, null abgeschlossene Tage, kein Mittelwert. 159R zeigt den separaten leeren Erstzustand.

Alle Ansichten beziehen denselben NutritionDay-Vertrag aus B05/B103/B107. Der bekannte 620-kcal-Teilwert wird nicht durch Ziele oder Tagesabschluss zur vollständigen Messung. Die bereits vorhandene Logik für vollständige Tage aus nutrition_screen.dart weiterverwenden und um feldweise Vollständigkeit/Eintragsquellen ergänzen. Tagesabschluss ist eine eigene Nutzerbestätigung; neue oder geänderte unvollständige Einträge heben ihn nachvollziehbar auf. Einträge bearbeiten, Sammlung öffnen und Foto-/Textentwurf behalten Datum und Rückkehrort.

Glukose erscheint im Ernährungsbereich nur bei eingerichteter Quelle bzw. ausdrücklicher aktivierter Karte; kein dauernder Sensor-Upsell im Basistag. Kein pauschaler Nutrition-Score aus unbekannter Methode; die eigenständige Entscheidung folgt Flow 109. Scrollposition je Datum erhalten, neue Speicherbestätigung darf den Nutzer nicht ungewollt zu einem anderen Tag verschieben.

## B109 · Ernährungsdarstellung und Health-Freigaben

**Aus Flow 108.** Bereichsmenü verlinkt Darstellung/Daten, eigene Ziele und Tagesabschluss. Eine persistente Kartenpräferenz steuert Ernährung in Übersicht und Journal; Ausblenden löscht keine Einträge, Definitionen oder Ziele. Wiederzugang über Einstellungen → Anpassen → Ernährung bleibt immer vorhanden. Zielanzeige ist getrennt vom Zielwert und seiner historischen Gültigkeit.

Glukoseanzeige verlangt eingerichtete, erlaubte Quelle und bleibt separat vom Quellimport und von Ernährungsbewertungen. Apple-Health-Schreiben unterscheidet gewünschten Umfang, tatsächlich erteilte Schreibrechte je Typ und letzten erfolgreichen Export. Energie/Makros und weitere Nährstoffe sind Vorauswahlgruppen, keine Behauptung einer pauschalen iOS-Freigabe. Keine Null für unbekannte Werte exportieren. Gemeinsamen B63-Exportvertrag um Ernährungstypen ergänzen; Quelle/Entry-ID verhindert Rückimportschleifen und Doppelbuchung. Bearbeiten/Löschen muss den eigenen exportierten Datensatz nachvollziehbar aktualisieren, ohne fremde Health-Einträge zu löschen.

Freigabe nicht erteilt, teilweise erteilt, nachträglich entzogen, Schreibfehler und bereits exportierter Eintrag bleiben unterscheidbar. Die gezeigte Auswahl ist noch nicht autorisiert und schreibt nichts vor Systemfreigabe. Später kehrt ohne geänderte Berechtigung zurück. Sichtbarkeitsänderungen sind sofort rückgängig möglich.

## B110 · Ernährung einordnen ohne pauschale Qualitätsnote

**Aus Flow 109.** Bevel reduziert Lebensmittelqualität und teils Glukoseeffekte auf einen Nutrition Score mit persönlichem Bereich, Verteilung und Trends. Diese konkrete Zahl und die Schwellen werden nicht übernommen. Für OpenBand ist die Produktentscheidung eine nachvollziehbare Darstellung einzelner Mengen, eigener Ziele, Vollständigkeit und persönlicher Verläufe. Ein zusätzlicher Gesamtscore würde diese unterschiedlichen Aussagen verwischen, auch wenn beliebig viel Backend-Arbeit möglich wäre.

Kein permanenter leerer Score-Kreis und keine künstliche Score-Bereitschaft. Die freien Flächen dienen Einträgen und konkreten nächsten Schritten. Analytics-/Edge-Suche nach nutritionScore/foodQuality/glycemic ergab keinen vorhandenen gleichartigen Vertrag; das ist Bestandsbefund, nicht alleinige Begründung. Falls später eine Ernährungsbewertung gewünscht wird, braucht sie separat gewählte und evaluierte Methode, erklärbare Beiträge, Quellenrechte, Vollständigkeitsregeln und eine neue Designentscheidung. Glukose allein ist kein allgemeines Qualitätsurteil über eine Mahlzeit. Bestehende Makro-/Nährstoff-/Zielansichten ersetzen den fremden Score-Ablauf.

## B111 · Nährstoffbeiträge und bestätigte Erfassung

**Aus Flow 110.** Suchbare Tagesliste mit Nährstoffschlüssel, Einheit, bekannter Summe, fehlenden Entry-IDs und optionalem datiertem Ziel. Energie und Makros öffnen denselben Beitragsaufbau; bekannte 450 + 170 kcal bzw. 14 + 4 g Fett bleiben Teilmengen, wenn Kaffee fehlt. Eigene isolierte Nährstoffangaben sind eigene Ereignisse und erzeugen nicht automatisch andere Nährwerte. Zielrichtung (Mindestmenge, Obergrenze, Bereich) bestimmt die Darstellung; kein pauschales Noch-X-übrig für unbekannte Intake-Werte.

**Präzisierung zu B108:** Bestätigung Alle Mahlzeiten erfasst und feldweise Nährwertvollständigkeit sind unabhängig. Nutzer dürfen ihre Erfassung bestätigen, obwohl ein Eintrag unbekannte Nährwerte hat. Das ist keine nachgewiesene Vollständigkeit der Zufuhr und qualifiziert den Tag nicht für einen vollständigen Kalorienmittelwert. Neue/entfernte Mahlzeiten öffnen die Erfassung wieder; reine Ergänzung eines vorhandenen Nährwerts aktualisiert dessen Abdeckung, ohne automatisch eine neue Mahlzeit zu behaupten. Speicherung beider Zustände atomar mit Zeitstempel; Wiederöffnen löscht keine Einträge.

Eine Woche zählt gültige Tage pro Nährstoff statt mit einem einzigen pauschalen Complete-Flag. Bereits vorhandene vollständige-Tage-Logik an diese Semantik angleichen. Im bestätigten synthetischen Basistag bleibt ≥620 kcal und kein vollständiger Kalorientag, solange Kaffee offen ist. Bereichsmenü enthält Alle Nährwerte als sichtbaren Einstieg. Weitere Vitamine/Mineralstoffe nutzen den bereits gestalteten Nährstoffkatalog und dieselbe Detailkomponente; fehlend bleibt offen.

## B112 · Zielverlauf, Mindestziele und Obergrenzen

**Aus Flow 111.** Zielwert, Einheit, Richtung und Gültigkeitsintervall gehören zusammen. Historische Ansichten verwenden die damals gültige Version. Neue Vorgaben ab 15. September zeichnen keine rückwirkende Ziellinie über 9.–14. September. B30/B76 liefern Editor und geplante spätere Änderungen; die neue Verlaufsansicht zeigt diese zeitliche Semantik ausdrücklich.

Die bekannte Variante bleibt 2.000 kcal / 125 g Eiweiß / 240 g Kohlenhydrate / 60 g Fett. Bekannte Mindestmengen sind 620/36/80/18, ohne genaue Restmenge. Fortschrittsbalken zeigen den bekannten Anteil, ohne unbekannte Bestandteile zu unterschlagen. Überschreiten nicht abschneiden oder automatisch moralisch bewerten.

Separate weitere-Ziele-Variante kombiniert die bereits entworfenen eigenen Vorgaben: Ballaststoffe mindestens 25 g, Menge offen; Zucker höchstens 30 g, bekannte Menge ≥8 g. Unbekannte Gesamtmenge erlaubt keinen Erfüllt-/Unter-Grenze-Status. Ein bekannter Mindestbetrag oberhalb einer Obergrenze kann dagegen die Überschreitung sicher belegen; diese asymmetrische Regel gehört in den gemeinsamen Zielvergleich. Wert 0, unbekannt, keine Vorgabe und deaktivierte Zielanzeige sind unterschiedliche Zustände.

Leere Ziele, Bearbeiten in g/%, Zeitraum, bekannte Teilmenge und zusätzliche Zielarten sind als konkrete Screens vorhanden. Alle Vorgaben bleiben nutzereigen; keine bedarfsbezogene Empfehlung aus diesen synthetischen Zahlen. NL7 ist die aktualisierte Zielübersicht nach dem Speichern, kein eigener zweiter Datenstand.

## B113 · Häufige Journaleinträge anheften

**Aus Flow 112.** Journalmenü erhält Oben im Journal. Geordnete Liste stabiler aktiver Feld-/Gewohnheits-IDs getrennt von Antworten und täglichen Einträgen speichern. Anheften beeinflusst die Sichtreihenfolge für alle betrachteten Tage, nicht historische Antwortwerte. Deaktivierte Felder verlieren ihre sichtbare Platzierung, behalten aber Daten; Wiederaktivieren stellt keine erfundenen Antworten her.

Die Auswahl zeigt eigene Gewohnheiten und Eingabearten mit eigener Bedeutung. Beobachtete Schritte oder Schlaf sind Messwerte, keine automatisch beantworteten Ja-/Nein-Tags. Eigene Reihenfolge und aktive Feldliste sind zentral zu persistieren, statt getrennte Listen für Journal, Übersicht und Einstellungen zu pflegen. Ohne angeheftete IDs gilt die gestaltete Standardreihenfolge. Abbrechen verwirft nur den Auswahlentwurf, Fertig speichert atomar. Lizenzierter Lucide-pin aus demselben festgehaltenen Commit ergänzt das Iconpaket (89 SVGs).

## B114 · Angeheftete Gewohnheit im Tagesjournal

**Aus Flow 113.** Einzelne Gewohnheit bietet Platzierung und Pin-Zustand. Änderungen speichern aktualisiert die B113-Reihenfolge atomar und kehrt ins Journal am bisherigen Datum zurück. Abbrechen behält alte Platzierung; Nicht mehr anheften entfernt nur die Pin-ID. Rückkehr an die normale Position ohne doppelte Darstellung.

Gezeigte Variante heftet Abends gelesen oben an. Antwort bleibt offen; Ja/Nein/Offen ändern nur die Gewohnheitsantwort für den ausgewählten Tag. Tagesgruppe Abends organisiert Anzeige/Erinnerung, verschiebt weder Daten in eine andere Nacht noch Assoziations-Lags. Angeheftete Eingabe bleibt eine einzige zugängliche Steuerung mit ausgeschriebenen Antwortzuständen. Eigene Beobachtungen und Quellenwerte werden nicht als automatisch bestätigte Ja-Antworten dargestellt. Journal-Ernährungszeile präzisiert auf 2 mit Nährwerten statt vermeintlich vollständig.

## B115 · Trainingsvorlagen anheften

**Aus Flow 114.** Vorlagen-ID und geordnete Pin-Liste getrennt von abgeschlossenen Workouts speichern. Basisszene Ganzkörper A enthält vier Übungen und zwölf geplante Sätze. Ihre angeheftete Karte zeigt den Planumfang, keine angeblich geleistete Tonnage. Die 3.300 kg darüber bleiben ausschließlich die abgeschlossene Kraftsession mit neun Sätzen.

Anpassen bei den Vorlagen öffnet die Pin-Auswahl; Alle öffnet die Sammlung. Auswahl speichern aktualisiert die Reihenfolge und kehrt an dieselbe Scrollposition zurück. Leere Auswahl fällt auf normale Sammlungsreihenfolge zurück. Entfernen eines Pins löscht weder Vorlage noch Trainingshistorie. Archivierte/entfernte Vorlage aus sichtbaren Pins entfernen, historische Sessions bleiben mit eigenem Snapshot erhalten. Aktuelle Template-Speicherung um stabile Pinpräferenz ergänzen, keine zweite Vorlagenstruktur. Auswahl von mehreren Vorlagen benötigt eine explizite Reihenfolge und barrierefreie Verschieben-Aktionen neben Ziehen. Einstieg in ein Training ist weiterhin eine eigene Aktion und startet nicht beim Anheften.

## B116 · Letzte Sätze während eines aktiven Trainings

**Aus Flow 115.** Letzte Sätze ist ein lesender Vergleich aus der laufenden Übung. Neueste abgeschlossene Einheit derselben stabilen Übungs-ID, Geräte-/Griffvariante und Lastkonvention suchen, nicht bloß denselben Anzeigenamen. Eigene Kopien einer Standardübung sind nicht automatisch identisch. Nur tatsächlich abgeschlossene Sätze zeigen; keine geplanten oder verworfenen Sätze als Historie.

Synthetisches Bankdrücken vom 13. September: drei Arbeitssätze à 8 Wiederholungen mit 40 kg Gesamtlast = 960 kg Volumen. Fehlende RPE-Werte werden nicht erfunden. Ausfallschritte mit Körpergewicht haben in der leeren Vergleichsvariante keine vorherigen Sätze. Gesamtlast, je Hantel, Zusatzgewicht und Haltezeit benötigen dieselben erklärten Einheiten wie B91.

Öffnen/Schließen verändert weder aktiven Satz noch Timer, pausiert nicht still und markiert nichts als abgeschlossen. Zurück kehrt genau zur laufenden Übung zurück. Für den nächsten Flow zum Trainingsstart wird dieser Vergleich als Aktion am Übungsblock verdrahtet. Eine spätere explizite Übernahme als Plan wäre ein eigener bestätigter Draftschritt, kein Nebeneffekt dieses Lesedialogs.

## B117 · Hauptschlaf mit Phasen und nächtlichen Verläufen

**Aus Flow 116.** Hauptschlaf ist eine eigene datierte Sessiondetailstrecke aus Schlaf oder Erholung: Dauer, Bettfenster, Schlafanteil, kurze persönliche Einordnung, zeitproportionale Phasen, Korrektur, Messwerte und Datenbasis. 16RN enthält den durchgehenden Inhalt; 16UZ zeigt die Fortsetzung. Der Screen ist keine einzelne statische Endkarte. Primäre Dauer statt kopiertem Schlafscore; dessen Produktentscheidung folgt Flow 136.

**Nachvollziehbare synthetische Darstellung:** sleep-detail.json ergänzt dieselbe Basisszene. 14 zusammenhängende Segmente decken 464 Minuten ab; REM 123 + Leicht 247 + Tief 68 = 438 Minuten Schlaf, Wach 26. Schlafanteil 438/464 = 94,3966 %, Anzeige 94 %. Ausgewählter Leicht-Abschnitt 02:00–03:02 = 62 Minuten. Die SVG-Breite folgt den tatsächlichen Minuten. Tooltip und barrierefreie Abschnittsliste verwenden dieselben Segmentdaten. Eine Zeitkorrektur ist keine manuelle Phasenetikettierung.

Puls-, HRV- und Atemkurven sind explizit synthetische Darstellungsreihen. Nachtwerte 54 /min Ruhepuls, 48 ms HRV und 16 /min Atmung stammen weiterhin aus der kanonischen Beispielzusammenfassung und wurden nicht aus diesen Illustrationsreihen neu abgeleitet. Insbesondere ist Ruhepuls nicht gleich Durchschnitt des Nachtverlaufs. Bei der Umsetzung Fenster, Aggregation, Methode, Einheit und persönliche Basis aus einem nachvollziehbaren Ergebnisvertrag beziehen. Rohwerte, geglätteter Verlauf und Nachtzusammenfassung nicht austauschbar behandeln.

HRV hat 11/16 verwertbare Fenster. Linien werden an null-Werten unterbrochen; vollständige Zeiterfassung ist keine vollständige Metrikabdeckung. Sauerstoffsättigung bleibt ohne verwertbare Quelle offen, mit weiter erreichbarem Metrikwechsel. Einschlafdauer bleibt ohne Marker des Einschlafversuchs offen; Beginn der Bandaufzeichnung oder erste Phase reichen nicht zur Ableitung. Kein Ersatzwert und keine Gleichsetzung von 26 Minuten Wachzeit mit Einschlafdauer.

Quelle/Berechnung öffnet die vorhandenen metrikspezifischen Erklärungen und zeigt Geräte-/Importquelle, verwertbare Abschnitte, Algorithmusversion und Grund der Bereitschaft. Schlafkorrektur bleibt Session-basiert, Rohdaten erhalten; Rückkehr erneuert nur betroffene Ergebnisse nach erfolgreichem Commit. Prüfung hier: Phasensummen, Lücken und Darstellung; kein Hardware- oder physiologischer Nachweis.

## B118 · Eine aktuelle Schlafdetailstrecke statt alter Parallelansicht

**Aus Flow 117, ausdrücklich als old katalogisiert.** Frühere Bevel-Darstellung hat denselben Einstieg, aber lange Qualitätsbeiträge und pauschale REM-/Tiefschlafurteile. Keine zweite Legacy-Ansicht in OpenBand. Alle Hauptschlaf-Einstiege führen in B117; kurze Einordnung bleibt an konkrete eigene Vergleichswerte gebunden. 36 Minuten über dem bisherigen oberen Quartil ist nachvollziehbar, eine unbelegte Aussage schlechter REM-Schlaf nicht.

Historische algorithmische Ergebnisse behalten Methoden- und Versionsherkunft, werden aber in demselben aktuellen UI angezeigt. Eine Neuberechnung ist eine bewusst nachvollziehbare Operation und kein stiller Austausch alter Zahlen. Im finalen Screeninventar alte Schlafparallelentwürfe ersetzen oder entfernen, statt sie als zusätzliche aktuelle Variante stehen zu lassen.

## B119 · Erholung als zusammenhängender Detailweg

Flow 118: Übersicht → Erholung → Nacht / Einflüsse / Verlauf. AMX-1 behält denselben synthetischen Composite 74; HRV 48, Ruhepuls 54, Atmung 16 und Basis 40/56/16. 17G5-0 zeigt 15 tatsächliche Fixturewerte statt dekorativer erfundener Trends; für Erholung liegt nur ein berechneter Tag vor. BGD-1 zeigt Modellbeiträge, keine Score-Punkte. Hauttemperatur bleibt unverfügbar.

Benötigt: datumsgebundener RecoveryDetail mit Ergebnisversion, verwendeten Eingängen, Baseline-Zeitraum, Gewichtung und Quelle; Historien je Messwert mit eigenen Lücken und Vergleichbarkeit. Rückkehr bewahrt Ursprung/Scrollposition, Detailseiten besitzen keinen zweiten Tabrahmen. Nachtlink öffnet 16RN-0; Schlafdauer wird nicht als direkte Recovery-Eingangsgröße behauptet. Grafik und Fixture prüfen keine physiologische Gültigkeit.

## B120 · Kartenreihenfolge als gespeicherte Ansicht

Flow 119 übernimmt Bevels Entwurf → Verschieben → Speichern → normaler Feed. LUP/YKF/YMJ zeigen Drag-Alternative über Nach oben/unten im Kartenmenü; 17IL-0 zeigt Journal vor Stress nach gespeichertem Entwurf. Tagesüberblick bleibt als Produktentscheidung oben, weitere Module sind anpassbar. Ausblenden löscht keine Daten.

Geordnete stabile Modul-IDs und Sichtbarkeit in einer atomar gespeicherten Ansichtspräferenz; Entwurf isoliert, Abbrechen verwirft, Fehler erhält Entwurf und bisherige Ansicht. Auch ohne Ziehen vollständig bedienbar: 44-Punkt-Menü, VoiceOver-Verschiebeaktionen, Ansage der neuen Position. Rückkehr zur betroffenen Karte mit unverändertem Datum. Globale Ansichtspräferenz nicht an Tagesdaten binden. Neu hinzugekommene Modultypen werden deterministisch in verfügbare Karten einsortiert, keine automatische Umordnung bestehender Präferenzen.

## B121 · Prioritäten je Datenart und nachvollziehbare Neuberechnung

Flow 120: Quellenkatalog → Schlafquellen → Reihenfolgeentwurf → gespeichert mit Berechnungsstand. Eigene Mehrquellenvariante: WHOOP plus Schlaf-App über Health; keine zusätzliche reale Quelle oder geänderte Nachtzahl behauptet. Prioritäten, Ein-/Ausschluss, OS-Leserecht, Importzustand und Ergebnisherkunft sind getrennte Daten.

Benötigt: geordnete stabile Source-IDs pro Datenart und versionierte Auswahlregeln. Deduplizierung nach Originalquelle/Datensatz-ID verhindert Reimport eigener Health-Exporte. Schlafsession-Auswahl muss kohärente Phasen und Grenzen verwenden; keine beliebige Vermischung widersprüchlicher Phasen verschiedener Quellen. Lücken auffüllen nur nach ausdrücklich definierter, prüfbarer Fusionsregel samt Segmentherkunft; bis dahin offene Abdeckung. Unverwertbare Daten werden durch höhere Priorität nicht verwertbar.

Atomarer Präferenz-Commit stößt idempotente Neuberechnung betroffener Fenster an; alte Ergebnisse als vorherigen Stand kennzeichnen, Fehler und Wiederaufnahme zeigen über vorhandenen Berechnungsstand W8J/WCS/WH8. Quellenwechsel löscht keine Originaldaten oder Nutzerkorrektur. Drag und Verschiebeaktionen sind gleichwertig; Abbrechen verändert keine Auswahlregel. Das ist eine erhebliche gemeinsame Daten- und Ableitungsanforderung, keine reine Sortierung von UI-Karten.

## B122 · Übungsreihenfolge im Vorlagenentwurf

Flow 121: DDO-Reihenfolgeaktion → 17SF-0 Editor → 17UW-0 zurück im Vorlagenentwurf. Variante stellt Kniebeuge vor Bankdrücken, Rudern und Plank; vier Übungen/zwölf geplante Sätze bleiben identisch. Last, Wiederholung, Satztyp, Pause und stabile Exercise-Instance-ID reisen mit dem Block. Reihenfolge übernehmen verändert nur den Vorlagenentwurf; Vorlage speichern ist die dauerhafte Transaktion.

Gruppierte Supersätze als Block verschieben, keine unbemerkte Trennung; Gruppen-internes Umordnen benötigt eigene Aktion. Vorlagenrevision und laufende/abgeschlossene Session-Snapshots trennen. Drag, Menü und VoiceOver-Aktionen müssen dieselbe Operation auslösen. Rückkehr zu bearbeiteter Übung statt Listenanfang. Bereits abgeschlossene Sätze werden durch Umordnung nicht neu nummeriert oder überschrieben.

## B123 · Übung ersetzen ohne falsche Lastübernahme

Flow 122: Übungsmenü → Einzelwahl → Folgen prüfen → neuer Block im Vorlagenentwurf. Beispiel ersetzt Langhantelbankdrücken durch Kurzhanteln. Drei Satzplätze und 8 Wiederholungen bleiben, Gewicht je Hantel ist offen. Kein rechnerisches 40/2: Lastkonvention und tatsächliche Eignung unterscheiden sich. Vier Übungen/zwölf geplante Sätze bleiben.

ExerciseDefinition-ID, Gerätevariante und Messschema müssen den Editor bestimmen. Nur kompatible Planfelder übernehmen; Wiederholungen↔Haltezeit oder Strecke wechseln zu passenden leeren Vorgaben statt falschen Zahlen. Ersetzen als reversible Draftoperation mit altem Snapshot. Vorlagenspeicherung erzeugt neue Revision, Historie behält alte Übungsidentität. Im laufenden Training nur unbegonnene Planblöcke ersetzen; abgeschlossene Sätze bleiben unter ursprünglicher Übung, neue Übung erhält getrennte Instanz. Supersatzbindung bewusst erhalten oder Konflikt vor Übernahme erklären.

## B124 · Problembericht mit geprüftem Inhalt und bestätigtem Eingang

Flow 123 aus dem Vorlageneditor: Beschreibung/optionales Foto → Inhaltsprüfung → senden → bestätigter Eingang oder erhaltener Fehlerentwurf. Technische Angaben sind separat opt-in, im Beispiel ausgeschaltet. Keine Gesundheitswerte, Rohaufzeichnungen, freie Logs oder Kontaktdaten automatisch anhängen. Fotoauswahl verwendet denselben prüfbaren Anhangsablauf wie B129. Entwurf schließen bewahrt den lokalen Entwurf und kehrt zur unveränderten Vorlage zurück.

Neu erforderlich: klar verantworteter privater Support-Empfänger und betriebener Intake vor Aktivierung dieses Features. Kein bestehender Endpunkt wurde behauptet. Lokaler Draft mit Kategorie/Route, Freitext, geprüften Anhängen, optionalen freigegebenen Diagnosedaten; Serververtrag mit idempotenter Submission-ID, Abruf des Eingangsstatus und bestätigter Referenz. Bei Antwortverlust erst Status abgleichen, nicht blind doppelt senden. Nur sicher nicht gesendeter Zustand heißt Nicht gesendet; mehrdeutiger Zustand muss Eingang wird geprüft anzeigen. Referenz OB-2026-015 ist ausschließlich synthetisch.

Anhänge auf Größe/Typ prüfen, Metadaten entfernen, Vorschau und Entfernen anbieten, Fristen und Datenschutzinformationen am tatsächlich betriebenen Kanal ausweisen. Offline-Draft bleibt bearbeitbar; keine automatische spätere Übertragung ohne explizit gewählten Sendeauftrag. Textpflicht vor Bericht prüfen, Fehler am Feld, Tastatur darf primäre Aktion nicht verdecken. Kein Konto nötig; Antwortkontakt nur optional und explizit. In dieser Designphase wurde nichts versendet.

## B125 · Kontextwissen statt kopierter Ressourcenartikel

Flow 124 übernimmt den Weg vom Messwert in eine kurze bebilderte Erklärung, nicht Bevels Text oder physiologische Versprechen. 18A5-0 erklärt die eigene Belastungsskala und führt zur Methode mit verwendeten Daten. Quelle der Produktbeschreibung: analytics/lib/src/onehz/clinical/load_trimp.dart, strainScore/strainScoreMetric, aktuell erneut gelesen. Persönliche ruhige Wachbasis ist erforderlich; eine feste populationsbasierte Ersetzung ist unzulässig.

Kleine lokal verfügbare, redaktionell versionierte Wissensinhalte je Metric-ID/Algorithmusversion: Kurzdefinition, interpretierbare Illustration, Eingänge, Grenzen und Quellen. Keine notwendige neue Content-Cloud und kein Konto. Künftige wissenschaftliche Aussagen brauchen fachlich geprüfte Primärquellen; diese Designtexte beschreiben nur die eigene Berechnung. Artikel öffnen modal/push aus Kontext und kehren zur vorherigen Messwertposition zurück. Dynamische individuelle Werte stammen aus demselben Resultat, nicht hartkodiertem Artikel. Lesezeit, Sprachversion und Revisionsdatum sind Inhaltsmetadaten.

## B126 · Vorlage speichern und danach ausdrücklich starten

Flow 125: Editor → persistierte Vorlagendetails → separates Training starten. 18C9-0 zeigt Ganzkörper A mit vier Übungen/zwölf geplanten Sätzen; Speichern startet keinen Timer. 18F1-0 erhält den Entwurf bei lokalem Schreibfehler. Neue-Reihenfolge- und Ersatzvarianten aus B122/B123 nutzen denselben Speichervertrag mit ihren jeweiligen Werten, keine zusätzliche Kopie der Datenstruktur.

Vorlagenkopf, Übungsreihenfolge, Satzvorgaben, Gruppen, Pausen und Lastkonvention in einer atomaren Revision speichern. Erfolg erst nach lokalem Commit, bei Fehler vorherige Revision unverändert. Erneuter Tap erzeugt keine zweite Vorlage; neue Vorlage bekommt einmalig eine stabile ID. Start erstellt einen unveränderlichen Plansnapshot im separaten Workout, tatsächliche Sätze bleiben leer bis bestätigt. Ungespeicherter Entwurf verlangt vor Start Speichern/Verwerfen/Zurück. Teilweise offene Lastvorgaben sind gültige Pläne, keine absolvierten Null-Kilogramm-Sätze.

## B127 · Eigenes Enddatum für Aktivitätsstatus

Flow 126 ergänzt B50 um konkreten Kalender 18G9-0 und gespeicherten Status 18K1-0. Eigene Variante: Trainingspause 15.–23. September 2026, inklusive Endtag in Europe/Berlin; technisches Ablaufdatum 24. September 00:00 lokal. Datum übernehmen verändert nur den inneren Entwurf, Status speichern die persistierte Statusrevision. Keine Verwechslung mit der Basisvariante Pause nur am 15. September.

Datumsgrenzen/DST aus lokaler Zone ableiten, nicht durch feste Stundenanzahl. 7 Tage ab 15. September enden einschließlich 21. September; Kalender startet montags. Kein Enddatum vor Beginn. Bis ich es ändere bleibt endlos, Zurück/Abbrechen lässt gespeicherten Status unangetastet. Nach Ablauf keine Diagnose Genesung; B50 regelt unterschiedliche Rückkehr bei Trainingspause vs. selbst berichteter Krankheit/Verletzung. Geplante Benachrichtigungen vor Auslieferung nochmals gegen gültigen Status prüfen.

## B128 · Rückmeldung zu einer einzelnen Coach-Antwort

Flow 127 ergänzt pro Antwort Kopieren/Rückmeldung, Kategorien, freiwilligen Hinweis, Inhaltsprüfung und bestätigten Eingang. Die Antwort bleibt unverändert; Rückmeldung ist weder eine neue Modellanweisung noch eine garantierte automatische Lernfunktion. Default-Anhang aus: weder Gespräch noch Gesundheitswerte gehen mit. Explizites Anhängen einer Antwort benötigt Volltextvorschau und gegebenenfalls Entfernen einzelner persönlicher Abschnitte.

B124-Intake mit lokaler, stabiler Message-/Feedback-ID und idempotenter Sendetransaktion wiederverwenden. Im nur lokal betriebenen Coach darf keine Support-Cloud still aktiviert werden; Empfänger und Übertragung sind im Prüfschritt klar benannt. Abbrechen erhält Gespräch/Scrollposition, Offline-Fehler erhält den Feedbackentwurf; shared Fehlerzustand 187R trägt kontextabhängigen Titel und Rückweg. Anhänge, Modellbezeichnung und technische Diagnose nur nach expliziter Auswahl. Bestätigter Eingang erst mit Serverbeleg, bei Antwortverlust Status prüfen.

## B129 · Fotos im Coach und gemeinsame Anhangsvorschau

Flow 128: Kamera/Systemfotoauswahl → sichtbarer Nachrichtentwurf mit Entfernen → ausdrücklich Senden → Fotoantwort; zusätzlich Modell ohne Bildfähigkeit. Ein synthetisches eigenes Mahlzeitenbild ist wiederverwendet, keine Bevel-Aufnahme. Text-/Bildteile erhalten stabile Attachment-IDs, lokale temporäre Dateien und Lebenszyklus bei Entfernen, Abbruch, Sendefehler und Gesprächslöschung. Kein stiller Upload schon beim Auswählen.

Benötigt: multimodaler Message-Vertrag und Capability-Abfrage/Probe des tatsächlich gewählten Heimnetz-/Cloud-Modells, begrenzte Bildgröße/Anzahl, Metadatenentfernung, nachvollziehbare Transportschritte. Bestehende Text-Coach-Suche zeigte keine gleichwertige Fotoanbindung; nicht nur ein Plus-Symbol anschließen. Kameraablehnung erlaubt Systemfotoauswahl; Teilzugriff verwenden statt Vollbibliothek verlangen. Modellwechsel darf Fotos nicht ohne erneutes Senden an neuen Empfänger schicken.

Streaming, Abbruch, Retry und gespeicherter Gesprächsverlauf teilen den B89-Vertrag. Fotoanalyse liefert Vorschläge mit Unsicherheit und keine automatisch gespeicherten Nährwerte. Mahlzeit als Entwurf öffnen geht in den vorhandenen Zutaten-/Portionsprüfpfad, Duplicate-IDs verhindern zweimaliges Loggen. Der Kamera/Fotowahl/Vorschau/Entfernen-Baustein gilt auch für Supportberichte B124, dort aber ohne Modellanalyse und mit anderem Empfänger. In dieser Phase wurde nichts hochgeladen oder gesendet.

## B130 · Vorgaben beschleunigen Eingaben, erzeugen keine Beobachtungen

Flow 129 zeigt automatisch vorbelegte tägliche Ja/Nein-/Mengenwerte. Bewusste Produktentscheidung: OpenBand übernimmt dieses automatische Tagesbefüllen nicht. Es würde fehlende Antworten wie tatsächlich beobachtete Werte aussehen lassen und die Assoziationen aus B93 verzerren. Stattdessen vorhandene Schnellmengen B51/B95/B100: Startmenge nur im Eingabeentwurf, Eintrag erst nach ausdrücklichem Speichern. Angeheftete Felder B113 und ein kompakter Tagesabschluss beschleunigen den Zugriff, ohne unbeantwortete Tage zu erfinden.

12SZ präzisiert diese Regel sichtbar. Mengenpreset, Tagebuchantwort und Tagesvollständigkeit sind getrennte Felder. Null Alkohol benötigt aktive Bestätigung (13WK), kein stilles 0 für jeden Tag. Ein künftiger Vorlagen-Mehrfacheintrag müsste immer einen datierten Prüfschritt mit einzelnen Bestätigungen haben, wäre aber keine Voraussetzung dieses Designs. Keine Backend-Automatik zum täglichen Erzeugen von Standardantworten bauen.

## B131 · Bandwecker mit Wunschzeit, Bestätigung und sauberem Ausschalten

Flow 130: bestehender Wecker → Zeit/Wochentage → geänderter Plan → getrennt/unbestätigt → 07:30 bestätigt; Ausschalten mit offenem und bestätigtem Gerätestand. Basisszene 07:00 bleibt in 5UV, eigene Bearbeitungsvariante 07:30 Mo.–Fr., nächster Termin Mittwoch 16. September. Keine echte Bandoperation wurde ausgeführt.

Erneut gelesen: edge/state/alarm_schedule.dart, AppState setAlarm/_onArmed/_onAlarmGraceElapsed und protocol AlarmStatus. Persistierter Wochenplan, gewünschter nächster Epoch, tatsächlich an Band geschriebener Epoch, bestätigter Epoch/Zeit und letzter Fehler sind getrennte Zustände. Ein Transporterfolg oder äußerer SUCCESS-Code beweist kein erfolgreiches Scharfschalten: inneren AlarmStatus und bestätigenden Geräteevent berücksichtigen. Runtime hapticsBusy bedeutet wiederum nicht automatisch unscharf. Statusabgleich vor dem Überschreiben neuerer Zeit, Neustart/DST und Reisezone explizit behandeln.

Der heutige Code speichert einen optimistischen Alarm-Epoch; für UI und Ausschalten einen nachvollziehbaren Desired/Observed-Vertrag schaffen. Bestätigte Deaktivierung darf nicht aus bloßem lokalen Löschen abgeleitet werden; Wiederholung nach Verbindungsabbruch muss vorherigen Gerätestand sichtbar lassen. Mehrtagesplan bleibt auf dem iPhone; nächste Gelegenheit muss übertragen werden. Wiederaufnahme darf keinen bereits deaktivierten Plan neu scharfstellen.

Bevels Smart-/Schlafbedarfswecker und Haptikintensitäten nicht ohne geprüfte WHOOP-5-Gerätefähigkeit versprechen. Substantielle Forschung/Backendarbeit ist erlaubt, aber ein Schlafphasenwecker braucht zuverlässige Echtzeitphasen und autonomen Auslösepfad bei gesperrtem iPhone sowie echte Hardwareprüfung. Bis dahin zuverlässig konzipierter fester Bandwecker; Vibration testen ist eine ausdrückliche Aktion mit eigenem Ergebnis. Keine Firmwareänderung in dieser Designphase.

## B132 · Einstellungen als vollständiger, ruhiger Navigationsweg

Flow 131: Profil → Einstellungen, fortgesetzte Gruppen, Datenschutz/optionale Dienste und Lizenzübersicht. Hauptinhalt 5OM und Fortsetzung 1980 sind derselbe Scrollweg. Aufteilung: Für dich; Aufzeichnen; Deine Daten; Hilfe/Informationen. Kein Konto-, Abo- oder Cloud-Sync-Kasten ohne tatsächliche Produktfunktion. Vorhandene Daten-/Backup-/Quellenwege bleiben erreichbar.

Aktuelle Settings-Implementierung erneut abgeglichen: Einheiten/Darstellung → bestehende Picker; Phone-Schritte → Quellen/Schritte; Health lesen/schreiben → Datenquellen/Health; Zyklus → Journal-Anpassen; Gesten/Automatisierung → Band bzw. Kurzbefehle; Telemetrie/Barcode → Datenschutz; Entwickleroptionen/Wartung → Weitere Optionen; Lizenzhinweise → lokal verfügbare Übersicht. App-Version aus PackageInfo, Beispielstand aus pubspec 0.9.29+65. Keine alte upstream-notice-URL als OpenBand-Verantwortlichen stehen lassen.

Quelle zeigte optionale Uploads der gesamten Gesundheitsdatenbank und Update-Dienst. Diese sind nicht Teil des neuen Standardprodukts: nicht durch bestehende Altpräferenz still weiterlaufen lassen. Bei einer künftig bewusst angebotenen Datenspende wären getrennte aufgeklärte Auswahl, geprüfter eigener Empfänger, Widerruf und belegter Umfang erforderlich. Aktuell lokale Datenhaltung mit ausdrücklichen Einzelübertragungen und optionalen gewählten Diensten. Keine Übertragung allein durch Besuch der Datenschutzeinstellungen.

Buildgenerierte Open-Source-Lizenzen offline bereitstellen; Lucide-/Feather-Hinweise und Inter-OFL sowie Datenanbieterherkunft erhalten. Exakte betriebene Dienste, Verantwortlichkeit, Datenfristen und Datenschutztext vor Veröffentlichung konkret ergänzen; diese Designansichten sind keine fertige rechtliche Erklärung. Elternroute und Scrollposition auf Rückkehr bewahren. Sprachwechsel ändert Formatierung, nicht gespeicherte Zeitzonen oder Messwerte.

## B133 · Trainingskarte mit echter Vorschau teilen

Flow 132: Aktivitätsdetail → gestaltete Exportvorschau → natives iPhone-Teilen-Menü. 19H9-0 verwendet denselben synthetischen Lauf 14. September, 5 km/25 Min./5:00 min pro km. Route und Puls sind einzeln optional und hier ausgeschaltet. Die Vorschau ist exakt die exportierte Karte, nicht ein Screenshot mit App-Bedienflächen. 19J7 erhält Auswahl bei Rasterisierungsfehler.

Vorhandenen activity/poster.dart-Export anschließen/überarbeiten. Einheit, Rundung, Herkunft und Teilabdeckung aus demselben Session-Snapshot; keine dekorativen erfundenen Routen oder Trainingswerte. Export in festem Seitenverhältnis mit eingebetteter lesbarer Typografie, semantischem Textäquivalent und Metadatenbereinigung. Synthetischer Beispielmodus bleibt auch im Export sichtbar. Optionale Route nur mit vorhandenen Koordinaten und expliziter Vorschau; Wohn-/Start-/Endpunkte müssen vor Auswahl verbergbar sein.

Erst Bild lokal erstellen, dann System-Share-Sheet. Abbruch ist kein Fehler. Rückkehr zeigt keinen behaupteten Versand an einen Empfänger; OS-Übergabe ist keine Zustellbestätigung. Temporäres Exportbild nach Nutzung aufräumen, Trainingsdaten bleiben. Native Share-Sheet-Ziele werden vom iPhone geliefert, keine eigenen Kontaktlisten/Cloud nötig.

## B134 · Kurzbefehle mit Datums- und Frischekontext

Flow 133: Einstellungen → Kurzbefehle → Abendroutine in Apple Kurzbefehle. 19KF bündelt lesende Abfragen und bewusstes Öffnen von Wecker/Atemübung; KLC ist aktualisierte Einrichtungsanleitung. Wecker öffnen schreibt keinen Alarm und behauptet keine aktivierte iOS-Fokusautomation. Fokusaktionen stellt der Nutzer in der nativen Kurzbefehle-App zusammen.

Aktuelle ios/OpenStrapIntents.swift gelesen: drei Messwertabfragen und Atemroute vorhanden, aber englische OpenStrap-Dialoge, globale 26h-Frische sowie unbekannter Zeitstempel als hasData erlaubt. Auf OpenBand, deutsche LocalizedStringResource und metrikspezifische datierte Snapshot-Verträge umstellen. Unbekannte Frische ist unbekannt, nicht aktuell; Abdeckung/Bereitschaft fehlen aktuell im gemeinsamen Snapshot. Antworten nennen Tag/Nacht, Stand und konkrete Lücke, negative Sentinelwerte nie vorlesen.

Wecker-Öffnen-Intent neu ergänzen, pending_route mit stabiler Route/ID beim Kaltstart und Foreground genau einmal konsumieren. Sperrbildschirm-/Siri-Ausgabe respektiert vom Nutzer gewählte Sichtbarkeit persönlicher Werte. Kein Bandereignis als funktionierender iOS-Automationsauslöser behaupten; aktuelle App nennt hier Android-Asymmetrie. Kurzbefehle-Ziel und Einrichtungsseite nativ prüfen, tatsächliche AppIntent-Registrierung/Sprachdialoge erst bei Implementierung nachweisen.

## B135 · Schlafübersicht, einzelne Nacht und Zeitprüfung klar trennen

Flow 134 ersetzt die alten Inhalte von 22Q und 187 vollständig: Schlafübersicht mit Datum, letzter Nacht, knapper Einordnung, persönlicher Planung und weiterem Verlauf; Hauptschlaf öffnet die aktuelle B117-Detailstrecke. 187 ist jetzt ausschließlich die Zeitfensterprüfung. Alte szenische Textunterlage, nicht zeitproportionaler Phasenstreifen und Tabnavigation auf Schlafdetails entfernt. 19QM zeigt die echte Fortsetzung von 22Q.

Ein gemeinsamer SleepDay-Kontext enthält Sessions samt Typ, Zeitzone, Grenzen, Quellen, Prüfstatus und verfügbaren Metriken. Acht Dauerwerte 8.–15. September sind vorhanden; REM/Tief/Schlafanteil nur für die letzte Nacht, daher keine erfundenen Trends. 36 Minuten Vergleich bleibt über dem oberen Quartil der sieben vorherigen Nächte. Hauptschlaf und Nickerchen getrennt, Tagessumme nur bei eindeutigem Bezug und ohne Überschneidungsdoppelzählung.

Planungskarte verwendet die zuvor entworfene eigene Zielvariante 8h ab 15./16. September (B45), niemals rückwirkend für 14./15. Schlafziel, physiologisch geschätzter Bedarf und Zeit im Bett sind verschiedene Größen. Der Wecker bleibt kanonisch 07:00 mit bestätigtem Stand 07:42; B131-07:30 ist separate Bearbeitungsvariante.

Zeiten bestätigen markiert nur Nutzerprüfung; Zeiten ändern öffnet JN, Vorschau/Speicherung/Neuberechnung bleiben eigenständige Zustände. Als Nickerchen einordnen bzw. Kein Schlaf ändern die Sessionklassifikation nach Vorschau und erhalten Originaldaten sowie rücknehmbare Revision. Keine manuelle Änderung der gemessenen Phasen durch reine Bestätigung. Datumsauswahl verwendet denselben Kalender/Tageskontext wie Übersicht, Rückkehr erhält Scrollposition.

## B136 · Schlafziel, geschätzter Bedarf und Zeit im Bett

Flow 135: Basiszustand 19TV zeigt eigenes Ziel 8h und Wecker07:00, aber keinen berechneten Bedarf ohne persönliche Basis. Separate reife Historienvariante 19W1/19Y9 mit sleep-plan.json: Basis8h +Rückstand30Min +Belastungsbeitrag3,4286Min −0Gutschrift = 8h33 gerundet. Bei persönlichem typischen Schlafanteil95% und Aufstehen07:00 ergeben sich 540,451Min Bettzeit, Beginn21:59:33 → ca.22:00.

Die tatsächlichen Funktionen sleepNeed, recommendedBedtime und recommendedWake wurden mit Dart ausgeführt; Resultate und direkte synthetische Eingänge liegen im Fixture. Das prüft Arithmetik/Rendering, nicht vorgelagerte OSD-/Rückstandsableitung oder physiologische Eignung. Keine Übertragung dieser Bedarfsschätzung auf die Basisszene ohne passende Historie.

Vorhandene crossday_pipeline verweigert fehlende persönliche OSD und typische Effizienz, richtig beibehalten. Bedarf ist ein datierter vorläufiger Forecast mit Datenstand, Beiträge samt Bereitschaft, genutzter Historie, Modellversion und Einschränkungen. Keine Null als bekannter Belastungsbeitrag, wenn Pipeline null-Strain nur intern durch0 ersetzt: UI muss fehlenden Beitrag kenntlich halten. Nickerchen-Gutschrift0 ist nicht der Beweis, dass es keine Nickerchen gab. Clamps müssen angewandte statt rohe Beiträge liefern.

Eigener Schlafzielwert bleibt getrennt von Modellbedarf. Gewählte Aufstehzeit/Wecker und historisch typische Aufstehzeit als unterschiedliche Anker führen; explizit gewählte07:00 nicht still durch Median ersetzen. Planung ändert keinen Bandwecker. Grobe Zeitangaben sind Vorschläge, keine garantiert nötige Schlafdauer. Phasenwecker, 90-Minuten-Zyklusquantisierung und kopierte Schlafschuldetiketten sind nicht Bestandteil dieser Planung. Entdeckter Anschlussbefund: heutiger crossday sleepPerformance dividiert die letzte Nacht durch den Bedarf für die kommende Nacht; für eine historische Zielerreichung muss der zeitlich zugehörige Forecast verwendet werden, siehe nächster Flow.

## B137 · Keine pauschale Schlafnote, nachvollziehbare Schlafgrößen

Flow 136 inspiriert metrikspezifisches Detail mit Verlauf und Erklärung. Bewusste eigene Produktentscheidung: kein zusammengewichteter, klinisch unbelegter Schlafqualitäts-Score. Hauptwert bleibt Dauer; Schlafanteil94% ist eine benannte physikalische Quote 438/464 und keine Gesamtbewertung der Nacht. 1A07-0 führt zur neuen Einordnung; B117 bietet Phasen und Messwerte, B135 den Dauervergleich. Nur ein bekannter Effizienzwert erlaubt keine Trendlinie oder Normalbereichsbewertung.

Vorhandene sleepPerformance ist Ziel-/Bedarfsabdeckung, kein Qualitäts-Score. Falls künftig angezeigt, muss für Nacht N der vor dieser Nacht gültige Ziel-/Bedarfsstand verwendet werden. Aktuelle crossday_pipeline koppelt lastTstMin an need für heute Abend; diesen zeitlichen Vertragsfehler vor Nutzung beheben. Ist der damalige Bedarf nicht gespeichert/reproduzierbar, bleibt Zielerreichung offen. Nachträgliches Ziel8h darf alte Nacht nicht rückwirkend als91% bewerten.

Erholung bleibt unabhängiger kanonischer Composite. Subjektives Schlafgefühl aus Journal ist separat datiert und wird nicht aus94% oder Recovery74 abgeleitet. Sollte später ein eigener Schlafqualitätsindex entwickelt werden, braucht er benannte Eingänge, fehlende-Daten-Regeln, erklärbare Beiträge, Versionshistorie und physiologische Validierung; er ist keine Voraussetzung für ein reichhaltiges visuelles Schlaf-UI.

## B138 · Live-Training, Abschluss und Wiederaufnahme

Bevel-Flow 137 vollständig (12 Positionen). Eigene Einheit: 15.09.2026 09:30, 11:00 aktive Minuten, 2 abgeschlossene Bankdrück-Sätze à 40 kg × 8 = 640 kg; dritter Satz geplant. Abschlussvariante 09:41:40: 11:40, 3 Sätze = 960 kg, RPE 7/10, 9 übrige Plansätze nicht gezählt. Keine Pulsdaten: Puls, Belastung und pulsbasiert abgeleitete Kennzahlen bleiben offen. Getrennte Variante vom historischen 13.09.-Training mit 3.300 kg.

Vorhanden: edge/lib/ui2/activity/live.dart besitzt route/journey/power, strength, laps, flow, match und interval; ActivityHost verhindert parallele Starts, LiveDraft hält Zeit und Pause über Minimieren, Sätze werden inkrementell weitergereicht. Diese Fähigkeiten bleiben in einer einheitlichen Bedienung erhalten: Vorbereitung → Start → aktiv/pausiert → Abschlussprüfung → gespeichertes Ergebnis. Zurück minimiert ohne Ende. Aus Übersicht 11QX zurück zur laufenden Einheit. C4F wurde als veraltete Doppelung entfernt.

Erforderlich: dauerhafte Draft-ID, atomare Checkpoints, monotone aktive Dauer plus Wallclock-Bezug, unterbrochene Zeit explizit pausiert. Eine ausstehende Endspeicherung hat einen dauerhaften Terminalentwurf mit idempotenter Save-ID. Der aktuelle finish-Pfad leert LiveDraft auch nach onFinish-Fehler: erst nach bestätigtem Commit löschen; Ergebnis und Retry müssen App-Neustart überleben. Kein zweites Training, während eine Einheit aktiv ist; zum bestehenden Entwurf führen. Ungespeicherter Abschluss kann später gesichert werden, ohne doppelte Sätze/Aktivitäten. Bandverbindung, Pulsfrische und Standortfreigabe getrennt führen. Manuell gezählte Bahnen/Spielstände/Haltungen als eigene Angaben, keine Sensorbehauptung.

Satzstatus planned/active/completed/skipped; nur bestätigte tatsächliche Wiederholungen, Gewicht oder Haltezeit zählen. Pausentimer eingefroren bei globaler Pause. Vorlage aktualisieren zeigt einen expliziten Diff und ändert erst nach Bestätigung; abgeschlossene Einheit bleibt unverändert. Abschluss-RPE freiwillig, kein Defaultwert. Speichern-Fehler bleibt bearbeitbar/retrybar. Paper prüft Hierarchie und lesbare 44-pt-Steuerung; keine reale Bluetooth-/Persistenzprüfung.

## B139 · Belastungsdetail und unabhängige Ergebnisse

Flow 138: Home → Tagesbelastung → Aktivitäten/Zonen → Trends. Hauptwert 1,6 bleibt synthetischer Darstellungswert bis 07:42. Keine zugehörige Minutenkurve, Tageszonensumme, Energie oder persönliche Belastungsspanne erfunden. Schritte 1.240; Wochenzeit 102 Minuten aus 3 Einheiten. Seite scrollt tatsächlich in die in 1ATB dargestellten weiteren Abschnitte; keine neue Registerkarte für das Detail.

Vorhanden: edge/lib/ui2/activity/day_strain.dart unterscheidet gespeicherten Score ohne Kurve von ganz fehlendem Ergebnis. analytics/lib/src/onehz/clinical/load_trimp.dart braucht TRIMP, gültiges Wachfenster und persönlich ermitteltes quietHrr. Die logarithmisch skalierte Belastung über der persönlichen ruhigen Wachbasis kann bei sinkender Intensität wieder abnehmen; keine monotone Nur-Anstieg-Aussage. Deutsche bestehende Copy ist teils gegenüber englischer Copy veraltet.

Erforderlich: Tages-Snapshot mit score, trace und zoneBreakdown unabhängigem Zustand, jeweiligem Zeitfenster/Abdeckung/Version; nachvollziehbare Quellen für HRmax und Ruhepuls. Kein Prozentwert aus 1,6/21 als physiologische Quote, keine Summe von Workout-Scores als Tageswert. Vergleichsbereich nur aus geeigneten vollständigen Tagen gleicher Modellversion. Untertägliche Werte getrennt von abgeschlossenen Tagen vergleichen. Zielkalibrierung folgt Flow 146. Körperenergie und Trainingenergie über bestehenden Energy-Vertrag, ohne Doppelzählung. Referenz führt visuell von Ring über kompakte Werte zu tieferen Listen; eigenes neutrales Canvas und semantische Farben.

## B140 · Belastungshistorie mit sauberem Vergleich

Flow 139 vollständig. Basishistorie 1AZ4: alleiniger untertäglicher Wert 1,6 am 15.09.; sechs Tage fehlen, keine Nullwerte und kein Vergleich. Reife Variante 1B11/1B40 getrennt in strain-history.json: 30 vollständige synthetische Tage 16.08.–14.09., letzter Wert 10,8, vorherige 29 Tage Q25–Q75 = 6,1–9,4; Mittel letzte sieben 8,4857 vs vorherige sieben 7,9143, Differenz +0,5714. Nicht physiologisch berechnet; der 14.09.-Wert ersetzt nicht den kanonisch offenen Tageswert dieses Datums.

Erforderlich: periodisierte Abfrage mit expliziten fehlenden Tagen, Status untertäglich/abgeschlossen, Berechnungsversion, Abdeckung und Zeitpunkt. Historienchart zeigt echte Punkte, Lücken ohne Verbindung, auswählbaren Punkt plus Datum; gleiche Skala0–21. Persönlicher Bereich verwendet nur vorherige geeignete Tage, kein Self-inclusion; Aggregation und Rundung server-/domainseitig konsistent. Mindestzahl gültiger Vergleichstage und Coveragekriterium vor Implementierung fachlich definieren, keine Bevel-Schwellen kopieren. Kalenderauswahl wiederverwendet vorhandenen Datumsdialog; 7T/1M/3M/1J bewahren Auswahl oder zeigen jüngsten passenden Tag. Wochenmittel nur aus vollständigen vergleichbaren Tagen; keine Übertraining-/Gesundheitsbewertung aus der Farbe. Belastungserklärung18A5 und BerechnungBJ3 über bestehende Details erreichbar; keine Bibliothek mit leeren Artikeln.

## B141 · Kraftentwicklung aus abgeschlossenen Sätzen

Flow 140: Bevel zeigt Gesamtvolumen, Muskelgruppen und Übungsprogression mit Zeitraum. Eigener Einstieg 1B8D: 3.300kg aus Kniebeuge1.440, Bank960, Rudern900, neun abgeschlossene Sätze am13.09. DG0 zeigt kanonisch nur diese eine Bank-Einheit40kg×8, keine erfundenen früheren Rekorde. Separate Reifevariante1BBA:20.08.3×8×35=840kg;27.08.und03.09.je3×8×37,5=900kg;13.09.3×8×40=960kg. Datumsabstände im Chart proportional.

Bestehende strength_set/exercise_def/ActivityHistory weiterverwenden. Erforderlich: stabile Übungs- und Ausrüstungsidentität, tatsächliche Satzstatus, Gewichtsemantik gesamt/proHand/Assistenz, Wiederholungen vs Haltedauer getrennt. Volumen nur aus bekannten tatsächlichen Lasten/Reps; offene Sätze und Templates zählen nicht. Arbeitsgewicht mit Wiederholungszahl anzeigen; höchster Satz bei anderer Wiederholungszahl ist kein uneingeschränkter Leistungsrekord. Eigengewicht, assistierte Last, Planks und einseitige Übungen brauchen jeweils geeignete Messgrößen statt pauschal0kg oder verdoppelter Last. Individuelle Übung → Historie → gespeicherte Einheit; Bearbeitung/Entfernung invalidiert abhängige Summen und Rekorde. Zeiträume und Metricpicker Gewicht/Volumen/Sätze nutzen gemeinsamen Vertrag. Kein Bevel-Polardiagramm kopiert, keine geschätzte1RM unbeschriftet als Messwert. Muscle-Zuordnung zählt Volumen einmal primär, weitere Gruppen nur als Beteiligung.

## B142 · Stress: Körperliche Anspannung, Fenster und eigene Wahrnehmung

Flow141 vollständig. APX jetziger Einstieg trennt Tag/Nacht und eigenes Journal. 1BMT zeigt kanonisch keine Stressauswertung trotz verfügbarer nächtlicher HRV48/Ruhepuls54. Ursache ohne gelieferten reason nicht aus Verbindung oder RR-Güte erraten. Neue separate Darstellungsvariante15.09.07:00–07:40: acht5-Minutenfenster [18,23,30,null,null,52,43,35], 6/8=30/40 auswertbare Minuten. Gap07:15–07:25. Letzter Wert35 stammt aus07:35–07:40, nicht aktueller Livezustand09:41. Punkte liegen an Fensterenden, fehlende Fenster werden nicht überbrückt.

Vorhanden: analytics stress_si berechnet Baevsky-SI in 256-Beat-Fenstern mit128-Beat-Schritt, Minimum30Beats, Quantisierungsschutz minRange20ms und Median gültiger Fenster. edge onehz_pipeline bildet SI logarithmisch von20–600 auf0–100 ab. Dieser vorhandene Nachtauswertungsvertrag ist kein Beweis für kontinuierliche Tagesmessung.

Erforderliche Erweiterung: Zeitstempel/Intervallkontinuität beim Bereinigen bewahren, ruhige stationäre Zeitfenster erkennen, Bewegung/Training/Schlaf kennzeichnen, QC pro Fenster und echte reasonCodes liefern. Keine zeitlosen zusammengeklebten RR-Listen oder großen Lücken als ein gültiges Fenster. Fachlich validierter Bezug zwischen zeitbasierten Tagesfenstern und vorhandenen Beatfenstern; die dargestellten Zahlen sind illustrative Werte, nicht als physiologisch berechnet ausgegeben. Signalqualität bei WHOOP5 und Wrist-PRV zuerst belegen. Tages-/Nachtaggregate, Fensterzahl, gültige Dauer, Datenstand und Version getrennt. Keine mentale Stressdiagnose oder automatische Ursache. Subjektive Journalbewertung bleibt eigenes Feld mit eigener Provenienz. Verzicht auf Bevels pauschale Low/Medium/High-Zeitquoten und Energy-Bank ohne eigene validierte Schwellen. Backend-Erweiterung zulässig, keine Messbereitschaft aus einer schönen Kurve ableiten.

## B143 · Koffeinhilfe als Portionenrechnung

Flow142 heißt Suggested drink intake, zeigt tatsächlich Koffeinlog → Getränkeübersicht mit typischen mg und Tageshinweis. Wir übernehmen den kurzen Hilfeweg, keine fremden Getränkemengen oder pauschale Tagesempfehlung. Infoaktion am Koffeinentwurf12XL öffnet1BOH. Eigene Produktangabe30mg/100ml und300ml ergibt90mg; ausdrücklich synthetisches Rechenbeispiel. Übernehmen ändert nur den Entwurf; separater Save legt den Beitrag an. Zurück ohne Übernahme verwirft nur die Hilfsrechnung.

Backend: Konzentration mit Basisvolumen und Portionsvolumen, dimensionstreue Berechnung und Normalisierung, bekannteNull vs unbekannt unterscheiden. provenance label/user_estimate; Menge und Zeitpunkt erhalten, keine zusätzliche Nahrung/Wasser-Anlage als Nebenwirkung. Produktdaten oder kuratierte Portionsbeispiele nur mit Quelle/Version und variabler Portionsgröße. Bestehenden offenen Kaffee gezielt ergänzen statt unbemerkt duplizieren; zusätzlicher90mg-Beitrag führt gemäßB95 zu≥90mg solange vorhandener Kaffee offen bleibt. Keine automatische Einnahmeempfehlung aus Benutzergewicht oder UI-Vorgabe. Rechenhilfe wiederverwendbarer Sheetzustand, Eingaben und Keyboardreturn erhalten Draft.

## B144 · Darstellung als durchgängiger Vertrag

Flow143:6 Bevel-Positionen zeigen Farbschema, Hintergrundvorschau, Home, Journal, Fitness und Trend im Dunkeln. Eigene Auswahl nur Wie iPhone/Hell/Dunkel, feste illustrative Vorschauen, sofort wirksam ohne Speichern. Kein zweiter Hintergrundstil mit abweichender Lesbarkeit. Dunkle Varianten aus aktuellen Quellen erneuert: Schlaf25K, TrainingAXY, JournalB2I, GesundheitASA, EinstellungenBPM, erstes gespeichertes ErgebnisBLP, SchlafkorrekturBNU, LaufJDE, MahlzeitentwurfFJP. Neue Varianten: Belastungsverlauf1D4J, Stress1D8S, Ernährung1DAZ. Bestehende Übersicht1Y8 visuell abgeglichen.

Dusk: Canvas#101318, Karte#1C2027, Ink#F0F2F6, Muted#AFB8C8, Linie#343B47, interaktive Schrift#9DBDFA. Primärbutton#245AC6/weiß; Sekundärfläche#263449. Schlaf#A8BFF0, Erholung#89B6A5, Belastung#E3B76C, Puls#E597AE, Ernährung#C5AEDF. Farbige Flächen sind eigene dunkle Tönungen; keine unveränderten pastelligen Light-Chips. Karten werden über Flächen und Abstand getrennt. Karten-/Diagramm-Schatten im Dark entfallen. Illustrative Route ebenfalls in Dark-Palette. Alte dekorative dunkle Landschaftsblöcke bei Korrektur/Receipt entfernt.

Rechnerisch geprüfte Kontraste: Light Ink auf Weiß12,63:1, Muted5,95:1, Weiß auf Primärblau6,26:1. Dark Ink auf Karte14,58:1, Muted8,18:1, Action auf Sekundärfläche6,64:1. Erholungs-/Belastungslinien in Dark7,23/8,76:1. Light-Schlafakzent#759DDF erreicht nur2,75:1; ausschließlich dekorativ verwenden, bedeutungstragende Diagrammlinien brauchen eine stärkere Farbe ≥3:1 gemäß der abschließenden Palette. Kein pauschales WCAG-Konformitätsversprechen aus wenigen Paaren.

Größere Schrift375×812 QO3 plus Scrollfortsetzung1DQ9: Inhalt wächst, Texte mindestens17/24, Zeilen umbrechen, kein Abschneiden um alles in ersten Viewport zu pressen; sicherer Bereich vor Home-Indikator. Vier Tabs und Detail-Rückkehr bleiben gleich. Systemumschaltung verändert nur Darstellung, keine Datenabfrage oder verlorenen Drafts; aktuelle Route/Scroll/Fokus erhalten. Persistenter lokaler ThemeOverride enum system/light/dark und effektiver OS-Modus; Dynamic Type, Bold Text, Increase Contrast und Reduce Motion separat berücksichtigen. Weitere Ansichten mit 20/26-Lesetext und der globale Altbestandsabgleich sind in B162 dokumentiert.

## B145 · Vorlagenliste als Standard

Flow144 zeigt zwei Positionen zum Wechsel von Vorlagenkacheln auf eine kompakte Liste. Eigene Entscheidung: eine Liste statt zusätzlicher Darstellungspräferenz. 1DSA zeigt kanonische GanzkörperA mit4Übungen/12geplantenSätzen, Öffnen →18C9/DDO, Menü→YEH, Anheften→16HE/16IR. Trainingsfeed zeigt angeheftete Vorlagen zuerst; nicht angeheftet bedeutet nicht gelöscht. Neue Vorlage→bestehender Editor oder geführter Entwurf, Flow153 schließt den Einstieg ab.

Backend: keine neue Datenstruktur für zweite Ansicht. Stabile Vorlagen-ID, definierte Sortierung (Pins, danach selbst gewählte/relevante Reihenfolge), eigener Archivstatus. Zählwerte aus aktuellem Plan, nicht aus Trainingshistorie. Einheit und Vorlage bleiben getrennt. Eine Darstellungsauswahl wäre nur eine lokale Präferenz, sollte sie später durch echte Sammlungskomplexität nötig werden. Kein vorgetäuschtes gerätesynchronisiertes Template; WHOOP-Frage folgt145.

## B146 · Bandübertragung: Verbindung, Speicherung, Abdeckung, Bereitschaft

Flow145 komplett: Bevel synchronisiert Vorlagen in eine Watch-App, zeigt connected/disconnected und bestätigten letzten Sync. Nicht unverändert übernommen: WHOOP5 ist keine Uhr mit unserer Vorlagenoberfläche. Training bleibt auf dem iPhone; kein unbewiesenes Schreiben von Trainingsplänen auf das Band. Eigenes Banddetail5QW und Datenstandseiten ersetzen den veralteten Stand.

Basissnapshot: verbunden64%, Bandzeitstempel lokal dauerhaft bis07:42, Nacht23:10–06:54 vollständig, Schlaf/Ruhepuls/Erholung bereit, Stress offen. Neue Synczustände1DYG läuft mit altem dauerhaftemStand;1E0M getrennt, gespeicherte Nacht weiterhin nutzbar;1E2V bekannter Fehler storage_full;1E53 explizit zusätzliche Fortschrittsvariante neu bis09:38 nach bestätigt abgeschlossenem Transfer, Tageswerte noch in Neuberechnung;1E79 vollständiger kanonischer Datenstand. Partielle VarianteA4: Gap02:10–02:34 in sonst vollständigem464-Minutenfenster;440 erfasst,26wach,414Min=6h54Schlaf erkannt. Daraus keine Aussage über die24unbekannten Minuten. Erholung gesondert pending, nicht automatisch wegen Bluetooth oder Lücke abwesend.

Edge benötigt getrennte read models: ConnectionSnapshot(peer,state,observedAt,batteryFreshness), DurableSourceFrontier(latestBandTimestamp,committedAt,source), CoverageWindow(start,end,knownIntervals,gaps,unknownQuality), MetricReadiness(value/status/reason/inputs/algorithm/asOf). Empfangene aber noch nicht gespeicherte Pakete dürfen die UI-Freshness nicht vorziehen. TransferProgress durablyStored/receiving/committing/awaitingEnd/interrupted/failed/completed; Fortschritt ohne bekannten Nenner unbestimmt statt fiktiver Prozentzahl. Bereits gespeicherte Daten bleiben navigierbar. Gründe storage_full,store_io,link_lost,permission_denied und OS-paused unterscheiden und passende Aktionen anzeigen. iPhone-Speicher prüfen nur bei explizitemPlatzmangel, sonst Retry und Bericht.

Bestehenden commit-before-ACK-Vertrag und retryfähigen historischen Cursor erhalten; aktuellble_state hat Commit-/ACK-Gates und Token-Recovery, keine neue parallele Syncmaschine bauen. Commitquelle dauerhaft, Deduplikation und Resume über Neustart; fehlgeschlagener Commit bestätigt dem Band keinen Fortschritt. HISTORY_END oder Write-Erfolg allein nicht als vollständig lokale/ausgewertete Historie verkaufen. Endbestätigung plus durable frontier und letzte offene Fehler erforderlich. Wiederverbinden darf keine zweiteüberlagerteSession starten. Dynamischer Gerätebericht liefert Ursachen; keinefirmwareänderndenSchalter. Datenstandlink im vollständigenHome→1E79, im partiellen→A4, Bandakku→5QW, Unterbrechung→1E0M. 24–72hGerätetest bleibt getrennte spätereImplementierungsabnahme, hier nurEntwurf.

## B147 · Kalibrierung ohne falsches Tagesziel

Flow146 zeigt Bevels bis-zu-zwei-Wochen-Kalibrierhinweis für ein Belastungsziel aus Erholung und Strainbaseline. Eigenes1E9H trennt heutige Belastung1,6, bereits verfügbareErholung74 und noch fehlenden persönlichen Vergleich. Bereite Vergleichsvariante wiederverwendet1B11/1B40 mit tatsächlichen Quantilen aus29vorherigen synthetischen Tagen. Keine pauschale14-Tage-Uhr, kein automatischer Sollwert.

Sourceprüfung: analytics/human/coaching.dart strainTarget gibt beiRecovery74 und fehlendenCTL/ATL/TSB bereits9–14 aus. Es handelt sich um ein heuristisches Recoveryband, nicht um einen empirisch kalibrierten persönlichen Bereich. inputs_used nennt load auch bei fehlenden Lastdaten; rationale erklärt die tatsächlich fehlendeLastkomponente nicht. crossday_pipeline liest immerhin datiert recToday und verweigert fehlendeRecovery. Das vorhandeneZiel nicht still in persönlicheHistorie umbenennen.

Produktentscheidung: persönliche Vergleichsspanne statt trainingsvorschreibendemZiel im Kernflow. Neues Readmodel historyReadiness{eligibleDays,window,excludedByReason,criteriaVersion,range} unabhängig von RecoveryReadiness. Mindestumfang und vollständigeTagesabdeckung als explizite fachlich zu prüfende Policy, keine geschätzteFertigstellungszeit ohneBeleg. Ausgeschlossene/partialTage keineNull; Modellwechsel trenntReihen. Wer später ein eigenes Tagesziel setzt, braucht ownGoal mit Gültigkeit und Herkunft statt Überschreiben von berechnetenScores. Ein künftig entwickeltes adaptives Trainingsziel wäre eine separat zu evaluierende Erweiterung, keine reine UI-Abstraktion.

## B148 · Schlafdauer: datierte Historie und Erklärung

Flow147:3Positionen von Schlaftrend über periodisierte Schlafdauer und Wochenverteilung bis zuVergleich/Erklärung. 13A vollständig erneuert, alteDekoration entfernt. 9.–15.09. siebenvollständigeNächte mitMinuten[375,382,390,400,402,422,438], Summe2809/Mittel401,2857→6h41. AusgewählteNacht438=7h18;Bett464=7h44,Wach26. Vergleich6h15–6h42 ausvorherigen7Nächten8.–14.09., nichtausdemaktuellenChartfenster;36MinüberoberemQuartil402.

Darstellung: lesbareStundenskala ab0, echteTagespunkte, schmalerpersönlicherBereich,Zeitraumwahl;Nachtansehen→16RN,Dauerverstehen→1EEM,Prüfen→187/Korrektur. Nickerchen separat, nichtstillschweigendderHauptnachtzugeschlagen. Teilnächte tragenPartialzustandundbekannteDauer;keine0fürohneDatenundkeineLinieüberfehlendeTage. MittelwertnennernurvollständigegeeigneteNächte, Anzahl sichtbar. NachKorrektur betroffeneNacht/Trend/Baseline neu berechnen und alteangezeigteWertealsveraltetmarkieren. PersönlichesSchlafzielgiltversioniertabkommenderNacht(B45),keinerückwirkendePerformancegegenheutigenBedarf. Erwachensdatum/Nacht-ID/ZoneanalleDrilldownsweitergeben.

## B149 · Supersatz lösen, ohne Sätze zu verlieren

Flow 148: vier Quellpositionen führen von einer verbundenen Übung über Gruppenbearbeitung zum getrennten Entwurf. Eigener Einstieg XOE → 1EGN → 1EIN. Bankdrücken 3×8×40 kg und Rudern 3×10×30 kg bleiben erhalten. Im gezeigten Entwurf werden die 90 Sekunden Gruppenpause nach expliziter Vorschau zu 90 Sekunden Satzpause für beide Übungen. Kniebeuge und Plank ändern sich nicht; insgesamt weiterhin vier Übungen und zwölf geplante Sätze.

Backend: lokale Draft-Transformation mit stabilen Mitglieds- und Satz-IDs, Entfernen der groupId/round-Kopplung, vorhersehbarer Reihenfolge und expliziter Pausenpolitik. Gruppenpausen niemals still verwerfen oder mit früheren individuellen Pausen überschreiben. Rückgängig stellt die gesamte frühere Gruppe einschließlich Pause und Reihenfolge wieder her. Erst Vorlage speichern persistiert atomar; Verwerfen kehrt zur unveränderten gespeicherten Vorlage zurück. Wiederholtes Speichern ist idempotent. Historische Einheiten besitzen eigene Snapshots und bleiben unverändert. Auflösen während einer laufenden Einheit darf nur künftige Sätze umordnen; bereits abgeschlossene Sets und aktive Timer brauchen eine eigene, explizite Übergangsregel aus B138. Kein Löschen einer Übung als Nebeneffekt. Speicherfehler verwendet den bestehenden erhaltenen Vorlagenentwurf/Retry-Zustand 18F1.

## B150 · VO₂max-Referenzbereiche nur mit nachvollziehbarer Herkunft

Flow149 zeigt zwei Quellpositionen: VO₂max-Historie und farbige alters-/geschlechtsbezogene Normtabelle mit FRIEND als Quelle. Wir übernehmen die kurze Erklärung und Quellenbindung, keine aus einem Screenshot abgeschriebenen Grenzwerte. 1ELE zeigt die Voraussetzungen für eine Einordnung und den Zustand ohne passenden Referenzbereich.

Erforderlich: sourceType measured/estimated/user_entered, measuredAt separat von importedAt, Einheiten-normalisierter Wert, Messmethode, Referenzkatalog-ID samt Version/Lizenz/Gruppe und Gültigkeit. Keine nachträgliche Umklassifizierung alter Werte allein durch heutiges Alter; Alter am Messdatum verwenden. Referenzgruppe transparent, keine unpassende Kategorie still aus unbekannten Profilfeldern ableiten. Ohne passende Referenz bleibt der Wert sichtbar und die Bewertung offen. Ein eigener Befund oder freigegebener Anbieter kann eine belegte Einordnung liefern; alternative Messverfahren in Trends unterscheiden. Redaktionell geprüfter, lizenzierter Normkatalog wäre eine bewusste Backend-Erweiterung mit Quelle und methodischer Prüfung. Das Design definiert keine neuen physiologischen Normwerte.

## B151 · VO₂max: vorhandenen Messwert erhalten

Flow 150: Biologieübersicht → VO₂max-Verlauf. Eigene Screens 1ENR/1EOW/1ER7/1ET8 zeigen fehlenden Wert, datierten Entwurf, gespeicherten Eintrag und erhaltenen Entwurf bei Speicherfehler. Separate synthetische Variante: 42,0 ml/kg/min, Messdatum 14.09.2026, Spiroergometrie laut selbst eingegebenem Befund; erfasst am 15.09. um 09:41. Eigene Eingabe ist keine vom Labor verifizierte Messung. Ein Wert wird als Eintrag statt als erfundener Trend gezeigt. Normbewertung bleibt ohne passende Quelle offen (B150).

Der frühere VO₂max-Schätzer k/Ruhepuls wurde aus dem Backend entfernt; ihn nicht für die neue Oberfläche reaktivieren. Erweiterung: datierter Messwert mit stabiler ID, Mess-/Erfassungsdatum, normalisierter Einheit, Quelltyp, Methode und Revision. Anbieterimport mit Berechtigung, Deduplikation und Herkunft; manuelle Werte getrennt kennzeichnen. Bearbeiten und Löschen betreffen den gewählten Eintrag, erhalten Historie/abhängige Neuberechnung und erlauben kontrolliertes Rückgängig. Ein verlorener Save darf keinen zweiten Eintrag erzeugen: Draft-ID und idempotenter Commit, Fehler behalten alle Eingaben. Ohne Datum vorhandenes Profilgewicht oder Ruhepuls erzeugen keinen VO₂max-Wert. Körperwerte R9O verweist auf diesen Einstieg; Quelle und Norm sind unabhängige Details.

## B152 · Gewicht: Journalverlauf und Profil getrennt

Flow 151 komplett: Körperwerte → Verlauf mit Energievergleich → Trendanalyse. Eigene Entscheidung: datierte Einträge und geglätteter Verlauf ohne Prognose, Zielgewicht oder farbliche Bewertung einer Zu-/Abnahme. Basissnapshot enthält nur einen undatierten Profilwert 75 kg; 1EUD–1EVG ergänzen getrennte Zustände ohne ihn nachträglich zum Messwert zu erklären. Zusätzliche Eintragsvariante 15.09.2026 07:15, selbst eingegebene 75,0 kg. Separate reife Verlaufsvorschau aus assets/fixtures/weight-history.json: sieben Eingaben 9.–15.09., EWMA mit 7 Tagen Halbwertszeit, letzter geglätteter Wert 75,2330 → 75,2 kg. Keine rohe Kurve und keine vorgetäuschte Energieregression.

Vorhanden: Journalfeld weight_kg, weightTrendEwma mit zeitbasierter Glättung und ausdrücklich nicht an BMR gekoppelt. HealthProfileSnapshot importiert Gewicht als Skalar und verliert Messdatum/Provenienz; Health-Werte überschreiben aktuell Profilgewicht. Erweiterung: datierte Beobachtungen mit Quelle, Originaleinheit, Import-/Messdatum, Revision und Löschstatus. Lücken trotz vorhandener Glättungswerte nicht verbinden. Tagesauflösung, mehrere Eingaben, Importduplikate und Quellwechsel müssen deterministisch sein. Profilübernahme separat bestätigen, Gültigkeit ab gewähltem Datum speichern und betroffene Berechnungen markieren; keine stille Neuschreibung aller historischen Energiezahlen. Fehlende oder verweigerte Health-Daten bleiben unbekannt. Eintragseditor erhält Draft bei Fehler und erlaubt Bearbeiten/Löschen des ausgewählten Werts. Kein Körperfett oder fettfreie Masse aus Gewicht allein. Gespeicherten Einzelwert und reife Verlaufsvorschau nicht in denselben Basissnapshot mischen.

## B153 · Widgets: datierte Snapshots und gezielte Rückkehr

Flow 152 mit drei Quellpositionen zeigt viele Widgetfamilien: Tagesringe, Nachtwerte, Stress/Energie, Ernährung, Wasser. Eigene Widgets spiegeln nur definierte Daten: Schlaf, Tageswerte, HRV/Ruhepuls, Bandakku und laufende Einheit. 7OY vollständig ersetzt; 1F3V erklärt die Einrichtung ohne vorgetäuschte automatische Installation. Unbekannte Energie oder Stresswerte werden nicht durch fremde Energy-Bank- oder Food-Score-Abstraktionen aufgefüllt. Vorhandene Nacht bleibt bei Linkverlust sichtbar. Fehlend, teilweise, älterer datierter Snapshot und Datenschutzdarstellung sind eigene Varianten. Widgetgrößen sind Vorschauen, endgültige Maße bestimmt WidgetKit je Gerät/Familie.

Vorhanden: App-Group-Snapshot und WidgetService, Schlaf-/Nacht-/Akkuwidget sowie LiveActivity. Erweiterung: atomare versionierte Snapshot-Publikation mit Datum, Zeitzone, metricReadiness je Wert, CoverageWindow, SourceFrontier und batteryObservedAt. Nicht alle Werte pauschal mit globalen 26 Stunden invalidieren. Fehlender Zeitstempel ist unknown, nicht frisch. Historische Nachtwerte bleiben datiert sichtbar, Tageswerte erhalten ihren eigenen Tag. Widgettap transportiert Zielroute, Tag/Nacht-ID und Quelle; App-Rückkehr wahrt Navigation. Bei alten Snapshots erst Aktualität erklären, dann aktualisieren. Keine Bluetooth-Session aus dem Widget starten.

Dynamische Schrift, akzentuierte/monochrome iOS-Darstellung, Light/Dark und sensible Sperrbildschirmwerte testen; privacySensitive und Einstellung zum Ausblenden nutzen. Native Systemicons in WidgetKit folgen der Apple-Plattformlizenz; plattformübergreifende Paper-Icons sind lizenzierte Lucide-Vektoren. Trainings-LiveActivity folgt dem persistierten Sitzungszustand, nicht einem unabhängigen Timer. Ende, App-Neustart, Pause und Save-Fehler müssen zum selben Draft zurückführen. Sperrbildschirmaktionen höchstens explizite Pause/Fortsetzen über stabile Session-ID, kein destruktives Training-Verwerfen.

## B154 · Vorlagen: ein Einstieg, drei bewusste Wege

Flow 153: globale Aktion öffnet Vorlagenliste. Eigene Route Übersicht → Eintragen 11XM → Vorlagen 1DSA → gespeicherte Vorlage 18C9 → Training starten. Neue Vorlage 1F6K bietet Selbst zusammenstellen → DDO/KWG, Geführt entwerfen →10X6 und Foto →P4R. Jeder Weg endet in demselben prüfbaren Vorlagenentwurf. Anheften bleibt eigener Listenfilter; keine zweite Vorlagenkopie.

Bestehende template/workout-Trennung bewahren und um Draft/Revision/Archivstatus, Supersatzgruppen, Pausen und stabile Übungs-/Satz-IDs erweitern. Eine Vorlage ist eine Planung; aus ihr entsteht beim Start ein eigener Workout-Snapshot. Geplante Gewichte oder Sätze dürfen weder Volumen noch Trainingserfolg vorfüllen. Foto/Assistent dürfen Entwürfe erzeugen, benötigen aber Review, Herkunft und Fehlerzustand; keine automatische Speicherung aus Modellantworten. Route besitzt returnTo, sodass Rückkehr aus Editor/Detail wieder zum ursprünglichen Home- oder Trainingseinstieg führt. Wiederholter Start darf keine parallele aktive Einheit erzeugen; vorhandene Einheit fortsetzen oder erst bewusst beenden. Damit sind alle 153 Katalogflows einzeln geprüft. Der globale Abgleich aller behaltenen Paper-Screens ist in B162 abgeschlossen.

## B155 · Abschlussabgleich: Schlafkorrektur und unabhängige Zustände

Der globale Abgleich ersetzt die frühen Schlaf- und Home-Zustände. Home-Unterbrechung lässt die bereits bereiten 7h18/74/1,6 und Nachtwerte stehen; Verbindung, gespeicherte Zeit, Abdeckung und Berechnungszustand bleiben getrennt. Teilnacht nutzt B146 mit 24 unbekannten Minuten und separat laufender Neuberechnung; unzuverlässige Herzintervalle sind eine eigene Variante.

Korrektur JN → L1 → M8 → NG oder OT: 23:10 wird zu 23:25, Ende bleibt 06:54. Das neue Bettfenster hat 449 Minuten. Für die synthetische Ergebnisvariante werden aus B117 die ersten 15 Minuten abgeschnitten: 5 Minuten wach und 10 Minuten leichter Schlaf. Damit 428 Minuten Schlaf = 7h08, 21 Minuten wach, 26 Minuten über dem bisherigen oberen Quartil 402. Diese nachvollziehbare Darstellungsvariante ersetzt den alten ungebundenen Wert 7h13; sie ist kein Test des realen Staging-Algorithmus. Erholung darf während eigener Neuberechnung noch offen sein.

Gespeicherte Änderung und erfolgreiche Neuberechnung sind zwei Transaktionen mit je eigener Revision/Bereitschaft. Save-Fehler erhält den ungespeicherten Draft; Analysefehler erhält die bereits gespeicherten Zeiten. Wiederholen darf keine zweite Korrektur erzeugen. Ungültiges Enddatum blockiert Save und fokussiert das betroffene Feld. Rücknahme benötigt Vorschau, bestätigt den neuen gültigen Revisionstand und rechnet abhängige Daten neu. Zeitfenster bleibt in der Aufzeichnungszone, UTC-Abstände an DST-Grenzen pro Endpunkt. 15O zeigt dieselben Instants in Berlin und London. Kein manueller Ersatz fehlender Sensorabschnitte.

## B156 · Medikamente als vollständiger Eintragsfluss

Design: 5CG-0 und 1HFP-0, 1HIV-0, 1HL7-0, 1HN2-0, 1HQ3-0, 1HRB-0, 1HSR-0, 1HV7-0. Präparate A/B und Verlauf sind zusätzliche synthetische Varianten, keine Empfehlung. MedDef um UUID statt Namensschlüssel, Menge/Einheit/Art/Notiz und mehrere Zeiten im UI erschließen. Plan beenden setzt active=false und behält Dosen. Plan und Dosis idempotent speichern, danach OS-Erinnerungen neu abgleichen; Fehler erhält Entwurf. Offene vergangene Termine nicht als sicher verpasste Einnahme bezeichnen. Quote zählt nur vergangene geplante Termine, Zukunft nicht. Benachrichtigung prüft Termin, gelöscht/beendet/bereits bestätigt und öffnet vorhandenen Eintrag. Historische Tageswahl, Korrektur, Auslassen und Rücknahme erhalten eindeutige Slot-ID und lokale Zeitzone/DST. Keine Dosisberatung oder Wechselwirkungsprüfung.

## B157 · Freiwilliger Zyklus ohne medizinische Phasenbehauptung

Design 5EF-0, 7EJ-0, 1I0F-0, 1I2M-0, 1I4O-0, 1I68-0, 1I8D-0, 1IAV-0. Einen kanonischen Aktivierungsschalter statt Prefs/profile-Doppelzustand verwenden. Protokollieren und optionale Zeitschätzung getrennt; gespeicherte Starts bleiben beim Ausschalten erhalten. Ausgewähltes Datum für Start und Symptome; Bearbeiten/Löschen mit Beleg und idempotenten Fehlerpfaden. Keine Ovulations-Phasenpille: sie beruht aktuell nur auf Kalenderarithmetik. Gaps >60 Tage sperren künftig auch Vorhersage, nicht nur Reviewchart. Zusätzliche synthetische Starts 2026-06-01, 06-29, 07-31, 08-24: Gaps 28/32/24, Median28, unskalierte MAD4; am15.09. Tag23, Schätzung17.–25.09. Kalenderdaten über DST prüfen. Keine Diagnose, Verhütungs- oder Fruchtbarkeitsfunktion.

## B158 · Atemführung, Messung und Speichern

Design 56F-0 und 1IFA-0, 1IGZ-0, 1IJ0-0, 1IKB-0, 1IM9-0, 1INY-0, 1IQ7-0. Drei getrennte Modi: Atemführung ohne Sensor; gemessene Resonanzsitzung; Tempovergleich mit verbindlicher RR-Prüfung. Box, 4–7–8 und verlängerte Ausatmung erzeugen keinen Kohärenzwert. Dauer wird auf vollständige Zyklen gerundet und im Setup konkret gezeigt; Beispiel 4+6 Sekunden ×30 =300 Sekunden. Speichern ab60 Sekunden und höchstens tatsächliche aktive Dauer/Target; Rückkehr aus Hintergrund darf keine Pausenzeit hinzuaddieren. Ruhefenster optional je2 Minuten; vor/nach RMSSD nicht als einzelne Wirkung behaupten, SessionEffect benötigt12 geeignete Paare. Unterbrechung, <60 Sekunden ohne Datensatz, ungültige Intervalle und Speicherfehler getrennt. Save-Failure erhält PendingResult bis Wiederholen oder bewusstem Verwerfen. Pace-Sweep ohne Band verweigern; Abbruch ohne Gewinner. Reduce Motion: statischer Kreis mit Text-/Sekundentakt, keine notwendige Animation.

## B159 · Befundbasierte Laborwerte

Design 4E4-0 und 1ISJ-0, 1IUJ-0, 1IXQ-0, 1IZS-0, 1J1R-0, 1J30-0. Katalog und eigene Marker, Zahl/Einheit/Abnahmedatum, eigener Befundbereich und Provenienz. Beispiel Ferritin42 ng/ml, Befundbereich30–400 ist synthetisch und keine neue klinische Vorgabe. Vorhandene Katalognorm nicht still als Befundnorm anzeigen. Optionalen lab_result-spezifischen Bereich/Quelle ergänzen; Katalogversion und sexabhängige Zuordnung getrennt. Fehlendes Profil/Referenz ohne Rot-Grün-Bewertung. Exakte Einheiten, Dezimalkomma und Datum validieren; Speicherfehler erhält Entwurf. Löschen eines Resultats benennt Marker+Datum+Wert. Markerarchivierung behält Resultate und deren damalige Einheit/Bezeichnung, keine verwaisten Daten. CSV enthält Laborresultate samt Provenienz; keine Diagnosen.

## B160 · Vollständiger Export und erreichbare Gerätefunktionen

Design 1J4D-0, 1J6M-0, 1J8R-0, 1JAM-0, 1JCI-0, 1JER-0, 1JGD-0, 1JI3-0, 1JK3-0, 1JLN-0, 1JO0-0, 1JPJ-0. CSV enthält Tagesdaten und manuelle Bereiche mit Provenienz, aber keine Rohsignale/GPS. Neuer vollständiger verschlüsselter Sicherungscontainer muss transaktionalen DB-Snapshot, aufbewahrte Originalaufzeichnungen, Schema/Quellenmanifest und benötigte Einstellungen umfassen; Schlüssel und Zugangsdaten ausschließen. Bestehende .osbk/.db-Importe weiter explizit erkennen. Unverschlüsseltes Originalarchiv mit Integritätsmanifest, Abdeckung und Zeitraum; fehlende Archivteile als Teilfehler statt Erfolg. ExportPrepared, SharePresented, Cancelled und bestätigtes Ergebnis trennen: Share-Aufruf ist keine dauerhafte Speicherung. Teilfehler nennt betroffenen Bereich; leere Exporte eigener Zustand. Sensoren über Band erreichbar, fremde Quellen zunächst nur capture_only; keine Wellness-Scores aus kDerivableSources ohne Freigabe. iOS-Scan/AccessorySetupKit-Zuständigkeit vor Implementierung bereinigen, keine versteckte Kopplungsblockade durch CBCentralManager. Sensorkennung/Quelle und Entfernung erhalten Historie. Gesten bleiben opt-in, Capability-Filter, Deduplizierung, lesbarer Beleg und Undo; Training öffnen ersetzt gefährliches sofortiges Start/Stop. Native Android-BandNotifications/Tasker/Lautstärke werden nicht als iPhone-Funktion gezeigt.

## B161 · Zielauflösung für Kurzbefehle, Widgets und Mitteilungen

Kalter und warmer Start benutzen einen Router mit Bereich+Objekt+Tageskontext. /meds→5CG-0 mit Slotauflösung, bereits bestätigt öffnet Beleg; entfernt→1JPJ-0. /breathing→56F-0 oder aktive Sitzung; /water→13XR-0 ohne doppelten Nutrition-Push; /journal/compose→53Y-0/Eintragseditor mit übergebenem Datum; /workouts/suggestion?id→geprüfter Vorschlag oder freundlicher fehlender Eintrag; /profile→5L1-0; /recap→CE1-0; /alarm→18VN-0. Veraltetes Widget öffnet belegten Tag mit Aktualität, kein stilles heute. Unbekannte alte Payload öffnet Übersicht ohne Mutation. Benachrichtigungen nach Planänderung, Löschen und Widerruf abgleichen. Back führt zum Ursprung oder zum passenden Tab; kein Leerstapel.

## B162 · Abschlussharmonisierung und verbindlicher Beispieldatenstand

Alle 153 Katalogflows sind abgeschlossen; alle 591 behaltenen Artboards wurden im globalen Abgleich berücksichtigt. 583 sind iPhone-Ansichten, acht Tafeln. Alte Parallelen 44K, 67J und 7GA wurden entfernt; aktuelle Ziele sind 14I, 1AKS und 13IE. Die fehlerhafte Referenz IUP heißt IUA. Die konkrete Übersicht und der dokumentierte A/B-Vergleich verwenden denselben Basissnapshot mit Erholung 74 und HRV 48; unzuverlässige Intervalle bleiben eine separate Variante.

Aktuelle Datenquelle für Designbeispiele: `assets/fixtures/day-summary.json` plus `additional-flows.json` und die benannten Detailfixtures. Ergänzt wurden konsistente stündliche Schritte (0, 0, 0, 0, 10, 20, 180, 1030 = 1.240), sieben Bettzeitfenster mit getrennten Schlaf-/Wachminuten, Medikamententermine, Zyklusstarts, Atemzyklen, ein synthetischer Laborbefund, erster Sync und korrigierte Nacht. Joghurt und Kaffee besitzen im Basissnapshot keine Uhrzeit; der Hafer-Eintrag liegt um 07:00. Reife Journal-/Trainings-/Gewichtsverläufe bleiben eigene Varianten. Belastung 1,6 ist im Tagesfixture illustrativ und kein Beweis der kompletten Tagespipeline.

Korrektur 23:25–06:54 schneidet fünf Wach- und zehn Leichtschlafminuten aus dem Original: 449 Minuten Bettzeit, 428 Schlaf, 21 wach. Der Vorschauzustand zeigt nur das Zeitfenster. Der Schlafring der Übersicht zeigt die Phasenzusammensetzung der Bettzeit und innen die Schlafdauer, ohne Schlafscore oder Zielbehauptung (B163); die ausdrücklich bezeichnete Schlafanteil-Detailansicht darf dagegen 438/464 ≈ 94 % zeigen. Ein Tagesstresspunkt steht am Ende seines fünfminütigen Fensters; die sichtbare Abnahme beginnt im Beispiel am Punkt 07:30.

Gestaltung: aktueller Journal-Kopf und vier Tabs in allen Journalwurzelzuständen; Details ohne zusätzliche Tabbar. Eiweiß rot, Kohlenhydrate gold, Fett violett. Lucide-SVGs aus den beigelegten, lizenzierten Quellen. Layoutziel 393 × 852 pt, zusätzliche 375 × 812- und größere Schriftvarianten. Datenfarben, sichtbare Texte und Datenzustände dürfen nicht aus einem abweichenden alten Screen übernommen werden. Maßgeblich sind aktuelles Paper-Inventar und DESIGN_DIRECTION.md.

Die abschließende Sichtprüfung ist eine Designprüfung. Klickziele, Scrollfortsetzungen und gemeinsame Fehlermuster sind beschrieben, noch nicht als App verdrahtet. Systemdialoge, Dynamic Type, VoiceOver, Tastatur, Hardware und Wiederherstellung bleiben nach Implementierung zu prüfen.


## B163 · Datenbilder mit eindeutiger Bedeutung

Revision 17.09.2026. Die neue Übersicht gilt für sämtliche Bereiche. Phasenring: 464 Minuten Bettzeit als Nenner, 123 REM, 247 leicht, 68 tief, 26 wach; 438 Schlaf im Zentrum. Teilnacht: 24 unbekannte Minuten bleiben als Lücke sichtbar, nicht auf bekannte Phasen umverteilen. Korrektur übernimmt erst nach Neuberechnung die neue Phasenverteilung. Schlafanteil ist eine eigene Metrik (438/464 ≈94 %), kein Schlafscore. Erholung 0–100 und Belastung 0–21 verwenden ihre eigenen Skalen.

Benötigt: gemeinsamer versionierter Darstellungsdatensatz pro Metrik mit Wert/Einheit, betrachteter Zeit, Quelle, Bereitschaftsgrund, Vergleichsart und Diagrammsemantik. Zeitreihen besitzen Zeitgrenzen und gültige/fehlende Intervalle; nicht lediglich eine Liste von Zahlen. Null, unbekannt, nicht berechnet und unzuverlässig dürfen nicht zusammenfallen. Ein aggregierter Tageswert kann bereit sein, obwohl Minutenkurve und Zonenaufteilung fehlen. Das Design braucht dafür keine erfundenen Zwischenwerte.

Bereichsbänder kennzeichnen persönliche Basis und Zeitraum; keine automatisch erzeugten medizinischen Normen. Einzelwerte ohne Datum ergeben keinen Verlauf. Karten wie Wasser, Check-in, Atemführung und Bandtransfer verwenden eigene Illustrationen: dekorative Wellen sind weder Füllstand gegen ein verborgenes Ziel noch Sensorkurven. Die Pulsintervall-Methode darf ein deutlich bezeichnetes Prinzipbild zeigen; Messansichten benötigen echte Intervalle. Abnahme: numerischer Snapshot, Diagramm, zugängliche Beschreibung und Detailansicht verwenden dieselbe Revision.

## B164 · Knappe Oberfläche, vollständige Vertiefung

Jede Karte öffnet den dargestellten Gegenstand mit ausgewähltem Tag bzw. Nacht-/Eintrags-ID. Kleine Einordnungen gehören zum Wert und verlinken ihre Vergleichsbasis. Informationsaktionen öffnen Methode oder Quelle; Fehleraktionen führen zum betroffenen Feld, Auftrag oder Sync. Keine lose Anleitung unter einer bereits verständlichen Aktion. Feldlabels, Einwilligungsumfang, Folgen destruktiver Änderungen und nicht offensichtliche Ablehnungsgründe bleiben sichtbar.

Ein gemeinsames Detailmodell liefert die Ebenen Wert/Verlauf → Vergleich/Treiber → Methode/Quelle. Erweiterung des Routers um origin, selectedDay, objectId und Wiederherstellung von Scroll-/Draftzustand; keine separaten, driftenden Datenkopien für Feed, Modal, Widget und Historie. Vier Tabs bleiben stabil, Formulare erhalten explizite Rückkehr. Sheet und Tastatur liegen vor dem Feed; Scrollcontainer besitzen den tatsächlichen Safe-Area-/Aktionsleisten-Abstand. Die Paper-Ansichten zeigen Zustände und Fortsetzungen, keine bereits implementierte Navigation.

## B165 · Dichte, Textvergrößerung und Darstellung

Gemeinsame Tokens für Flächen, Text und Datenfarben statt pauschaler Abdunkelung. Diagrammfarben und kleine farbige Texte sind getrennte Rollen. Neutraler Text bleibt die Regel; Farbe ergänzt Name, Zahl und Form. Hell: Schlaftext #4F68AE, Erholungstext #2D7463, Belastungstext #926018. Die weicheren Diagrammrollen dürfen nicht ungeprüft als kleine Schrift verwendet werden. Lucide-Pfade und Lizenzen unter assets/icons bleiben die kanonische Quelle.

Standard: 14/19 Lesetext, 13/19 Labels, 12/19 Metadaten, 15/20 Abschnitte, 18/24 Detailkopf, 22/28 Bereichskopf. 44-pt-Bedienflächen trotz kleinerer Glyphen. Bei großer Schrift zuerst Werte und Zeilen stapeln, dann Inhalt scrollen; keine Schriftverkleinerung oder abgeschnittene Buttons. Check-in-Skalen erhalten gleich große Felder, sichtbare Auswahl, Namen und VoiceOver-Werte. Datengrafiken bieten eine Textzusammenfassung und abrufbare Einzelwerte. Reduce Motion entfernt notwendige Atemanimation, nicht den Phasen-/Sekundenstatus. Native Dynamic Type, VoiceOver, Bold Text, Increase Contrast und Tastaturverdeckung nach Implementierung am Gerät prüfen.

## B166 · Visuelle Speicher- und Fortschrittsbelege

Band/iPhone-Darstellung besitzt unabhängige Verbindung, Akku mit Beobachtungszeit, bestätigten SourceFrontier, Abdeckung und Metrikbereitschaft. Eine animierte Verbindung ersetzt keinen Commit. Erster Abschnitt 09:12–09:28 =16 Minuten, endgültiger Beispieltransfer bis09:40 =28 Minuten. Ohne bekannte Gesamtmenge kein Prozentfortschritt. Speicher voll, Verbindung weg und Berechnung offen führen zu unterschiedlichen Wiederholungen; gespeicherte Daten bleiben sichtbar.

Gleiches Prinzip für Korrektur, Check-in, Mahlzeit, Wasser und Training: visuelle Zusammenfassung der konkret gespeicherten Änderung, stabile Eintrags-/Draft-ID und idempotentes Wiederholen. Bei Fehler bleibt der Entwurf erhalten. Atemphase und Timer leiten sich aus einer monotonen aktiven Sitzungszeit ab; Beispiel127 Sekunden aktiv bedeutet bei4 Sekunden Ein-/6 Sekunden Ausatmen noch3 Sekunden Ausatmen, 173 Sekunden Restdauer. Keine unabhängig driftenden Countdown-Werte. Diese Anforderungen ergänzen B03/B04, B138 und B155–B160; sie sind noch keine Backend-Implementierung.
