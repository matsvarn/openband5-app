// GENERATED from docs/openband5/design/tokens.json
// (Paper file 01M2TRX5GZKAXKTSXK7D34E8AY, hash a96ee6a1).
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

  /// G2 Gerät: Tiefschlaf, volle LED.
  static const Color stageDeep = Color(0xFF1B1B1A);

  /// G2 Gerät: Leichtschlaf.
  static const Color stageLight = Color(0xFF6A6A66);

  /// G2 Gerät: REM.
  static const Color stageRem = Color(0xFFAEAEA9);

  /// G2 Gerät: Wach.
  static const Color wake = Color(0xFFC9C9C4);

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

  /// G2 Gerät dunkel: Wach.
  static const Color darkWake = Color(0xFF4A4A45);

  /// G2 Gerät dunkel: Tiefschlaf.
  static const Color darkStageDeep = Color(0xFFEDEDE9);

  /// G2 Gerät dunkel: Leichtschlaf.
  static const Color darkStageLight = Color(0xFF9A9A94);

  /// G2 Gerät dunkel: REM.
  static const Color darkStageRem = Color(0xFF5E5E59);

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

  /// G2 Gerät: Signal-Orange.
  static const Color signal = Color(0xFFFF5A1A);

  /// G2 Gerät dunkel: eingedrückte Fläche.
  static const Color darkInset = Color(0xFF0B0B0A);

  /// G2 Gerät dunkel: Status-LED.
  static const Color darkLed = Color(0xFF3DDC5A);

  /// G2 Gerät dunkel: Signal-Orange.
  static const Color darkSignal = Color(0xFFFF6A2E);
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
}

abstract final class AlpFont {
  static const String sans = 'Inter';
  static const String display = 'Inter Tight';
}
