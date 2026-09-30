// GENERATED from docs/openband5/design/tokens.json
// (Paper file 01M2TRX5GZKAXKTSXK7D34E8AY, hash 7aa43eab).
// Do not edit; run tool/gen_alp_tokens.py.
import 'dart:ui';

abstract final class AlpColor {
  /// G2 Gerät: Gehäuse. Erhabene Panels und Tasten.
  static const Color canvas = Color(0xFFF5F5F2);

  /// G2 Gerät: Mulde im Panel. Datenbilder und Skalenspur.
  static const Color well = Color(0xFFEAEAE6);

  /// G2 Gerät: Trennlinie im Panel.
  static const Color line = Color(0xFFE3E3DF);

  /// G2 Gerät: Tinte. Text, Zeiger, Primärtaste.
  static const Color ink = Color(0xFF1B1B1A);

  /// G2 Gerät: Beschriftung. Paper's label grey on Gehäuse and Mulde.
  static const Color muted = Color(0xFF6A6A66);

  /// G2 Gerät: Aktion ist Tinte; Handlungen sind Tasten, nicht Farbe.
  static const Color action = Color(0xFF1B1B1A);

  /// G2 Gerät: Schlaf-Füllung.
  static const Color sleep = Color(0xFF1B1B1A);

  /// G2 Gerät: Schlaf-Spur.
  static const Color sleepTint = Color(0xFFE3E3DF);

  /// G3.1 Schlaf: Hypnogramm-Rampe.
  static const Color stageDeep = Color(0xFF3B2E8C);

  /// G3.1 Schlaf: Hypnogramm-Rampe.
  static const Color stageLight = Color(0xFF8474D6);

  /// G3.1 Schlaf: Hypnogramm-Rampe.
  static const Color stageRem = Color(0xFFB7ACEB);

  /// G3.1 Schlaf: Hypnogramm-Rampe.
  static const Color wake = Color(0xFFDAD5F2);

  /// G2 Gerät: Signal-Orange. Nur Erholung.
  static const Color recovery = Color(0xFFFF5A1A);

  /// G2 Gerät: Signal-Spur.
  static const Color recoveryTint = Color(0xFFFBE3D8);

  /// G2 Gerät: Belastung-Füllung.
  static const Color strain = Color(0xFF33332F);

  /// G2 Gerät: Belastung-Spur.
  static const Color strainTint = Color(0xFFE3E3DF);

  /// G2 Gerät: Puls-Linie.
  static const Color pulse = Color(0xFF262624);

  /// G2 Gerät: Puls-Spur.
  static const Color pulseTint = Color(0xFFE3E3DF);

  /// G2 Gerät: Schlaf für kleinen Text.
  static const Color sleepText = Color(0xFF1B1B1A);

  /// G2 Gerät: Signal für kleinen Text, AA auf Gehäuse.
  static const Color recoveryText = Color(0xFFB8400C);

  /// G2 Gerät: Belastung für kleinen Text.
  static const Color strainText = Color(0xFF33332F);

  /// G2 Gerät: Puls für kleinen Text.
  static const Color pulseText = Color(0xFF262624);

  /// G2 Gerät: Ernährung für kleinen Text.
  static const Color foodText = Color(0xFF55554F);

  /// G2 Gerät dunkel: Seite (Alpin-Name: dunkler Seitenhintergrund).
  static const Color darkCanvas = Color(0xFF121211);

  /// G2 Gerät dunkel: Gehäuse (Karte).
  static const Color darkCard = Color(0xFF1F1F1D);

  /// G2 Gerät dunkel: Mulde.
  static const Color darkWell = Color(0xFF161615);

  /// G2 Gerät dunkel: Trennlinie.
  static const Color darkLine = Color(0xFF2E2E2B);

  /// G2 Gerät dunkel: Tinte.
  static const Color darkInk = Color(0xFFEDEDE9);

  /// G2 Gerät dunkel: Beschriftung.
  static const Color darkMuted = Color(0xFFA3A39D);

  /// G2 Gerät dunkel: Aktion.
  static const Color darkAction = Color(0xFFEDEDE9);

  /// G2 Gerät dunkel: Schlaf.
  static const Color darkSleep = Color(0xFFEDEDE9);

  /// G2 Gerät dunkel: Schlaf-Spur.
  static const Color darkSleepTint = Color(0xFF2E2E2B);

  /// G2 Gerät dunkel: Signal-Orange.
  static const Color darkRecovery = Color(0xFFFF6A2E);

  /// G2 Gerät dunkel: Signal-Spur.
  static const Color darkRecoveryTint = Color(0xFF3A2217);

  /// G2 Gerät dunkel: Belastung.
  static const Color darkStrain = Color(0xFFD6D6D1);

  /// G2 Gerät dunkel: Belastung-Spur.
  static const Color darkStrainTint = Color(0xFF2E2E2B);

  /// G2 Gerät dunkel: Puls.
  static const Color darkPulse = Color(0xFFE4E4DF);

  /// G2 Gerät dunkel: Puls-Spur.
  static const Color darkPulseTint = Color(0xFF2E2E2B);

  /// G3.1 Schlaf: Hypnogramm-Rampe.
  static const Color darkWake = Color(0xFF3A3558);

  /// G3.1 Schlaf: Hypnogramm-Rampe.
  static const Color darkStageDeep = Color(0xFFC9C0FA);

  /// G3.1 Schlaf: Hypnogramm-Rampe.
  static const Color darkStageLight = Color(0xFF8A7BD9);

  /// G3.1 Schlaf: Hypnogramm-Rampe.
  static const Color darkStageRem = Color(0xFF584C9C);

  /// G2 Gerät: Warntext.
  static const Color warning = Color(0xFF7A4F00);

  /// G2 Gerät: Warnfläche.
  static const Color warningTint = Color(0xFFEFE3C6);

  /// G2 Gerät: Fehlertext und destruktive Aktion.
  static const Color danger = Color(0xFFB3261E);

  /// G2 Gerät: Fehlerfläche.
  static const Color dangerTint = Color(0xFFF2D9D5);

  /// G2 Gerät: Ernährung.
  static const Color food = Color(0xFF6A6A66);

  /// G2 Gerät: Ernährung-Spur.
  static const Color foodTint = Color(0xFFE3E3DF);

  /// G2 Gerät: hohl und gestrichelt, keine Daten, Chevrons.
  static const Color gap = Color(0xFFAEAEA9);

  /// G2 Gerät dunkel: Ernährung.
  static const Color darkFood = Color(0xFFA3A39D);

  /// G2 Gerät dunkel: Ernährung-Spur.
  static const Color darkFoodTint = Color(0xFF2E2E2B);

  /// G2 Gerät dunkel: hohl, keine Daten, Chevrons.
  static const Color darkGap = Color(0xFF4A4A45);

  /// G2 Gerät dunkel: Warntext.
  static const Color darkWarning = Color(0xFFF2C36B);

  /// G2 Gerät dunkel: Warnfläche.
  static const Color darkWarningTint = Color(0xFF3A2F17);

  /// G2 Gerät dunkel: Fehlertext.
  static const Color darkDanger = Color(0xFFFF7A6E);

  /// G2 Gerät dunkel: Fehlerfläche.
  static const Color darkDangerTint = Color(0xFF3E1F1C);

  /// G2 Gerät: Seite hinter den Panels.
  static const Color page = Color(0xFFE3E3DF);

  /// G2 Gerät: eingedrückte Fläche auf der Seite (verweigerte Werte, Hinweise).
  static const Color inset = Color(0xFFD8D8D3);

  /// G2 Gerät: Status-LED, verbunden.
  static const Color led = Color(0xFF2FB344);

  /// Verdict: outside your normal range on the good side. Delta text (4.8:1 on card).
  static const Color better = Color(0xFF1E7D34);

  /// Verdict: today's marker (knob, newest bar) on the good side.
  static const Color betterMark = Color(0xFF2FB344);

  /// Verdict: outside your normal range on the bad side. Delta text (4.8:1 on card).
  static const Color worse = Color(0xFFA15C00);

  /// Verdict: today's marker on the bad side.
  static const Color worseMark = Color(0xFFE39A2D);

  /// Dark: verdict good side, text and marker.
  static const Color darkBetter = Color(0xFF3DDC5A);

  /// Dark: verdict bad side, text and marker.
  static const Color darkWorse = Color(0xFFF0A43A);

  /// G2 Gerät: Signal-Orange.
  static const Color signal = Color(0xFFFF5A1A);

  /// G2 Gerät dunkel: eingedrückte Fläche.
  static const Color darkInset = Color(0xFF0B0B0A);

  /// G2 Gerät dunkel: Status-LED.
  static const Color darkLed = Color(0xFF3DDC5A);

  /// G2 Gerät dunkel: Signal-Orange.
  static const Color darkSignal = Color(0xFFFF6A2E);

  /// G3 Tagesblatt: G3: zweite Tintenstufe für Fließtext und Meta.
  static const Color ink2 = Color(0xFF3D3D3A);

  /// G3 Tagesblatt: G3: persönlicher Normalbereich auf Skalen.
  static const Color band = Color(0xFFC4C4BE);

  /// G3 Tagesblatt: G3: Skalenspur, in die Karte gedrückt.
  static const Color track = Color(0xFFE3E3DF);

  /// G3 Tagesblatt: G3: neutrale Chip-Fläche (Delta, Tag).
  static const Color chip = Color(0xFFE3E3DF);

  /// G3 Tagesblatt: G3: Haarlinie auf der Seite (Grundlinie, Kopf).
  static const Color hairline = Color(0xFFD2D2CC);

  /// G3 Tagesblatt: G3: Säule für vergangene Tage.
  static const Color bar = Color(0xFFB4B4AE);

  /// G3 Tagesblatt: G3: besser, Chip-Fläche.
  static const Color betterTint = Color(0xFFDCEBD9);

  /// G3 Tagesblatt: G3: schlechter, Chip-Fläche.
  static const Color worseTint = Color(0xFFF3E4CB);

  /// G3 Tagesblatt: G3: Fläche der Für-heute-Notiz, einzige gefüllte Fläche.
  static const Color note = Color(0xFF1B1B1A);

  /// G3 Tagesblatt: G3: Handlungszeile in der Notiz.
  static const Color noteInset = Color(0xFF0B0B0A);

  /// G3 Tagesblatt: G3: Text auf der Notiz.
  static const Color noteInk = Color(0xFFF5F5F2);

  /// G3 Tagesblatt: G3: Begründung auf der Notiz.
  static const Color noteInk2 = Color(0xFFCFCFCA);

  /// G3 Tagesblatt: G3: Beschriftung auf der Notiz.
  static const Color noteMuted = Color(0xFFA3A39D);

  /// G3 Tagesblatt: G3: Taste auf der Notiz.
  static const Color noteAction = Color(0xFFF5F5F2);

  /// G3.1 Bereichsfarbe (domain-recovery).
  static const Color domainRecovery = Color(0xFF1B6294);

  /// G3.1 Bereichsfarbe (domain-recovery-bar).
  static const Color domainRecoveryBar = Color(0xFFA9C6DE);

  /// G3.1 Bereichsfarbe (domain-recovery-tint).
  static const Color domainRecoveryTint = Color(0xFFD9E7F2);

  /// G3.1 Bereichsfarbe (domain-sleep).
  static const Color domainSleep = Color(0xFF5F48C5);

  /// G3.1 Bereichsfarbe (domain-sleep-bar).
  static const Color domainSleepBar = Color(0xFFC3B9EE);

  /// G3.1 Bereichsfarbe (domain-sleep-tint).
  static const Color domainSleepTint = Color(0xFFE4E0F6);

  /// G3.1 Bereichsfarbe (domain-load).
  static const Color domainLoad = Color(0xFF9D376A);

  /// G3.1 Bereichsfarbe (domain-load-bar).
  static const Color domainLoadBar = Color(0xFFE3B3CB);

  /// G3.1 Bereichsfarbe (domain-load-tint).
  static const Color domainLoadTint = Color(0xFFF3DDE8);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color zone1 = Color(0xFFE8C3D5);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color zone2 = Color(0xFFD99BBB);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color zone3 = Color(0xFFC8729C);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color zone4 = Color(0xFF9D376A);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color zone5 = Color(0xFF6B1E45);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color zoneTint1 = Color(0xFFF3EEEE);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color zoneTint2 = Color(0xFFF1E7E9);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color zoneTint3 = Color(0xFFECDCE2);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color zoneTint4 = Color(0xFFE2CBD4);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color zoneTint5 = Color(0xFFD2BFC7);

  /// G3.1 Schlaf: Hypnogramm-Rampe.
  static const Color hypnoLane = Color(0xFFF0EEF8);

  /// G3 Tagesblatt: G3 dunkel: zweite Tintenstufe für Fließtext und Meta.
  static const Color darkInk2 = Color(0xFFCFCFCA);

  /// G3 Tagesblatt: G3 dunkel: persönlicher Normalbereich auf Skalen.
  static const Color darkBand = Color(0xFF4A4A45);

  /// G3 Tagesblatt: G3 dunkel: Skalenspur, in die Karte gedrückt.
  static const Color darkTrack = Color(0xFF121211);

  /// G3 Tagesblatt: G3 dunkel: neutrale Chip-Fläche (Delta, Tag).
  static const Color darkChip = Color(0xFF2E2E2B);

  /// G3 Tagesblatt: G3 dunkel: Haarlinie auf der Seite (Grundlinie, Kopf).
  static const Color darkHairline = Color(0xFF2E2E2B);

  /// G3 Tagesblatt: G3 dunkel: Säule für vergangene Tage.
  static const Color darkBar = Color(0xFF55554F);

  /// G3 Tagesblatt: G3 dunkel: besser als dein Normalbereich (Marke).
  static const Color darkBetterMark = Color(0xFF45C865);

  /// G3 Tagesblatt: G3 dunkel: besser, kleiner Text.
  static const Color darkBetterText = Color(0xFF6BD983);

  /// G3 Tagesblatt: G3 dunkel: besser, Chip-Fläche.
  static const Color darkBetterTint = Color(0xFF1C3322);

  /// G3 Tagesblatt: G3 dunkel: schlechter als dein Normalbereich (Marke).
  static const Color darkWorseMark = Color(0xFFF0A640);

  /// G3 Tagesblatt: G3 dunkel: schlechter, kleiner Text.
  static const Color darkWorseText = Color(0xFFF2B35E);

  /// G3 Tagesblatt: G3 dunkel: schlechter, Chip-Fläche.
  static const Color darkWorseTint = Color(0xFF3A2C17);

  /// G3 Tagesblatt: G3 dunkel: Fläche der Für-heute-Notiz, einzige gefüllte Fläche.
  static const Color darkNote = Color(0xFF2A2A27);

  /// G3 Tagesblatt: G3 dunkel: Handlungszeile in der Notiz.
  static const Color darkNoteInset = Color(0xFF161615);

  /// G3 Tagesblatt: G3 dunkel: Text auf der Notiz.
  static const Color darkNoteInk = Color(0xFFF5F5F2);

  /// G3 Tagesblatt: G3 dunkel: Begründung auf der Notiz.
  static const Color darkNoteInk2 = Color(0xFFCFCFCA);

  /// G3 Tagesblatt: G3 dunkel: Beschriftung auf der Notiz.
  static const Color darkNoteMuted = Color(0xFFA3A39D);

  /// G3 Tagesblatt: G3 dunkel: Taste auf der Notiz.
  static const Color darkNoteAction = Color(0xFFEDEDE9);

  /// G3.1 dunkel: Bereichsfarbe (domain-recovery).
  static const Color darkDomainRecovery = Color(0xFF6FB6E6);

  /// G3.1 dunkel: Bereichsfarbe (domain-recovery-bar).
  static const Color darkDomainRecoveryBar = Color(0xFF35566E);

  /// G3.1 dunkel: Bereichsfarbe (domain-recovery-tint).
  static const Color darkDomainRecoveryTint = Color(0xFF1B2B38);

  /// G3.1 dunkel: Bereichsfarbe (domain-sleep).
  static const Color darkDomainSleep = Color(0xFFA898F0);

  /// G3.1 dunkel: Bereichsfarbe (domain-sleep-bar).
  static const Color darkDomainSleepBar = Color(0xFF463C80);

  /// G3.1 dunkel: Bereichsfarbe (domain-sleep-tint).
  static const Color darkDomainSleepTint = Color(0xFF28233F);

  /// G3.1 dunkel: Bereichsfarbe (domain-load).
  static const Color darkDomainLoad = Color(0xFFE58AB7);

  /// G3.1 dunkel: Bereichsfarbe (domain-load-bar).
  static const Color darkDomainLoadBar = Color(0xFF6A3452);

  /// G3.1 dunkel: Bereichsfarbe (domain-load-tint).
  static const Color darkDomainLoadTint = Color(0xFF3A2130);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color darkZone1 = Color(0xFF4E2A3F);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color darkZone2 = Color(0xFF733A5A);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color darkZone3 = Color(0xFF9E5380);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color darkZone4 = Color(0xFFC86A9B);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color darkZone5 = Color(0xFFE58AB7);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color darkZoneTint1 = Color(0xFF262122);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color darkZoneTint2 = Color(0xFF2E2428);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color darkZoneTint3 = Color(0xFF3A2A32);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color darkZoneTint4 = Color(0xFF48313B);

  /// G3.1 Belastung: Zone oder Pulsdiagramm-Band.
  static const Color darkZoneTint5 = Color(0xFF543C47);

  /// G3.1 Schlaf: Hypnogramm-Rampe.
  static const Color darkHypnoLane = Color(0xFF232130);
}

abstract final class AlpText {
  static const double micro = 12;
  static const double label = 13;
  static const double body = 14;
  static const double cardTitle = 17;
  static const double section = 20;
  static const double ring = 26;
  static const double title = 30;
  static const double value = 34;
  static const double gauge = 60;
  static const double hero = 64;

  /// G3 Tagesblatt: note-title
  static const double noteTitle = 21;

  /// G3 Tagesblatt: metric
  static const double metric = 36;

  /// G3 Tagesblatt: figure
  static const double figure = 44;

  /// G3 Tagesblatt: lead
  static const double lead = 92;
}

abstract final class AlpSpace {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;

  /// Karteninnenraum · 14 pt
  static const double s14 = 14;
}

abstract final class AlpRadius {
  static const double well = 12;
  static const double row = 14;
  static const double card = 18;
  static const double pill = 60;

  /// G3 Tagesblatt: hero
  static const double hero = 22;

  /// G3 Tagesblatt: tabbar
  static const double tabbar = 32;
}

abstract final class AlpLeading {
  /// G3 Tagesblatt: lead
  static const double lead = 84;
}

abstract final class AlpTracking {
  /// G3 Tagesblatt: lead
  static const double lead = -0.045;
}

abstract final class AlpFont {
  static const String sans = 'Inter';
  static const String display = 'Inter Tight';
}
