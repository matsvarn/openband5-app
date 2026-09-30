# Designabdeckung · OpenBand 5

Stand: 17. September 2026. Ergänzung zu [DESIGN_DIRECTION.md](DESIGN_DIRECTION.md). Abgleich gegen den aktuellen lokalen Quellstand, einschließlich vorhandener uncommitteter Änderungen.

## Umfang und Lesart

Die bereinigte [Paper-Datei](https://app.paper.design/file/01M2KDQRH0A9K3N46EWHMBF61D/H-0) enthält **583 iPhone-Ansichten und acht Referenz-, Richtungs- und Komponententafeln auf neun Seiten**.

**Ansicht** bezeichnet einen ausgearbeiteten iPhone-Screen. **Muster** bezeichnet einen editierbaren gemeinsamen Baustein oder eine Zustandsreferenz, die auf mehrere bestehende Funktionen angewendet wird. Die Matrix deckt die vorhandenen Screenfamilien ab; sie behauptet keine einzeln gestaltete Variante jeder Metrik, Sportart, Einstellung oder möglichen Zustandskombination.

## Quellcode zu Design

Die Dateilinks führen in `edge/lib/ui2`. Die sichtbaren Namen entsprechen den Paper-Artboards. Eine Kombination aus Ansicht und Muster ist ausdrücklich benannt.

### Start, Verbindung und Navigation

| Vorhandene Quelle | Gestaltung | Erhaltenes Verhalten |
| --- | --- | --- |
| [onboarding/splash.dart](../../lib/ui2/onboarding/splash.dart) | Muster: „Berechtigung und Start“, Speicher-/Fehlerzustände | Initialisierung, Wiederholen und Diagnose. Lade- oder Startfehler setzt vorhandene Daten nicht zurück. |
| [onboarding/welcome.dart](../../lib/ui2/onboarding/welcome.dart) | Ansichten: Willkommen, Import abgeschlossen; Muster: lokale Bestandssicherung | Band verbinden oder Bestand importieren; spätere Einrichtung bleibt möglich. Import zählt übernommen, übersprungen und abgelehnt getrennt. |
| [pairing/device_picker.dart](../../lib/ui2/pairing/device_picker.dart)<br>[onboarding/pairing.dart](../../lib/ui2/onboarding/pairing.dart) | Ansichten: Band vorbereiten, gekoppelt ohne Aufzeichnungen, Bluetooth einschalten, Band nicht gefunden, Band noch offen | Nativer iPhone-Zubehördialog; Scannen, Bluetooth blockiert, nicht gefunden, abgelehnt, abgebrochen und fehlgeschlagen. Erneut versuchen koppelt ein bereits gekoppeltes Band nicht unnötig erneut. |
| [onboarding/profile_setup.dart](../../lib/ui2/onboarding/profile_setup.dart)<br>[profile/birth_date_field.dart](../../lib/ui2/profile/birth_date_field.dart) | Ansicht: Dein Profil einrichten; Muster: Eingaben / Profil | Alle Profilangaben sind überspringbar; fehlende Eingänge bleiben unbekannt (B02). Ungültiges Datum bleibt ein Feldfehler. Profilbearbeitung verwendet dieselben Felder. |
| [app_shell.dart](../../lib/ui2/app_shell.dart) | Ansichten: vier Bereiche; Tafeln: Navigation, Widgets und laufende Aktivität | Übersicht, Gesundheit, Training, Journal. Ernährung und eigene Beobachtungen liegen im Journal. Profil und Coach bleiben Unterseiten. Laufendes Training bleibt erreichbar, auch nach Wiederaufnahme oder unbekanntem Aktivitätstyp. |
| [app.dart](../../lib/app.dart) | Ansichten: erster Speicherbeleg, bestätigtes Übertragungsende, Dein Tag entsteht, Übertragung fortsetzen | Quellenwahl → optionales Profil → Übertragung → lokal gespeicherter Abschnitt → Übersicht. Der neue Speicherbeleg braucht später eine ausdrückliche Anbindung an die vorhandene Zustandsmaschine. |

### Übersicht und Gesundheit

| Vorhandene Quelle | Gestaltung | Erhaltenes Verhalten |
| --- | --- | --- |
| [screens/home_screen.dart](../../lib/ui2/screens/home_screen.dart) | Ansichten: Übersicht vollständig, dunkel, teilweise, unterbrochen, ohne Nacht; Datumsauswahl, historischer Tag, Scrollfortsetzung und A/B-Vergleich | Kleine tägliche Einordnung neben den Hauptwerten; jede Zahl hat ihren Zeitraum. Fehlende Daten sind keine Null. Laufende Auswertung und veraltete Ergebnisse erhalten eigene Gründe. |
| [screens/health_screen.dart](../../lib/ui2/screens/health_screen.dart) | Ansichten: Gesundheit hell/dunkel mit Scrollfortsetzung, Alle Messwerte, Laborwert eintragen; Muster: Trend, Eintrag, begründeter Leerzustand | Überblick, Erkunden, Trends, Vitalwerte und Labor bleiben erreichbar. Manuelle Laborwerte sind keine Bandmessungen. |
| [screens/metric_detail.dart](../../lib/ui2/screens/metric_detail.dart) | Ansichten: Ruhepuls, Deine Schritte, Erklärungen; Muster: gemeinsames Messwertdetail | Wert, Einheit, Datum, eigener Vergleich, Verlauf, Quelle und Verfügbarkeit. Das Muster gilt auch für Atemrate, Schlafanteile, Effizienz, TRIMP, HRR, Dip, LF/HF, HRV-CV, BRV, Aktivminuten, Tragezeit und Nickerchen. Erholung, Tagesbelastung und nächtlicher Stress haben eigene Detailansichten. Keine erfundene Kurve bei fehlenden Eingängen. |
| [screens/investigate.dart](../../lib/ui2/screens/investigate.dart)<br>[screens/beats.dart](../../lib/ui2/screens/beats.dart) | Ansichten: Herzintervalle, Dein Datenstand; Muster: Diagnose-/Quellzeile | Qualität und Ablehnungsgrund vor Details. RMSSD-Verlauf, Poincaré und RR-Qualitätswerte nur bei tatsächlichen Daten. Quellnotiz, Algorithmusstand und Abdeckung bleiben zugänglich. Keine erfundene Messkurve. Eine ausdrücklich als Prinzipbild bezeichnete Pulsintervall-Illustration erklärt die Methode, ohne Rohdaten vorzugeben. |
| [screens/readiness_detail.dart](../../lib/ui2/screens/readiness_detail.dart)<br>[screens/driver_breakdown.dart](../../lib/ui2/screens/driver_breakdown.dart) | Ansichten: Erholung verstehen, Deine Erholung, Erholung verfügbar, verwendete Eingänge und Modell; Muster: verfügbare / offene Treiber | Vorhandene OpenStrap-Berechnung und dieselben Treiber wie im Backend. Fehlende Basis, unzuverlässige Intervalle und fehlende Nacht sind unterschiedliche Zustände. Der verfügbare Score hat eine eigene Ansicht mit verwendeten Eingängen und Modell. Kanonischer Composite und ältere parallele Bewertung dürfen nicht vermischt werden; keine WHOOP-Formel. |
| [screens/circadian_detail.dart](../../lib/ui2/screens/circadian_detail.dart) | Ansicht: Dein Schlafrhythmus; Muster: Messwertdetail | Aktogramm und eigener Rhythmus. Chronotyp, SRI und sozialer Jetlag nur bei ausreichendem Verlauf. M10/L5 beruhen auf stündlicher Herzfrequenz, nicht auf Bewegungsbeschleunigung. |
| [screens/month_grid.dart](../../lib/ui2/screens/month_grid.dart)<br>[screens/day_timeline.dart](../../lib/ui2/screens/day_timeline.dart) | Ansichten: Dein Verlauf, Dein Tag im Verlauf | Datumswahl; Zeitachse für zeitlich bekannte Ereignisse. Einträge ohne Uhrzeit darunter. Nebeneinanderliegende Ereignisse behaupten keine Ursache. |
| [screens/findings_log.dart](../../lib/ui2/screens/findings_log.dart)<br>[screens/what_changed.dart](../../lib/ui2/screens/what_changed.dart)<br>[screens/rough_night.dart](../../lib/ui2/screens/rough_night.dart) | Ansichten: Rückblick, Auffälligkeiten; Muster: ruhige Auswertung, eigene Einordnung und Datenquellen; Einstieg über Gesundheit | Ruhiger Vergleich ohne Auffälligkeit ist ein gültiges Ergebnis. Rückblick und Auffälligkeiten bleiben datiert. Bei rauer Nacht erst Messbeobachtung, dann freiwillige eigene Einordnung. Keine unbestätigte Alkohol-, Krankheits- oder Zyklusursache und kein künstlicher Ungelesen-Zähler. |
| [screens/day_steps.dart](../../lib/ui2/screens/day_steps.dart) | Ansicht: Deine Schritte; Muster: Quelle / Abdeckung | Band- und iPhone-Fenster getrennt; Überlappung nicht doppelt zählen. Null nur bei tatsächlichem Zählerstand. Keine Stundenbalken nach dem letzten gespeicherten Datensatz. |

### Schlaf und Korrektur

| Vorhandene Quelle | Gestaltung | Erhaltenes Verhalten |
| --- | --- | --- |
| [screens/sleep_detail.dart](../../lib/ui2/screens/sleep_detail.dart) | Ansichten: Nachtbild 22Q/25K hell/dunkel, 24 Minuten ohne Daten, Noch keine Nacht, Nacht im Detail | Bettzeit, geschätzter Schlaf, Phasen, Lücken, persönliche Spanne und Quelle. Der Ring zeigt die Phasenzusammensetzung der Bettzeit mit Schlafdauer im Zentrum, keinen Schlafscore. Der Phasenverlauf besitzt eine Uhrzeitachse. |
| [screens/sleep_detail.dart](../../lib/ui2/screens/sleep_detail.dart) | Ansichten: Schlafzeiten prüfen → Vorschau → Zeiten gespeichert → Schlaf aktualisiert / Auswertung pausiert; Dialog: Korrektur zurücknehmen | Automatische Nacht bestätigen, ändern, verwerfen und Änderung zurücknehmen. Speichern und Neuberechnen bleiben getrennt. Vorherige Schätzung wird datiert, kein stilles Zurückspringen. |
| [screens/sleep_detail.dart](../../lib/ui2/screens/sleep_detail.dart) | Ansicht: Zeitzone prüfen; Muster: native Datum-/Zeitauswahl | Aufzeichnungszeitzone und aktuelle iPhone-Zeitzone unterscheiden. Die Nacht gehört zum Aufwachtag. Zeitumstellung verändert die reale Dauer. |
| [screens/naps.dart](../../lib/ui2/screens/naps.dart) | Ansicht: Nacht & Nickerchen; Muster: Zeitformular, Speichern/Auswerten, Löschbestätigung | Hinzufügen, Bearbeiten, Entfernen und Wiederherstellen. Manuell eingetragen und automatisch erkannt bleiben verschieden. Keine Schlafphasen oder zweite Erholung. Erkannte, verworfene Sitzungen bleiben wiederherstellbar; eigene gelöschte Einträge werden nicht als Detektor-Ablehnung gespeichert. |

### Training und Aktivität

| Vorhandene Quelle | Gestaltung | Erhaltenes Verhalten |
| --- | --- | --- |
| [screens/workout_screen.dart](../../lib/ui2/screens/workout_screen.dart) | Ansichten: Training hell/dunkel, Verlauf und Filter, minimierte Aufzeichnung; Muster: Vorschlag, noch zu wenig Historie | Für dich, Aktivitäten und Verlauf. Eigene Vorlagen und geführte Entwürfe sind vorgesehen; kein ungeprüfter Trainingsplan wird automatisch gespeichert. CTL/ATL benötigen ausreichend Historie. |
| [activity/picker.dart](../../lib/ui2/activity/picker.dart)<br>[activity/catalogue.dart](../../lib/ui2/activity/catalogue.dart)<br>[activity/tiles.dart](../../lib/ui2/activity/tiles.dart) | Ansicht: Was hast du vor?; gemeinsame Auswahl-/Suchzeilen | Aktivitätsbibliothek, Gruppen und zuletzt verwendet. Gleiche Auswahl für bestehende Sportarten; keine Kalorienvorschau ohne Gewicht. Geh-/Laufsymbole nur für passende Aktivität. |
| [activity/setup.dart](../../lib/ui2/activity/setup.dart) | Ansicht: Laufen vorbereiten; Muster: Berechtigungsfehler / laufende Sitzung | GPS und Privatsphäre nur, wo sinnvoll. Bestehendes laufendes Training zuerst fortsetzen oder beenden. Keine wirkungslosen Zielregler. |
| [activity/live.dart](../../lib/ui2/activity/live.dart) | Sechs Ansichten: Laufen, Krafttraining, Schwimmen, Yoga, Tennis, Intervalle; Dialog: Beenden | Zeit und tatsächliche Eingaben bestimmen die Darstellung. Kein Puls, GPS oder Watt ohne Quelle. Aktive Entwürfe und PendingResult müssen Speicherfehler überleben (B138). Sätze, Bahnen, Positionen, Punkte und Intervalle verwenden die jeweilige Bedienform. Pause und Wiederaufnahme erhalten den Entwurf. |
| [activity/summary.dart](../../lib/ui2/activity/summary.dart) | Ansicht: Dein Lauf; Tafel: acht Ergebnisformen | Route, Kraft, Intervalle, Flow/Yoga, Bahnen, Tour, Spiel und Grundform. Gleicher Rahmen für Art-/Zeitedit, RPE, Teilen und Löschen. Ergebnis-Yoga zeigt Positionen; thermische Aktivitäten verwenden tatsächlichen Pulsverlauf. Keine Muskelkarte. |
| [activity/share.dart](../../lib/ui2/activity/share.dart)<br>[activity/poster.dart](../../lib/ui2/activity/poster.dart) | Ansicht: Training teilen als Einstieg; Muster: Ergebnisbaustein + native Teilen-Ansicht | Exportposter verwendet dieselben gemessenen Werte und denselben Zeitraum. Keine ergänzten Kalorien, Strecke oder Route. |
| [activity/zones.dart](../../lib/ui2/activity/zones.dart)<br>[activity/day_strain.dart](../../lib/ui2/activity/day_strain.dart) | Ansichten: Belastung, Berechnung und Daten, Herzfrequenzbereiche | Geschätzte Herzfrequenzgrenzen von beobachteten Maxima unterscheiden. Belastung 0–21 stammt aus der vorhandenen Banister-Verwandtschaft, nicht aus WHOOP. |
| [screens/log_workout.dart](../../lib/ui2/screens/log_workout.dart) | Ansicht: Training eintragen; Dialog: Erkennung prüfen; Muster: Löschen / gespeicherte Änderung | Erkannter Kernabschnitt ist nicht automatisch die ganze Trainingseinheit. Bestätigung hat Berechnungsfolgen für Belastung und Kalorien. Ausblenden entfernt nur den Vorschlag. |

### Ernährung

| Vorhandene Quelle | Gestaltung | Erhaltenes Verhalten |
| --- | --- | --- |
| [screens/nutrition_screen.dart](../../lib/ui2/screens/nutrition_screen.dart) | Ansichten: Ernährung, Ernährungswoche, Ernährungsziele | Heute/Woche/Ziele; bei unbekannter Mahlzeitenenergie „mindestens“. Wochenmittel nur aus vollständigen Tagen. Wasser in 250-ml-Schritten, keine negativen Mengen. Ziele manuell und optional; leeres Feld entfernt, ungültige Eingabe überschreibt nicht. |
| [screens/log_food.dart](../../lib/ui2/screens/log_food.dart) | Ansicht: Mahlzeit eintragen; Muster: Suche, Auswahl, Bearbeiten/Löschen | Mahlzeit, Suche und Barcode. Externe Lebensmittelsuche nur bei eingeschalteter Option. Keine erfundene Nährstoffanalyse. |
| [screens/scan_barcode.dart](../../lib/ui2/screens/scan_barcode.dart) | Ansicht: Barcode scannen; Muster: Kamera nicht erlaubt / manuell eingeben | Kamerafreigabe und manuelle Alternative. Produkt-Strichcodes; QR-Codes sind keine Lebensmittel. |

### Journal, eigene Beobachtungen und Coach

| Vorhandene Quelle | Gestaltung | Erhaltenes Verhalten |
| --- | --- | --- |
| [screens/wellness_screen.dart](../../lib/ui2/screens/wellness_screen.dart) | Ansichten: Journal hell/dunkel mit Scrollfortsetzung, Gewohnheiten, Medikamente; gemeinsame Messwert-/Formmuster | Mind, Habits, Medication und optional Cycle im Journal; Recovery und nächtlicher Stress in Gesundheit. Stimmung 1–5; gespeicherte Stressberechnung. Gewohnheiten binär höchstens einmal täglich, Konsistenz über 14 Tage. Medikamentenquote schließt zukünftige Termine aus. |
| [screens/calm_breathing.dart](../../lib/ui2/screens/calm_breathing.dart)<br>[screens/start_card.dart](../../lib/ui2/screens/start_card.dart) | Ansichten: 56F und 1IFA–1IQ7; Tafel: laufende Aktivität | Vorbereitung, Lauf, Pause, Abschluss. Ruhige Atemführung ohne erfundene Wirkung. Einzelne Vorher-/Nachher-Werte sind kein Wirkungsnachweis; Live Activity und Kurzbefehle berücksichtigen. |
| [journal_editor.dart](../../lib/openband/journal_editor.dart)<br>[journal_fields.dart](../../lib/openband/journal_fields.dart) | Ansichten: Dein Journal, gespeichert, Speicherfehler und Änderungen verwerfen; Muster: Formularfeld, Auswahl, eigener Eintrag | Stimmung, Schlafqualität, Energie, Stress, Muskelkater 1–5; Wasser, Koffein mit Uhrzeit, Alkohol mit Uhrzeit, Bildschirmzeit, Gewicht, Tags und Notiz. Eigene binäre Felder. Gewichtstrend erhält Lücken und keine ungefragten Ziele oder Benachrichtigungen. |
| [screens/cycle_screen.dart](../../lib/ui2/screens/cycle_screen.dart) | Ansichten: 5EF/7EJ und 1I0F–1IAV; historischer Beginn, Symptome, Einstellungen und fehlende Schätzung | Freiwillig und anfangs aus. Schätzung aus eigenen Startdaten: mindestens zwei für eine Vorhersage, drei für eine Bandbreite; große Lücken verweigern sie. Keine Fruchtbarkeit, Ovulation oder Schwangerschaftsbehauptung. |
| [screens/coach.dart](../../lib/ui2/screens/coach.dart)<br>[screens/coach_figures.dart](../../lib/ui2/screens/coach_figures.dart)<br>[screens/ai_briefing.dart](../../lib/ui2/screens/ai_briefing.dart) | Ansichten: Dein Coach, Coach einrichten, Verwendete Daten; Muster: explizite Schreibbestätigung | Optionaler lokaler Anbieter oder eigener Cloud-Schlüssel. Erlaubte Datenansichten und genaue Eingaben bleiben sichtbar. Jede Änderung braucht Bestätigung. Morgen-/Abendbriefing verlinkt seine verwendeten Daten. |

### Profil, Band, Daten und Einstellungen

| Vorhandene Quelle | Gestaltung | Erhaltenes Verhalten |
| --- | --- | --- |
| [profile/profile.dart](../../lib/ui2/profile/profile.dart) | Ansicht: Dein Profil; Muster: Profilfelder / externe Links | Profil, Geräte, Coach, Sprache, Speicher, Einstellungen und Community. Reine Speicherinformation ist keine vorgetäuschte Navigation. |
| [profile/settings.dart](../../lib/ui2/profile/settings.dart) | Ansichten: Einstellungen, Weitere Optionen, Mitteilungen; Dialoge: Darstellung, Zurücksetzen | Einheiten, Sprache, Darstellung, Telefon-Schritte, Mitteilungen, Zyklus, Health-Schreiben, App-Symbol, Gesten, Kurzbefehle, Diagnosefreigabe, externe Barcode-Suche, Hinweise und Reset. Allgemeine Auswahllisten verwenden das Darstellungsmuster, Untergruppen dieselben Einstellungszeilen. |
| [profile/devices.dart](../../lib/ui2/profile/devices.dart)<br>[profile/pair_sensor.dart](../../lib/ui2/profile/pair_sensor.dart) | Ansichten: 5QW, 1JER–1JK3; priorisierte Quellen, Suche, Verbindung und Unterbrechung | Primäres Band und weitere Sensoren getrennt. Priorität nur für tatsächlich konkurrierende Signale und speicherbare Geräte-IDs. Bereits abgeschlossene Tage behalten ihre Quelle. Nur gelieferte Quellen erscheinen; ein Verbundensein allein bedeutet keine Messwertbereitschaft. iOS-Zubehörfreigabe vor dem BLE-Sensorzugriff. |
| [profile/data.dart](../../lib/ui2/profile/data.dart) | Ansichten: Deine Daten, Sicherung erstellen, Import abgeschlossen; Muster: Speicher-/Fehlerzustände | CSV, Datenbank, vollständige geschützte Sicherung, Originalarchiv, Import und Neuauswertung. Der neue Sicherungscontainer benötigt DB, Originale und Manifest (B160). Vorhandene automatische DB-Sicherungen bleiben anfangs aus und werden als unverschlüsselt bezeichnet. Vorhandene Bandtage nicht überschreiben; gespeicherter Import bleibt bei Rollup-Fehler bestehen. |
| [profile/phone_import.dart](../../lib/ui2/profile/phone_import.dart) | Ansicht: Daten vom iPhone; Muster: native Health-Freigabe | Quellenfreigabe nachvollziehbar. Importierter Ruhepuls ist ein Startwert, keine gemessene Bandnacht. Kein SDNN-HRV-Import als RMSSD. Blutdruck, Glukose und Temperatur nur mit ihrer importierten Quelle anzeigen. |
| [profile/alarm.dart](../../lib/ui2/profile/alarm.dart) | Ansicht: Dein Wecker; Tafel: Wecker ohne Plan / bestätigt / unbekannt | Wochenplan mit Uhrzeit pro Tag, Testvibration, Abbrechen. Gesendet, ausstehend, bestätigt und unbekannt getrennt; kein Erfolg allein wegen eines abgeschickten Schreibbefehls. |
| [profile/gestures.dart](../../lib/ui2/profile/gestures.dart)<br>[profile/band_notifications.dart](../../lib/ui2/profile/band_notifications.dart) | Ansichten: 61S, 1JLN/1JO0; verfügbare Aktionen und Plattformbeschränkung | Auf iPhone nur unterstützte Doppeltipp- und Kurzbefehlsaktionen. Android-Benachrichtigungsweiterleitung und Tasker nicht als iPhone-Funktion zeigen. Kein zugesagter Systemlautstärke- oder Fremdplayerzugriff. |
| [profile/gallery.dart](../../lib/ui2/profile/gallery.dart) | Tafeln: Grundlagen und gemeinsame Zustände; kein regulärer Produktweg | Entwicklergalerie bleibt versteckt. Synthetische Galeriebeispiele werden niemals als gemessene Nutzerdaten ausgegeben. |

## Gemeinsame Zustände und Bedienung

Die bestehenden Rollen aus [grammar.dart](../../lib/ui2/grammar.dart) bleiben die funktionale Grundlage: einzelner Messwert, Fortschritt, Verlauf, Einordnung, Aktion, Status und Detail. [theme.dart](../../lib/ui2/theme.dart), [charts.dart](../../lib/ui2/charts.dart), [paint_activity.dart](../../lib/ui2/paint_activity.dart), [live_hr.dart](../../lib/ui2/live_hr.dart), [nudges.dart](../../lib/ui2/nudges.dart) und [scroll_hint.dart](../../lib/ui2/scroll_hint.dart) sind gemeinsame Darstellungshilfen, keine zusätzlichen Screenfamilien. Ein fehlender Wert erhält immer einen lesbaren Grund; ein Strich allein reicht nicht.

Die Tafeln „Zustände · vier unabhängige Aussagen“ und „Gemeinsame Bedienmuster und Sonderfälle“ ergänzen die iPhone-Ansichten:

| Dimension | Unterscheidung |
| --- | --- |
| Verbindung | Gekoppelt, verbunden, getrennt, Bluetooth aus, Verbindung abgebrochen |
| Übertragung | Noch nichts gespeichert, läuft, pausiert/unterbrochen, aktueller Lauf bestätigt beendet |
| Aktualität | Zeit der jüngsten gespeicherten Bandaufzeichnung; Zeitpunkt des Eingangs separat. Alter bezieht sich auf den gewählten Datenzeitraum. |
| Abdeckung | Zeitraum benennen; vollständig, teilweise mit Lücke, ohne Daten. Keine Gleichsetzung mit Tragezeit oder Tagesquote. |
| Messwert | Bereit, noch zu wenig Vergleich, ungeeignete Eingänge, Auswertung ausstehend/fehlgeschlagen, technisch nicht unterstützt |
| Formular | Leer/optional, gewählt, bearbeitet, ungültig, Speichern gesperrt, gespeichert; Feldfehler erklärt die nötige Korrektur. |
| Änderung | Vorschau, Bestätigen, Abbrechen, gespeichert aber noch nicht berechnet, aktualisiert, erneut auswerten, zurücknehmen |
| Destruktive Aktion | Konkretes Objekt und Folge im Dialog; Beenden/Verwerfen/Löschen nicht durch generisches „OK“ ersetzen. |
| Berechtigung | Vor Erklärung keine Freigabe vortäuschen; native Dialoge für Zubehör, Health, Standort, Bewegung, Kamera und Mitteilungen. Ablehnung lässt gespeicherte Daten zugänglich. |
| Lokaler Bestand | Wiederhergestellte Daten und fehlende Tabellen benennen; beschädigtes Original separat erhalten; Importresultate einzeln ausweisen. |
| Auswertung ohne Auffälligkeit | Erfolgreicher ruhiger Zustand; nicht „keine Daten“ und keine künstliche Warnung. |

Mitteilungen umfassen die bestehenden Kategorien: Gesundheit, Bandakku, Weckerfehler/fehlender Plan, Erholung, Wochenrückblick, Training, Bewegung, Schlafvorbereitung, Schritte, Medikamente, Check-in, Wasser und Ruhezeiten. Schlafvorbereitung bleibt ohne gelerntes Zeitfenster ruhig. Die gezeigte Einstellungsansicht bündelt diese Kategorien; Unterlisten wiederholen dasselbe Zeilenmuster.

Quellenpriorität verwendet eine verschiebbare Liste je konkurrierendem Signal, mit „Automatische Reihenfolge wiederherstellen“. Der Einstieg entfällt bei nur einer geeigneten Quelle. Freigaben und verbundenes Zubehör ersetzen keine gespeicherten Messdaten.

## Routen, Widgets und native Oberflächen

Quellen: [Benachrichtigungsrouten](../../lib/notify/tap_router.dart), [Widget-Service](../../lib/widget/widget_service.dart), [Training-Live-Activity](../../lib/live/live_activity.dart) und [Atem-Live-Activity](../../lib/live/breathing_live_activity.dart).

| Vorhandenes Ziel | Sichtbarer Weg |
| --- | --- |
| `/ai/morning`, `/ai/evening` | Übersicht → Briefing → verwendete Daten |
| `/journal/compose`, `/breathing` | Journal → datierter Editor; Atmen aus Journal oder Gesundheit mit Rückkehr zum Ursprung |
| `/water`, `/meds` | Journal → Wasserabschnitt oder Medikamente; bestehendes Ziel fokussieren |
| `/today/movement`, `/today/recovery`, `/today/steps` | Übersicht, passender datierter Eintrag; Schlaf-/Messwertdetails über denselben Datenstand |
| `/workouts/suggestion?id=`, `/workouts/idle` | Training → Vorschlag / laufende Aktivität |
| `/profile`, `/alarm`, `/recap` | Profil / Wecker / Gesundheit-Rückblick |

Bekannte entfernte Objekte öffnen einen verständlichen Leerzustand im passenden Bereich (1JPJ); nur unbekannte alte Payloads fallen ohne Mutation auf Übersicht zurück. Die Tafel „Widgets und laufende Aktivität“ zeigt kleine/mittlere Widgets und eine pausierte Aktivität. Auch dort bleiben Datum und Datenstand sichtbar. Native Zubehör-, Datum-/Zeit-, Share-, Berechtigungs- und Tastaturoberflächen werden in der Umsetzung vom iPhone bereitgestellt; sie sind keine nachgezeichneten Systemdialoge.


## Konkrete Vertiefungen und Abschlussstände

Die IDs sind Paper-Artboards; der exakte Titel und die Seite stehen im [Screeninventar](DESIGN_SCREEN_INVENTORY.json). Zwischenansichten, Fehler und Rückkehr sind zusätzlich pro Flow verzeichnet.

| Familie | Aktuelle Review-Anker | Vertrag |
| --- | --- | --- |
| Übersicht | 1V0, 1Y8, 8OM, AF2, AJS, 2B9, 2EM, 2HU, L6R, 11QX | Datum, weiterführender Feed, laufende Einheit, vier unabhängige Statusdimensionen |
| Schlaf | 22Q/25K; 16RN/16UZ; 16Y1–19QM; JN/L1/M8/NG/OT; 1GDD/1GDQ; 6B2 | Dauer und Phasen; zeitlich richtige Korrektur, Commit und Neuberechnung; ungültige Eingabe/Retry/Rücknahme |
| Schlafplanung/Nickerchen | 19TV/19W1/19Y9/1A07; NO1/NT9; 14NV/14Q0 | Eigener Zielwert und geschätzter Bedarf getrennt; eigenständige Sitzungen, Überlappung und exakte Löschung |
| Erholung/Stress | AMX, BGD, 17G5; APX; 1BGC/1BIA/1BKG/1BMT/1D8S | Erholung aus versioniertem Composite; Nacht-SI, geplante Tagesfenster und eigene Stressangabe nicht vermischen |
| Gewicht/VO₂max | 1EUD/1EUQ/1EV3/1EVG; 1ELE/1ENR/1EOW/1ER7/1ET8 | Undatiertes Profil ist keine Messung; importierte/eigene Messung mit Datum und Quelle; keine VO₂max-Schätzung aus bloßem Ruhepuls |
| Labor | 4E4; 1ISJ/1IUJ/1IXQ/1IZS/1J1R/1J30 | Marker, eigener Befundbereich, Datum, Einheit, Speichern, fehlende Referenz und exakte Löschung |
| Live-Training | 4LC–4TM; 11QX; 1AKS | Sieben vorhandene Darstellungsfamilien in gemeinsamem Lebenszyklus; Pause, Minimieren, Abschluss, Save-Failure und Wiederaufnahme |
| Trainingsdetail | 4UY/JDE/J9D; IUA/ILE/IOA/IRC/IXD; J51 | Route, Splits, Zonen, Lücken, Energiequelle, HRR und Kraftsätze; keine erfundenen fehlenden Werte |
| Vorlagen/Übungen | 1F6K/1DSA/18C9/DDO; 7AX als Wegweiser | Definition, Planrevision und Workout-Snapshot trennen; Auswahl, Suche, Fotoentwurf, Supersatz, Reihenfolge, Austausch, Archiv und Retry |
| Journal | 53Y/B2I/BC6; 57I/C16/BYY/C05; ODJ/UPN/12P1 | Offene Antworten bleiben offen; aktueller Tabrahmen, historischer Tag, atomare Teiländerungen und erhaltene Entwürfe |
| Journalmuster | 129V/12C2/12DY/12FD/12GR; Flows 092/093 | Paarzahl, Vergleich und Unsicherheit; keine Kausalbehauptung, keine „Nein“-Antwort aus fehlender Zeile |
| Ernährung | 4XB/FR6/1DAZ; 143W/146V/149T/15NG; 4ZY/G75 | Bekannte Teilsummen; Portionen, Eintrag und Definition trennen; Bearbeiten/Löschen und sichere Rückkehr |
| Lebensmittel/Rezepte | F-Seite, Flows 003–016, 020–024, 027–039, 091–114 | Lokale Suche, freiwillige externe Suche, Barcode, Foto/Textvorschlag, Prüfung, Rezeptdefinition, Verzehr und Herkunft |
| Medikamente | 5CG; 1HFP/1HIV/1HL7/1HN2/1HQ3/1HRB/1HSR/1HV7 | Plan → Termin → Eintrag; Erinnerungen optional; unbekannt/ausgelassen/eingenommen getrennt; Zukunft aus Quote ausgeschlossen |
| Zyklus | 5EF/7EJ; 1I0F/1I2M/1I4O/1I68/1I8D/1IAV | Einwilligung, historischer Beginn, Symptome, Zeitspanne, Ausblenden ohne Löschen; große Lücken sperren die Schätzung |
| Atmen | 56F; 1IFA/1IGZ/1IJ0/1IKB/1IM9/1INY/1IQ7 | Atemführung ohne Band, optionale Resonanzmessung, Tempovergleich, frühes Ende und nicht gespeichertes Ergebnis |
| Coach | 5G3/XBX/5J9; 5HD; RPW–S14; VV6–W0R | Optionaler Anbieter, konkrete Freigaben, Quellen, bestätigte Änderungen, gespeicherte Angaben und Widerruf |
| Band/Übertragung | 5QW/A4; 1DYG/1E0M/1E2V/1E53/1E79 | Verbindung ≠ Datenstand ≠ Nachtabdeckung ≠ fertige Auswertung; Teilcommit und Wiederaufnahme |
| Quellen/Health | 5Y3; TI3/TKP/TMY; X4T/X7A/X9R; 11F3/17LR/17NQ/17Q1 | Lesen/Schreiben getrennt; Quelle, Priorität, historischer Import und Berechnungsrevision |
| Export/Sicherung | 5SX/5WD/642; 1J4D/1J6M/1J8R/1JAM/1JCI | Vorbereiten ≠ extern gespeichert; vollständige Sicherung vs Tabellen/DB/Originale, Bereichsfehler und Retry |
| Geräte/Gesten | 1JER/1JGD/1JI3/1JK3; 1JLN/1JO0 | Zusätzliche HR-Quelle, iOS-Zubehörzugriff, keine unbelegte Wellness-Auswertung; Gesten mit Beleg und Undo |
| Wecker | 5UV/KNI; 18VN/18XH/18YU/1909/191V | Lokal geplanter Termin, zuletzt bestätigt, ausstehend und bestätigt ausgeschaltet getrennt |
| Einstellungen | 5OM/BPM/1980; QO3/QKD/1DQ9; 19CF/19EW | Wie iPhone/Hell/Dunkel; kein paralleler Hintergrundschalter; Datenschutz, freiwillige Dienste, Lizenznachweise |
| Mitteilungen/Widgets | ZAD/ZDJ/ZEX/ZHZ; 7OY/1F3V/19KF/1JPJ | Datierter Snapshot, Route plus Objekt, kalter/warmer Start, verlorenes Ziel und keine automatische Mutation |
| Datenpflege/Entfernen | W8J/WIM/WAQ/WCS/WF0/WH8; 68X/Y4L/Y61/Y7P | Anzeige neu laden vs neu berechnen; Originale fehlen; Löschen mit Umfang, Teilfehler und erneutem Einrichten |

## Anschlusslücken und Verantwortlichkeiten

[Backend-Anforderungen B01–B166](DESIGN_BACKEND.md) sind der verbindliche technische Anschluss nach Review. Die vorhandene App ist die Grundlage, keine Aussage über bereits implementierte Entwurfsfunktionen.

- **edge:** vier Tabs statt alter fünf Indizes (Migration 0→0, 1→1, 2→3, 3→2, 4→3); gemeinsamer Tageskontext; Router mit Herkunft; Draft, Commit, Retry und klare Belege; Bluetooth-Sitzung, gespeicherter Frontier und Quelldatenarchiv.
- **analytics:** datierte, versionierte Ergebnisse samt verwendeten Fenstern, Eingängen, persönlicher Basis, Qualitätsgründen und Berechnungsbereitschaft. Neue Tagesstressfenster aus B142 müssen erst umgesetzt und validiert werden.
- **protocol:** korrekte Decoder und Bandbefehle. Keine UI- oder Datenbankzuständigkeit; ACK erst nach von edge bestätigtem Commit.
- **iPhone:** Health-Provenienz, Berechtigungen im passenden Moment, Alarmbestätigung, WidgetKit/App Intents, Dynamic Type, VoiceOver, Tastatur und Reduce Motion.
- **Speicherfehler:** Live-Abschluss, Schlafkorrektur, Journal, Essen, Vorlagen, Medikamente und Atemsitzung dürfen ihren Entwurf nicht vor erfolgreichem Commit verlieren.
- **Profil:** Überspringen ist erlaubt. Der aktuelle Code verwendet teilweise Ersatzkonstanten; B02 verlangt einen unbekannten Zustand und konkrete Refusal-Gründe statt verdeckter Ersatzwerte.
- **Datenhaltung:** kein unbegrenztes Archiv versprechen. Vollständige Sicherung enthält nur tatsächlich aufbewahrte Originale, mit Zeitraum, Manifest und fehlenden Teilen.

## Synthetische Daten und Regeln

[day-summary.json](assets/fixtures/day-summary.json) ist der gemeinsame A/B-Basissnapshot. Weitere Fixtures dokumentieren Schlafphasen, Lauf, Glukose, Journalmuster, Schlafplanung, Belastungs- und Gewichtsverlauf sowie zusätzliche Bereiche. Sie sind keine Aufzeichnungen einer Person.

Die aktuelle Nacht darf ihren eigenen Vergleich nicht erweitern. Unbekannt ist nicht null. Ein vollständiges Quellfenster garantiert keine geeigneten Herzintervalle. Historische Methodenwechsel bleiben sichtbar. Selbst erfasste Stimmung, Medikamente, Essen oder Symptome sind keine Sensormessungen. Planung ist keine abgeschlossene Aktivität.

## Plattformgrenzen und bewusste Nichtübernahmen

Kein Konto-/Paywallzwang, proprietärer WHOOP-Score, übernommener Bevel-Food-Score oder Energy-Bank. Keine Fruchtbarkeits-, Medikamenteninteraktions- oder Diagnosefunktion. VO₂max benötigt eine benannte Messung; SpO₂ kann als separate tatsächlich verfügbare Quelle dargestellt werden, keine erfundene Bandmessung oder Apnoe-Diagnose. Watt und GPS nur bei geeigneter Quelle. Eine Watch-App ist nicht Teil dieses iPhone-Entwurfs.

Android-Bandbenachrichtigungen, Tasker und Systemlautstärke bleiben plattformspezifisch. Firmwareänderungen, R22 und Force-Trim sind keine nutzerseitigen Reparaturaktionen. Native Zubehör-, Berechtigungs-, Share- und Datum-/Zeitdialoge werden später vom System bereitgestellt.

## Nachweis

Jede behaltene Ansicht ist im Inventar erfasst. Gemeinsame Listen-, Formular-, Messwert-, Fehler- und Bestätigungsmuster decken Wiederholungen ab; es gibt nicht für jede theoretische Kombination eine eigene Zeichenfläche. Alle 153 Quellflows sind mit Entscheidung, Paper-Zuordnung und Backend-Notiz dokumentiert.

[Handoff und Nachweisgrenzen](DESIGN_DIRECTION.md#quellen-und-nachweisgrenzen). Dies ist ein editierbarer Designstand, kein interaktiver App-Prototyp. Kein App-Code wurde für diese Phase geändert. Native Bedienung, Bluetooth, physiologische Gültigkeit und tatsächliche Wiederherstellung bleiben eigene spätere Nachweise.


## Visuelle Revision · 17. September 2026

Alle 583 iPhone-Ansichten und acht Tafeln sind an die bestätigte Übersicht angeglichen. 102 gezielte Neuaufbauten ergänzen die gemeinsame Verdichtung von Typografie, Text, Karten, Symbolen und sicheren unteren Abständen. Der erneute vollständige Export und die Kontaktbogenprüfung decken sämtliche behaltenen Ansichten ab. Bestands- und Textzensus stehen im Screeninventar; die technischen Ergänzungen B163–B166 im Backend-Handoff. Native Interaktion bleibt unimplementiert.
