// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Easy Piano';

  @override
  String get logoLabel => 'Easy-Piano-Logo';

  @override
  String get navLearn => 'Lernen';

  @override
  String get navPractice => 'Üben';

  @override
  String get navProfile => 'Profil';

  @override
  String get sectionMore => 'Mehr';

  @override
  String get kickerContinue => 'Weiter';

  @override
  String get play => 'Spielen';

  @override
  String get comingSoon => 'Demnächst';

  @override
  String moduleNumber(int number) {
    return 'Modul $number';
  }

  @override
  String get kindSong => 'Lied';

  @override
  String get kindBoss => 'Boss';

  @override
  String get kindChallenge => 'Herausforderung';

  @override
  String get kindStarGate => 'Sternentor';

  @override
  String get kindLesson => 'Lektion';

  @override
  String taskCount(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Aufgaben',
      one: '1 Aufgabe',
    );
    return '$_temp0';
  }

  @override
  String get practiceSubtitle => 'Trainiere Fähigkeiten abseits des Kurspfads.';

  @override
  String get freePlay => 'Freies Spiel';

  @override
  String get noteNames => 'C,C♯,D,D♯,E,F,F♯,G,G♯,A,A♯,H';

  @override
  String get freePlayHint =>
      'Spiel eine beliebige Taste. Nutze ein MIDI-Keyboard oder tippe auf den Bildschirm.';

  @override
  String get octaveDown => 'Tiefere Oktave';

  @override
  String get octaveUp => 'Höhere Oktave';

  @override
  String get freePlayDesc =>
      'Spiel, was du willst, auf deinem MIDI-Keyboard oder dem Bildschirm.';

  @override
  String get sightReading => 'Vom-Blatt-Spiel';

  @override
  String get sightReadingDesc =>
      'Lies kurze zufällige Phrasen auf deinem Niveau.';

  @override
  String get rhythmDrills => 'Rhythmusübungen';

  @override
  String get rhythmDrillsDesc => 'Klopf den Takt: Viertel, Halbe, Achtel.';

  @override
  String get songLibrary => 'Liederbibliothek';

  @override
  String get songLibraryDesc =>
      'Übe jedes freigeschaltete Lied in jedem Tempo.';

  @override
  String get soon => 'Bald';

  @override
  String get statStars => 'Sterne';

  @override
  String get statTasks => 'Aufgaben';

  @override
  String get statModules => 'Module';

  @override
  String get profileSubtitle => 'Dein Fortschritt auf diesem Gerät.';

  @override
  String get settings => 'Einstellungen';

  @override
  String get developerTools => 'Entwicklerwerkzeuge';

  @override
  String get soundEffects => 'Soundeffekte';

  @override
  String get language => 'Sprache';

  @override
  String get languageSystem => 'Gerätestandard';

  @override
  String get midiNotFound =>
      'Kein MIDI-Keyboard gefunden. Schließ es an und versuch es erneut.';

  @override
  String get midiUnavailable =>
      'Web MIDI ist in diesem Browser nicht verfügbar.';

  @override
  String get scenePending =>
      '(Die animierte Szene kommt mit dem Szenenplayer in Phase 2.)';

  @override
  String get notAvailableYet => 'Noch nicht verfügbar.';

  @override
  String get continueButton => 'Weiter';

  @override
  String get exit => 'Beenden';

  @override
  String get playFollowingNotes => 'Spiel die folgenden Noten';

  @override
  String get resume => 'Fortsetzen';

  @override
  String get restart => 'Neu starten';

  @override
  String get exitToMap => 'Zur Karte';

  @override
  String get pause => 'Pause';

  @override
  String get listenFirst => 'Erst zuhören…';

  @override
  String playAlongTempo(int percent) {
    return 'Mitspielen · $percent %';
  }

  @override
  String get skip => 'Überspringen';

  @override
  String get connectMidi => 'MIDI verbinden';

  @override
  String get mutePianoSound => 'Klaviersound stummschalten';

  @override
  String get playPianoSound => 'Klaviersound einschalten';

  @override
  String get metronomeOff => 'Metronom ausschalten';

  @override
  String get metronomeOn => 'Metronom einschalten';

  @override
  String get hideKeyboard => 'Tastatur ausblenden';

  @override
  String get showKeyboard => 'Tastatur einblenden';

  @override
  String get getReady => 'Mach dich bereit…';

  @override
  String passRulePlayAlong(int percent) {
    return 'Triff $percent % der Noten in jedem Teil, um zu bestehen.';
  }

  @override
  String get passRuleOneNote => 'Spiel mehr als 80 % der Noten.';

  @override
  String get passRuleWait =>
      'Spiel mehr als 80 % der Noten, bevor der Hinweis erscheint.';

  @override
  String get trySlowerTempo => 'Versuch ein langsameres Tempo.';

  @override
  String get completed => 'Geschafft!';

  @override
  String get almostThere => 'Fast geschafft!';

  @override
  String get statNotes => 'Noten';

  @override
  String get statTiming => 'Timing';

  @override
  String get statAssists => 'Hilfen';

  @override
  String get retry => 'Nochmal';

  @override
  String get next => 'Weiter';

  @override
  String get locked => 'Gesperrt';

  @override
  String get middleCLabel => 'C';

  @override
  String gateProgress(int need, int have) {
    return 'Sammle $need Sterne mit beliebigen dieser Lieder ($have/$need)';
  }
}
