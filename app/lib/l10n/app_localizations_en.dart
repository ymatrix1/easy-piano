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
  String get early => 'Early';

  @override
  String get late => 'Late';

  @override
  String get slowPractice => 'Slow practice';

  @override
  String get slowPracticeIntro => 'Let\'s practise this part slower';

  @override
  String get sectionTryAgain => 'Try this part again';

  @override
  String get sectionFullSpeed => 'Now at full speed!';

  @override
  String get micInput => 'Microphone';

  @override
  String get micUseMidi => 'Use MIDI / screen keys';

  @override
  String get micExplainTitle => 'Play with the microphone';

  @override
  String get micExplainBody =>
      'Easy Piano listens to your piano through the microphone so you can play without a cable. Audio is analysed on this device and never recorded or sent. The app\'s own piano sound is muted while listening.';

  @override
  String get micAllow => 'Allow microphone';

  @override
  String get cancel => 'Cancel';

  @override
  String get micDenied =>
      'Microphone access was blocked. Allow it in the browser\'s site settings and try again.';

  @override
  String get micUnavailable =>
      'Microphone input is not available in this browser.';

  @override
  String get micCalibrate => 'Calibrate';

  @override
  String get micCalibrateTitle => 'Calibrate the microphone';

  @override
  String get micCalibrateBody => 'Play any key each time the circle lights up.';

  @override
  String get micCalibrateRetry =>
      'I didn\'t hear enough notes. Try again a little louder.';

  @override
  String micCalibrateDone(int ms) {
    return 'Done: $ms ms delay';
  }

  @override
  String get micListening => 'Listening';

  @override
  String get micDefaultDevice => 'Default microphone';

  @override
  String micHeard(String note) {
    return 'Heard: $note';
  }

  @override
  String get micTestHint =>
      'Play a key: the bar moves and the note shows here.';

  @override
  String get micTurnOff => 'Turn off';

  @override
  String get micNoteNames => 'C,C♯,D,D♯,E,F,F♯,G,G♯,A,A♯,B';

  @override
  String get micNotFound =>
      'No microphone found. Plug one in or pick another input.';

  @override
  String get micBusy =>
      'The microphone is in use by another app. Close it and try again.';

  @override
  String get midiUnavailableApp =>
      'MIDI input is not available on this device.';

  @override
  String get micUnavailableApp =>
      'Microphone input is not available on this device.';

  @override
  String get micDeniedApp =>
      'Microphone access was blocked. Allow it in the app\'s system settings and try again.';

  @override
  String get micQuietTip =>
      'Best in a quiet room: talking, typing or music nearby can be heard as notes.';
}
