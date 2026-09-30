# G3.1 Paper review — 30 September 2026

Scope: the nine Flutter screens on Paper page `p-1F-0`, in light and dark mode, using synthetic data. The score is the share of pixels whose channel difference exceeds the harness threshold; lower is closer. Each report in `build/g3-review/<mode>/<name>.png` shows Paper, app, onion, and diff. The reports are generated artifacts; the reference PNGs and registration are retained here.

## Baseline against the old G3 boards

These scores were measured before registering G3.1. They compare the current app to the **old grey G3** references. The dark HRV detail had no old entry. The G3.1 exports have different composition and height, so these are context, not paired improvement measurements.

| Existing G3 entry | Light | Dark |
| --- | ---: | ---: |
| `heute` | 18.09% | 14.41% |
| `schlaf-letzte-nacht` | 17.06% | 14.94% |
| `training-wurzel` | 16.50% | 14.93% |
| `G3JournalTabLight/Dark` | 16.34% | 12.05% |
| `verlauf-erholung-30-tage` | 17.33% | 9.81% |
| `verlauf-hrv` | 14.52% | — |
| `schlaf-nachtverlauf-puls` | 12.38% | 8.96% |
| `training-lauf-ergebnis` | 9.69% | 8.60% |
| `training-belastung-30-tage` | 8.84% | 7.33% |

## G3.1 screen results

`F` = fixture/render difference: synthetic values, trace shape, board height, scroll crop, or OS/font rasterization. `A` = visible app difference from Paper in layout, colour role, content, or copy. Common to every row: small status-bar/font raster differences and different bottom crop. The table records the additional prominent differences visible in each four-panel report. Fixture values and header controls that could be matched cheaply were corrected in the G3.1 builders; remaining fixture differences are stated explicitly. The names below have the `g31-` prefix in the registry.

| Frame | Score | Visible differences and classification |
| --- | ---: | --- |
| `heute-hell` | 19.67% | F: day trend samples/crop. A: taller check-in, different note wording, breathing-rate baseline text instead of a range scale; lower steps card is cropped. |
| `heute-dunkel` | 14.91% | F: day trend samples/crop. A: same check-in, note, breathing-rate and steps composition differences. |
| `schlaf-hell` | 18.11% | F: fine hypnogram/trace shape. A: tall night card with method text; different night metrics, week/regularity/debt order and extra navigation rows. |
| `schlaf-dunkel` | 15.00% | F: fine hypnogram/trace shape. A: same card height, method text, section order and navigation rows. |
| `training-hell` | 16.44% | F: week/recent values and zone-strip presence now matched; strip proportions are approximate. A: load hero uses a pointer, today's action row and week footer differ, taller recent cards crop the second row. |
| `training-dunkel` | 14.91% | F: week/recent values and zone-strip presence now matched; proportions approximate. A: same load, action, footer and recent-card height differences. |
| `journal-hell` | 16.58% | F: some prior-day synthetic values differ. A: taller check-in, `Ja` for caffeine instead of `1 Getränk`, expanded history before Muster. |
| `journal-dunkel` | 10.22% | F: some prior-day synthetic values differ. A: same check-in, caffeine answer and history ordering. |
| `verlauf-erholung-30-tage-hell` | 17.34% | F: app fixture has 27 chart days against Paper's 28. A: daily 74 lead and generic metric layout instead of 30-day Ø66 summary and four-day list. |
| `verlauf-erholung-30-tage-dunkel` | 17.11% | F: 27-versus-28 chart days. A: same 30-day-summary layout and content difference. |
| `verlauf-hrv-hell` | 13.69% | F: trend samples/dates differ. A: lead sits outside card; chart and five-night list are taller than Paper's compact card and four-night list. |
| `verlauf-hrv-dunkel` | 11.36% | F: trend samples/dates differ. A: same lead placement, chart and list differences. This dark variant was absent from the old registry. |
| `schlaf-nachtverlauf-hell` | 11.90% | F: pulse waveform differs; the 49/min low now occurs at 03:48 in both. A: lead/card captions, scale, pulse statistics and quality row differ; app card is taller. |
| `schlaf-nachtverlauf-dunkel` | 8.66% | F: pulse waveform differs; low time matches. A: same captions, scale, statistics, quality row and card height. |
| `training-lauf-ergebnis-hell` | 11.61% | F: pulse waveform differs; zone minutes/session state and 09:38 stamp match. A: header actions/date and card heights differ; Paper's basis, route, note and source rows are absent. |
| `training-lauf-ergebnis-dunkel` | 10.08% | F: pulse waveform differs. A: same header, card height and missing rows. |
| `training-belastung-hell` | 9.83% | F: fixture lacks Paper's 30-day strain series, leaving the app chart sparse. A: card order/height, Heute Bisher breakdown, and Traininglast composition differ. |
| `training-belastung-dunkel` | 7.34% | F: same missing 30-day series. A: same card order, breakdown and Traininglast differences. |

Median of the 18 G3.1 scores: **14.30%**. A score measures rendered difference, not product correctness or clinical validity.

## After the alignment round — 30 September 2026

Measured on `openband5/g31-paper` at `074f7060`, same harness, same references. Every four-panel report was inspected in light; Schlaf and Training also in dark.

| Frame | Before | After |
| --- | ---: | ---: |
| `heute-hell` / `-dunkel` | 19.67% / 14.91% | 8.99% / 7.22% |
| `schlaf-hell` / `-dunkel` | 18.11% / 15.00% | 12.29% / 9.84% |
| `training-hell` / `-dunkel` | 16.44% / 14.91% | 11.91% / 9.89% |
| `journal-hell` / `-dunkel` | 16.58% / 10.22% | 8.58% / 6.67% |
| `verlauf-erholung-30-tage-hell` / `-dunkel` | 17.34% / 17.11% | 7.29% / 5.93% |
| `verlauf-hrv-hell` / `-dunkel` | 13.69% / 11.36% | 9.36% / 7.26% |
| `schlaf-nachtverlauf-hell` / `-dunkel` | 11.90% / 8.66% | 10.85% / 7.86% |
| `training-lauf-ergebnis-hell` / `-dunkel` | 11.61% / 10.08% | 9.47% / 8.32% |
| `training-belastung-hell` / `-dunkel` | 9.83% / 7.34% | 10.47% / 8.15% |

Median of the 18 scores: **8.79%** (before: 14.30%). All nine screens now have the boards' sections, order, header style and copy. What still differs is listed below; the rest is synthetic trace shape, font rasterisation and the status bar.

The Belastung detail scores slightly higher than before although it is structurally closer: it gained the statistics card and the activity rows the board has, and the board's "Übriger Tag" row is deliberately absent, which shifts everything below it.

### Deliberate deviations from the boards

The app shows only what its data layer provides and keeps every function reachable.

- **Belastung detail:** no "Übriger Tag · +3,3" row. The app has no derived non-activity load, and Belastung is not additive, so it is not computed as a difference.
- **Einheit:** no "Strecke hinzufügen" and no "Notiz" row, and no "+ hinzufügen" under STRECKE: the app has no function to store either. No percentage range per zone row: the zone edges are not stored with the session. The header keeps ⓘ for a confirmed session, because the explanation is its only action.
- **Training root:** the sync line has no "· Puls lückenlos"; day-level pulse coverage is not known. The week footer says "ohne Belastungswert", not "ohne Bandpuls", because the reason for a missing day is not stored.
- **Schlaf root:** "Zeiten ändern ›" sits in the NACHT card footer (the board has no entry point for correcting sleep times). The empty nap row carries a chevron, because it opens the week history. Atemfrequenz shows the empty scale while its baseline is still building.
- **Nachtverlauf:** no "Ø Schlaf" and no "Optisches Signal verwertbar" row; the night data carries neither value.
- **Journal:** caffeine reads "Ja", not "1 Getränk"; the field is stored as yes/no.

## App differences found before the alignment round

No app code was changed for this review. These are the first responsible source locations, with the visible consequence:

- Heute: `lib/openband/g3/screens/heute.dart:1177` builds the larger check-in; `lib/openband/g3/day.dart:88` renders the different note; `lib/openband/g3/screens/heute.dart:1616` builds the breathing-rate baseline row; `lib/openband/g3/screens/heute.dart:1715` places steps beneath the taller content.
- Schlaf: `lib/openband/g3/screens/sleep.dart:405` builds the taller night summary; `:800` adds the overview method text; `:556`, `:676`, and `:953` place the navigation/regularity/week sections differently from Paper.
- Training root: `lib/openband/g3/screens/training_screen.dart:328` builds the load hero with pointer; `:426` builds the taller Traininglast card; `:526` builds the week chart and its different footer; `:551` builds the taller recent rows; `:314` supplies the shorter sync status. The today's confirmation footer at `:594`–`:612` omits Paper's `Ändern` action.
- Journal: `lib/openband/g3/screens/journal_screen.dart:743` builds the larger check-in and `:836`–`:890` orders expanded history before Muster. `:43` and `:805` use a yes/no caffeine field, so Paper's drink count is not represented by this screen's state (`lib/openband/g3_data.dart:490`).
- Erholung and HRV details: `lib/openband/g3/screens/verlauf.dart:307` builds the generic current-value lead; `:358` and `:384` build the trend and summary; `:396`–`:405` build a different recent-day list. The Paper recovery board is a 30-day aggregate, not this generic daily-detail composition.
- Nachtverlauf: `lib/openband/g3/screens/sleep_night.dart:145`–`:170` builds the alternate lead and range caption; `:211`–`:268` builds the taller pulse card, text statistics and signal-gap footer instead of Paper's compact quality row.
- Lauf result: `lib/openband/g3/screens/training_screen.dart:929` builds the header; `:1054` and `:1080` build the different trace/zone composition; `:1141`–`:1174` end the detail before Paper's basis, route, note and source rows.
- Belastung detail: `lib/openband/g3/screens/training_screen.dart:1363`–`:1419` builds the current card order and single activity text; `lib/openband/g3/training_parts.dart:88` builds the taller Traininglast component. Paper's Heute Bisher breakdown is absent.

## Bausteine spot check

The Bausteine boards `7IQH-0` and `7JCI-0` are single large compositions, so they were inspected by eye against the existing component specimens; no per-component G3.1 frames were invented. G3.1's stated roles are blue for recovery/body, violet for sleep, rosé for load/activity/steps, neutral for controls, lead numbers and ordinary text. The full-screen reports show the expected domain hues on recovery/body week bars and scales, sleep week bars and hypnogram, training zone rows and strip, trend/HR lines, activity and steps, and their section/card headers in both modes.

The **existing standalone specimen registrations are still neutral**: `lib/openband/g3/specimens.dart:315` onward constructs week bars, scales, hypnogram, zone rows/strip, trend chart, HR trace, activity row, steps card and headers without a domain argument. Their old component reports therefore cannot prove the new coloured Bausteine variants. This is a registration/fixture limitation, not evidence that those full-screen widgets are grey. The old `OBZoneRows` component frame also reports a 30-pixel bottom overflow at `lib/openband/g3/charts.dart:436`; its G3-sized frame is too short for the rendered rows.

## Verification and limits

- `python3 tool/g3_review.py refs g31-`: exported all 18 synthetic Paper references.
- `python3 tool/g3_review.py g31-`: rendered and scored all 18; every four-panel report was visually inspected.
- `flutter analyze --no-pub tool/`: clean after the registration changes.
- No physical iPhone, Bluetooth, live-user, or physiological evaluation was performed. The Paper strain series is unavailable as an exact synthetic fixture, so its empty/sparse app plot remains a fixture difference.
