# Design-Assets

Stand: 17. September 2026. Nur Design und Referenzmaterial.

| Datei | Herkunft und Verwendung |
| --- | --- |
| `sleep-dawn.png` | Eigenes, mit ImageGen erzeugtes Hintergrundmotiv; 1254 × 1254 Pixel. Frühes dekoratives Morgenmotiv, im aktuellen Daten-UI nicht mehr verwendet. Keine Messdaten, Schrift oder UI eingebrannt. |
| `meal-synthetic-v1.png` | Eigenes generiertes Beispielbild für Fotoanhänge; keine Mengen- oder Nährwertmessung. |
| `bench-press-illustration-v1.png` | Eigene generierte Geräteillustration; keine Bevel-Grafik und keine Ausführungsanleitung. |
| `bevel-home-reference.webp` | [Bevel Home auf Mobbin](https://mobbin.com/screens/c33feab6-41f6-475a-b370-caa18c10e204); hochauflösende Quelle für die interne Referenztafel. |
| `whoop-recovery-reference.webp` | [WHOOP Erholung auf Mobbin](https://mobbin.com/screens/33b30723-adc2-4efa-82d5-6c320624aff3); hochauflösende Quelle für die interne Referenztafel. |

Die Konkurrenzaufnahmen bleiben als Originalreferenzen gekennzeichnet. Sie sind keine OpenBand-Produktassets. Die zeitlich begrenzten Download-URLs wurden nicht als dauerhafte Quellen verwendet.

## Originalprompt des Landschaftsmotivs

Der englische Prompt ist zur Reproduzierbarkeit unverändert dokumentiert:

> Use case: stylized-concept. Create one original image asset for the upper background of a gentle iPhone sleep-and-health app. Artwork only, absolutely no UI, no text, no numbers, no rings, no logos, no watermark, no device mockup. A softly rendered predawn landscape: three layers of smooth distant alpine silhouettes, thin mist collecting in the valley, a very small translucent crescent moon near the upper right. Refined atmospheric 3D / airbrushed editorial illustration, not cartoon. Pale ice blue and powder periwinkle, very faint rosy light along the horizon. It should feel like waking after a quiet night. Compose for a square 1024x1024 background cropped into a portrait phone header: upper 45 percent mostly open, very light luminous sky so dark UI text can sit there; hills occupy the middle and lower third, and the very bottom fades smoothly into near-white #F5F6FB. Low contrast, soft natural depth, elegant detail, no sharp mountains, no heavy shadow, no sparkles, no star scatter, no photorealistic clutter. The scene must remain decorative atmosphere, readable data will be added separately in editable native design layers.

Die tatsächliche Ausgabegröße ist maßgeblich. Das Motiv bleibt als dokumentiertes Entwurfsasset erhalten; die aktuelle Richtung verwendet ruhige Flächen ohne Landschaft hinter Daten. Weiche Linsen, Phasenbilder, Atemflächen und Bandillustrationen sind getrennte editierbare Vektoren. Dunkel verwendet eigene Graphitflächen und Datenfarben.


## Symbole und Schrift

[Lucide-Original-SVGs und Lizenznachweise](icons/README.md) liegen im Projekt. Die Symbole bleiben in Paper editierbar. Keine Emoji-Ersatzsymbole für reguläre Bedienelemente. Inter verwendet die SIL Open Font License; die App muss die Lizenztexte ihrer tatsächlich gebündelten Version ausliefern.

## Synthetische Fixtures

- `day-summary.json`: gemeinsamer A/B-Basissnapshot, Erholung 74, HRV 48.
- `sleep-detail.json`, `sleep-plan.json`: Nachtphasen und getrennte reife Planung.
- `run-detail.json`, `strain-history.json`: datierter Lauf und eigenständige Belastungshistorie.
- `journal-insight.json`, `journal-insight-no-finding.json`: getrennte reife Muster-/Kein-Muster-Beispiele.
- `glucose-source.json`, `weight-history.json`: zusätzliche Quellen und datierte Gewichtshistorie.
- `additional-flows.json`: Bettzeitfenster, Schritte, Korrektur, Medikamente, Zyklus, Atmen, Labor, Tagesstress und erster Sync.

Keine Datei enthält echte Gesundheitsdaten. Neue Einträge und reife Historien dürfen nicht still in den Basissnapshot gemischt werden. Die generierten Bildprompts und ihre Grenzen stehen in [GENERATED_ASSETS.md](GENERATED_ASSETS.md). UI, Diagramme und Text sind keine eingebrannten Bestandteile der Rasterbilder.
