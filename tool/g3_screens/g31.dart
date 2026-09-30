// G3.1 boards use the same synthetic states as their G3 screen counterparts.
import 'env.dart';
import 'heute.dart';
import 'journal.dart';
import 'schlaf.dart';
import 'training.dart';
import 'verlauf.dart';

final Map<String, G3ScreenBuilder> g31Screens = {
  'g31-heute-hell': g31HeuteBuilder,
  'g31-heute-dunkel': g31HeuteBuilder,
  'g31-schlaf-hell': g31SleepBuilder('schlaf-letzte-nacht-hell'),
  'g31-schlaf-dunkel': g31SleepBuilder('schlaf-letzte-nacht-dunkel'),
  'g31-training-hell': g31TrainingBuilder('training-wurzel-hell'),
  'g31-training-dunkel': g31TrainingBuilder('training-wurzel-dunkel'),
  'g31-journal-hell': g31JournalBuilder('G3JournalTabLight'),
  'g31-journal-dunkel': g31JournalBuilder('G3JournalTabDark'),
  'g31-verlauf-erholung-30-tage-hell': g31RecoveryBuilder,
  'g31-verlauf-erholung-30-tage-dunkel': g31RecoveryBuilder,
  'g31-verlauf-hrv-hell': verlaufScreens['verlauf-hrv-hell']!,
  'g31-verlauf-hrv-dunkel': verlaufScreens['verlauf-hrv-hell']!,
  'g31-schlaf-nachtverlauf-hell': g31SleepBuilder(
    'schlaf-nachtverlauf-puls-hell',
  ),
  'g31-schlaf-nachtverlauf-dunkel': g31SleepBuilder(
    'schlaf-nachtverlauf-puls-dunkel',
  ),
  'g31-training-lauf-ergebnis-hell': g31TrainingBuilder(
    'training-lauf-ergebnis-hell',
  ),
  'g31-training-lauf-ergebnis-dunkel': g31TrainingBuilder(
    'training-lauf-ergebnis-dunkel',
  ),
  'g31-training-belastung-hell': g31TrainingBuilder(
    'training-belastung-30-tage-hell',
  ),
  'g31-training-belastung-dunkel': g31TrainingBuilder(
    'training-belastung-30-tage-dunkel',
  ),
};
