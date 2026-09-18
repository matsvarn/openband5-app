# Bevel → OpenBand 5 · Flow-Review

Stand: 17. September 2026 · **Quellreview und globale Sichtprüfung abgeschlossen · Design zur Nutzerprüfung**.

## Fortschritt

- Katalog vollständig erfasst: **153 / 153 Flows**, 709 Screen-Positionen.
- Vollständig abgeschlossen: **153 / 153 Flows**.
- Gesehene Screen-Positionen: **709 / 709**. Positionen verschiedener Flows können dasselbe Quellbild verwenden.
- Aktuell: **Quellreview und globaler Designabgleich abgeschlossen**.
- Globaler Bestand: **591 Artboards = 583 iPhone-Ansichten + acht Tafeln**, auf neun Seiten. Alle einzeln exportiert und visuell geprüft; korrigierte Ansichten erneut angesehen. Veraltete Parallelentwürfe wurden ersetzt oder entfernt.
- [Screeninventar](DESIGN_SCREEN_INVENTORY.json) und [Handoff](DESIGN_DIRECTION.md) sind der aktuelle Abschlussstand. Die Prüfnotizen unten protokollieren den jeweiligen Flow-Schritt; spätere globale Korrekturen sind in B155–B166 festgehalten.
- Nachweisgrenze: editierbare Zustandsansichten, keine lauffähige App. Native Bedienung, Dynamic Type, VoiceOver, Tastatur, Bluetooth und physiologische Gültigkeit bleiben Implementierungsprüfungen.

Quelle: [Bevel-Katalog](https://mobbin.com/apps/bevel-ios-4e7bb614-26f2-4464-a26b-9314adeef824/3d33cc95-b1c4-449a-b342-a8c7e0452ede/flows). Referenz ist dieser veröffentlichte Katalogstand, keine Behauptung über die aktuelle installierte Bevel-App.

## Visuelle Revision · 17. September

Die bestätigte Übersicht ist jetzt das gemeinsame Gestaltungsprinzip aller Bereiche: Wert → Bild → Handlung. Verdichtet wurden auch Formulare, Einstellungen, Fehler, Tastaturen und Bestätigungen. Schlaf zeigt Phasen und Zeitfenster; Training Verlauf und Zonen; Ernährung Mengen; Journal Symbolskalen; Sync den bestätigten Speicherstand. Lose Untertitel und redundante Anleitungen entfallen. Notwendige Feldlabels, Einwilligungen und Fehlerfolgen bleiben sichtbar.

Der vollständige Quellreview vom 16. September bleibt erhalten. Für diese Revision wurden ausgewählte gespeicherte Bevel-Ansichten erneut betrachtet; es wird kein zweiter vollständiger Durchlauf aller 709 Quellpositionen behauptet. Die neuen gemeinsamen Backend-Verträge stehen in B163–B166.

## Abschlusskriterium

Pro Flow: alle Screen-Positionen ansehen → konkrete Beobachtung → eigene OpenBand-Entscheidung → Paper anpassen → Zustände, Rückkehr und Darstellung prüfen → Backend-Anforderung festhalten → nächster Flow. Eine begründete Nichtübernahme wird erst nach Quellprüfung abgeschlossen. Screenshots beweisen keine nicht gezeigten Abläufe.

[Strukturierte Liste](DESIGN_FLOW_REVIEW.json) · [Backend-Anforderungen](DESIGN_BACKEND.md) · [Paper](https://app.paper.design/file/01M2KDQRH0A9K3N46EWHMBF61D/H-0)

## Reihenfolge

| Nr. | Bevel-Flow | Screens | Stand |
| --- | --- | ---: | --- |
| 001 | [Onboarding](https://mobbin.com/flows/0b6f9210-c215-4b32-872d-3fb66ab3ed28) | 48 | Erledigt · B01, B02, B03, B04 |
| 002 | [Subscribing to Bevel Pro](https://mobbin.com/flows/f561e1bb-3568-4289-a908-ae6d0235a030) | 4 | Erledigt |
| 003 | [Logging a food](https://mobbin.com/flows/bdd7a8b6-2f3c-44f1-9bd6-8f53c0af6bc3) | 9 | Erledigt · B05 |
| 004 | [Changing food serving](https://mobbin.com/flows/726141c7-4d01-4e77-ab71-5dd02773c4e5) | 4 | Erledigt · B06 |
| 005 | [Removing a food](https://mobbin.com/flows/612f2812-a9d8-4548-b3f2-89a7d18417c7) | 2 | Erledigt · B07 |
| 006 | [Edit food detail](https://mobbin.com/flows/52c02c14-4d6c-41fc-878e-566cd0edc0ff) | 3 | Erledigt · B08 |
| 007 | [Editing an ingredient serving amount](https://mobbin.com/flows/c849e32d-5295-4a6e-bf54-8208f926e3d9) | 6 | Erledigt · B09, B06 |
| 008 | [Adding an ingredient](https://mobbin.com/flows/46415b49-0e99-40d1-9bfe-470b3a7bdc11) | 7 | Erledigt · B10 |
| 009 | [Favoriting a food](https://mobbin.com/flows/60ef1186-cbfd-4007-aad4-50416d80970f) | 2 | Erledigt · B11 |
| 010 | [Log summary](https://mobbin.com/flows/a673d664-b91d-4a60-8eb0-8301a803446a) | 2 | Erledigt · B12 |
| 011 | [Importing a food](https://mobbin.com/flows/a07c5ac4-45ff-435e-8161-39e5454284d7) | 5 | Erledigt · B13 |
| 012 | [Capture a food](https://mobbin.com/flows/effc5423-4d3f-427a-9479-2bcdb6c6e5cf) | 2 | Erledigt · B14 |
| 013 | [Scan a barcode](https://mobbin.com/flows/4b3b299e-3c60-408c-80f2-6a22ef047d99) | 4 | Erledigt · B15 |
| 014 | [Searching a food](https://mobbin.com/flows/694b6ec8-2244-4b82-af32-3a7aed5447c5) | 6 | Erledigt · B16, B10 |
| 015 | [About macronutrients](https://mobbin.com/flows/160f71ca-26fa-4a1d-9700-a80ddf14c6fc) | 2 | Erledigt · B17 |
| 016 | [Account detail](https://mobbin.com/flows/9d6a3283-b826-49cf-9a52-d41995412dd4) | 2 | Erledigt · B18, B02 |
| 017 | [Activity details](https://mobbin.com/flows/60e3eab3-367a-406c-82e9-bd3073331ad8) | 6 | Erledigt · B19 |
| 018 | [Activity summary](https://mobbin.com/flows/44322961-68b0-4885-bda5-3b5b6d7540eb) | 3 | Erledigt · B20 |
| 019 | [Add a recipe](https://mobbin.com/flows/e8ebe8e0-ae2e-4ee9-82b0-2044e81aed71) | 6 | Erledigt · B21 |
| 020 | [Add a sleep alarm shortcut](https://mobbin.com/flows/158a5004-fd28-4bc8-9cc5-7e4dc5a9790f) | 4 | Erledigt · B22 |
| 021 | [Add a workout template](https://mobbin.com/flows/ab3ab3a6-46d1-4b45-91c3-a13a4b962813) | 3 | Erledigt · B23 |
| 022 | [Adding a bar weight](https://mobbin.com/flows/e68c4049-d1d4-43f1-97f4-23c3797164d5) | 6 | Erledigt · B24 |
| 023 | [Adding a card](https://mobbin.com/flows/44d9e5e3-1150-448d-8b02-c72b663d4fab) | 4 | Erledigt · B25 |
| 024 | [Adding a custom exercise](https://mobbin.com/flows/f950020a-9ead-4927-9bcc-1ee639e45a8c) | 9 | Erledigt · B26 |
| 025 | [Adding a custom food](https://mobbin.com/flows/6b7c9f6b-1d44-47fc-8941-528ce0753e05) | 4 | Erledigt · B27 |
| 026 | [Adding a custom nutrition log](https://mobbin.com/flows/eb93e363-07c1-4e4e-aa80-35ee5db17678) | 7 | Erledigt · B28 |
| 027 | [Adding a custom tag](https://mobbin.com/flows/c6213d8d-e0c5-49b6-88f4-97f0325dd51d) | 5 | Erledigt · B29 |
| 028 | [Adding a macronutrient goal](https://mobbin.com/flows/ed041444-7bbb-4549-95b0-7c0b7c816ca4) | 6 | Erledigt · B30 |
| 029 | [Adding a manual sleep](https://mobbin.com/flows/a6d9be95-e0de-468d-9ec6-1d3c71ca3fcf) | 3 | Erledigt · B31 |
| 030 | [Adding a nutrient](https://mobbin.com/flows/28f76d68-fb11-4bce-bda5-9b19ab177aad) | 3 | Erledigt · B32, B28 |
| 031 | [Adding a photo](https://mobbin.com/flows/e353adba-7b2f-4639-98f4-744863ed984f) | 3 | Erledigt · B33, B13, B14 |
| 032 | [Adding a recipe (old)](https://mobbin.com/flows/fb89f2cd-9202-4675-8787-d491a892eda8) | 3 | Erledigt · B21, B08, B09, B10 |
| 033 | [Adding a tag](https://mobbin.com/flows/08392ace-8b00-4033-8678-c0bf4aedb29c) | 6 | Erledigt · B34, B29 |
| 034 | [Adding additional nutrients](https://mobbin.com/flows/6a785b81-1a81-4f0d-88c7-d0bac4107ace) | 6 | Erledigt · B35, B27 |
| 035 | [Adding an exercise](https://mobbin.com/flows/37c92d24-2600-4dbe-bc83-afdc2600d8aa) | 6 | Erledigt · B36, B23, B26 |
| 036 | [Adding an exercise (photo)](https://mobbin.com/flows/5a166ef9-db46-4ab3-83a7-9c727bdfeba2) | 3 | Erledigt · B37, B36, B13 |
| 037 | [Adding excluded excercises](https://mobbin.com/flows/ff7fcead-3b70-4d16-b549-c578f6a132b5) | 6 | Erledigt · B38, B24, B26, B36 |
| 038 | [Adding target nutrients](https://mobbin.com/flows/2a6e0445-d1ce-4f6e-8f43-516ff5e895e8) | 5 | Erledigt · B39, B30, B35 |
| 039 | [Adding weight](https://mobbin.com/flows/30919586-42c8-4d90-95d5-c601cebe33eb) | 4 | Erledigt · B40 |
| 040 | [All categories](https://mobbin.com/flows/6836df2a-0555-4453-9cdd-565daeadd39b) | 2 | Erledigt · B41, B25 |
| 041 | [Appearance](https://mobbin.com/flows/1e2d2a85-609d-41dd-89a0-816b2dacdc77) | 4 | Erledigt · B42 |
| 042 | [Biology](https://mobbin.com/flows/f5aa5514-7c93-4641-9b89-f23e3d33d0e0) | 3 | Erledigt · B43, B41 |
| 043 | [Calculations](https://mobbin.com/flows/9d8e1dbc-f441-4ce9-b312-578512977a7e) | 3 | Erledigt · B44 |
| 044 | [Change sleep goal method](https://mobbin.com/flows/b6c9f621-49c6-4e9d-9253-6c7503480aef) | 6 | Erledigt · B45 |
| 045 | [Changing AI tone](https://mobbin.com/flows/6e03e90a-3564-47f2-98f7-775b78d1ba7f) | 5 | Erledigt · B46 |
| 046 | [Changing a memory expiration](https://mobbin.com/flows/11456d65-d9ab-430d-9470-700208d4a05b) | 5 | Erledigt · B47 |
| 047 | [Changing a nutrient daily target](https://mobbin.com/flows/1b68731d-158d-4aed-a3d8-64d90df3a0d6) | 4 | Erledigt · B48, B39, B30 |
| 048 | [Changing a set type](https://mobbin.com/flows/977a2f12-d618-470f-b7af-c35bed09d8e4) | 3 | Erledigt · B49, B23, B26 |
| 049 | [Changing activity status](https://mobbin.com/flows/538c235f-cbeb-4913-a3c4-1ead316e200a) | 8 | Erledigt · B50 |
| 050 | [Changing an alcohol preset amount](https://mobbin.com/flows/0897547f-fe58-4c92-98fe-efda25ac7bee) | 3 | Erledigt · B51 |
| 051 | [Changing an exercise duration](https://mobbin.com/flows/dbff665c-cf0b-4bd2-9556-af9f39288377) | 4 | Erledigt · B52, B40, B23 |
| 052 | [Changing data loading window time period](https://mobbin.com/flows/1f5f177b-c801-4831-a7a8-dc8a9173584b) | 6 | Erledigt · B53, B43 |
| 053 | [Changing date](https://mobbin.com/flows/1a1f850c-ddfc-4242-9adb-f0dc65f02741) | 4 | Erledigt · B54 |
| 054 | [Changing date period](https://mobbin.com/flows/d3acc24a-d99f-4040-a4c0-1d90175bb3fe) | 6 | Erledigt · B55 |
| 055 | [Changing distance unit](https://mobbin.com/flows/dd29cdad-c8b1-4baf-b3bd-43fdd88ae6cc) | 5 | Erledigt · B56 |
| 056 | [Changing log time](https://mobbin.com/flows/6bddba67-671c-4a05-8cc0-b2fd3813c35c) | 4 | Erledigt · B57 |
| 057 | [Changing tracking intent](https://mobbin.com/flows/33ff0052-23da-4566-a1f4-527eb7d2b357) | 6 | Erledigt · B58 |
| 058 | [Changing zone calculation method](https://mobbin.com/flows/e7e02394-0939-4186-b1d4-9867c91580ae) | 4 | Erledigt · B59 |
| 059 | [Chatting with Bevel AI](https://mobbin.com/flows/dcb43f1e-d11d-4b46-9f46-afd9f528db18) | 6 | Erledigt · B60 |
| 060 | [Clearing cache & reload all data](https://mobbin.com/flows/1562d9a8-d6d2-4b4d-91f6-17123aa56796) | 2 | Erledigt · B61 |
| 061 | [Connect a CGM](https://mobbin.com/flows/abea731e-e315-48e1-9873-35fa79e5eb73) | 8 | Erledigt · B62 |
| 062 | [Connecting with Apple Health](https://mobbin.com/flows/2b28bc6f-dab3-45fd-98b3-f3cabd7a10f8) | 3 | Erledigt · B63 |
| 063 | [Copying a message](https://mobbin.com/flows/e0caa343-b615-4e34-9c22-5e883cdc18b9) | 2 | Erledigt · B64 |
| 064 | [Copying an exercise](https://mobbin.com/flows/d0467c38-a02a-4abe-9a88-525d6ef3df3e) | 4 | Erledigt · B65 |
| 065 | [Creating a superset](https://mobbin.com/flows/42e724f4-7a08-4b1a-bf58-ba7b47bb7f7a) | 5 | Erledigt · B66 |
| 066 | [Customization](https://mobbin.com/flows/a88cbad0-ea9b-4556-ab88-474c1581bdf7) | 2 | Erledigt · B67 |
| 067 | [Deleting a chat](https://mobbin.com/flows/d9c5e886-afec-49d7-bc62-51c08a9e59e0) | 3 | Erledigt · B68 |
| 068 | [Deleting a custom exercise](https://mobbin.com/flows/5b160039-5a41-48fd-9eac-64315806ddb9) | 5 | Erledigt · B69 |
| 069 | [Deleting account](https://mobbin.com/flows/0d5e70e8-d51e-422b-85e3-eb2f3fcf40aa) | 3 | Erledigt · B70 |
| 070 | [Deleting an alcohol log](https://mobbin.com/flows/312326c1-0d48-4426-a6b3-c937a3a08dfb) | 3 | Erledigt · B71 |
| 071 | [Disconnecting a CGM](https://mobbin.com/flows/3cc5c84f-3973-4b9c-8974-119ba42ef4bc) | 3 | Erledigt · B72 |
| 072 | [Duplicating a template](https://mobbin.com/flows/29b9b04f-6164-4451-935b-4a885982138f) | 3 | Erledigt · B73 |
| 073 | [Edit home](https://mobbin.com/flows/4deecd0d-c054-452e-9d05-6bf116e0636b) | 3 | Erledigt · B74 |
| 074 | [Editing a food icon](https://mobbin.com/flows/dde97aad-9e6a-4302-b4fb-9aa82066c07b) | 4 | Erledigt · B75 |
| 075 | [Editing a nutrition goal](https://mobbin.com/flows/826c3059-e956-4393-a7e2-df5b1ed6a46b) | 6 | Erledigt · B76 |
| 076 | [Editing an activity title](https://mobbin.com/flows/5e810c97-905f-4f78-ac77-d2db81753bda) | 4 | Erledigt · B77 |
| 077 | [Editing quick add amount](https://mobbin.com/flows/f1149067-5b85-46b6-a7cc-ce02f45ecab8) | 3 | Erledigt · B78 |
| 078 | [Enabling notifications](https://mobbin.com/flows/f6cbe68b-e20c-43ce-849a-a8cb9b2de3a2) | 3 | Erledigt · B79 |
| 079 | [Exercise detail](https://mobbin.com/flows/0ab9a32d-2c2f-48e6-ba88-24631ae29a88) | 3 | Erledigt · B80 |
| 080 | [Filtering activity summary](https://mobbin.com/flows/beaef332-052b-4083-b163-d396853f0500) | 4 | Erledigt · B81 |
| 081 | [Filtering cardio focus](https://mobbin.com/flows/87ca40cf-f5ee-44db-a9aa-3dd7d9547e97) | 5 | Erledigt · B82 |
| 082 | [Filtering exercises](https://mobbin.com/flows/65348c72-c301-4283-b3eb-f70d26de1ef1) | 5 | Erledigt · B83 |
| 083 | [Filtering memories](https://mobbin.com/flows/e7925dbe-bb4f-4e12-ad31-a9d703611114) | 4 | Erledigt · B84, B47 |
| 084 | [Fitness](https://mobbin.com/flows/56e193d6-9518-4ef8-93de-0fbe3872d4d4) | 7 | Erledigt · B85, B81, B82 |
| 085 | [Food quality contributors](https://mobbin.com/flows/4a55a3c0-d632-4dfc-b6d1-51a8e985e9c1) | 2 | Erledigt · B86 |
| 086 | [Generating a template](https://mobbin.com/flows/025b5d92-9360-45e5-a677-6fc5d5b09281) | 19 | Erledigt · B87, B36, B38, B65 |
| 087 | [Hiding a data source](https://mobbin.com/flows/1d4055ff-27fa-4e32-b247-f2a0c95af9cb) | 6 | Erledigt · B88 |
| 088 | [History](https://mobbin.com/flows/e6426cea-cded-4d4a-8e52-1d0e663e69ef) | 2 | Erledigt · B89, B68 |
| 089 | [Home](https://mobbin.com/flows/1d703d24-dc17-4758-8c6e-7c916f2aacc9) | 7 | Erledigt · B90, B85, B88 |
| 090 | [How to log](https://mobbin.com/flows/63e97631-7b3d-4e99-af04-71a0f25dc858) | 2 | Erledigt · B91, B26, B40 |
| 091 | [Importing a recipe](https://mobbin.com/flows/61f72fd6-1eb9-421e-9cf2-8abeb7ea378b) | 7 | Erledigt · B92, B08, B25 |
| 092 | [Insights](https://mobbin.com/flows/f1d1e2a8-91fd-4236-b3e6-37dfdc356574) | 3 | Erledigt · B93 |
| 093 | [Journal](https://mobbin.com/flows/6ca9f8c5-9491-4230-91da-5a7c894ad0a6) | 5 | Erledigt · B94, B93 |
| 094 | [Log custom caffeine intake](https://mobbin.com/flows/d5f5e19a-e3ff-4d8b-868e-334c42ee66d8) | 4 | Erledigt · B95 |
| 095 | [Log detail](https://mobbin.com/flows/49043cef-3e33-4233-a20a-5241b9ba1993) | 3 | Erledigt · B96, B86, B07 |
| 096 | [Logging a daily mood](https://mobbin.com/flows/689681d7-2f51-41a2-b979-04f43feac7fd) | 9 | Erledigt · B97 |
| 097 | [Logging an activity](https://mobbin.com/flows/b0d7bf80-c407-466e-a2a2-afd02c7138c1) | 9 | Erledigt · B98 |
| 098 | [Logging custom alcohol intake](https://mobbin.com/flows/c7e67e1b-b6e3-4a84-9fd1-a1768b78092b) | 5 | Erledigt · B99 |
| 099 | [Logging custom water intake](https://mobbin.com/flows/935eaede-4bf6-4634-8f6a-7d0555ddb5e4) | 4 | Erledigt · B100 |
| 100 | [Logging in](https://mobbin.com/flows/2388be46-642e-4d82-951f-5c25d4e0d9f0) | 5 | Erledigt · B101 |
| 101 | [Logging out](https://mobbin.com/flows/41202d78-a0e0-4bb4-9bd9-d87c39776667) | 2 | Erledigt · B102, B70 |
| 102 | [Macro balance](https://mobbin.com/flows/c103aac7-560d-488b-aa6b-69959bf0973d) | 4 | Erledigt · B103 |
| 103 | [Manage subscription](https://mobbin.com/flows/ae639dbf-d808-4e22-8a71-6a1b4bb7beca) | 2 | Erledigt · B104 |
| 104 | [My foods](https://mobbin.com/flows/48efbaa3-1ea1-4613-ae2e-aacf64e9c47d) | 8 | Erledigt · B105 |
| 105 | [Nap](https://mobbin.com/flows/ca797ea1-379a-4998-afbe-a7f5368d627b) | 2 | Erledigt · B106 |
| 106 | [Net energy](https://mobbin.com/flows/0d26bb8b-117c-453d-aba3-17399cf502bf) | 3 | Erledigt · B107 |
| 107 | [Nutrition](https://mobbin.com/flows/13e9745c-3374-4a02-8538-0063ca9dbd76) | 7 | Erledigt · B108 |
| 108 | [Nutrition (Settings)](https://mobbin.com/flows/3db51671-d32e-45fc-8aa7-df4765bf523f) | 3 | Erledigt · B109 |
| 109 | [Nutrition score](https://mobbin.com/flows/f51d9c32-4ad9-4322-92cb-ff747edc87df) | 3 | Erledigt · B110 |
| 110 | [Nutritional detail](https://mobbin.com/flows/6b9e1af2-27d2-4c24-9a89-1693b32561d8) | 5 | Erledigt · B111 |
| 111 | [Nutritional goals](https://mobbin.com/flows/f4a23782-2faf-4db2-980d-e3ae1a74315b) | 7 | Erledigt · B112 |
| 112 | [Pinned tags](https://mobbin.com/flows/90cfba9f-330c-49e8-92c9-c62c9b81815c) | 2 | Erledigt · B113 |
| 113 | [Pinning a tag](https://mobbin.com/flows/ce0a4943-ef71-466b-a5cd-69e83e15c32e) | 3 | Erledigt · B114 |
| 114 | [Pinning a workout](https://mobbin.com/flows/578b5a0a-db28-401c-b313-9942640532b5) | 5 | Erledigt · B115 |
| 115 | [Previous recorded workout](https://mobbin.com/flows/ce08e59e-5edc-4800-bf93-48fb5dd645df) | 3 | Erledigt · B116 |
| 116 | [Primary sleep](https://mobbin.com/flows/a3fb194c-c64d-4ac1-b424-317a26c013af) | 10 | Erledigt · B117 |
| 117 | [Primary sleep (old)](https://mobbin.com/flows/82b6f9ec-e66e-4a2a-8b00-66d6d33de184) | 2 | Erledigt · B118 |
| 118 | [Recovery](https://mobbin.com/flows/457f547b-88b9-43f1-a2ae-0688a9aa489f) | 3 | Erledigt · B119 |
| 119 | [Reordering cards](https://mobbin.com/flows/cfd24a7e-3bee-45a1-b79d-ec89ed6f0318) | 4 | Erledigt · B120 |
| 120 | [Reordering data sources](https://mobbin.com/flows/90fb0efc-fd69-47de-a771-d922f4962743) | 6 | Erledigt · B121 |
| 121 | [Reordering excercises](https://mobbin.com/flows/d9718554-e4a0-4d1a-9c88-9588d2d7f292) | 5 | Erledigt · B122 |
| 122 | [Replacing an exercise](https://mobbin.com/flows/88a33299-735a-4d6a-89b3-427fd4217678) | 5 | Erledigt · B123 |
| 123 | [Reporting an issue](https://mobbin.com/flows/e59afbf1-beaf-491f-9101-58d8136cd566) | 6 | Erledigt · B124 |
| 124 | [Resource article](https://mobbin.com/flows/0f09066a-be78-4daf-b4c5-0b00f928927f) | 2 | Erledigt · B125 |
| 125 | [Saving a workout template](https://mobbin.com/flows/512b065f-5067-423c-a99b-71ab9231bd41) | 3 | Erledigt · B126 |
| 126 | [Scheduling keep status](https://mobbin.com/flows/326003b5-8a0b-4761-98a2-89dda5216d4d) | 4 | Erledigt · B127 |
| 127 | [Sending a feedback](https://mobbin.com/flows/e17dc00f-f7fe-4793-b2cd-2325172ccfd3) | 5 | Erledigt · B128 |
| 128 | [Sending photos](https://mobbin.com/flows/30eca368-3ae6-4ec8-9b0f-724ddbfed7d2) | 5 | Erledigt · B129 |
| 129 | [Set default entries](https://mobbin.com/flows/ab6b6109-6cb0-4869-abdd-4599ee512f6b) | 3 | Erledigt · B130 |
| 130 | [Setting a sleep alarm](https://mobbin.com/flows/249674c3-dc9c-46e5-9d41-14614c6e7a03) | 8 | Erledigt · B131 |
| 131 | [Settings](https://mobbin.com/flows/3e689062-664e-4cc6-aa8f-0f1f6a9b42df) | 4 | Erledigt · B132 |
| 132 | [Share an activity](https://mobbin.com/flows/a38cb469-2efb-48a8-8ced-483213eec744) | 2 | Erledigt · B133 |
| 133 | [Shortcuts](https://mobbin.com/flows/4d57ff55-d681-4cce-8325-bbc50549d4d5) | 2 | Erledigt · B134 |
| 134 | [Sleep](https://mobbin.com/flows/3a06c364-7fc8-49c6-bf09-575b31f0001e) | 5 | Erledigt · B135 |
| 135 | [Sleep needed calculated](https://mobbin.com/flows/08ff2fd1-2e92-4f66-bc16-0bc163d1ab74) | 2 | Erledigt · B136 |
| 136 | [Sleep score](https://mobbin.com/flows/f0da0c5d-3661-4fdc-9173-a8307eebf15f) | 3 | Erledigt · B137 |
| 137 | [Starting a workout](https://mobbin.com/flows/9bb0f287-231c-4b95-a47f-2e4a17c21dcc) | 12 | Erledigt · B138 |
| 138 | [Strain](https://mobbin.com/flows/c839a180-55a8-43d8-96d9-109f476644ba) | 4 | Erledigt · B139 |
| 139 | [Strain score](https://mobbin.com/flows/95239001-1ba4-4ee5-9b1a-226ace49fcd8) | 4 | Erledigt · B140 |
| 140 | [Strength progression](https://mobbin.com/flows/f7bdcb74-7c8d-4db9-9d65-04dfbb20ec97) | 2 | Erledigt · B141 |
| 141 | [Stress](https://mobbin.com/flows/16556c28-76a3-4823-912b-6e53457d0b3d) | 4 | Erledigt · B142 |
| 142 | [Suggested drink intake](https://mobbin.com/flows/b2171be3-d693-4b3b-8e11-a453ea138028) | 3 | Erledigt · B143 |
| 143 | [Switching to dark mode](https://mobbin.com/flows/60b14239-ca79-4251-b8ed-b92aaa02f101) | 6 | Erledigt · B144 |
| 144 | [Switching to list view](https://mobbin.com/flows/8d13aeae-ed7b-4034-9808-3e499fa8f4a7) | 2 | Erledigt · B145 |
| 145 | [Syncing to a watch](https://mobbin.com/flows/bd7d115f-dfac-4376-9939-c3556b8ccee7) | 4 | Erledigt · B146 |
| 146 | [Target strain calibration](https://mobbin.com/flows/a8912086-a82a-4b75-8cc3-162d9171fd31) | 2 | Erledigt · B147 |
| 147 | [Time asleep](https://mobbin.com/flows/56589996-8b53-4288-b60d-4f41310645ce) | 3 | Erledigt · B148 |
| 148 | [Unlinking a superset](https://mobbin.com/flows/183a0d54-fbc2-4b55-a5f5-0a7e41a6782a) | 4 | Erledigt · B149 |
| 149 | [VO2 Max ranges](https://mobbin.com/flows/f6d8a48a-1e96-4989-99cd-986043fb0b34) | 2 | Erledigt · B150 |
| 150 | [VO2 max](https://mobbin.com/flows/bdbbf347-3ec7-4848-886c-3cbdc9fea1fc) | 2 | Erledigt · B150, B151 |
| 151 | [Weight](https://mobbin.com/flows/8e06d420-ce21-4637-8a13-880fd88b1d98) | 3 | Erledigt · B152 |
| 152 | [Widgets](https://mobbin.com/flows/2d2fa6fc-159d-4a6d-8bca-96f4a69a85b1) | 3 | Erledigt · B153 |
| 153 | [Workout templates](https://mobbin.com/flows/f30f3acd-af98-42bc-8f1b-66b787597c8d) | 2 | Erledigt · B154 |

## Abgeschlossene Entscheidungen

### 001 · Onboarding

**Beobachtet:** 48 Positionen vollständig angesehen: visuelle Vorschau, Login, Datenschutz, Schwerpunkt und Hürden, personalisierte Erklärungen, Health, Profil, Einheiten, Mitteilungen, Verarbeitung, Paywall, Kurzführung und leere Startseite.

**OpenBand:** Eigener lokaler Einstieg mit optionalem Schwerpunkt und überspringbarem Profil. Quellenweg Band/Import/später; Datenbeleg nach Commit; erste Nacht mit separater Metrikbereitschaft. Keine Konto- oder Paywallpflicht. Erklärung in passenden Details statt langer Pflicht-Tour.

**Prüfung:** Paper-Sichtprüfung der 15 Einrichtungsansichten sowie dunklem Speicherbeleg und großer Schrift 375×812. Text, Abstände, Lucide-Icons, Zustandsunterschiede und Rückkehr geprüft. Native Interaktionen bleiben Implementierungsnachweis.

### 002 · Subscribing to Bevel Pro

**Beobachtet:** Paywall mit Jahres-/Monatstarif, Reviews, Wiederherstellen und Code-Einlösen sowie anschließender leerer Startseite. Kein iOS-Kaufdialog und kein Kaufabschluss belegt.

**OpenBand:** Begründet nicht übernommen: OpenBand bleibt ohne Abonnement und ohne Kontopflicht. Keine gesperrten lokalen Verläufe. Optionaler BYOK-Coach erklärt externe Anbieterkosten an seiner Einrichtung.

**Prüfung:** Alle vier Screens angesehen; Willkommen hat direkten Bandeinstieg/Import/später und keinen Kaufzwischenschritt. Kein Kauf oder externer Schreibvorgang ausgeführt.

### 003 · Logging a food

**Beobachtet:** Neun Positionen: leere und gefüllte Startansicht, Aktionsmenü, Beschreibung leer/gefüllt, Vorbereitung im Hintergrund, bereit zur Prüfung, editierbarer Vorschlag und Rückkehr in den Feed. Die Erfassung springt zwischen Beispieltagen; sie belegt keine durchgängige einzelne Datensitzung.

**OpenBand:** Datierter eigener Food-Draft mit lokaler Suche, prüfbaren Einzelportionen, mehreren Einträgen und atomarem Speichern. Ohne Nährwerte bleibt ein Mahlzeiteneintrag möglich. Fehler hält den Entwurf; die erfolgreiche Rückkehr zeigt Tagesuntergrenzen einschließlich offenem Kaffee.

**Prüfung:** Acht Paper-Zustände/Varianten geprüft: leerer Nährwertstand, Beschreibung, Vorschau, Fehler, normaler und bestätigter Tagesstand, dunkle Vorschau und 375×812 mit größerer Schrift und fester Speicheraktion. Nur Design, keine echten Schreibvorgänge.

### 004 · Changing food serving

**Beobachtet:** Vier Positionen: Portionszeile öffnet eine Dezimaltastatur, Menge ändert sich von einer auf zwei Portionen, danach Rückkehr zur Vorschau. Die abgebildete Gesamtsumme bleibt 699 kcal; der Screenshot belegt nicht, wann sie neu berechnet wird.

**OpenBand:** Fokussiertes Portionsblatt mit Referenzportion, Kommaeingabe, schnellen Bruchteilen und unmittelbarer Einzelwertvorschau. Übernehmen aktualisiert alle Draft-Summen gemeinsam. Beispiel 1,5 Schüsseln ergibt 675 kcal, gesamter Entwurf 845 kcal.

**Prüfung:** Tastaturblatt und geänderter Entwurf visuell geprüft. Tastatur vollständig sichtbar; Mengenfeld und Aktion frei erreichbar; die vier Nährwertsummen stimmen mit den synthetischen Basisangaben überein.

### 005 · Removing a food

**Beobachtet:** Zwei Screens zeigen das Entfernen eines Latte aus dem Entwurf; die Summe wechselt von 699 auf 577 kcal. Eine Bestätigung ist nicht gezeigt. Datumsangaben variieren.

**OpenBand:** Im Entwurf sofort entfernen und Rückgängig anbieten; gespeicherte Einträge dagegen mit Lebensmittel und Datum bestätigen. Definitionen und andere Tage bleiben erhalten.

**Prüfung:** Beide 393 × 852 Ansichten visuell geprüft: Summen 450 kcal und 22/60/14 g stimmen nach Entfernen des Joghurts; Buttons, Iconspalten und Dialog passen. Datum im Dialog bewusst in eigener Zeile. Statische Designs, keine funktionale Löschprüfung.

### 006 · Edit food detail

**Beobachtet:** Drei Screens führen von der Mahlzeitenliste zur Detailansicht mit Energie-/Makroübersicht, Portion und einer scrollbaren Zutatenliste. Zutaten und Entfernen/Speichern sind direkt erreichbar.

**OpenBand:** Eigene kompakte Rezeptansicht mit vier Zutaten, sichtbarer Bezugsportion und Entwurfsstatus. Die bisherige manuelle Nährwerteingabe bleibt ein klar benannter separater Weg. Rezeptänderungen verändern gespeicherte Tage nicht still.

**Prüfung:** 393 × 852 visuell geprüft: vier Zutaten, Summen, Herkunft und Übernehmen passen ohne Überlagerung. Gemeinsame Icon- und Zahlenachsen, lizenzierte Lucide-Icons. Synthetischer ungespeicherter Rezeptfall getrennt vom Tagesbeispiel.

### 007 · Editing an ingredient serving amount

**Beobachtet:** Sechs Screens zeigen den Sprung von Zutatenliste zu einzelner Zutat, Mengeneingabe mit Einheitenauswahl und Tastatur sowie eine geänderte Menge von 110 g. Einheitenauswahl verändert die gezeigte Menge deutlich.

**OpenBand:** Gemeinsamer Mengeneditor zeigt Zutat, Bezugswert und neue Energiemenge zusammen. Nur bekannte Einheiten anbieten; Übernehmen führt in den Rezeptdraft zurück. Eigene Vorher-/Nachher-Ansicht zeigt 90 g Hafer und 565 kcal Rezeptsumme.

**Prüfung:** Keyboard und übernommene Rezeptansicht bei 393 × 852 geprüft. 1,5 × 230 = 345 kcal, Rezeptgesamtwert 565 kcal, Makros 33/70/13 g. Einheit und Zahlenwert bleiben visuell getrennt und eindeutig.

### 008 · Adding an ingredient

**Beobachtet:** Sieben Screens zeigen Hinzufügen über Barcode oder Suche, mehrere Suchtreffer, eine Auswahlmarkierung/Chip und die Rückkehr in die Zutatenliste. Der letzte Quellscreen ist teilweise abgeschnitten; nicht sichtbare Inhalte werden nicht interpretiert.

**OpenBand:** Zutatenpicker mit sichtbarer Auswahl und klarer Bestätigung; Rückkehr in denselben Rezeptdraft. Herkunft an den Suchtreffern, feste Abschlussleiste, kompakte fünfteilige Zutatenliste. Kein ungeprüftes Verifiziert-Siegel.

**Prüfung:** Suchauswahl und hinzugefügte Banane bei 393 × 852 visuell geprüft. Fünf Zutaten passen über die Abschlussleiste, 450 + 90 = 540 kcal; Makros 30/72/11 g. Tastatur-/Lange-Listen-Verhalten als Implementierungsanforderung dokumentiert.

### 009 · Favoriting a food

**Beobachtet:** Zwei identische Detailansichten unterscheiden sich durch den Stern rechts oben: erst grau, dann gelb. Eine Sammlung oder ein Verzehr-Commit ist im Quellflow nicht gezeigt.

**OpenBand:** Merken mit Lucide-Lesezeichen und sichtbarem Speicherstatus; eigene Sammlung mit Suche und Filtern. Rezept speichern und Mahlzeit eintragen sind getrennte Aktionen. Bestehende Tage bleiben unangetastet.

**Prüfung:** Rezeptzustand und Sammlung bei 393 × 852 geprüft. Kontrastfehler am aktiven Filter korrigiert und erneut visuell geprüft. Alle neuen Symbole stammen aus dem beigefügten, lizenzierten Lucide-Stand.

### 010 · Log summary

**Beobachtet:** Zwei Screens zeigen die Mahlzeitensumme als Einstieg und eine lange Nährwerttabelle mit Untergruppen, Makro- und Mikronährstoffen. Der Quellflow zeigt keine Herkunft oder Vollständigkeitsanzeige pro Nährstoff.

**OpenBand:** Kompakte eigene Übersicht mit Makros zuerst und zusätzlicher Herkunft/Vollständigkeit je Nährstoff. 620 kcal sind vollständig für den Draft, Zucker ≥8 g teilweise, andere Angaben offen. Summenzeile erhält einen sichtbaren Detailzugang.

**Prüfung:** Nährwertübersicht und geänderter Draft-Einstieg bei 393 × 852 visuell geprüft. Werteachsen, Zeilenabstand, Kontrast, mindestens 44 px hohe Summenaktion und Safe Area passen.

### 011 · Importing a food

**Beobachtet:** Fünf Screens zeigen Fotoimport, optionale Beschreibung, laufende Verarbeitung, Bereit-Hinweis und eine prüfbare Lebensmittelliste. Home- und Eintragsdaten wechseln im Quellenmaterial; ein konsistenter einzelner Beispieltag ist daraus nicht ableitbar.

**OpenBand:** Fotos bleiben lokal nutzbar; optionale Vorschläge erfordern eine sichtbare Weitergabe an den eingerichteten Anbieter. Fortschritt kann verlassen werden, Fehler erhält den Draft. Erkanntes Lebensmittel und unbekannte Portion werden getrennt, eigene Vorlage muss bewusst bestätigt werden.

**Prüfung:** Vier 393 × 852 Zustände visuell geprüft: Import, laufender Auftrag, Prüfung und Fehler. Keine erfundenen Gramm-/Kalorienwerte aus dem Bild. Eigene editierbare Bowl-Illustration als synthetisches Beispiel, keine kopierten Bevel-Grafiken.

### 012 · Capture a food

**Beobachtet:** Zwei Screens zeigen den Fotoeinstieg und einen dunklen Kamerasucher mit Schließen, Blitz, Zoom, Auslöser, Import und Beschreiben. Ein aufgenommenes Ergebnis ist in diesem Flow nicht enthalten.

**OpenBand:** Gemeinsamer eigener Kameraeinstieg für Foto, Etikett und Barcode. Kamera-Freigabe und verweigerter Zugriff haben konkrete Alternativen. Als eigene Erweiterung lokale Etiketterkennung mit sichtbarer Bezugsmenge, unsicherem Feld und geprüfter Korrektur; Foto kehrt in die Importvorschau zurück.

**Prüfung:** Dunkle Kamera, Erstfreigabe, verweigerter Zugriff, unsicheres Etikett und korrigiertes Etikett visuell geprüft. Alle 393 × 852, klare Bedienflächen und lesbare Kontraste. Keine Kamera-/OCR-Laufzeitprüfung; editierbare synthetische Bildbeispiele.

### 013 · Scan a barcode

**Beobachtet:** Vier Screens zeigen Scanrahmen, optionalen Multi-Scan und manuelle Zahleneingabe. Kein Produktresultat ist in dieser Quellenfolge gezeigt.

**OpenBand:** Gemeinsame Kamera, Einzelscan direkt zur Portionsprüfung; weitere Produkte kommen in denselben Mahlzeitendraft. Manuelle Codeeingabe und explizite Erstwahl für nicht lokale Onlineabfrage. Bestehende Backend-Zustände separat gestaltet: nicht gefunden, nicht erreichbar, problematische Angaben und Suche deaktiviert. Quellen-/Lizenzhinweis am Ergebnis.

**Prüfung:** Acht 393 × 852 Ansichten visuell geprüft, einschließlich Tastatur und dunklem Scanner. Bestehende off_lookup.dart-Zustände und Gate/Cache-Logik direkt gelesen; keine echte Barcode- oder Kameraabfrage. OFF-Lizenzübersicht als Primärquelle geprüft und verlinkt.

### 014 · Searching a food

**Beobachtet:** Sechs Screens zeigen Suche, Verlauf, mehrere Suchtreffer, auswählbare Zeilen und über Suchbegriffe erhaltene Chips. Gemeinsam ausgewählte Lebensmittel werden vor dem Hinzufügen gesammelt.

**OpenBand:** Lokale Suche nach zuletzt verwendeten Lebensmitteln oder Sammlung; stabile Mehrfachauswahl bleibt beim Weitersuchen erhalten. Expliziter Onlineweg mit benannter Quelle, eigener Erstwahl für Suchtexte und prüfbarem Ergebnis. Leere lokale Suche führt zu Online, Anlegen oder Erfassung.

**Prüfung:** Fünf Suchzustände bei 393 × 852 visuell geprüft: lokal, ausgewählt, online, kein lokaler Treffer und Onlinewahl. Ziel bleibt derselbe Mahlzeitendraft; kein Eintrag durch bloße Auswahl. Konkreter Online-Suchendpunkt ist noch Implementierungsarbeit, kein getesteter Provideraufruf.

### 015 · About macronutrients

**Beobachtet:** Zwei Screens zeigen die Zielbearbeitung und ein Informationsblatt zu Fett, Kohlenhydraten und Protein mit 9/4/4 kcal je Gramm. Die Quelle vermittelt Grundlagen direkt im Zielkontext.

**OpenBand:** Kurze eigene Erklärung mit konsistenter Protein/Kohlenhydrate/Fett-Reihenfolge, Energiefaktoren und konkretem Unterschied zwischen deklarierter Energie und Makrorechnung. Ein gemeinsames Hilfemodul aus Übersicht, Details und Zielbearbeitung; keine automatischen Ziele durch den Hilfetext.

**Prüfung:** Erkläransicht bei 393 × 852 visuell geprüft. 36×4 + 80×4 + 18×9 = 626, deklarierte Summe bleibt 620. DGE-Primärquellen geprüft und im Handoff verlinkt. Zielbearbeitung selbst folgt im eigenen Katalogflow.

### 016 · Account detail

**Beobachtet:** Zwei Screens zeigen Einstellungen und Kontodetails mit Avatar, Name, Geburtstag/Alter, Abmelden und Konto löschen.

**OpenBand:** Kontospezifische Aktionen entfallen im lokalen Produkt. Eigener Profil-Hub mit Band, freiwilligen Berechnungsangaben, Zielen, Anbieter und Datenverwaltung. Vorhandener Geburtsdatum-/datierter Profilvertrag wird weiterverwendet; Änderungen erfolgen im Draft.

**Prüfung:** Profil-Hub und Editor bei 393 × 852 visuell geprüft. Doppelte Profilnavigation entfernt; Verbindung, Akku und Speicherstand getrennt. PersonalProfile und dessen datierte Altersberechnung direkt gelesen. Keine App-Implementierung geändert.

### 017 · Activity details

**Beobachtet:** Alle sechs Positionen angesehen: Belastungsübersicht, Activity-Hero, Cardioimpact/Anstrengung, Pulszonen, Splits mit HR-Recovery und Kraftdetails mit Muskelanteilen. Die Bilder verwenden unterschiedliche Aktivitäten; sie beweisen keinen durchgängigen Laufdatensatz.

**OpenBand:** Eigenständiger Lauf-Detailstack mit kompakter Route, Einheitsbelastung, Energie, Herzfrequenz und tieferer Abschnitts-/Quellenansicht. Persönliche Anstrengung und Notiz im Scrollverlauf. Kraftansicht fokussiert tatsächlich aufgezeichnete Sätze und Last, ohne fremde Muskel- oder Overtraining-Scores. Vollständig, Pulslücke, keine Messdaten, fehlendes Gewicht sowie Dunkel und große Schrift gestaltet.

**Prüfung:** Alle sechs Quellpositionen visuell geprüft. Paper-Screens nach Gruppen geprüft und Karte/Schrift/fehlende Werte korrigiert. 393×852 und 375×812, editierbare SVGs, volle/punktuell fehlende Daten. Vorhandene Dart-Algorithmen berechnen die synthetische Lauf-Fixture; 5 km, 25 Min., 142/162 Puls, 5,9 Belastung und 327 kcal sind damit konsistent. Keine App-, Hardware- oder physiologische Validierung.

### 018 · Activity summary

**Beobachtet:** Alle drei Positionen angesehen: Fitness-Kalender mit Activity Summary, Verlauf als kumulierter Vergleich über einen Monat und darunter chronologische Aktivitäten mit Filter und Hinzufügen.

**OpenBand:** Gemeinsamer Trainingsverlauf mit klaren 7/30/90-Tage-/Jahreszeiträumen, Aktivitätsfilter, Tagesbalken und prüfbarer Liste. Derselbe Diagrammtyp bleibt beim Filtern erhalten. Leerer Zeitraum und Rückkehr gestaltet; Hub heißt korrekt Letzte 7 Tage und nutzt dieselben Daten wie Details.

**Prüfung:** Alle Quellpositionen und Paper-Zustände Alle/Laufen/leer visuell geprüft. Überlappende Diagrammbeschriftung korrigiert; Filterflächen 44 pt. Summen 32+45+25=102 und Vergleich 78/+24 dokumentiert. Training Light/Dark aktualisiert; keine App-Implementierung.

### 019 · Add a recipe

**Beobachtet:** Sechs Positionen zeigen leere Rezeptsammlung mit Hinzufügen-Menü, Lebensmittelsuche und Auswahl, danach Rezeptname, Portionszahl, Gesamtgewicht und Nährwerte je Portion.

**OpenBand:** Eigener Rezeptdraft mit Gesamtzutaten, Portionen und optionalem tatsächlich gewogenem Endgewicht. Vorhandene Suche/Mengenbearbeitung wiederverwenden. Speichern erzeugt eine Vorlage in der Sammlung und keinen Verzehr. Leerer Draft, fertiger Draft, Speicherfehler und bestätigte Rückkehr sind gestaltet.

**Prüfung:** Alle sechs Quellen visuell angesehen. Vier neue Paper-Zustände bei 393×852 geprüft; Name/Zutaten/Portionen und 900 kcal gesamt / 450 je Portion konsistent. Aktionen und Fehler erhalten den Draft; keine Implementierung.

### 020 · Add a sleep alarm shortcut

**Beobachtet:** Alle vier Positionen angesehen: Bevel-Alarmtypen/Haptik, erklärende Einführung, Apple-Watch-Anleitung und Shortcut für Alarm plus Schlaffokus.

**OpenBand:** Eigener WHOOP-Bandwecker mit nächstem bestätigtem Termin und getrenntem lokalem Wochenplan. Kompakte Kurzbefehle-Hilfe öffnet den Wecker per App Intent; keine Übernahme von Apple-Watch-Onboarding oder unbewiesenen Smart-Alarm-Modi. Getrennt/unbestätigt zeigt eine klare Verbindungsaktion.

**Prüfung:** Vier Quellen und drei Paper-Screens visuell geprüft; echte Lucide-Icons. Aktuelle Alarm-Planmethoden/Statusmaschine gelesen, Offline-Kommentar gegen Verhalten geprüft. Apple-Primärdokumentation stützt native Shortcut-Einstiege. Keine Hardware- oder App-Intent-Ausführung.

### 021 · Add a workout template

**Beobachtet:** Drei Positionen zeigen Vorlagen-Einstieg, leeren Editor sowie gefüllten Plan mit Gewichten, Wiederholungen, Aufwärmsatz, Satzaktionen und Superset-Einstieg.

**OpenBand:** Vorlageneditor enthält geplante Sätze und unterstützt Wiederholungen oder Haltezeit. Kompakte Tabellen, einklappbare Übungen und feste Speicherleiste. Leerer Zustand erklärt die zwei fehlenden Voraussetzungen; Scrollfortsetzung zeigt weitere Übungen. Plan und ausgeführte Sätze bleiben getrennt.

**Prüfung:** Alle drei Quellen und drei bearbeitete Paper-Zustände visuell geprüft. Spalten, 44-pt-Felder und feste Speicheraktion kontrolliert. Vier Übungen / zwölf geplante Arbeitssätze konsistent. Picker/Superset/Speicherdetails bleiben den eigenen späteren Flows zugeordnet.

### 022 · Adding a bar weight

**Beobachtet:** Sechs Positionen zeigen Ausstattung im Vorlagengenerator, Smith-Machine-Stangen/Scheiben, Hinzufügen einer Stange über Zahlentastatur und gespeicherten 6-kg-Eintrag.

**OpenBand:** Eigene Ausstattung mit echten Geräteangaben: Stangenleergewicht, Scheibengewichte und Stückzahlen. Gemeinsamer Zahleneingabepfad und Bestätigung nach lokalem Speichern. Ein neuer Gerätewert verändert keine bestehenden Satzlasten; spätere Generatoren nutzen denselben Bestand.

**Prüfung:** Alle sechs Quellpositionen und drei Paper-Zustände visuell geprüft. Eigene Langhantelgrafik, Lucide-Symbole, deutsche Dezimaltastatur, 44-pt-Bedienflächen. Synthetische 7-kg-Stange erscheint nach Speichern; keine Hardware- oder Rechenimplementierung.

### 023 · Adding a card

**Beobachtet:** Alle vier Positionen zeigen Home-Bearbeitung, Kartenkatalog, Vorschau/Erklärung einer Cardio-Load-Karte und Hinzufügen vor finalem Speichern.

**OpenBand:** Eigener Karten-Draft mit Vorschau, Hinzufügen und explizitem Gesamt-Speichern. Kernübersicht bleibt oben, weitere Abschnitte wählbar. Trainingsumfang verwendet nachvollziehbare Minuten statt fremdem Belastungsscore. Reguläre Übersicht auf berechenbare Erholung 74/HRV 48 vereinheitlicht, Intervallfehler als eigene Variante bewahrt.

**Prüfung:** Vier Quellen und alle sieben bearbeiteten Paper-Screens visuell geprüft. Hauptscreen und Dark mit kompakteren Messwertkarten; Scrollfortsetzung und Editorzustände. Statusleisten-Ebenen und Reihenfolge nach Speichern korrigiert. Recovery-Fixture erneut mit reiner Dart-Funktion geprüft. Globaler Variantenabgleich bleibt offen.

### 024 · Adding a custom exercise

**Beobachtet:** Neun Positionen zeigen Bibliothek, Erstellen mit Name, Geräteauswahl, Wiederholungen/Dauer, Muskelgruppen und Rückkehr zur eigenen gespeicherten Übung.

**OpenBand:** Eigene Übungen mit Gerätesemantik und klarer Last-/Wiederholungsbasis. Muskelgruppen sind optionale Filter. Speichern erzeugt eine Bibliotheksdefinition; Auswählen/Hinzufügen zur Vorlage bleibt ein eigener Schritt. Leerer Zustand, Geräteauswahl, fertige Definition und gespeicherte Bibliothek sind gestaltet.

**Prüfung:** Alle neun Referenzpositionen visuell geprüft. Vier Paper-Zustände kontrolliert, zu lange Geräte-Unterzeile gekürzt. 44-pt-Back-/Auswahlflächen und Kopfzentrierung im gemeinsamen Helper korrigiert. Lastbasis-Beispiel 2×10 kg×8=160 kg als Backend-Vertrag dokumentiert; nicht implementiert.

### 025 · Adding a custom food

**Beobachtet:** Vier Positionen: Sammlung, leere Definition, ausgefüllte Nährwerte, gespeichert. Quellbeispiel enthält widersprüchliche Energie-/Makrowerte.

**OpenBand:** Kompaktes Formular mit expliziter Basis und üblicher Portion; Definition getrennt vom Konsum, unbekannt getrennt von null, eigener Konfliktzustand.

**Prüfung:** Alle vier Quellen und fünf Paper-Zustände visuell geprüft; 393 × 852. Keine App-Implementierung.

### 026 · Adding a custom nutrition log

**Beobachtet:** Nährstoffdetail → Mengen- und Zeitänderung → gespeicherter Einzelbeitrag; sieben Positionen.

**OpenBand:** Eigenständiger Nährstoffbeitrag mit Datum/Zeit und nachvollziehbaren Quellen; keine automatische Energie und kein Zielring ohne Ziel.

**Prüfung:** Sieben Quellpositionen und drei Paper-Zustände visuell geprüft. Bestehender nullable Ernährungsspeicher gelesen; Eintragstyp und Abdeckungssemantik noch umzusetzen.

### 027 · Adding a custom tag

**Beobachtet:** Fünf Quellen: Journal anpassen, eigene Bezeichnung/Symbol, Tagesbereich und Anheften, gespeicherte Definition.

**OpenBand:** Eigene Frage mit Vorschau und Lucide-Symbolen. Sichtbarkeit getrennt von Ja/Nein/Offen; stabile Definition getrennt von Tagesantwort.

**Prüfung:** Alle Quellen und drei neue Paper-Zustände angesehen; bestehende JournalFieldSpec/Custom-Editor gelesen.

### 028 · Adding a macronutrient goal

**Beobachtet:** Zielliste, Profilbestätigung, TDEE-Ladezustand, Prozent/Gramm und gespeicherte Ziele; sechs Positionen.

**OpenBand:** Direkte eigene Ziele ohne Profilzwang, optional und zeitlich versioniert. Kompakte Makrofelder; unvollständiger Tag zeigt bekannte Mengen statt exakter Restwerte. Automatische TDEE-Vorgabe nicht übernommen.

**Prüfung:** Alle Quellen und vier eigene Zustände angesehen; 2.000-kcal-Beispiel rechnerisch konsistent; alte Ziele-Seite ersetzt.

### 029 · Adding a manual sleep

**Beobachtet:** Schlafzeitliste, manueller Start/Ende und anschließender Nap. Unterschiedliche Beispielzeiten zwischen den drei Quellen.

**OpenBand:** Hauptschlaf/Nickerchen, Datum und Zeitzone explizit. Überschneidungen klären; manuelles Fenster bleibt von gemessenen Phasen und Ergebnisbereitschaft getrennt.

**Prüfung:** Alle drei Quellen und drei eigene Zustände angesehen; sleep_override/sleep_nap und AppState-Neuberechnung geprüft. Alte Schlafzeitenliste ersetzt.

### 030 · Adding a nutrient

**Beobachtet:** Drei Positionen: Nährstoffdetail ohne Werte, feste Mengenaktion, gespeicherter Beitrag.

**OpenBand:** Eigene Schnellmenge, nachvollziehbarer Zeitpunkt, Commit-Beleg mit Rückgängig. Fehlende Lebensmittelwerte bleiben offen; keine Zielvorgabe aus der Referenz übernommen.

**Prüfung:** Alle Quellen und zwei eigene Zustände visuell geprüft; bestehender Mengen-/Zeitdialog wiederverwendet.

### 031 · Adding a photo

**Beobachtet:** Drei Positionen: gespeicherte Mahlzeit ohne Foto, Fotoaktion im Menü, Mahlzeit mit Foto.

**OpenBand:** Direkter Fotoplatz plus Quellenpicker; lokaler Anhang getrennt von Nährwertquelle und optionaler Bildauswertung. Originales synthetisches Foto statt schematischer Bowl-Platzhalter.

**Prüfung:** Quellen und eigene drei Zustände sowie fünf aktualisierte Fotostrecken angesehen. Asset und Prompt lokal dokumentiert.

### 032 · Adding a recipe (old)

**Beobachtet:** Drei ältere Quellpositionen: Sammlungseinstieg, leerer Rezepteditor, benanntes Rezept mit zwei Zutaten und Portionen. Import nur als Menüaktion sichtbar.

**OpenBand:** Aktuellen Rezepteditor aus Flow 019 verwenden; keine zusätzliche Legacy-Variante. Leere Summe bleibt unbekannt, Gesamtzutaten und Werte je Portion explizit. Import in Flow 091.

**Prüfung:** Alle drei Quellen angesehen, aktuelle leere/gefüllte Paper-Editoren erneut geprüft. Bestehende Speichern/Fehler-Varianten wiederverwendet.

### 033 · Adding a tag

**Beobachtet:** Journal → Anpassungsmenü → Kategorienkatalog → zwei Fragen eingeschaltet → neue unbeantwortete Zeilen; sechs Positionen.

**OpenBand:** Sichtbarkeit direkt speichern, Antworten getrennt erhalten. Gemeinsamer Katalog für bestehende und eigene Felder; automatische Auswertungen benötigen echte Bereitschaft.

**Prüfung:** Sechs Quellen und zwei neue Paper-Zustände angesehen; Katalog beruht auf vorhandenen JournalFieldSpec-Typen.

### 034 · Adding additional nutrients

**Beobachtet:** Sechs Positionen: Lebensmitteleditor, weitere Felder, Katalog, Auswahl, eingegebene Zusatzwerte und Rückkehr zur Zutat.

**OpenBand:** Geteilter Nährstoffkatalog, vorhandene Felder markiert, neue Werte unbekannt. Basis und Einheiten sichtbar; Übernehmen nur in den richtigen Draft.

**Prüfung:** Alle sechs Quellen und drei neue Zustände angesehen; vorhandener Zusatzeditor erweitert. 100-g-/200-g-Beispiel konsistent.

### 035 · Adding an exercise

**Beobachtet:** Sechs Quellen: Vorlage, Hinzufügen-Menü, Bibliothek, Suche, Auswahl, hinzugefügte Übung.

**OpenBand:** Gerätevarianten/Erfassungsbasis klar; Details und Auswahl getrennt. Bestätigung in Zieldraft, keine ausgeführten Sätze oder erfundenen Vorgaben.

**Prüfung:** Alle sechs Quellen und vier neue Zustände visuell geprüft. Fixierte Aktion und 44-pt-Ziele; bestehender Katalog gelesen.

### 036 · Adding an exercise (photo)

**Beobachtet:** Fotoaktion, laufende Erkennung, eingefügte Übung mit Satzvorgaben; drei Positionen. Quellfoto selbst nicht zuverlässig lesbar.

**OpenBand:** Lokaler Plantextimport und explizite optionale Bilderkennung getrennt. Alle Übungs-/Setvorschläge vor Übernahme prüfen, Original erreichbar, Fehler erhält den Draft.

**Prüfung:** Alle drei Quellen und vier eigene Zustände angesehen. Keine OCR-/Providerintegration oder Erkennungsgenauigkeit behauptet.

### 037 · Adding excluded excercises

**Beobachtet:** Generator → erweiterte Vorgaben → Ausschlüsse → Bibliothek → Auswahl → Ausschlussliste; sechs Positionen.

**OpenBand:** Konkrete Gerätevarianten ausschließen, Vorschlagspräferenz getrennt von alten Vorlagen/Logs. Auswahl im Draft, danach speichern; künftiger Generator darf Einschränkungen nicht still lockern.

**Prüfung:** Alle Quellen und drei eigene Zustände visuell geprüft; bestehender Übungs-/Trainingspfad für fehlenden Ausschlussvertrag gelesen.

### 038 · Adding target nutrients

**Beobachtet:** Fünf Positionen: Zielübersicht, Katalog/Kategorien, Aktivieren und neue Zielkarten.

**OpenBand:** Explizite eigene Zielmenge nach Katalogauswahl, Zielwert/Obergrenze getrennt. Fehlende Tageswerte bleiben offen statt 0 %; gemeinsamer Katalog und Zielperioden.

**Prüfung:** Alle Quellen und drei eigene Zustände angesehen; synthetisches Ziel klar von B32-Eintrag getrennt.

### 039 · Adding weight

**Beobachtet:** Vier Positionen: Vorlageneditor, Gewichteingabe in kg/lb, Übernahme für folgende Sätze und aktualisierte Last.

**OpenBand:** Explizite Lastbasis und Zielmenge; Einzeländerung als Standard, Vorlagendraft erst separat speichern.

**Prüfung:** Alle vier Quellpositionen und drei eigene Zustände visuell geprüft; Dialogkopf zentriert und Aktionen 44 pt.

### 040 · All categories

**Beobachtet:** Zwei Positionen: Einstieg am Ende des Home-Verlaufs, Kategorien mit Messwerten und Mini-Verläufen.

**OpenBand:** Gemeinsamer suchbarer Wertekatalog aus Übersicht und Gesundheit; eigene Zeitbasis und Bereitschaft pro Wert.

**Prüfung:** Beide Quellen sowie Katalog, Fortsetzung und Home-Einstieg visuell geprüft.

### 041 · Appearance

**Beobachtet:** Vier Positionen: Darstellung mit App-/Hintergrund-/Widget- und Icon-Auswahl.

**OpenBand:** Drei Farbschemata mit Vorschau, zwei ruhige Hintergrundoptionen, systemgesteuerte Schrift und gemeinsames Widget-Schema. Keine dekorative Icon-Galerie.

**Prüfung:** Alle vier Quellen und Light/Dark sowie 375×812 mit 17/24-Text geprüft; Home-Indikator mittig, keine abgeschnittene Option.

### 042 · Biology

**Beobachtet:** Drei Positionen zeigen Home sowie Biology mit persönlichen Basiswerten und Körper-/Ausdauermessungen; unterschiedliche Beispieldaten.

**OpenBand:** Gesundheit mit Tageswerten, datierter Basis und optionalen Körpermessungen; keine erfundenen Trends aus Profilwerten. Hintergrund auf ruhigen Kopfverlauf reduziert.

**Prüfung:** Drei Quellen und eigene Gesundheit hell/dunkel, Scrollfortsetzung und Körperwerte angesehen; Basiswerte mit Fixture abgeglichen.

### 043 · Calculations

**Beobachtet:** Drei Positionen mit Berechnungsmethoden, Zeitfenstern und Datenpräferenzen.

**OpenBand:** Veränderbare Vorgaben von erklärten Methoden trennen; Daten-/Methodenversion und unterschiedliche HRV-Verfahren explizit.

**Prüfung:** Alle drei Quellen und beide eigenen Screens angesehen; RMSSD-, Ruhepuls- und Profileingangspfade im aktuellen Code gelesen.

### 044 · Change sleep goal method

**Beobachtet:** Sechs Positionen: manuelle/automatische Zielmethode, Analyse und fehlende Daten bei einer 90-Tage-Anforderung.

**OpenBand:** Eigene Dauer klar vom geschätzten Bedarf trennen; Bereitschaft vorab sichtbar und keinen üblichen Schlaf als Ziel ausgeben.

**Prüfung:** Alle sechs Quellen und vier eigene Zustände angesehen; bestehende Schlafbasis-/Freinacht-Annahmen im Code geprüft.

### 045 · Changing AI tone

**Beobachtet:** Fünf Positionen: Chatverlauf, Personalisierung, Tonvorschau und Speichern.

**OpenBand:** Drei benannte Stile mit lokalem, faktisch gleichem Beispiel; Entwurf/Commit und Faktenregeln unabhängig vom Stil.

**Prüfung:** Fünf Quellen und vier eigene Zustände visuell geprüft; bestehender Coach-Prompt und AiPrefs gelesen.

### 046 · Changing a memory expiration

**Beobachtet:** Fünf Positionen: gemerkte Angaben, Kontextmenü, Ablaufdatum und aktualisierte Liste.

**OpenBand:** Nur bestätigte eigene Angaben, inklusive Datum/Zeitzone, getrennte abgelaufene Liste; Ablauf ist keine Löschung alter Chats.

**Prüfung:** Alle fünf Quellen und vier eigene Zustände angesehen; bestehende Chatpersistenz ohne separaten Memory-Vertrag geprüft.

### 047 · Changing a nutrient daily target

**Beobachtet:** Vier Positionen: Katalog, Tagesziel/Schnelllog, Mengenänderung und aktiviertes Ziel.

**OpenBand:** 25→30 g als eigene Änderung mit Gültigkeit; Schnelllog 5 g unabhängig, fehlende Tagesmenge bleibt offen. Gemeinsamen Editor kompakter gemacht.

**Prüfung:** Alle vier Quellen und Änderungs-/Ergebnisansicht angesehen; bestehender Eingabebaustein mit aktualisiert.

### 048 · Changing a set type

**Beobachtet:** Drei Positionen: Vorlageneditor, fünf Satzarten und aktualisierte Kennzeichnung.

**OpenBand:** Kontextbezogene Satzart mit ausgeschriebener Zählung; geplante Absicht von bestätigter Ausführung trennen, Mengen unverändert.

**Prüfung:** Drei Quellen und Picker/Ergebnis angesehen; vorhandenes strength_set-Schema geprüft.

### 049 · Changing activity status

**Beobachtet:** Acht Positionen: eigener Aktivitätsstatus, Dauerwahl und Wirkung im Home.

**OpenBand:** Direkter Statuseditor, keine Gesundheitsannahme als Standard; zeitweise Trainingsimpulse pausieren, Messwerte und laufende Aufzeichnung behalten.

**Prüfung:** Alle acht Quellen sowie Editor, Dauer, Profileinstieg und Home-Zustand angesehen. Synthetische Tageswerte unverändert.

### 050 · Changing an alcohol preset amount

**Beobachtet:** Drei Positionen: Tagesliste und Bearbeitung der Alkohol-Schnelllog-Menge.

**OpenBand:** Portion und Alkoholgehalt statt undefinierter Drink-Einheit; Vorlagenänderung separat vom datierten Journal-Commit.

**Prüfung:** Drei Quellen und beide eigenen Zustände angesehen; units-Feld gelesen und ungefähre Alkoholmenge gegen NIAAA-Primärquelle geprüft.

### 051 · Changing an exercise duration

**Beobachtet:** Vier Positionen: Dauer-/Wiederholungseditor und Übernahme auf weitere Sätze.

**OpenBand:** Zeit und Wiederholungen klar typisieren, Minuten/Sekunden getrennt wählen; nur ausdrücklich genannte geplante Sätze ändern.

**Prüfung:** Alle vier Quellen, eigener Zeitdialog und drei geänderte Planzeilen angesehen; 60 s Dauer und 60 s Pause getrennt.

### 052 · Changing data loading window time period

**Beobachtet:** Sechs Positionen: erweitertes Ladefenster, Jahreswahl und Speichern.

**OpenBand:** Expliziter Nachladeauftrag nach Quelle/Datentyp, Wiederaufnahme mit bestätigtem Bestand; Abfrage, Speicherung und Berechnung getrennt.

**Prüfung:** Alle sechs Quellen und vier eigene Zustände angesehen; feste Importfenster, leere/fehlgeschlagene Reads und Rohdatenaufbewahrung im Code geprüft.

### 053 · Changing date

**Beobachtet:** Vier Positionen: Home, Monatskalender, Messwertwahl und historischer Tag.

**OpenBand:** Gemeinsamer Tageskontext mit metrikspezifischen Kalenderpunkten; vorhandener 14. September und leerer 20. August getrennt. Live-Bandstatus bleibt als heute bezeichnet.

**Prüfung:** Alle Quellen sowie drei eigene Ansichten visuell geprüft; Kalenderüberlauf behoben, native Statuszeilen und synthetische Kennzeichnung erneuert.

### 054 · Changing date period

**Beobachtet:** Sechs Positionen: 1M/1Y, Kalender-Endtag, Monatswechsel, bestätigter neuer Zeitraum.

**OpenBand:** 7/30 Tage/Jahr mit expliziter Aggregation; 30-Tage-Ruhepuls zeigt 15 fehlende Nächte und den Durchschnitt nur vorhandener Werte.

**Prüfung:** Alle Quellen, Tages-/Periodenansicht und Endtagpicker geprüft. Durchschnitt 55,866… berechnet; Lücke ohne Interpolation, Footerabstand und 44-pt-Kopf korrigiert.

### 055 · Changing distance unit

**Beobachtet:** Fünf Positionen zeigen Einheitenliste, km/mi-Auswahl, Wechsel und gespeicherten Rücksprung.

**OpenBand:** Unabhängige Einheiten mit sofortiger Einzel-Speicherung und Distanz-/Pace-Vorschau; Einstellungen in denselben kompakten Zeilen neu aufgebaut.

**Prüfung:** Alle Quellen und vier eigene Ansichten geprüft; bestehende Konversionsfaktoren gelesen und 3,11 mi / 8:03 min/mi nachvollzogen.

### 056 · Changing log time

**Beobachtet:** Vier Positionen: Journalanpassung, Tages-/Nachtgruppe, Wechsel und Journal mit umgeordneter Frage.

**OpenBand:** Anzeigegruppe heißt Anordnung; eigene Frage im Tagesverlauf, Antwort weiterhin Offen. Keine Umdeutung von Zeit oder Nacht.

**Prüfung:** Alle Quellen, Auswahl und Rückkehrzustand angesehen; Feldvertrag hasTime von Anzeigegruppe getrennt.

### 057 · Changing tracking intent

**Beobachtet:** Sechs Positionen: Nährstoff, Einstellungsmenü Ziel/Limit/None, geänderte Absicht und Zielübersicht.

**OpenBand:** Drei eigene Vergleichsarten mit datierter Grenze; unvollständige Zuckerangaben ergeben ≥8 g und offene Bewertung statt erfundenem Restbudget.

**Prüfung:** Alle Quellen und beide eigenen Zustände visuell geprüft; Teilmenge 8 g mit fehlendem Haferbeitrag, keine falsche Null oder automatische Empfehlung.

### 058 · Changing zone calculation method

**Beobachtet:** Vier Positionen: vorhandene Zonen, Methodenwahl, Reserve-Methode mit zweitem Eingang.

**OpenBand:** Automatisch/Maximalpuls/Pulsreserve/eigene Grenzen; Eingänge, Herkunft, Vorschau und fehlende Basis. Änderung gilt für neue Trainings.

**Prüfung:** Quellen und fünf eigene Zustände angesehen; bestehende Automatik/Reserve-Formel und Mindesthistorie gelesen, numerische Grenzen überprüft.

### 059 · Chatting with Bevel AI

**Beobachtet:** Sechs Positionen: Home-Einstieg, Vorschläge, Frage, Verarbeitung und Antwort mit Fortsetzung.

**OpenBand:** Kontextuelles Gespräch auf deckender Fläche, kurze datenbelegte Antwort, Quellen, Stopp/Fehler/fehlende Messung, bestätigte Notiz und Einrichtungswege mit Datenfreigabe.

**Prüfung:** Alle Quellen und eigener Gesprächs-/Einrichtungsweg visuell geprüft. Quellenliste, 17/24-Prosa, feste Eingabe, keine leere Nachricht, Freigabegruppen und separate Aktionsbelege dokumentiert.

### 060 · Clearing cache & reload all data

**Beobachtet:** Zwei Positionen zeigen kombinierte Cache-/Reload-Aktion und zurückgekehrte Home-Ansicht.

**OpenBand:** Anzeige neu laden, Werte neu auswerten und Quelldaten nachladen getrennt. Vorprüfung, atomarer Abschluss, fehlende Originale und Unterbrechung mit erhaltenem Bestand.

**Prüfung:** Quellen und sechs eigene Zustände geprüft; reanalyzeAll-Nullbefund bei Fehler gelesen und als neuer getypter Jobvertrag dokumentiert.

### 061 · Connect a CGM

**Beobachtet:** Acht Positionen: Ernährungseinstieg, Sensorwahl, Verbindungsart und Herstelleranmeldung. Health als alternativer Datenweg sichtbar.

**OpenBand:** Optionaler Health-Leseweg mit genauer Quellen-/Zeitangabe. Keine unbewiesene Herstellerintegration oder Live-Zusage; echte Datenlücke und leeres Ergebnis ohne behauptete Verweigerung.

**Prüfung:** Alle acht Quellen und eigene Zustände angesehen. Elf synthetische Werte mit Lücke, aktueller Importcode und Apple-Dokumentation geprüft; keine echte Health-Verbindung.

### 062 · Connecting with Apple Health

**Beobachtet:** Drei Schritte: Health als Glukoseweg, fehlgeschlagenes Lesen, Verwaltung mit fester Verzögerungsangabe.

**OpenBand:** Eigener Quellen-Hub trennt Lesen, gewünschte automatische Übernahme, Schreibauswahl und tatsächlich exportierte Ergebnisse. Keine pauschale Herstellerverzögerung.

**Prüfung:** Alle drei Quellpositionen und vier eigene Verwaltungs-/Freigabeansichten visuell geprüft; aktueller Import-/Exportcode und Apple-Autorisierung gelesen.

### 063 · Copying a message

**Beobachtet:** Kleine Aktion unter Antwort, danach Haken und Kopierhinweis.

**OpenBand:** Antwort mit Datum, Datenstand und lesbaren Kennzahlen kopierbar; Erfolg direkt am Auslöser.

**Prüfung:** 2/2 Quellen und Kopierbeleg visuell geprüft; Coach-Textpfad auf Clipboard geprüft.

### 064 · Copying an exercise

**Beobachtet:** Optionale Ausgangsübung aus Bibliothek, Einzelauswahl, übernommenes Formular.

**OpenBand:** Metadaten in neue eigene Definition kopieren; Bearbeiten, Speichern und zur Vorlage hinzufügen bleiben getrennt.

**Prüfung:** 4/4 Quellen sowie Picker, Entwurf und Speicherbeleg visuell geprüft; statischen Katalog gelesen.

### 065 · Creating a superset

**Beobachtet:** Mehrfachauswahl verbindet Übungskarten; Gruppen lassen sich wieder lösen.

**OpenBand:** Gemeinsame A1/A2-Karte mit Rundenfolge und expliziter Rundenpause. Gruppierung verändert keine absolvierten Sätze.

**Prüfung:** 5/5 Quellen, Auswahl und gruppierten Vorlagenentwurf visuell geprüft; Satz-/Übungstabellen gelesen.

### 066 · Customization

**Beobachtet:** Anpassungsmenü führt zu Zielen, Einheiten, Berechnung und einzelnen Produktbereichen.

**OpenBand:** Gemeinsamer Hub mit denselben kontextuellen Editoren; Datenverwaltung bleibt eigener Weg.

**Prüfung:** 2/2 Quellen, Hub und aktualisierter Einstieg visuell geprüft.

### 067 · Deleting a chat

**Beobachtet:** Gesprächsmenü mit Löschen, anschließend aktualisierte Liste.

**OpenBand:** Lokalen Umfang bestätigen, konkrete Gesprächs-ID löschen, Journal und gemerkte Angaben getrennt verwalten.

**Prüfung:** 3/3 Quellen und drei eigene Ablaufzustände angesehen; Lösch-/Persistenzcode gelesen. Wiederholte Paper-Exporte lassen gemeinsame Kopfebenen teilweise aus; abschließender Renderabgleich bleibt offen.

### 068 · Deleting a custom exercise

**Beobachtet:** Löschen einer eigenen Übung mit Zusage, aufgezeichnete Daten zu behalten.

**OpenBand:** Reversibles Archivieren mit eigener Ansicht und Wiederherstellung; stabile historische Definitionen erhalten.

**Prüfung:** 5/5 Quellen sowie Verwaltung und Archivzustand visuell angesehen; bestehende exercise_def-Tabelle berücksichtigt.

### 069 · Deleting account

**Beobachtet:** Kontolöschung mit endgültiger Bestätigung und Rückkehr zum Einstieg.

**OpenBand:** Lokaler Reset mit konkretem Umfang, optionaler Sicherung, Teilfehler und bestätigtem Abschluss; kein erfundenes Konto.

**Prüfung:** 3/3 Quellen und vier eigene Zustände visuell angesehen; Reset-/Tabellenlöschcode geprüft. Lange Unterzeile verkürzt und Rückweg nach bereits erfolgter Löschung entfernt.

### 070 · Deleting an alcohol log

**Beobachtet:** Einzelnen Alkoholeintrag löschen; leerer Tag bietet ausdrückliche Nullangabe.

**OpenBand:** Entfernen mit Rückgängig, unbekannten Tag und bewusste Kein-Alkohol-Bestätigung unterscheiden.

**Prüfung:** 3/3 Quellen und beide eigenen Zustände visuell geprüft; separate synthetische Vortagsvariante dokumentiert.

### 071 · Disconnecting a CGM

**Beobachtet:** CGM-Verwaltung: Trennen entfernt die aktive Quelle und bietet Verbinden an.

**OpenBand:** Health-Übernahme explizit ausschalten; gespeicherte Werte, Messzeit und Systemfreigabe getrennt erhalten.

**Prüfung:** 3/3 Quellen und eigener abgeschalteter Zustand visuell geprüft.

### 072 · Duplicating a template

**Beobachtet:** Vorlagenmenü dupliziert den Plan und zeigt Original und Kopie in derselben Liste.

**OpenBand:** Gespeicherte eigenständige Kopie mit neuem Identitätsbaum, klarer Bearbeitungsaktion und erhaltenem Original.

**Prüfung:** 3/3 Quellen und beide eigenen Zustände angesehen; Abgrenzung zu Übungskopie und Trainingshistorie dokumentiert.

### 073 · Edit home

**Beobachtet:** Home scrollt bis zu Bearbeiten/Alle Kategorien; Bearbeitungsmodus bietet Karten und Standard-Reset.

**OpenBand:** Bestehenden Kartenentwurf um sichtbare Menüs und zugängliches schrittweises Verschieben ergänzen; Kopf bleibt verlässlich.

**Prüfung:** 3/3 Quellen, bestehenden Editor und zwei neue Anpassungszustände angesehen; bestehende Hinzufügen-Variante ebenfalls harmonisiert.

### 074 · Editing a food icon

**Beobachtet:** Bildsymbol-Picker mit Lebensmittelkategorien verändert die Darstellung im Editor.

**OpenBand:** Beschriftete lizenzierte Lucide-Auswahl; Symboländerung von Nährstoff- und Verzehrdaten trennen.

**Prüfung:** 4/4 Quellen und zwei eigene Zustände visuell geprüft; sechs offizielle Icons mit gleichem Lizenzbezug ergänzt.

### 075 · Editing a nutrition goal

**Beobachtet:** Zieländerung passt Grammwerte bei konstanten Prozentanteilen an; Zahleneingabe und gespeicherte Vorschau.

**OpenBand:** Gramm- und Prozentmodus mit expliziter Rechenregel, Gültigkeitstag und erhaltener Historie. Zieländerung ab morgen getrennt vom heutigen Fortschritt.

**Prüfung:** 6/6 Quellen, bestehender Gramm-Editor und neue Prozentänderung/Gültigkeitsansicht angesehen; 2.100-kcal-Verteilung geprüft.

### 076 · Editing an activity title

**Beobachtet:** Titel wird über Aktivitätsmenü geändert; gespeicherte Messwerte bleiben gleich.

**OpenBand:** Eigener Titel als stabile Metadatenkorrektur, ursprünglichen Aktivitätstyp und Messwerte behalten.

**Prüfung:** 4/4 Quellen und Titelentwurf/gespeichertes Laufdetail angesehen; Eingabelimit und Rückweg korrigiert.

### 077 · Editing quick add amount

**Beobachtet:** Schnellmenge wird unabhängig vom Ziel geändert; danach trägt die Eintragsaktion die neue Menge.

**OpenBand:** Eigene Schnellmenge 5 auf 10 g ändern, Tagesziel 30 g und fehlende Tagesangabe bleiben unverändert.

**Prüfung:** 3/3 Quellen und beide eigenen Zustände angesehen; Änderungs- und Eintragswirkung getrennt dokumentiert.

### 078 · Enabling notifications

**Beobachtet:** Freigabe schaltet Kategorien frei; eigene Mitteilungsarten sind getrennt wählbar.

**OpenBand:** OS-Status, Kategorien, Zeitplan, Ruhezeit und Bandwecker getrennt. Keine Zustell- oder Gesundheitsversprechen aus bloßer Aktivierung.

**Prüfung:** 3/3 Quellen und fünf eigene Ansichten angesehen; bestehende Benachrichtigungseinstellungen und Scheduler gelesen.

### 079 · Exercise detail

**Beobachtet:** Übungsdetail verbindet Illustration, Geräte-/Muskelgruppen und Anleitung.

**OpenBand:** Originale Geräteillustration, beschriftete Bibliotheksangaben, eigener letzter Satzbestand und separate Erfassungshilfe. Keine gemessene Muskelkarte suggerieren.

**Prüfung:** 3/3 Quellen, eigene Illustration und beide Detailansichten angesehen; Volumenarithmetik geprüft, Asset im Projekt mit Herkunft gespeichert.

### 080 · Filtering activity summary

**Beobachtet:** Aktivitätsübersicht wechselt zwischen Dauer, Distanz und Höhengewinn bei gleichem Zeitraum.

**OpenBand:** Vergleichbare Einheiten und bekannte Teilsummen offenlegen; fehlende Distanz nicht als Null und Kraft nicht als Distanzlücke zählen.

**Prüfung:** 4/4 Quellen und drei neue Filterzustände angesehen; unbekannte Strecke als Text/Fragezeichen statt Balkenwert korrigiert.

### 081 · Filtering cardio focus

**Beobachtet:** Cardio-Fokus lässt sich nach Aktivitätsart filtern; Verteilung und Verlauf wechseln gemeinsam.

**OpenBand:** Eigene Trainingszonen mit Dauer-Nenner und Methodenbasis. Bei All-Filter fehlende 77 Minuten offenlegen, Lauf vollständig.

**Prüfung:** 5/5 Quellen und drei eigene Ansichten angesehen; 0/6/15/4/0 Minuten ergeben 25 Minuten und 60 % Zone 3.

### 082 · Filtering exercises

**Beobachtet:** Mehrfachfilter für Muskelgruppen und Geräte; aktive Chips zeigen Anzahl.

**OpenBand:** Getrennte Detail-/Auswahlziele, Filterentwurf und sichtbarer Zähler verdeckter Auswahl.

**Prüfung:** 5/5 Quellen angesehen; drei editable Ansichten geprüft, aktive Bestätigung korrigiert.

### 083 · Filtering memories

**Beobachtet:** Themenfilter ergänzt Aktivitätsdauer-Tabs in gemerkten Angaben.

**OpenBand:** Themenwahl, sichtbarer Filter und klarer Unterschied zu den tatsächlich vom Coach genutzten Angaben.

**Prüfung:** 4/4 Quellen und zwei eigene Ansichten geprüft. Kein Filter löscht oder deaktiviert eine Angabe.

### 084 · Fitness

**Beobachtet:** Fitness führt von Kalender und Übersicht über Cardio zu Muskelgruppen, Fortschritt und Vorlagen; die Seite scrollt deutlich weiter.

**OpenBand:** Training neu verdichtet, zwei Scrollpositionen und Kraftdarstellung. Eigene lesbare Balken statt kopiertem Radardiagramm, Datenbasis sichtbar.

**Prüfung:** 7/7 Quellen angesehen. Training und Fortsetzung bei 393 × 852 geprüft; 102 Minuten, drei Einheiten und 3.300 kg stimmen mit Fixtures überein.

### 085 · Food quality contributors

**Beobachtet:** Bevel erklärt Makro-Balance, Salz und zugesetzten Zucker unter einer Lebensmittelbewertung.

**OpenBand:** Eigene portionsbezogene Nährwerterklärung und Herkunft. Unbekannter zugesetzter Zucker bleibt offen, kein unbelegter Qualitätsscore.

**Prüfung:** 2/2 Quellen und beide eigenen Ansichten geprüft; 170 kcal Originalangabe und 172 kcal Makroenergie ausdrücklich unterschieden.

### 086 · Generating a template

**Beobachtet:** 19 Positionen führen durch Erfahrung, Ort/Geräte, Ziel, Methode, Zeit, Fokus, Intensität und editierbaren generierten Plan.

**OpenBand:** Drei übersichtliche Schritte mit Drill-down-Auswahl, Geräte statt pauschalem Ort, prüfbarer Vorschlag. Lokaler geführter Weg; manuelle Erstellung bleibt direkt erreichbar.

**Prüfung:** 19/19 Quellen angesehen. Zehn eigene Zustände geprüft, inklusive Erstellung, Unterbrechung, bearbeitbarem Ergebnis und Speicherbestätigung. Keine Vorlage als Training gezählt.

### 087 · Hiding a data source

**Beobachtet:** Bevel blendet einzelne Datenquellen je Messgröße aus und zeigt die Anzahl ausgeblendeter Quellen.

**OpenBand:** Expliziter Ausschluss von Anzeige/Auswertung mit Auswirkungen, erhaltenem Bestand und eigener Importsteuerung. Leerer Zustand erklärt den selbst gewählten Ausschluss.

**Prüfung:** 6/6 Quellen sowie Quellenliste, Entwurf, Bestätigung und Glukose-Leerzustand geprüft. 11 Originalwerte bleiben erhalten.

### 088 · History

**Beobachtet:** Der Verlauf liegt hinter dem Gespräch und bietet einen neuen Chat sowie zeitlich gruppierte Einträge.

**OpenBand:** Vorhandene Gesprächsliste wiederverwendet, vollständiges Coach-Menü und leeren Verlauf ergänzt. Gespeicherte Antwort bleibt mit Datenstand verbunden.

**Prüfung:** 2/2 Quellen und Liste, Menü, leerer Verlauf sowie bestehende Antwort visuell geprüft.

### 089 · Home

**Beobachtet:** Sieben Home-Positionen zeigen Datum, drei Ringe, kurzen Insight, Stress/Energie, Ernährung, Gesundheitswerte, Zeitlinie, Anpassung und laufendes Training.

**OpenBand:** Kompakten freigegebenen Tagesfeed erhalten; scrollbaren unteren Bereich vervollständigt, eigene Erfassungsauswahl und persistente Trainingsrückkehr ergänzt. Schlafkreis ohne unbelegte Zielskala.

**Prüfung:** 7/7 Quellen und fünf eigene Ansichten angesehen. Light/Dark und Scrollende stimmen überein; Werte bleiben am selben synthetischen Tag. Gesamtinventar-QA separat offen.

### 090 · How to log

**Beobachtet:** Übungsdetails öffnen eine gezielte Erklärung der Gewichtseingabe für die Geräteart.

**OpenBand:** Bestehende Langhantel-Hilfe ergänzt um visuelle Hanteladdition und Maschinenlast, jeweils mit klarer Bezugsgröße.

**Prüfung:** 2/2 Quellen und drei eigene Hilfen geprüft. Maschinenanzeige, Last je Hantel und Gesamtlast bleiben verschieden.

### 091 · Importing a recipe

**Beobachtet:** Text/Foto-Import führt über Erkennung zur editierbaren Rezeptdefinition; Speichern kehrt in die Sammlung zurück.

**OpenBand:** Originaltext, Zutatenzuordnung und Portionen sichtbar, unsicheres Lebensmittel gezielt auflösen. Bestehenden Rezepteditor und Speicherzustände wiederverwendet.

**Prüfung:** 7/7 Quellen, vier neue Importzustände und bestehender Editor/Sammlung angesehen. 900 kcal/2 =450 je Portion; kein Tagesverzehr erzeugt.

### 092 · Insights

**Beobachtet:** Journal-Insights bieten Schlaf/Erholung und eine Übersicht noch gesperrter Gewohnheiten.

**OpenBand:** Bereitschaft, vorhandenes Ergebnis und geprüftes Nicht-Ergebnis getrennt; Vergleich bis auf verwendete Tage nachvollziehbar. Keine dekorative Freischalt-Prozentzahl.

**Prüfung:** 3/3 Quellen und fünf eigene Ansichten geprüft. Zwei synthetische Langzeitfälle tatsächlich mit vorhandenem Dart-Algorithmus gerechnet, Ergebnisse als Design-Fixtures gespeichert.

### 093 · Journal

**Beobachtet:** Journal kombiniert Wochenwahl, knappe tägliche Eingaben, Gewohnheiten und automatisch gelesene Beobachtungen; Insights/Anpassung liegen im Kopf.

**OpenBand:** Tagesübersicht neu verdichtet und weiterführende Scrollposition angelegt. Gewohnheitsantworten klar von Sensorbeobachtungen getrennt.

**Prüfung:** 5/5 Quellen und drei eigene Ansichten geprüft. Header zwischen Scrollpositionen angeglichen, Footer vollständig sichtbar gemacht; erfundene historische Journalmarker entfernt.

### 094 · Log custom caffeine intake

**Beobachtet:** Koffein zeigt Tagesbeiträge, eigene mg-Eingabe, Stepper und Zeitpunkt.

**OpenBand:** Unbekannten Kaffee sichtbar halten und Ergänzen von zusätzlichem Beitrag trennen. Eigene90mg erzeugen eine ehrliche Untergrenze.

**Prüfung:** 4/4 Quellen und drei eigene Zustände geprüft. Bekannte90mg, unbekannter Kaffee und unveränderte übrige Tageswerte unterschieden.

### 095 · Log detail

**Beobachtet:** Gespeicherte Mahlzeit führt von Portion/Makros über weitere Nährwerte zu Zutaten und Quelle.

**OpenBand:** Bestehende Hafer-/Rezeptdetails weiterverwendet, Joghurtportion und unvollständigen Kaffee ergänzt; Aktionen beziehen sich klar auf den gespeicherten Verzehr.

**Prüfung:** 3/3 Quellen und vollständiger/partieller Eintrag samt Aktionen geprüft. 170-kcal-Portion entspricht200g, gespeicherte und Katalogwerte nicht vermischt.

### 096 · Logging a daily mood

**Beobachtet:** Neun Positionen zeigen Stimmungsauswahl, optionale Gefühlsworte, Kontext und gespeicherten Moment.

**OpenBand:** Eigene ruhige Gefühlsdarstellung, fünf beschriftete Stufen ohne Vorauswahl; Details optional und gemischte Gefühle möglich.

**Prüfung:** 9/9 Quellen und vier neue Ansichten geprüft. Offener und bewusst gewählter Zustand getrennt, gespeicherte4/5 als Moment09:41.

### 097 · Logging an activity

**Beobachtet:** Neun Positionen: Aktivitätsauswahl, Zeitauswahl, manuelle Details, Distanz und Speichern. Bevel hält Eingaben in kompakten gruppierten Formularen.

**OpenBand:** Eigener Nachtrag mit klarer Sensor-/Eigenangaben-Trennung, berechneter Pace und Überschneidungsprüfung. Kein Puls, keine Route und kein Belastungswert aus einer bloßen Dauer.

**Prüfung:** Alle neun Quellpositionen und vier neue 393×852-Screens visuell geprüft. 2 km in 25 Minuten = 12:30/km; Duplikatvariante separat. Vorhandener manueller Lauf bleibt als fehlende-Daten-Variante.

### 098 · Logging custom alcohol intake

**Beobachtet:** Alle fünf Positionen zeigen leeren Alkoholtag, explizite Nullantwort und einen frei veränderbaren Drink mit Uhrzeit bis zum gespeicherten Listeneintrag.

**OpenBand:** Vier eigene Ansichten trennen offen, Getränkedraft, gespeicherte Menge und ausdrücklich keinen Alkohol. Volumen und % vol erklären die Grammangabe; keine unklare Drink-Norm.

**Prüfung:** 5/5 Quellen angesehen; vier 393×852-Ansichten visuell geprüft, Eingaben und Ergebnis ohne Überlauf. 150 ml bei 12 % vol ergeben gerundet 14 g. Gemeinsamer Zeit- und Zahleneingabevertrag.

### 099 · Logging custom water intake

**Beobachtet:** Vier Positionen zeigen leere Wasserliste, Schnellmenge, freie Menge mit Uhrzeit und aktualisierte Tagesliste. Das Glas illustriert eine Eingabe, keinen physiologisch gemessenen Zustand.

**OpenBand:** Kompakte Tropfen-/Mengenansicht, eigene Mengenwahl und bestätigte Teilsummen. Ohne gesetztes Ziel kein Bedarfsring. Tagesbestand bleibt nachvollziehbar statt erfundener Einzelzeiten.

**Prüfung:** 4/4 Quellen und vier 393×852-Ansichten geprüft. 750 + 350 = 1.100 ml; fehlende Menge und gespeicherter Bestand getrennt. Einträge nutzen gemeinsame Bearbeiten-/Löschen-Aktionen.

### 100 · Logging in

**Beobachtet:** Fünf Positionen: Einstieg mit Apple oder E-Mail, Mailadresse, Linkversand mit erneuter Sendemöglichkeit und eingeloggte Übersicht.

**OpenBand:** Keine Anmeldung für lokale Kernfunktionen. Vorhandener Start erhält ausdrücklich Ohne Konto loslegen und die aktuelle Schlafdauer-Darstellung ohne Zielquote. Import und spätere Bandverbindung bleiben gleichwertige Wege.

**Prüfung:** 5/5 Quellen gesehen; bestehender Willkommen-Screen nach zwei Änderungen erneut visuell geprüft. Keine erfundene Kontosynchronisierung.

### 101 · Logging out

**Beobachtet:** Zwei Positionen: Accountdetails mit getrennten Log-out-/Delete-account-Aktionen und Rückkehr zum Start.

**OpenBand:** Bewusste Nichtübernahme eines allgemeinen Logouts. Lokales Profil, Band, optionale Anbieter und Datenlöschung bleiben eigene Aufgaben. Bestehende Profil- und Löschvorschau passen zur neuen Gestaltung.

**Prüfung:** 2/2 Quellen angesehen, Profil und Löschvorschau erneut visuell geprüft. Bestätigung, Teilfehler und Abschluss aus Flow 069 bleiben die vorhandenen Ausgänge.

### 102 · Macro balance

**Beobachtet:** Vier Positionen zeigen gestapelte Makrohistorie, Grammwahl, Wochen-/Monatslisten mit Mittel/Summe sowie Erklärung. Quellseitig werden leere Zeiträume teilweise als Null dargestellt.

**OpenBand:** Eigene Makroansicht mit drei klaren Mengen und bekannten Energieanteilen, lückenbewusster Wochenansicht und kurzer Erklärung. Kein Gesamt-Gramm-Score und keine Nullwerte für nicht protokollierte Tage.

**Prüfung:** 4/4 Quellen und drei 393×852-Screens geprüft. 36×4 + 80×4 + 18×9 = 626; gerundete Anteile 23/51/26 %. Fehlende Tage, Eintragsbasis und unabhängige 620-kcal-Summe bleiben sichtbar.

### 103 · Manage subscription

**Beobachtet:** Zwei Positionen: Bevel-Pro-Einstieg in Einstellungen und Abo-/Testzeitverwaltung mit Bearbeiten-Link.

**OpenBand:** Keine Übernahme einer Abonnementverwaltung. Der Produktauftrag bleibt abonnementfrei, optionale externe Dienste erhalten ihre eigene erklärte Einrichtung.

**Prüfung:** 2/2 Quellen gesehen; bestehende Einstellungen und lokaler Modellweg visuell geprüft. Keine neue Paywall oder Kontobindung eingeführt.

### 104 · My foods

**Beobachtet:** Acht Positionen zeigen Nutrition-Einstieg und die Bibliotheksfilter Historie, Favoriten, Rezepte und eigene Lebensmittel jeweils mit leeren bzw. gefüllten Listen.

**OpenBand:** Sammlung vollständig auf vier verständliche Filter überarbeitet. Eigene Vorlagendetails führen erst nach Portion und Bestätigung zum Verzehr. Favorit-/Rezept-/Lebensmittelspeicherung landen im passenden Filter; neue Anlage hat eine klare Typwahl.

**Prüfung:** 8/8 Quellen und sieben eigene Ansichten geprüft, drei bestehende Screens ersetzt. Header der Favoritenbestätigung zusätzlich in 2× geprüft. Aktuelle food_def/recent-Implementierung gelesen; Identitäts- und Sortierlücke dokumentiert.

### 105 · Nap

**Beobachtet:** Zwei Positionen zeigen Nickerchen im Schlafverlauf und Detail mit Dauer, Zeitfenster, Quelle, Schlafbankwirkung und Pulskurve.

**OpenBand:** Nickerchen erhält eine eigene kompakte Detailansicht und explizites Entfernen. Eigene Zeitangabe, Messdaten und Hauptnacht bleiben getrennt; Bearbeiten nutzt den vorhandenen Schlafeditor.

**Prüfung:** 2/2 Quellen sowie Sessionliste und zwei neue Screens visuell geprüft. 14:10–14:35 = 25 Minuten; keine erfundene Pulskurve, Phasen oder Schlafbankwirkung.

### 106 · Net energy

**Beobachtet:** Drei Positionen zeigen Zufuhr-/Verbrauchsbalken, negative Bilanz, Zeitraummittel und eine Erklärung der Differenz.

**OpenBand:** Bilanz im Basistag offen, verfügbare Darstellung in klar separater synthetischer Volltagsvariante. Kompakter Zweibalkenvergleich, Eingänge und Erklärung statt suggestiver Defizitampel.

**Prüfung:** 3/3 Quellen und drei 393×852-Ansichten visuell geprüft. Aktuelle gemeinsame Tagesenergie-Berechnung gelesen. Nur Darstellungsarithmetik 1.900−2.300=−400 geprüft; keine physiologische Validierung.

### 107 · Nutrition

**Beobachtet:** Sieben Positionen zeigen den gesamten Ernährungsbereich leer und gefüllt: Einstieg, Score, Erfassungswege, Sammlung/Ziele, Makros, Bilanz, Timeline, Trends und optionale Glukose.

**OpenBand:** Ernährung und Speicherzustand vollständig neu aufgebaut, klare zurückführende Detailnavigation mit Datum/Menü, durchgehender Inhalt und eigene Fortsetzungsansicht. Alte unpassende Wochenwerte ersetzt. Leerer Zustand ohne Nullkalorien oder erfundenes Defizit.

**Prüfung:** 7/7 Quellen gesehen. Fünf Ansichten visuell geprüft, Reihenfolge kopierter Fortsetzungskarten korrigiert, vollständiger Leerzustand nach Renderauffrischung geprüft. Oberer Ausschnitt und Fortsetzung bleiben konsistent; kein App-Code verändert.

### 108 · Nutrition (Settings)

**Beobachtet:** Drei Positionen zeigen Ernährungsanpassung, Sichtbarkeit, Zielverfolgung, Glukose und getrennte Apple-Health-Schreibgruppen.

**OpenBand:** Vier kompakte eigene Ansichten: Bereichsmenü, sichtbare/ausgeblendete Karten und explizite Health-Auswahl. Sichtbarkeit, Datenbestand, Zielwerte und Berechtigungen werden unabhängig behandelt.

**Prüfung:** 3/3 Quellen und vier eigene Screens visuell geprüft. Schalter mindestens 44 pt hoch; kein abgeschnittener Text. Ausgewählte Datenarten bleiben vor iOS-Freigabe unautorisiert.

### 109 · Nutrition score

**Beobachtet:** Drei Positionen zeigen Nutrition-Score-Verlauf, persönlichen Bereich, Kategorienverteilung, gleitende Trends und Qualitätsbeschreibung.

**OpenBand:** Begründete Nichtübernahme eines pauschalen Ernährungsqualitäts-Scores. OpenBand verwendet die bereits neu gestalteten Mengen, eigenen Ziele, Erfassungsbasis und Verläufe. Kein nutzloser leerer Score-Platzhalter.

**Prüfung:** 3/3 Quellen angesehen, zugehörige eigene Ansichten in Flows 102/107 geprüft. Gezielte Suche nach vorhandenem Scorevertrag ohne Treffer; keine fremden Schwellen übernommen.

### 110 · Nutritional detail

**Beobachtet:** Fünf Positionen zeigen suchbare Nährstoffliste, Kalorien-/Fett-/Cholesterinbeiträge, individuelle Ergänzungen und Ziele.

**OpenBand:** Tagesliste, Energie- und Fettbeiträge im gemeinsamen Layout. Expliziter Abschluss unterscheidet bestätigte Mahlzeitenerfassung von bekannten Nährwerten. Sichtbarer Alle-Nährwerte-Einstieg, deutsche Eiweiß-Benennung auch in vorhandenen Drafts.

**Prüfung:** 5/5 Quellen und fünf neue Ansichten visuell geprüft; Menüergänzung geprüft. 450+170=620 kcal, 14+4=18 g Fett. Bestätigung erfindet keine Vollständigkeit des Kalorientags.

### 111 · Nutritional goals

**Beobachtet:** Sieben Positionen zeigen Ziele ohne Vorgaben und mit Werten, historischen Tagwechsel, Makrorestmengen sowie getrennte Ziel- und Grenznährstoffe.

**OpenBand:** Bestehende Zielübersicht verdichtet und neu gestaltet; Zielgültigkeit erhält einen eigenen Verlauf. Mindestziel und Obergrenze mit unbekannten bzw. partiellen Mengen werden explizit gezeigt. Vorhandene Ziel- und Nährstoffeditoren bleiben die Eingabewege.

**Prüfung:** 7/7 Quellen gesehen; drei aktualisierte/neue Zielansichten sowie bestehender Leerzustand und Nährstoffpicker geprüft. Ziel gilt erst ab 15. September. Teilwerte erzeugen keine genaue Restmenge.

### 112 · Pinned tags

**Beobachtet:** Zwei Positionen zeigen den Pinned-tags-Menüpunkt und die Liste aktiver Tags mit einzelnen Pin-Aktionen und Save.

**OpenBand:** Eigenständige Auswahl Oben im Journal, erreichbar aus dem aktualisierten Journalmenü. Persönliche Sortierung bleibt getrennt von Messwerten und Antworten.

**Prüfung:** 2/2 Quellen und Auswahl-/Menüansicht visuell geprüft. Fünf 44-pt-Pinflächen; offizielles Lucide-SVG samt bestehender Lizenzbasis aufgenommen.

### 113 · Pinning a tag

**Beobachtet:** Drei Positionen zeigen Pin/Unpin in der Tagkonfiguration und eine eigene Pinned-Sektion vor den übrigen Journalfeldern.

**OpenBand:** Gewohnheit mit Tagesgruppe und Pin-Zustand, danach tatsächliches Journal mit Abends gelesen vor dem Check-in. Keine doppelte Zeile; Antwort bleibt ausdrücklich offen.

**Prüfung:** 3/3 Quellen, Konfiguration und komplettes Journal nach Layoutauffrischung geprüft. Bestehende Tageswerte unverändert; Menü-/Tabnavigation entspricht dem neuen System.

### 114 · Pinning a workout

**Beobachtet:** Fünf Positionen zeigen Vorlagenbereich, Aktionsmenü, leere Pin-Auswahl, angeheftete Auswahl und Rückkehr zur Fitnessseite.

**OpenBand:** Leere und gewählte Vorlage sowie Trainingsfortsetzung mit Pin-Kennzeichnung. Planumfang ersetzt die missverständliche Vermischung von Vorlagen und bereits geleistetem Volumen.

**Prüfung:** 5/5 Quellen und drei eigene Ansichten geprüft. Ganzkörper A: vier Übungen, zwölf geplante Sätze; abgeschlossene Kraftsession unverändert 3.300 kg, neun Sätze. Pinfläche 44×44.

### 115 · Previous recorded workout

**Beobachtet:** Drei Positionen zeigen Previous aus einer laufenden Kraftübung, den leeren Vergleich und letzte aufgezeichnete Sätze.

**OpenBand:** Lesender Vergleich für genau dieselbe Übungsvariante, mit gespeicherten Sätzen oder klarem Erstzustand. Kein automatisches Abschließen oder Verändern der laufenden Einheit.

**Prüfung:** 3/3 Quellen und zwei eigene Ansichten visuell geprüft. 3×8×40 = 960 kg. Zurückweg und laufender Timer als unveränderter Zustand dokumentiert; konkrete Einbindung folgt beim Flow Trainingsstart.

### 116 · Primary sleep

**Beobachtet:** Zehn Positionen zeigen Hauptschlaf aus Erholung, Dauer/Bettzeit/Qualitätskacheln, Phasen mit ausgewähltem Abschnitt, Einschlafdauer vorhanden/fehlend und umschaltbare Puls-/HRV-/Atem-/SpO₂-Verläufe.

**OpenBand:** Neun eigene Ansichten mit kompaktem Hauptschlaf, kontinuierlicher Vertiefung, proportioniertem Phasenverlauf, ausgewähltem Abschnitt, drei Messkurven, fehlendem SpO₂, fehlendem Einschlafbeginn und Erklärung. Schlafanteil und tägliche Einordnung ersetzen pauschale Qualitätsnoten.

**Prüfung:** 10/10 Quellen gesehen, neun eigene Ansichten visuell geprüft; Fortsetzung zusätzlich in 2×. Phasenfixture rechnerisch geprüft: 464 Minuten, 438 Schlaf, 26 wach, 94,4 %. HRV-Lücken 11/16, keine Verbindung über fehlende Fenster. Keine physiologische Validierung.

### 117 · Primary sleep (old)

**Beobachtet:** Zwei ausdrücklich alte Quellpositionen zeigen denselben Recovery-Einstieg und Hauptschlaf mit älterem Score-/Contributor-Layout und pauschaler REM-Bewertung.

**OpenBand:** Keine eigene Legacy-Ansicht. Die in Flow 116 gestaltete aktuelle Schlafstrecke deckt diesen Einstieg ab; persönliche Einordnung wird an belegte Vergleichswerte gebunden.

**Prüfung:** 2/2 alte Quellen gesehen und gegen die frisch geprüfte Hauptschlafstrecke abgeglichen. Keine neue veraltete Parallelversion erzeugt.

### 118 · Recovery

**Beobachtet:** Alle drei Positionen betrachtet: Score mit zwei Treibern, kurze Einordnung, Nacht und fortgesetzte Messwertkarten.

**OpenBand:** Kompakter ringbasierter Erholungsdetailweg; Baseline und Datenverfügbarkeit bleiben explizit. Ruhige deckende Flächen statt Landschaft hinter Text.

**Prüfung:** Drei bearbeitete Ansichten in Paper visuell geprüft, Hauptansicht und Verlauf zusätzlich 2×. 44px Zurück, editierbare 15-Werte-Kurven, keine erfundene Erholungshistorie.

### 119 · Reordering cards

**Beobachtet:** Vier Positionen: Bearbeitungsmodus, Drag, geänderte Reihenfolge und gespeicherter Feed.

**OpenBand:** Gemeinsamen bestehenden Editor gestrafft; klare Entwurfsgrenze, zugängliche Verschiebeaktionen und konkreter gespeicherter Feed.

**Prüfung:** Editor, Menü, geänderte Reihenfolge und neue Feedfortsetzung visuell bzw. im bestehenden Flow geprüft. Header ohne funktionsloses Infoziel; Standardbreite 393.

### 120 · Reordering data sources

**Beobachtet:** Alle sechs Positionen: Datenart, Quellliste, Reihenfolgeeditor, Drag, aktiviertes Speichern, gespeicherte Priorität.

**OpenBand:** Priorität je Datenart mit sichtbarem Entwurf und separatem Neuberechnungsstand. Herkunft und Abdeckung werden nicht mit Quellenreihenfolge verwechselt.

**Prüfung:** Drei neue 393×852 Zustände visuell geprüft; Quelle/Import/Committexte geprüft. Rohdaten bleiben erhalten, keine neu berechneten Beispielwerte erfunden.

### 121 · Reordering excercises

**Beobachtet:** Fünf Positionen: Vorlage, Liste, Drag, neue Reihenfolge, Rückkehr in Vorlage.

**OpenBand:** Zweistufiger Entwurf: Reihenfolge übernehmen, dann Vorlage speichern. Konkrete 4-Übungen-Variante statt allein generischem Drag-Muster.

**Prüfung:** Beide neue Zustände visuell geprüft; Satzsummen unverändert 12, 44-Punkt-Menüs, keine historische Sessionänderung.

### 122 · Replacing an exercise

**Beobachtet:** Fünf Positionen: Vorlage, Übungsmenü, Bibliothek, Auswahl und ersetzter Block.

**OpenBand:** Vier konkrete OpenBand-Zustände ergänzen Folgenprüfung für andere Lastkonvention. Keine stille Übernahme alter Last.

**Prüfung:** Vier Screens visuell geprüft; 3 Satzplätze und 12 geplante Gesamtsätze konsistent, Einzelwahl, Rückweg und Rückgängig vorhanden.

### 123 · Reporting an issue

**Beobachtet:** Sechs Positionen: Einstieg, Formular, Text, Fotoquelle, Anhang, Eingangsdialog.

**OpenBand:** Bericht mit expliziter Inhaltsprüfung, optionaler Diagnose und erhaltenem Entwurf. Support-Infrastruktur als neue Voraussetzung dokumentiert.

**Prüfung:** Vier konkrete 393×852 Zustände visuell geprüft; Empfangsreferenz synthetisch, kein tatsächlicher Versand. Anhangsauswahl wird beim Foto-Flow gemeinsam entwickelt.

### 124 · Resource article

**Beobachtet:** Zwei Positionen: Ressourcenkarten und ausführlicher Belastungsartikel.

**OpenBand:** Eigener kurzer Erklärscreen mit Illustration, Eingängen, Grenzen und Methodenlink. Kein Bevel-Artikeltext übernommen.

**Prüfung:** 18A5-0 visuell geprüft; Beschreibung mit aktueller strainScore-Implementierung abgeglichen. Keine klinische Wirksamkeitsbehauptung.

### 125 · Saving a workout template

**Beobachtet:** Drei Positionen: Speichern im Editor und gespeicherte Vorlagendetails in zwei Sheet-Höhen.

**OpenBand:** Eine vollständige lesbare Vorlagendetailseite, separate Startaktion und konkreter Speicherfehler mit erhaltenem Entwurf.

**Prüfung:** Gespeicherte Vorlage und Fehler visuell geprüft. Vier Übungen/zwölf Plansätze konsistent; keine Trainingseinheit durch Speichern behauptet.

### 126 · Scheduling keep status

**Beobachtet:** Vier Positionen: Daueroptionen, benutzerdefinierter Kalender, geändertes Datum, zurück zur Dauerwahl.

**OpenBand:** Eigener Endtag mit explizitem inklusive Tagesende, innerem Entwurf und gespeichertem Status. Bestehenden Zeitraumdialog integriert.

**Prüfung:** Kalender 2026 und gespeicherte Variante visuell geprüft; 15. September Dienstag, 23. Mittwoch, 44-Punkt-Datumstasten.

### 127 · Sending a feedback

**Beobachtet:** Fünf Positionen: negative Antwortreaktion, Gründe, Auswahl, Freitext, Empfangsbestätigung.

**OpenBand:** Rückmeldung je Nachricht mit knappen Gründen und prüfbarer Übertragung. Keine automatische Gesprächsweitergabe oder Lernbehauptung.

**Prüfung:** Drei neue Screens visuell geprüft, Antwortaktionen ergänzt. Sendefehler nutzt gemeinsamen erhaltenen Entwurf aus B124.

### 128 · Sending photos

**Beobachtet:** Fünf Positionen: Plusmenü, Fotoquelle, Anhänge, Text plus Fotos, gesendete Nachricht.

**OpenBand:** Sichtbarer Fotoentwurf mit Zielmodell, prüfbarem Senden, echter Bildfähigkeitsgrenze und weiterführender Mahlzeit als Entwurf.

**Prüfung:** Vier Zustände visuell geprüft; eigenes synthetisches Bild, keine automatisch gespeicherten Mengen/Kalorien, Empfänger im Prüfschritt sichtbar.

### 129 · Set default entries

**Beobachtet:** Drei Positionen: Journalmenü, Standardantworten, gespeicherte Ja/Nein-/Mengen-Vorgaben.

**OpenBand:** Automatisches tägliches Beantworten bewusst nicht übernommen. Eigene Alternative nutzt vorhandene Schnellmengen als Entwurf, Pin-Auswahl und ausdrückliches Speichern; Menütext präzisiert.

**Prüfung:** Aktualisiertes Journalmenü visuell geprüft. Bereits gestaltete Schnellmengen- und explizite Null-Eingabezustände wiederverwendet; keine automatische Beobachtung erzeugt.

### 130 · Setting a sleep alarm

**Beobachtet:** Alle acht Positionen betrachtet: Wecker, Zeitpicker, Typwahl, Smart-Alarm-Fenster und Haptik.

**OpenBand:** Fester WHOOP-Bandwecker mit Wochentagen und getrennter Gerätebestätigung; Smart-Alarm benötigt gesondert belegte Hardwarefähigkeit. Ausschaltfehler explizit sichtbar.

**Prüfung:** Fünf neue Zustände und bestehender Wecker visuell geprüft; Source für Plan/Bestätigung erneut gelesen. Kein physischer Wecker- oder Vibrationstest behauptet.

### 131 · Settings

**Beobachtet:** Vier Positionen: Einstieg, allgemeine Einstellungen, Daten/Ressourcen, rechtliche und Wartungsbereiche.

**OpenBand:** Aktuelle gegliederte Einstellungen mit Scrollfortsetzung, Daten-/Supportwegen, optionalen Diensten und Lizenzübersicht; alte Konto/Abo/Cloud-Bereiche entfallen.

**Prüfung:** Vier revidierte/neue Screens visuell geprüft, vorhandene Settings-Zeilen im Quellcode gegengeprüft. Versionsstand belegt; Rechts-/Betreiberinhalte bleiben Umsetzungsarbeit.

### 132 · Share an activity

**Beobachtet:** Zwei Positionen: Aktivitätsmenü und gestaltete Share-Vorschau.

**OpenBand:** Eigene ruhige Exportkarte mit wählbarem Puls/Route und nativer Zielwahl. Fehlerzustand bewahrt Auswahl.

**Prüfung:** Vorschau und Exportfehler visuell geprüft; 5 km/25 Min./5:00 konsistent. Kein tatsächlicher Exportversand oder Zustellbeleg behauptet.

### 133 · Shortcuts

**Beobachtet:** Zwei Positionen: Einstellungen und Schlafalarm-/Fokus-Kurzbefehl.

**OpenBand:** Kurzbefehle-Hub mit bestehenden Messwertabfragen und neuen sicheren Öffnungswegen. Routine verändert Wecker erst in dessen eigenem Flow.

**Prüfung:** Hub und revidierte Routine visuell geprüft, Swift-Intents gelesen. Fehlende deutsche Dialoge, Snapshot-Kontext und Alarmroute dokumentiert.

### 134 · Sleep

**Beobachtet:** Fünf Positionen: Home, Schlaf mit kurzer Einordnung, Abendplanung/Zeitachse, zwei Fortsetzungen mit Trends.

**OpenBand:** Aktuelle Schlafübersicht und Planung statt zweiter überladener Nachtdetailansicht. Bestehende Nacht bleibt tiefer erreichbar; alte Schlafinhalte ersetzt.

**Prüfung:** Drei überarbeitete Ansichten visuell geprüft. Acht tatsächlich vorhandene Schlafdauern, keine erfundenen Phasenverläufe; eigener Zukunftszielwert von beobachteter Nacht getrennt.

### 135 · Sleep needed calculated

**Beobachtet:** Zwei Positionen: Nachtbedarf und Zusammensetzung aus Ziel, Belastung und Schlafrückstand.

**OpenBand:** Bedarf verständlich zerlegt; persönliches Ziel, Forecast und Bettzeit getrennt. Fehlende persönliche Basis bleibt offen, reife Variante separat gekennzeichnet.

**Prüfung:** Drei Screens visuell geprüft, Abendplan vollständig bei2×. Reine Dart-Funktionen tatsächlich ausgeführt; 30805,714s Bedarf und21:59:33 Bettbeginn. Keine Pipeline-/physiologische Prüfung.

### 136 · Sleep score

**Beobachtet:** Drei Positionen: Schlafscore-Trendkarte, zeitlicher Verlauf, Verteilung und Trendanalyse.

**OpenBand:** Kein kopierter Pauschalscore. Eigener Schlafanteil mit eindeutigem Nenner, ehrlichem Ein-Wert-Verlauf und Erklärweg; Dauer bleibt Hauptsignal.

**Prüfung:** Neues Messwertdetail visuell geprüft. 438/464=94,3966%; vorhandene sleepPerformance zeitlich geprüft und Anschlussfehler dokumentiert.

### 137 · Starting a workout

**Beobachtet:** Alle 12 Positionen: Vorlage → Training → Satz/Pause → weitere Übungen → Ende → subjektive Anstrengung → Auswertung und Vorlagenänderung. Aktuelle Übung und Timer erhalten Priorität.

**OpenBand:** Einheitliche Live-Shell für vorhandene Trainingsarten; Satzabschluss und tatsächliches Volumen explizit; freiwillige Anstrengung; fehlender Puls separat. Recoverable Abschluss bei Speicherfehler, minimierte Rückkehr und Neustart statt Datenverlust. Veralteten C4F entfernt.

**Prüfung:** Quellpositionen 1–12 angesehen. Picker, Vorbereitung, 6 Live-Archetypen, Satz aktiv, Pause, Abschluss, gespeichert, Fehler und Wiederaufnahme in Paper angesehen. 3 × 8 × 40 = 960 kg; 11:40 Zeit konsistent. Editierbare Nodes und feste Steuerung. Endgültige Dark-/Großtextprüfung im Gesamtabgleich.

### 138 · Strain

**Beobachtet:** Alle 4 Positionen: kompakter Ring, Dauer/Energie, kurze Einordnung, Aktivitäten, Pulszonen und längere Trendliste unterhalb des ersten Viewports.

**OpenBand:** Kompakter Belastungsring mit eigener Skala 0–21, Schritte und Energiezustand; Minute-by-minute-Detail unabhängig vom gespeicherten Score. Durchgehende Scrollseite mit Zonen, Wochenzeit, Verlauf und verständlicher Berechnung.

**Prüfung:** 4 Quellpositionen und 3 Paper-Artboards visuell geprüft. Stale Detail-Tabs entfernt, 44-pt-Zurück und Aktionen, gleiche Morgen-/Wochenwerte; kontinuierlicher Inhalt hinter dem ersten Viewport. Hardware/physiologische Validierung nicht behauptet.

### 139 · Strain score

**Beobachtet:** 4 Positionen: historischer Chart mit Zeitraumwahl, persönlicher Spanne, Veränderungsvergleichen und erklärenden Ressourcen.

**OpenBand:** Frühe Daten und reife Historie ausdrücklich getrennt. Ein auswählbarer Tageswert, lesbare Skala, zurückhaltender Bereich und Wochenvergleich statt pauschaler Belastungsampel. Vorhandene eigene Erklärung wiederverwendet.

**Prüfung:** 4 Quellpositionen, 3 Paper-Screens geprüft; Achsenbeschriftung ergänzt. 30-Tage-Fixture und Quantile/Mittelwerte unabhängig per Python berechnet. Keine physiologische Validierung.

### 140 · Strength progression

**Beobachtet:** 2 Positionen: Kraftvolumen und einzelne Übungen führen zu einem längeren Progressionsdiagramm mit Filtern und Zeitraum.

**OpenBand:** Komplettes Volumen auf Übungen verteilt, danach gleichartige Arbeitssätze vergleichen. Vorhandene alte Bank-Historie durch kanonisch eine echte Fixture-Einheit ersetzt; separate reife Variante mit nachvollziehbaren vier Datenpunkten.

**Prüfung:** Beide Quellen und drei Paper-Ansichten angesehen. 3.300kg-Summe, Einzelvolumina, Chartdaten und Datumabstände geprüft. Keine Algorithmus-/App-Implementierung.

### 141 · Stress

**Beobachtet:** 4 Positionen: Stressheadline, aktueller Messkontext, Tageskurve mit Schlaf/Aktivität, Daueranteile und getrennte Trendtypen.

**OpenBand:** Eigene Stress-Semantik als körperliche Anspannung; Tag/Nacht und Journal getrennt. Früher Zustand und zusätzliche bereite Tagesvariante inklusive auswählbarer Lücke. Vorhandene HRV/Ruhepulswerte bleiben sichtbar, obwohl Stress offen ist.

**Prüfung:** 4 Referenzen und 5 Paper-Screens angesehen; Fensterenden, 30/40-Minuten-Abdeckung, Lücke und Ursprungszeiten geprüft. Modellanforderung ausdrücklich dokumentiert, kein Sensor- oder psychologischer Nachweis.

### 142 · Suggested drink intake

**Beobachtet:** 3 Quellpositionen zeigen Koffein-Eingabe und eine Hilfe mit Getränkearten/typischen mg; trotz Flowname keine Wasserzielberechnung.

**OpenBand:** Infoaktion führt zu einer portionsbezogenen Rechnung aus eigener Produktangabe. Ergebnis nur explizit in Entwurf übernehmen, kein automatischer Log und keine kopierten Tagesgrenzen.

**Prüfung:** 3 Quellen sowie Rechenhilfe und bestehender Entwurf visuell geprüft. 30mg/100ml ×300ml=90mg, unbekannter Kaffee bleibt separat. 44-pt-Zurück korrigiert; gespeicherter Folgepfad ausB95 wiederverwendet.

### 143 · Switching to dark mode

**Beobachtet:** 6 Positionen: Auswahl mit Vorschauen, getrennte Flächenhierarchie in Dark, gleiche Informationsdichte über Home/Journal/Fitness/Diagramme.

**OpenBand:** Ein durchgängiges Farbschema mit semantischen Dark-Farben; aktuelle Light-Inhalte bilden die Basis der erneuerten Dark-Varianten. Keine hellen Kartenreste, Kartencharts und Route angepasst. Schrift folgt iPhone, der Inhalt scrollt.

**Prüfung:** 6 Referenzen und 17 eigene Light/Dark/Large-Text-Ansichten kontrolliert, verbliebene Pastellchips/Gradienten/Route und Buttonkontrast korrigiert. Kontrastpaare berechnet,375×812 mit17/24 und Scrollfortsetzung geprüft. Abschließender Gesamtbestand-Abgleich bleibt ausdrücklich offen.

### 144 · Switching to list view

**Beobachtet:** 2 Positionen: Kontextmenü wechselt die Vorlagen von Kacheln in eine zeilenweise Liste mit Übungs-/Satzzahlen und Einzelaktionen.

**OpenBand:** Kompakte Liste als einziger Standard; vorhandene Pinverwaltung und Vorlagenaktionen wiederverwenden. Kein unnötiger Darstellungsschalter, geplante Sätze eindeutig beschriftet.

**Prüfung:** 2 Quellen angesehen. Neue Liste bei393×852 mit44-pt-Menü und Rückkehr geprüft; identische4Übungen/12Plansätze. Vorhandene Pin- und Aktionszustände verknüpft.

### 145 · Syncing to a watch

**Beobachtet:** 4 Positionen: Vorlagenmenü → Watch-Sync getrennt/verbunden → bestätigter letzter Synchronisierungszeitpunkt.

**OpenBand:** Kein vorgetäuschter WHOOP-Vorlagensync. Übernommen werden unabhängige Verbindung und bestätigte Aktualität, erweitert um lokale Speicherung, Abdeckung und Bereitschaft. Banddetail und alter Datenstand vollständig erneuert, laufend/unterbrochen/Platzmangel/abgeschlossen ausgearbeitet.

**Prüfung:** 4 Referenzen und7Paper-Artboards bei393×852 angesehen.464−24=440,440−26=414=6h54 geprüft. Neue09:38-Variante separat; keineMess-/Hardwarevalidierung behauptet. SourcecodeCommit-/ACK-Vertrag berücksichtigt.

### 146 · Target strain calibration

**Beobachtet:** 2 Positionen: Tagesbelastung führt zu einem erklärenden Kalibrierhinweis mit erwarteter Lernzeit.

**OpenBand:** Sichtbare persönliche Vergleichsbasis mit klarer Bereitschaft; heutige Belastung und Erholung bleiben nutzbar. Vorhandenes heuristisches Recovery-Ziel nicht als personalisierten Vergleich ausgeben, keine kopierte Wartefrist.

**Prüfung:** 2 Quellen und eigener frühe-Basis-Screen geprüft; bereite Vergleichsvariante ausB140 wiederverwendet. Aktuelle strainTarget-/crossday-Implementierung gelesen, Grenze der vorhandenen Berechnung dokumentiert.

### 147 · Time asleep

**Beobachtet:** 3 Positionen: Schlafdauer als eigener Trend mit Zeitraum, persönlichem Bereich, Wochenansicht und erklärenden Inhalten.

**OpenBand:** Bestehendes Dauerdetail komplett aktualisiert: 7-Nächte-Chart mit Bereich, Bettzeit/Wachzeit, nachvollziehbares Mittel und direkte Wege zur Nacht bzw. Korrektur. Eigenes Ziel und historischer Vergleich bleiben getrennt.

**Prüfung:** 3 Quellen sowie2aktualisierte/neue Screens angesehen.7×Dauer,401,2857MinMittel,464−26=438 und36Minüber402 abgeglichen. Primär-/Erkläraktion kompaktnebeneinander; vorhandenerNacht-/Korrekturpfad weiterverwendet.

### 148 · Unlinking a superset

**Beobachtet:** 4 Positionen: Supersatzmenü, Auswahl/Bearbeitung der Gruppe, Lösen und zurück zum unverknüpften Vorlagenentwurf.

**OpenBand:** Verbindung und Pausenänderung vor der Aktion verständlich machen. Getrennter Entwurf behält alle Satzdaten, bietet Rückgängig und wird erst mit Vorlage speichern dauerhaft.

**Prüfung:** Alle 4 Quellen und 2 neue Paper-Zustände angesehen; vier Übungen/zwölf Plansätze und beide Lasten erhalten. Rückgängig/Verwerfen/Speicherfehler sowie Abgrenzung zur Live-Einheit dokumentiert.

### 149 · VO2 Max ranges

**Beobachtet:** 2 Positionen: vorhandener VO₂max-Wert und eine farbige Referenztabelle mit Alters-/Geschlechtsbezug und Quellenname.

**OpenBand:** Quellen- und Methodenbezug übernehmen; keinen fremden Grenzwertkatalog kopieren. Fehlender Referenzbereich lässt Bewertung offen, nicht den vorhandenen Wert verschwinden.

**Prüfung:** Beide Quellen und eigener Erklärungsscreen geprüft. Keine normativen Zahlen erfunden; Herkunft, Einheit, Messdatum und Referenzversion für die Umsetzung festgehalten.

### 150 · VO2 max

**Beobachtet:** Biologieübersicht öffnet einen datierten VO₂max-Verlauf.

**OpenBand:** Keine Schätzung aus Ruhepuls. Eigene oder importierte Messwerte mit Herkunft und Datum; Normbewertung unabhängig. Ein einzelner Eintrag wird nicht zur Kurve.

**Prüfung:** Beide Quellen und alle vier neuen Zustände visuell geprüft; Einheit, Datum, fehlende Norm und Draft-Erhalt konsistent.

### 151 · Weight

**Beobachtet:** Drei Positionen: Körperwerte, Gewichtsverlauf mit Energieüberlagerung, Trendanalyse.

**OpenBand:** Glättung und datierte Herkunft übernehmen; Energieüberlagerung, Prognose und normative Gewichtsbewertung weglassen. Profilwert ist kein datierter Verlaufseintrag.

**Prüfung:** Alle drei Quellen und vier eigene Zustände angesehen. EWMA mit bestehender Formel nachgerechnet; eigene Fixture trennt Eingaben und geglättete Werte.

### 152 · Widgets

**Beobachtet:** Drei Positionen mit Tages-, Vital-, Ernährungs-, Wasser- und Energie-Widgets.

**OpenBand:** Datierte kompakte Widgets für vorhandene oder explizit geplante Werte. Keine erfundene Energy Bank. Eigener Akkuzeitstempel und sichere Rückkehr zur laufenden Einheit.

**Prüfung:** Alle drei Quellen, Einrichtungsscreen und neu aufgebautes Widgetboard geprüft. Vollständig/teilweise/fehlend/unterbrochen/älter sowie Datenschutzvariante dokumentiert.

### 153 · Workout templates

**Beobachtet:** Globale Erfassungsaktion führt zur Vorlagenliste und neuer Vorlage.

**OpenBand:** Ein gemeinsamer Einstieg mit selbst erstelltem, geführtem oder Fotoentwurf. Gespeicherte Vorlage, geplante Sätze und laufende Einheit bleiben getrennt.

**Prüfung:** Beide Quellen und eigene Einstiegs-/Listenansicht visuell geprüft; vorhandene Editor-, Review-, Save- und Trainingspfade zugeordnet. Globaler Screenabgleich: siehe Abschlussprotokoll und Inventar.
