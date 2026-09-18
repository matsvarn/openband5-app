# OpenBand 5 design research

Research date: **15 September 2026**. Scope: iPhone UX, German-first copy, subscription-free WHOOP 5.0 use. Research only; no interface or algorithm changes.

## Decision in brief

Design around three questions: **What happened? How much can I trust this result? What can I do next?** Use Bevel’s approachable summaries and explicit input explanations, WHOOP’s consistent metric drill-downs, and a more prominent account of stored data and gaps. Start with Today, Sleep, and onboarding through the first saved data.

“Free scores” is insufficient differentiation: Bevel now includes Recovery, Sleep, Strain and other core tracking in its free tier; Pro adds services including Intelligence. Its older captured paywall is obsolete evidence of current access. OpenBand’s candidate advantage is direct, subscription-free WHOOP use with understandable local data provenance and recovery from interrupted sync. This research does **not** establish uniqueness or user preference. [Bevel membership](https://help.bevel.health/en/articles/11583937), [OpenBand direction](../../OPENBAND5.md).

## Evidence and limits

- **O — observed:** visually inspected screenshots, not hands-on use. Reviewed 123 distinct screens across 19 Mobbin iOS sequences, plus a five-screen Refero permission sequence and two supplementary screens. All screens returned for those sequences were inspected; captured sequences can omit transitions, mix dates, or end before a task completes. Screen counts are not required-step counts.
- **D — documented:** official help or platform guidance retrieved on the research date. Several WHOOP support pages rendered a loading/CSS error; their claims below come from indexed official article text. Documentation describes intended behavior, not independently verified operation or physiological validity.
- **I — inference/proposal:** predicted friction and OpenBand recommendations. No participant usability study was conducted.
- **U — unavailable:** current German competitor journeys; complete Bevel new-user permission-to-first-import journey; current WHOOP 5.0 interrupted-sync-to-confirmed-completion capture; live workout pause/resume and error recovery. These gaps are not evidence that a feature is absent.

**Version boundary:** Bevel settings visibly identify **2.2.2 (2239)**; WHOOP device settings identify **4.6.251**, and pairing depicts **WHOOP 4.0**. Current documentation supersedes historical product details: WHOOP’s Plan tab is deprecated, and its Sleep Performance calculation has changed. Do not transplant captured navigation, paywalls, hardware instructions or scoring rules. [Bevel settings, screen 4](https://mobbin.com/flows/3e689062-664e-4cc6-aa8f-0f1f6a9b42df), [WHOOP device sequence](https://mobbin.com/flows/71950025-8213-4050-9302-88dedf54c6ff), [WHOOP Basics](https://support.whoop.com/s/article/WHOOP-Basics), [WHOOP Sleep](https://support.whoop.com/s/article/WHOOP-Sleep?language=en_US).

Refero brand queries did not return matching Bevel/WHOOP iOS journeys in the inspected results. Mobbin supplies the competitor screenshots; Refero supplies supplementary interaction and visual-direction evidence below.

### OpenBand’s starting point

The [product direction](../../OPENBAND5.md) prioritizes a retained night of data, visible coverage and understandable missing results. The [audit](AUDIT.md) identifies decoder, source-retention and biometric-validity risks; visual polish cannot resolve them. Preserve missing-input refusal, commit-before-ACK and the exclusion of experimental firmware/trim operations.

The latest [setup handoff](../../../STATUS.md) records physical iPhone installation and user-confirmed Apple pairing, continuation and arrival at Home. It does **not** prove sustained Bluetooth sync, complete overnight capture, disconnect recovery or physiological accuracy. Apple background execution is conditional; do not promise uninterrupted background syncing. [Apple restoration rules](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules).

Source inspection found useful foundations: [Home](../../lib/ui2/screens/home_screen.dart) suppresses prior-night values in today’s rings; [Sleep](../../lib/ui2/screens/sleep_detail.dart) has session review and gap-aware presentation; [Investigate](../../lib/ui2/screens/investigate.dart) exposes method and evidence; [device state](../../lib/state/app_state.dart) distinguishes record time from arrival time. Build on these. The [five-tab shell](../../lib/ui2/app_shell.dart) still contains English labels and broader domains than the first milestone needs. These are source findings, not a fresh rendered-app audit.

## Flow comparisons

Arrows describe the available capture or documented route. Friction and opportunities in the final column are **I**.

| Journey | Bevel evidence | WHOOP evidence | OpenBand opportunity |
| --- | --- | --- | --- |
| **Today** | **O:** [Home, 7 screens](https://mobbin.com/flows/1d703d24-dc17-4758-8c6e-7c916f2aacc9): three scores → short contextual summary → stress/energy → nutrition/health → timeline. Stress has its own update time. [Edit Home, 3 screens](https://mobbin.com/flows/4deecd0d-c054-452e-9d05-6bf116e0636b) exposes remove/reorder/add and Save; saved result is not captured. | **O:** [Home → Recovery, 5 screens](https://mobbin.com/flows/e569596c-2e34-4713-ace0-8d62c8681b56): daily dials → summary → drivers → trends. **D:** current Home has a customizable dashboard. [Basics](https://support.whoop.com/s/article/WHOOP-Basics). | Scores dominate both first views; data age is less prominent in these captures. Lead with the dated night and usable facts; expose freshness before interpretation. Defer customization until a useful default is established. |
| **Sleep** | **O:** [Sleep overview, 5](https://mobbin.com/flows/3a06c364-7fc8-49c6-bf09-575b31f0001e): Home → score, time in bed/asleep → tonight’s plan → timeline → trends. [Primary sleep, 10](https://mobbin.com/flows/a3fb194c-c64d-4ac1-b424-317a26c013af): recovery/timeline → session → stage selection → HR/HRV/respiration/oxygen. Missing latency explains the required recording feature. | **O:** [Daily sleep, 2](https://mobbin.com/flows/f4ed0184-ea2e-4926-b1ac-4081520add3a): Home session → duration, restorative sleep, stages and comparison. **D:** current Sleep Performance includes sufficiency, consistency, efficiency and sleep stress. [Sleep](https://support.whoop.com/s/article/WHOOP-Sleep?language=en_US). | Keep duration, interval and coverage together. Separate recorded/estimated results from goals. Decorative rings and extensive bedtime planning can push last night’s evidence down the screen. |
| **Recovery** | **O:** Primary-sleep sequence begins with recovery, HRV/RHR drivers and explanation. **D:** initial recovery requires two complete nights with usable sleep inputs; broader calibration takes 2–6 weeks. These are different milestones. [Troubleshooting](https://help.bevel.health/en/articles/11258241), [calibration](https://help.bevel.health/en/articles/11257601). | **O:** recovery → plain summary → drivers against the preceding 30 days → seven-day charts and explanation entry. **D:** recovery follows a sleep-to-sleep cycle; naps do not create another score. [Cycles](https://support.whoop.com/s/article/WHOOP-Cycles). | Show availability per metric. Distinguish “more baseline nights needed” from unreliable signals or an unsupported method. More wear cannot fix every refusal. Keep OpenBand’s day semantics; explain the night attached to a result. |
| **Activity** | **O:** [Activity, 6](https://mobbin.com/flows/60e3eab3-367a-406c-82e9-bd3073331ad8): strain → session duration/distance/energy → load and effort → HR/zones → splits/recovery. Captures include different activities, not one continuous workout. | **O:** [Log activity, 7](https://mobbin.com/flows/8723f8d0-b007-4d57-a17f-ebf01897b8a4): Add Activity → type/times → wear location → Saving → Saved. Start Activity is a separate action. **D:** auto-detection may take up to 20 minutes after HR returns to baseline. [Detection](https://support.whoop.com/s/article/Automatic-and-Manual-Activity-Detection). | Distinguish a recorded session, manual entry and analysis still pending. Make edits reviewable. Show activity facts before inferred training advice; do not reproduce confident “overtraining” conclusions without validated support. |
| **Trends** | **O:** [VO₂ max, 2](https://mobbin.com/flows/bdbbf347-3ec7-4848-886c-3cbdc9fea1fc): Biology → dated value, period selector, chart and analysis. **D:** chart aggregation changes by selected period. [Trends guide](https://help.bevel.health/en/articles/10430593). | **O:** [Strain, 5](https://mobbin.com/flows/d7499806-05cc-4b2f-bed0-3dbab7f0d5e5): daily summary → comparisons → seven-day charts. **D:** Steps supports weekly, monthly and six-month views. [Steps](https://support.whoop.com/s/article/Steps). | Put period, available-day count and comparison basis beside the chart. Label aggregation and retain gaps. A last-known value needs its measurement date. VO₂ max is a presentation reference, not a proposed first-milestone metric. |
| **Metric explanations** | **O:** sleep separates time asleep/in bed and exposes stage tooltips; unavailable latency names a prerequisite. **D:** source type can change inputs and precision; integration limitations are listed explicitly. [Devices](https://help.bevel.health/en/articles/10400449). | **O:** Recovery and Strain repeat summary → drivers → “What is…” → history. **D:** behavior impacts require enough yes/no observations. [Impacts](https://support.whoop.com/s/article/Recovery-Insights). | Use one reusable explanation order: meaning → this result’s inputs → comparison → limitations → method/source. A correlation or score contribution does not establish a cause. Avoid unexplained abbreviations on Today. |
| **Pairing** | **D:** profile → Data Sources → connect account → provider prompts → sync. Apple Health is another source route. The current device guide does not establish direct WHOOP historical BLE retrieval. **U:** full new-user hardware pairing capture. [Devices](https://help.bevel.health/en/articles/10400449). | **O:** [Onboarding, 15](https://mobbin.com/flows/06390f2f-8598-4b94-88f5-0bcb7b65ece4): ownership/login → hardware teaching → pairing mode → search → serial selection → Connecting → Connected. **D:** current WHOOP 5 setup starts pairing inside its app. [Setup](https://support.whoop.com/s/article/Setting-Up-Your-WHOOP-4-0?language=en_US). | Use OpenBand’s already-confirmed native Apple setup route and current device-specific instructions. “Gekoppelt” confirms association; it must not imply records have arrived. Offer help at the failing step. |
| **Sync recovery** | **O:** [source priority, 6](https://mobbin.com/flows/90fb0efc-fd69-47de-a771-d922f4962743): sources → priority → edit → Save → reordered list. [Hide source, 6](https://mobbin.com/flows/1d4055ff-27fa-4e32-b247-f2a0c95af9cb): hide → Save → acknowledgement. **D:** sleep troubleshooting follows device → Apple Health → Bevel, then source checks/refresh. [Sleep troubleshooting](https://help.bevel.health/en/articles/10796161). | **O:** [device settings, 5](https://mobbin.com/flows/71950025-8213-4050-9302-88dedf54c6ff) shows Connected separately from last sync and “catching up” timestamp. **D:** range, force-closing and power settings can interrupt transfers. [Troubleshooting](https://support.whoop.com/s/article/WHOOP-Troubleshooting-101). **U:** repair followed through to verified completeness. | Separate connection, stored-through time, interval gaps and processing. Provide a safe next step and visible read-back after retry. A settings-save toast proves neither new samples nor complete history. Do not import cloud-app cache clearing/reinstallation as local-data recovery advice. |
| **Onboarding → first useful data** | **O:** [login, 5](https://mobbin.com/flows/2388be46-642e-4d82-951f-5c25d4e0d9f0): Apple/email choice → email → magic link/countdown → populated Home. This is login, not proof of a first import. **U:** permission denial, initial history transfer and completion. | **O:** [account setup, 34](https://mobbin.com/flows/0d01383d-b82b-4321-87ee-dc64d664526c): Connected → profile → optional Health → body details → notifications → goals/teaching → empty Home tour. Contains variants; not 34 mandatory steps. **D:** first sleep score can follow one night; consistency needs three. [Sleep](https://support.whoop.com/s/article/WHOOP-Sleep?language=en_US). | Defer goals, notifications and optional integrations. Finish connection setup with a receipt of saved data or an explicit waiting state. A successful first transfer can coexist with unavailable sleep/recovery results. |

## Screen references for the design desk

These are inspected examples to adapt selectively, not a template to copy.

| Reference | Useful detail / limitation |
| --- | --- |
| [Bevel Home](https://mobbin.com/screens/25b9fe4f-75e9-4341-b9cd-4905f17fda56) | One short interpretation near metrics; numerous competing modules and faint update text. |
| [Bevel sleep duration](https://mobbin.com/screens/44e1614c-9450-45c8-9dd4-ba1815f9fc45) / [selected stage](https://mobbin.com/screens/c4c2dd72-1d95-431b-898f-ad415b4f5c39) | Distinguish time in bed/asleep; connect selected interval to a named stage. |
| [Bevel unavailable latency](https://mobbin.com/screens/ab7bd4a9-3e64-44ac-a5c7-e41fe1ef507f) / [insufficient sleep-goal history](https://mobbin.com/screens/be614ab9-9756-46cd-bec9-e7e45318cc3c) | Explain a specific prerequisite and, where valid, offer an alternative. The 90-day requirement belongs to automatic sleep goals, not every metric. |
| [Bevel sparse HRV](https://mobbin.com/screens/1682cf89-ebad-47a3-9bc8-454af9b04991) | A line joins widely separated plotted points. Show actual availability explicitly; the screenshot does not establish underlying sampling cadence. |
| [WHOOP recovery explanation](https://mobbin.com/screens/7bea0326-7a57-4132-9667-0373012375f9) / [drivers](https://mobbin.com/screens/33b30723-adc2-4efa-82d5-6c320624aff3) | Plain summary followed by comparison inputs; keep that hierarchy without importing score cutoffs. |
| [WHOOP connected and catching up](https://mobbin.com/screens/359a664b-0c3d-488b-99f2-b272bffd8673) | Connection and freshness can disagree. Promote that distinction to Today and first sync. |
| [Refero: Gentler Streak](https://refero.design/screens/7ced759c-f065-4dd4-bffe-9f775c05a241) | Explanation precedes the chart. Borrow hierarchy, not its causal recovery claim or mascot. |
| [Refero: Longevity Deck](https://refero.design/screens/e99e7b52-3e92-467c-997e-c720571ab2a3) | Period and workout count appear together; small, muted text deserves stronger legibility. |
| [Refero: Brink permissions, 5 screens](https://refero.design/flows/10923) | Active task → integration explanation → Continue/Not Now → Connecting with Help → connected banner. The OS permission sheet and actual storage outcome are not shown. |

**Refero visual directions compared:** WHOOP’s high-contrast neutral structure; Foodnoms’ light, approachable information density; Oura’s warm editorial presentation. Full style dossiers retrieved: WHOOP `cedc91cd-f747-4808-9d85-94e98c27273f`, Foodnoms `4c7e1e62-5c2d-4874-9640-ccbf7d88b5e8`, Oura `8f1f0540-574f-435f-86a6-aba9a4a1bca0`; source sites [WHOOP](https://whoop.com), [Foodnoms](https://foodnoms.com), [Oura](https://ouraring.com). These are website-style analyses, not current iOS token specifications.

**Provisional direction (I):** calm light surfaces, strong native text, compact quantitative comparisons, restrained metric colors, equally legible dark mode. Use Bevel’s grouping and WHOOP’s explanation consistency. Test an explanation-first Today against a compact metric-first alternative. Leave the final visual reference lock to the design phase; avoid averaging three brands into a decorative dashboard.

## Recommended principles

1. **A value always belongs to a period and source.** “Data received now” can contain old recordings. Latest record time does not prove continuous coverage or a valid metric.
2. **Missing results remain useful.** Distinguish no records, transfer pending, processing, missing baseline, unreliable input and unsupported measurement. Never replace these with zero, “normal,” a prior-night score or an invented confidence percentage.
3. **Expose the reason beside its consequence.** Give a short reason on the affected card; put input details and methodology one tap away. Keep valid sleep/activity information usable when recovery is unavailable.
4. **Match the action to the reason.** Retry a connection problem, wait for a known active computation, collect baseline nights when appropriate. Unsupported calibration needs an honest limitation, not an endless “keep wearing” message.
5. **Use uncertainty precisely.** Distinguish measured inputs, estimates and user corrections. Unknown intervals are not confirmed awake/off-wrist periods. Label associations and avoid causal coaching inferred from a few observations.
6. **Design German copy at iPhone size first.** Prefer “Heute,” “Schlaf,” “Erholung,” “Belastung,” “Ruhepuls” and “Datenstand.” Explain HRV on first use. Use locale-aware dates, decimal commas, 24-hour time and units; test long labels, larger text, VoiceOver and non-color status cues. These are proposed requirements, not evaluated competitor defects.
7. **Make local ownership practical.** Preserve records during recovery and explain retention/export when the product can substantiate it. “No subscription” must not become a promise of unlimited retained raw data before a retention policy exists.

## Prioritized design brief

### P0 — Today: a useful answer with incomplete data

First viewport: date/night context; concise data-status row with battery; one grounded summary; available sleep duration, resting pulse and activity. Include a recovery score only when supported, with its reason when unavailable. Keep detailed diagnostics behind “Daten ansehen.”

Design these states together: first use/no records; transfer in progress; recent records with gaps; processing; usable night with one refused metric; disconnected with previously saved data. Historical results keep their date when opened from Today.

The status detail must separately answer: Is the band connected? What is the latest stored recording time? Which intervals have usable data? Which calculations are ready? Show a numeric coverage percentage only when its interval and denominator are defined. A recent timestamp alone must not produce “complete.”

### P0 — Onboarding through first sync: a verifiable endpoint

Sequence: concise purpose/compatibility → power/proximity guidance → native Apple accessory setup → connection confirmation → first transfer → saved-data receipt → Today. Explain necessary profile inputs where needed; defer optional goals, Health integration and notifications. Preserve Back, cancellation and resumption without restarting completed setup. [Existing handoff](../../../STATUS.md), [Apple AccessorySetupKit](https://developer.apple.com/videos/play/wwdc2024/10203/).

Show distinct progress for association, connection, transfer and analysis. Use indeterminate progress when the total is unknown. “Erste Daten gespeichert” needs confirmed local storage; “Übertragung abgeschlossen” additionally needs a confirmed transfer endpoint. Neither implies complete history or calibrated recovery; show remaining gaps. If nothing has arrived, allow entry to Today with an explicit waiting/retry state rather than a false success screen.

Prototype Bluetooth unavailable, authorization cancelled, band not found, mid-transfer disconnect, relaunch, saved data with analysis pending, and no usable overnight inputs. Retry from the affected step and retain saved history. Do not offer erase, force-trim, firmware changes or reinstallation as routine repair.

### P0 — Sleep: inspect last night and understand the limits

Lead with the night’s date, start/end interval, sleep duration versus time in bed, recording coverage and source. Separate stages as estimates; render unknown intervals visibly and provide a text summary alongside the chart. Show HR/RHR/HRV only where usable, with per-metric reasons for absence.

Design session review → adjust interval → preview → save → recalculation pending → refreshed result, plus Cancel. Mark automatic versus user-confirmed intervals. Editing a sleep window must not imply repairing missing samples. Handle nights across midnight, naps and time-zone changes explicitly. Existing session review is a foundation; this complete interaction is a design proposal.

### P1 / P2 — Follow after the three core journeys

- **P1:** shared metric explanation; trends with period, aggregation and usable-day count; activity review/manual correction; detailed sync history and gap inspection.
- **P2:** card customization, additional coaching, bedtime planning and richer widgets. Widgets must retain result dates and freshness. Additional feature breadth must not delay the retained-night and sync-recovery milestone.

### German copy to test

Hypothetical states, not actual measurements or finalized strings:

| State | Proposed copy |
| --- | --- |
| Paired; transfer starting | „Band gekoppelt. Erste Daten werden übertragen.“ |
| First records stored | „Erste Daten gespeichert. Für Schlafdaten trage das Band über Nacht.“ |
| Recent records, partial coverage | „Daten bis heute, 07:42“ · „Keine Daten von 02:10 bis 02:34“ |
| Unreliable recovery input | „Erholung nicht berechenbar: Die Herzschlagabstände dieser Nacht sind nicht verlässlich genug.“ |
| Disconnected, history retained | „Band nicht verbunden. Gespeicherte Daten sind weiterhin verfügbar.“ |

### Design acceptance and remaining evidence

In a German iPhone prototype, ask participants to identify the represented night, tell whether data is current **and** complete, explain an unavailable recovery result, resume an interrupted transfer and correct a sleep interval. Observe mistaken “connected means finished” interpretations, lost navigation and unsupported confidence in estimates. Check the same tasks with larger text and VoiceOver; do not infer usability from visual polish.

The prototype can validate comprehension and navigation. The separate physical WHOOP 5.0 trial must establish retained records across disconnect/relaunch, correct freshness and coverage, and overnight sync recovery. Algorithm/physiological evaluation remains another boundary. Current German Bevel/WHOOP onboarding and real interrupted-sync sessions would strengthen the comparison but are not prerequisites for designing OpenBand’s explicit states.

## Key decisions for the design phase

1. Make **data freshness, coverage and metric readiness** distinct, visible concepts.
2. Make **Today useful before every score exists**; prioritize dated sleep and activity facts.
3. End setup at **confirmed saved data with clear remaining work**, with pairing as an intermediate milestone.
4. Make **Sleep the first complete evidence-to-explanation-to-correction journey**.
5. Use **German, readable native iPhone interaction** and test explanation-first versus metric-first hierarchy before locking the visual direction.
6. Position subscription-free direct WHOOP use and understandable local data as a **candidate advantage**; validate it through the physical capture trial and user tasks.

## Abschluss der vollständigen Bevel-Flow-Prüfung · 16. September 2026

Der erfasste [Bevel-Katalog](https://mobbin.com/apps/bevel-ios-4e7bb614-26f2-4464-a26b-9314adeef824/3d33cc95-b1c4-449a-b342-a8c7e0452ede/flows) umfasst 153 Flows mit 709 Quellpositionen. Jede Position wurde im jeweiligen Flow betrachtet, bevor die nächste Adaption begann. Mehrfach verwendete Quellbilder zählen als Positionen, nicht als 709 einzigartige Screens.

[DESIGN_FLOW_REVIEW.json](DESIGN_FLOW_REVIEW.json) enthält Reihenfolge, Original-IDs, betrachtete Positionen, Beobachtung, eigene Entscheidung, Paper-Ziele, Backend-Verweis und Prüfung. [DESIGN_DIRECTION.md](DESIGN_DIRECTION.md) ersetzt frühere Zwischenstände der Gestaltung. [DESIGN_COVERAGE.md](DESIGN_COVERAGE.md) verbindet die Quellcodefamilien mit den aktuellen Designwegen. Der Nachweis bezieht sich auf den betrachteten historischen Mobbin-Katalog, nicht auf eine live installierte aktuelle Bevel-Version.

Übernommen wurden Informationsdichte, ruhige Karten, kleine Visualisierungen und schrittweise Vertiefung. Eigenständig bleiben Navigation, deutsche Texte, Bildmaterial, Farbwelt, lokale Datenhaltung und die Trennung von Datenstand und Berechnungsbereitschaft. Proprietäre Scores, Paywall und nicht belegte Funktionen werden nicht durch Nachzeichnen eingeführt.


## Erneute Bildprüfung für die Verdichtung · 17. September 2026

Aus dem gespeicherten Katalog wurden Übersicht, Erholung, Schlaf, Journal, Ernährung, Fitness und Einstieg erneut betrachtet. Schwerpunkt war das Verhältnis von Datenbildern zu Text: kompakte Werte, kleine Diagramme, Beschriftungen direkt am Gegenstand und Vertiefung über Karten bzw. Informationsaktionen.

- [Home und langer Feed](https://mobbin.com/screens/45777953-3f7c-40ce-8675-09b3ec5bd8fd), [weitere Home-Ansicht](https://mobbin.com/screens/746c3b08-afd9-4790-945c-ac254f31f41c): kleine Hauptwerte, Inhalt unterhalb des ersten Viewports, kurze Einordnung innerhalb der Gruppe.
- [Erholung](https://mobbin.com/screens/bf86c914-92f3-441f-acf6-08a4c2a7e1d0), [Schlafphasen](https://mobbin.com/screens/c4c2dd72-1d95-431b-898f-ad415b4f5c39): zentrale Zahl und nahe Treiber; das Diagramm erklärt die Aufteilung.
- [Journal](https://mobbin.com/flows/6ca9f8c5-9491-4230-91da-5a7c894ad0a6), Positionen 1/3; [Primärer Schlaf](https://mobbin.com/flows/a3fb194c-c64d-4ac1-b424-317a26c013af), Position 6: wiederkehrende kompakte Gruppen und unmittelbare Bearbeitung.
- [Einstieg](https://mobbin.com/flows/0b6f9210-c215-4b32-872d-3fb66ab3ed28), Positionen 1/3; [Ernährung](https://mobbin.com/flows/13e9745c-3374-4a02-8538-0063ca9dbd76), Position 1; [Fitness](https://mobbin.com/flows/56e193d6-9518-4ef8-93de-0fbe3872d4d4), Position 1: persönliche Bildsprache und Zahlenhierarchie statt losem Erklärungstext.

Eigene Umsetzung: ruhige Flächen, kleine Phasenlinsen, farbige Mengen, weiche Atemillustration und ein Band–iPhone-Bild. Kein kopierter Bevel-Score oder proprietäres Bildmaterial. Die Hauptübersicht führt mit Daten; die tägliche Einordnung bleibt kurz in derselben Gruppe. Methoden behalten notwendige Erläuterungen. Vollständiger aktueller Bestand und technische Konsequenzen stehen im Handoff und in B163–B166.
