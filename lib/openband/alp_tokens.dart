// GENERATED from docs/openband5/design/tokens.json
// (Paper file 01M2TRX5GZKAXKTSXK7D34E8AY, hash 908ca522).
// Do not edit; run tool/gen_alp_tokens.py.
import 'dart:ui';

abstract final class AlpColor {
  /// Alpin: Schnee. Seitenhintergrund.
  static const Color canvas = Color(0xFFFFFFFF);
  /// Alpin: Schneeschatten. Vertiefte Innenfläche für Datenbilder.
  static const Color well = Color(0xFFF3F6FA);
  /// Alpin: Trennlinie.
  static const Color line = Color(0xFFE3E8F0);
  /// Alpin: Granit. Haupttext.
  static const Color ink = Color(0xFF131B2E);
  /// Alpin: Schiefer. Sekundärtext.
  static const Color muted = Color(0xFF5C6880);
  /// Alpin: Aktion.
  static const Color action = Color(0xFF2B5FE0);
  /// Alpin: Gletscher. Schlaf-Bogen und Werte.
  static const Color sleep = Color(0xFF3B6FE8);
  /// Alpin: Gletscher hell. Schlaf-Spur und Flächen.
  static const Color sleepTint = Color(0xFFE4ECFD);
  /// Alpin: Nachteis. Tiefschlaf.
  static const Color stageDeep = Color(0xFF1E3F9E);
  /// Alpin: Gletscher. Leichter Schlaf.
  static const Color stageLight = Color(0xFF5A8AF0);
  /// Alpin: Firn. REM.
  static const Color stageRem = Color(0xFF9DBCFF);
  /// Alpin: Morgenlicht. Wach und Lücken-Marker.
  static const Color wake = Color(0xFFF5B13B);
  /// Alpin: Tanne. Erholung.
  static const Color recovery = Color(0xFF1E9E63);
  /// Alpin: Tanne hell.
  static const Color recoveryTint = Color(0xFFE1F5EA);
  /// Alpin: Alpenglühen. Belastung.
  static const Color strain = Color(0xFFF08A24);
  /// Alpin: Alpenglühen hell.
  static const Color strainTint = Color(0xFFFDEEDD);
  /// Alpin: Alpenrose. Puls.
  static const Color pulse = Color(0xFFE0457B);
  /// Alpin: Alpenrose hell.
  static const Color pulseTint = Color(0xFFFCE6EE);
  /// Alpin dunkel: Nachthimmel. Seitenhintergrund.
  static const Color darkCanvas = Color(0xFF0F1420);
  /// Alpin dunkel: Karte.
  static const Color darkCard = Color(0xFF181F2E);
  /// Alpin dunkel: vertiefte Innenfläche.
  static const Color darkWell = Color(0xFF111828);
  /// Alpin dunkel: Trennlinie.
  static const Color darkLine = Color(0xFF2A3447);
  /// Alpin dunkel: Haupttext.
  static const Color darkInk = Color(0xFFF2F5FA);
  /// Alpin dunkel: Sekundärtext.
  static const Color darkMuted = Color(0xFFA3AEC2);
  /// Alpin dunkel: Aktion.
  static const Color darkAction = Color(0xFF8FB0FF);
  /// Alpin dunkel: Gletscher, Schlaf-Bogen.
  static const Color darkSleep = Color(0xFF7FA3FF);
  /// Alpin dunkel: Schlaf-Spur.
  static const Color darkSleepTint = Color(0xFF1E2C4F);
  /// Alpin dunkel: Tanne, Erholung.
  static const Color darkRecovery = Color(0xFF4CC98A);
  /// Alpin dunkel: Erholung-Spur.
  static const Color darkRecoveryTint = Color(0xFF173628);
  /// Alpin dunkel: Alpenglühen, Belastung.
  static const Color darkStrain = Color(0xFFFFA24D);
  /// Alpin dunkel: Belastung-Spur.
  static const Color darkStrainTint = Color(0xFF3A2A18);
  /// Alpin dunkel: Alpenrose, Puls.
  static const Color darkPulse = Color(0xFFFF6F9C);
  /// Alpin dunkel: Puls-Spur.
  static const Color darkPulseTint = Color(0xFF3B1F2C);
  /// Alpin dunkel: Wach und Lücken-Marker.
  static const Color darkWake = Color(0xFFFFC65C);
  /// Alpin dunkel: Tiefschlaf.
  static const Color darkStageDeep = Color(0xFF3D63D9);
  /// Alpin dunkel: Leichtschlaf.
  static const Color darkStageLight = Color(0xFF7FA3FF);
  /// Alpin dunkel: REM.
  static const Color darkStageRem = Color(0xFFBFD2FF);
  /// Alpin: Warntext auf Warnfläche.
  static const Color warning = Color(0xFF8A5A00);
  /// Alpin: Warnfläche.
  static const Color warningTint = Color(0xFFFFF1D6);
  /// Alpin: Fehlertext und destruktive Aktion.
  static const Color danger = Color(0xFFC42B3D);
  /// Alpin: Fehlerfläche.
  static const Color dangerTint = Color(0xFFFDE7EA);
  /// Alpin: Enzian. Ernährung / Fett.
  static const Color food = Color(0xFF7A5AD9);
  /// Alpin: Enzian hell.
  static const Color foodTint = Color(0xFFEEE9FB);
  /// Alpin: gestrichelte Lücke, keine Daten.
  static const Color gap = Color(0xFFC9D2E0);
  /// Alpin dunkel: Enzian, Ernährung / Fett.
  static const Color darkFood = Color(0xFFB6A0F2);
  /// Alpin dunkel: Ernährung-Spur.
  static const Color darkFoodTint = Color(0xFF2B2442);
  /// Alpin dunkel: gestrichelte Lücke, keine Daten, Chevrons.
  static const Color darkGap = Color(0xFF3C475C);
  /// Alpin dunkel: Warntext.
  static const Color darkWarning = Color(0xFFF2C36B);
  /// Alpin dunkel: Warnfläche.
  static const Color darkWarningTint = Color(0xFF3A2F17);
  /// Alpin dunkel: Fehlertext.
  static const Color darkDanger = Color(0xFFFF7A88);
  /// Alpin dunkel: Fehlerfläche.
  static const Color darkDangerTint = Color(0xFF3E1F26);
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
  static const double well = 14;
  static const double row = 18;
  static const double card = 24;
  static const double pill = 60;
}

abstract final class AlpFont {
  static const String sans = 'Inter';
  static const String display = 'Inter Tight';
}
