import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('pt'),
    Locale('pt', 'BR'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Easy Piano'**
  String get appTitle;

  /// No description provided for @logoLabel.
  ///
  /// In en, this message translates to:
  /// **'Easy Piano logo'**
  String get logoLabel;

  /// No description provided for @navLearn.
  ///
  /// In en, this message translates to:
  /// **'Learn'**
  String get navLearn;

  /// No description provided for @navPractice.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get navPractice;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @sectionMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get sectionMore;

  /// No description provided for @kickerContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get kickerContinue;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @moduleNumber.
  ///
  /// In en, this message translates to:
  /// **'Module {number}'**
  String moduleNumber(int number);

  /// No description provided for @kindSong.
  ///
  /// In en, this message translates to:
  /// **'Song'**
  String get kindSong;

  /// No description provided for @kindBoss.
  ///
  /// In en, this message translates to:
  /// **'Boss'**
  String get kindBoss;

  /// No description provided for @kindChallenge.
  ///
  /// In en, this message translates to:
  /// **'Challenge'**
  String get kindChallenge;

  /// No description provided for @kindStarGate.
  ///
  /// In en, this message translates to:
  /// **'Star gate'**
  String get kindStarGate;

  /// No description provided for @kindLesson.
  ///
  /// In en, this message translates to:
  /// **'Lesson'**
  String get kindLesson;

  /// Number of tasks (levels) in a submodule.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 task} other{{count} tasks}}'**
  String taskCount(num count);

  /// No description provided for @practiceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Train skills outside the course path.'**
  String get practiceSubtitle;

  /// No description provided for @freePlay.
  ///
  /// In en, this message translates to:
  /// **'Free play'**
  String get freePlay;

  /// No description provided for @freePlayDesc.
  ///
  /// In en, this message translates to:
  /// **'Play anything on your MIDI keyboard or the screen.'**
  String get freePlayDesc;

  /// No description provided for @sightReading.
  ///
  /// In en, this message translates to:
  /// **'Sight reading'**
  String get sightReading;

  /// No description provided for @sightReadingDesc.
  ///
  /// In en, this message translates to:
  /// **'Read short random phrases at your level.'**
  String get sightReadingDesc;

  /// No description provided for @rhythmDrills.
  ///
  /// In en, this message translates to:
  /// **'Rhythm drills'**
  String get rhythmDrills;

  /// No description provided for @rhythmDrillsDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap the beat: quarters, halves, eighths.'**
  String get rhythmDrillsDesc;

  /// No description provided for @songLibrary.
  ///
  /// In en, this message translates to:
  /// **'Song library'**
  String get songLibrary;

  /// No description provided for @songLibraryDesc.
  ///
  /// In en, this message translates to:
  /// **'Practice any song you unlocked, at any tempo.'**
  String get songLibraryDesc;

  /// No description provided for @soon.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get soon;

  /// No description provided for @statStars.
  ///
  /// In en, this message translates to:
  /// **'Stars'**
  String get statStars;

  /// No description provided for @statTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get statTasks;

  /// No description provided for @statModules.
  ///
  /// In en, this message translates to:
  /// **'Modules'**
  String get statModules;

  /// No description provided for @profileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your progress on this device.'**
  String get profileSubtitle;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @developerTools.
  ///
  /// In en, this message translates to:
  /// **'Developer tools'**
  String get developerTools;

  /// No description provided for @soundEffects.
  ///
  /// In en, this message translates to:
  /// **'Sound effects'**
  String get soundEffects;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Language picker option: follow the device language.
  ///
  /// In en, this message translates to:
  /// **'Device default'**
  String get languageSystem;

  /// No description provided for @midiNotFound.
  ///
  /// In en, this message translates to:
  /// **'No MIDI keyboard found. Plug it in and try again.'**
  String get midiNotFound;

  /// No description provided for @midiUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Web MIDI is not available in this browser.'**
  String get midiUnavailable;

  /// No description provided for @scenePending.
  ///
  /// In en, this message translates to:
  /// **'(Animated scene arrives with the Phase 2 scene player.)'**
  String get scenePending;

  /// No description provided for @notAvailableYet.
  ///
  /// In en, this message translates to:
  /// **'Not available yet.'**
  String get notAvailableYet;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @exit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get exit;

  /// No description provided for @playFollowingNotes.
  ///
  /// In en, this message translates to:
  /// **'Play the following notes'**
  String get playFollowingNotes;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @restart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get restart;

  /// No description provided for @exitToMap.
  ///
  /// In en, this message translates to:
  /// **'Exit to map'**
  String get exitToMap;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @listenFirst.
  ///
  /// In en, this message translates to:
  /// **'Listen first…'**
  String get listenFirst;

  /// No description provided for @playAlongTempo.
  ///
  /// In en, this message translates to:
  /// **'Play along · {percent}%'**
  String playAlongTempo(int percent);

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @connectMidi.
  ///
  /// In en, this message translates to:
  /// **'Connect MIDI'**
  String get connectMidi;

  /// No description provided for @mutePianoSound.
  ///
  /// In en, this message translates to:
  /// **'Mute piano sound'**
  String get mutePianoSound;

  /// No description provided for @playPianoSound.
  ///
  /// In en, this message translates to:
  /// **'Play piano sound'**
  String get playPianoSound;

  /// No description provided for @metronomeOff.
  ///
  /// In en, this message translates to:
  /// **'Turn metronome off'**
  String get metronomeOff;

  /// No description provided for @metronomeOn.
  ///
  /// In en, this message translates to:
  /// **'Turn metronome on'**
  String get metronomeOn;

  /// No description provided for @hideKeyboard.
  ///
  /// In en, this message translates to:
  /// **'Hide keyboard'**
  String get hideKeyboard;

  /// No description provided for @showKeyboard.
  ///
  /// In en, this message translates to:
  /// **'Show keyboard'**
  String get showKeyboard;

  /// No description provided for @getReady.
  ///
  /// In en, this message translates to:
  /// **'Get ready…'**
  String get getReady;

  /// No description provided for @passRulePlayAlong.
  ///
  /// In en, this message translates to:
  /// **'Hit {percent}% of the notes in each part to pass.'**
  String passRulePlayAlong(int percent);

  /// No description provided for @passRuleOneNote.
  ///
  /// In en, this message translates to:
  /// **'Play more than 80% of the notes.'**
  String get passRuleOneNote;

  /// No description provided for @passRuleWait.
  ///
  /// In en, this message translates to:
  /// **'Play more than 80% of the notes before the hint appears.'**
  String get passRuleWait;

  /// No description provided for @trySlowerTempo.
  ///
  /// In en, this message translates to:
  /// **'Try a slower tempo.'**
  String get trySlowerTempo;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed!'**
  String get completed;

  /// No description provided for @almostThere.
  ///
  /// In en, this message translates to:
  /// **'Almost there!'**
  String get almostThere;

  /// No description provided for @statNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get statNotes;

  /// Result stat: how on time the notes were.
  ///
  /// In en, this message translates to:
  /// **'Timing'**
  String get statTiming;

  /// No description provided for @statAssists.
  ///
  /// In en, this message translates to:
  /// **'Assists'**
  String get statAssists;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @locked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get locked;

  /// Letter or solfege name written on middle C of the on-screen keyboard. See docs/specs/i18n.md (note naming).
  ///
  /// In en, this message translates to:
  /// **'C'**
  String get middleCLabel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'es', 'fr', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'BR':
            return AppLocalizationsPtBr();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
