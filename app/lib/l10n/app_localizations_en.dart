// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Easy Piano';

  @override
  String get logoLabel => 'Easy Piano logo';

  @override
  String get navLearn => 'Learn';

  @override
  String get navPractice => 'Practice';

  @override
  String get navProfile => 'Profile';

  @override
  String get sectionMore => 'More';

  @override
  String get kickerContinue => 'Continue';

  @override
  String get play => 'Play';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String moduleNumber(int number) {
    return 'Module $number';
  }

  @override
  String get kindSong => 'Song';

  @override
  String get kindBoss => 'Boss';

  @override
  String get kindChallenge => 'Challenge';

  @override
  String get kindStarGate => 'Star gate';

  @override
  String get kindLesson => 'Lesson';

  @override
  String taskCount(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString tasks',
      one: '1 task',
    );
    return '$_temp0';
  }

  @override
  String get practiceSubtitle => 'Train skills outside the course path.';

  @override
  String get freePlay => 'Free play';

  @override
  String get noteNames => 'C,C♯,D,D♯,E,F,F♯,G,G♯,A,A♯,B';

  @override
  String get freePlayHint =>
      'Play any key. Use a MIDI keyboard or tap the screen.';

  @override
  String get octaveDown => 'Lower octave';

  @override
  String get octaveUp => 'Higher octave';

  @override
  String get freePlayDesc =>
      'Play anything on your MIDI keyboard or the screen.';

  @override
  String get sightReading => 'Sight reading';

  @override
  String get sightReadingDesc => 'Read short random phrases at your level.';

  @override
  String get rhythmDrills => 'Rhythm drills';

  @override
  String get rhythmDrillsDesc => 'Tap the beat: quarters, halves, eighths.';

  @override
  String get songLibrary => 'Song library';

  @override
  String get songLibraryDesc => 'Practice any song you unlocked, at any tempo.';

  @override
  String get soon => 'Soon';

  @override
  String get statStars => 'Stars';

  @override
  String get statTasks => 'Tasks';

  @override
  String get statModules => 'Modules';

  @override
  String get profileSubtitle => 'Your progress on this device.';

  @override
  String get settings => 'Settings';

  @override
  String get developerTools => 'Developer tools';

  @override
  String get soundEffects => 'Sound effects';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Device default';

  @override
  String get midiNotFound =>
      'No MIDI keyboard found. Plug it in and try again.';

  @override
  String get midiUnavailable => 'Web MIDI is not available in this browser.';

  @override
  String get scenePending =>
      '(Animated scene arrives with the Phase 2 scene player.)';

  @override
  String get notAvailableYet => 'Not available yet.';

  @override
  String get continueButton => 'Continue';

  @override
  String get exit => 'Exit';

  @override
  String get playFollowingNotes => 'Play the following notes';

  @override
  String get resume => 'Resume';

  @override
  String get restart => 'Restart';

  @override
  String get exitToMap => 'Exit to map';

  @override
  String get pause => 'Pause';

  @override
  String get listenFirst => 'Listen first…';

  @override
  String playAlongTempo(int percent) {
    return 'Play along · $percent%';
  }

  @override
  String get skip => 'Skip';

  @override
  String get connectMidi => 'Connect MIDI';

  @override
  String get mutePianoSound => 'Mute piano sound';

  @override
  String get playPianoSound => 'Play piano sound';

  @override
  String get metronomeOff => 'Turn metronome off';

  @override
  String get metronomeOn => 'Turn metronome on';

  @override
  String get hideKeyboard => 'Hide keyboard';

  @override
  String get showKeyboard => 'Show keyboard';

  @override
  String get getReady => 'Get ready…';

  @override
  String passRulePlayAlong(int percent) {
    return 'Hit $percent% of the notes in each part to pass.';
  }

  @override
  String get passRuleOneNote => 'Play more than 80% of the notes.';

  @override
  String get passRuleWait =>
      'Play more than 80% of the notes before the hint appears.';

  @override
  String get trySlowerTempo => 'Try a slower tempo.';

  @override
  String get completed => 'Completed!';

  @override
  String get almostThere => 'Almost there!';

  @override
  String get statNotes => 'Notes';

  @override
  String get statTiming => 'Timing';

  @override
  String get statAssists => 'Assists';

  @override
  String get retry => 'Retry';

  @override
  String get next => 'Next';

  @override
  String get locked => 'Locked';

  @override
  String get middleCLabel => 'C';

  @override
  String gateProgress(int need, int have) {
    return 'Earn $need stars from any of these songs ($have/$need)';
  }

  @override
  String get practiceTune => 'Practice tune';

  @override
  String get generatedBadge => 'Generated';

  @override
  String get practiceLoading => 'Getting the tune maker ready…';

  @override
  String practiceDownload(int percent) {
    return 'Downloading $percent%';
  }

  @override
  String get practiceGenerating => 'Writing a tune for this lesson…';

  @override
  String get practiceAnother => 'Another one';

  @override
  String get practiceAgain => 'Play again';

  @override
  String get practiceFailed =>
      'Couldn\'t make a tune that fits this lesson. Try again.';

  @override
  String get practiceNotYet =>
      'Practice tunes only work in the browser for now.';

  @override
  String get practiceModelError =>
      'Couldn\'t load the tune maker. Check your connection and try again.';

  @override
  String practiceNotesHit(int hit, int total) {
    return '$hit of $total notes';
  }

  @override
  String get practiceNoStars =>
      'A new tune made for this lesson. Practice only: no stars.';

  @override
  String get practiceWait => 'Wait for me';

  @override
  String get practicePlayAlong => 'Play along';
}
