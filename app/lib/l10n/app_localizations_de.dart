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

  @override
  String get early => 'Zu früh';

  @override
  String get late => 'Zu spät';

  @override
  String get slowPractice => 'Langsam üben';

  @override
  String get slowPracticeIntro => 'Üben wir diesen Teil langsamer';

  @override
  String get sectionTryAgain => 'Versuch diesen Teil noch einmal';

  @override
  String get sectionFullSpeed => 'Jetzt im vollen Tempo!';

  @override
  String get micInput => 'Mikrofon';

  @override
  String get micUseMidi => 'MIDI / Bildschirmtasten nutzen';

  @override
  String get micExplainTitle => 'Mit dem Mikrofon spielen';

  @override
  String get micExplainBody =>
      'Easy Piano hört dein Klavier über das Mikrofon, damit du ohne Kabel spielen kannst. Der Ton wird auf diesem Gerät ausgewertet und nie aufgenommen oder gesendet. Der Klavierklang der App ist beim Zuhören stumm.';

  @override
  String get micAllow => 'Mikrofon erlauben';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get micDenied =>
      'Der Mikrofonzugriff wurde blockiert. Erlaube ihn in den Website-Einstellungen des Browsers und versuche es erneut.';

  @override
  String get micUnavailable =>
      'Mikrofoneingabe ist in diesem Browser nicht verfügbar.';

  @override
  String get micCalibrate => 'Kalibrieren';

  @override
  String get micCalibrateTitle => 'Mikrofon kalibrieren';

  @override
  String get micCalibrateBody =>
      'Spiel eine beliebige Taste, sobald der Kreis aufleuchtet.';

  @override
  String get micCalibrateRetry =>
      'Ich habe nicht genug Töne gehört. Versuch es etwas lauter noch einmal.';

  @override
  String micCalibrateDone(int ms) {
    return 'Fertig: $ms ms Verzögerung';
  }

  @override
  String get micListening => 'Höre zu';

  @override
  String get micDefaultDevice => 'Standardmikrofon';

  @override
  String micHeard(String note) {
    return 'Gehört: $note';
  }

  @override
  String get micTestHint =>
      'Spiel eine Taste: Der Balken bewegt sich und der Ton erscheint hier.';

  @override
  String get micTurnOff => 'Ausschalten';

  @override
  String get micNoteNames => 'C,Cis,D,Dis,E,F,Fis,G,Gis,A,B,H';

  @override
  String get micNotFound =>
      'Kein Mikrofon gefunden. Schließ eins an oder wähle einen anderen Eingang.';

  @override
  String get micBusy =>
      'Das Mikrofon wird von einer anderen App benutzt. Schließ sie und versuch es erneut.';

  @override
  String get micQuietTip =>
      'Am besten in einem ruhigen Raum: Sprechen, Tippen oder Musik in der Nähe können als Töne erkannt werden.';

  @override
  String get generatedBadge => 'Generiert';

  @override
  String get practiceLoading => 'Der Melodie-Macher wird vorbereitet…';

  @override
  String practiceDownload(int percent) {
    return 'Download $percent%';
  }

  @override
  String get practiceGenerating =>
      'Ein Stück für diese Lektion wird geschrieben…';

  @override
  String get practiceAgain => 'Nochmal spielen';

  @override
  String get practiceFailed =>
      'Kein passendes Stück für diese Lektion gefunden. Versuch es nochmal.';

  @override
  String get practiceNotYet => 'Übungsstücke gibt es vorerst nur im Browser.';

  @override
  String get practiceModelError =>
      'Der Melodie-Macher konnte nicht geladen werden. Prüfe deine Verbindung und versuch es nochmal.';

  @override
  String practiceNotesHit(int hit, int total) {
    return '$hit von $total Noten';
  }

  @override
  String get practiceNoStars =>
      'Ein neues Stück für diese Lektion. Nur zum Üben: keine Sterne.';

  @override
  String get practiceWait => 'Warte auf mich';

  @override
  String get practicePlayAlong => 'Mitspielen';

  @override
  String get endlessPractice => 'Endlos üben';

  @override
  String get endlessPracticeDesc =>
      'Neue Musik für dein Level, geschrieben während du spielst. Wähle Level und Regeln.';

  @override
  String get setupLevel => 'Level';

  @override
  String get setupHands => 'Hände';

  @override
  String setupTempo(int bpm) {
    return 'Tempo · $bpm bpm';
  }

  @override
  String get setupNoteValues => 'Notenwerte';

  @override
  String get setupMode => 'Modus';

  @override
  String get handRight => 'Rechts';

  @override
  String get handLeft => 'Links';

  @override
  String get handBoth => 'Beide';

  @override
  String get noteValuesInvalid =>
      'Mit diesen Notenwerten lässt sich kein Takt füllen. Nimm einen längeren oder kürzeren dazu.';

  @override
  String get streamEnded =>
      'Mit diesen Einstellungen ließ sich keine weitere Musik schreiben.';

  @override
  String get setupStyle => 'Stil';

  @override
  String levelN(int level) {
    return 'Level $level';
  }

  @override
  String get styleAny => 'Egal';

  @override
  String get styleClassical => 'Klassik';

  @override
  String get styleFolk => 'Volkslied';

  @override
  String get styleChildren => 'Kinderlied';

  @override
  String get stylePop => 'Pop';

  @override
  String get styleJazz => 'Jazz';

  @override
  String get styleGame => 'Spiel';

  @override
  String get midiUnavailableApp =>
      'MIDI-Eingabe ist auf diesem Gerät nicht verfügbar.';

  @override
  String get micUnavailableApp =>
      'Mikrofoneingabe ist auf diesem Gerät nicht verfügbar.';

  @override
  String get micDeniedApp =>
      'Der Mikrofonzugriff wurde blockiert. Erlaube ihn in den Systemeinstellungen der App und versuche es erneut.';

  @override
  String songLibraryNoMatch(String query) {
    return 'Keine Partitur passt zu \"$query\".';
  }

  @override
  String get importScore => 'Partitur importieren';

  @override
  String get importScoreDesc =>
      'MusicXML-, MIDI-, ABC- oder LilyPond-Datei öffnen.';

  @override
  String get importScoreFailed => 'Diese Datei konnte nicht importiert werden.';

  @override
  String get importScoreUnsupported =>
      'Nicht unterstützte Datei. Verwende .xml, .musicxml, .mxl, .mid, .midi, .abc oder .ly.';

  @override
  String get songLibraryEmpty =>
      'Noch keine importierten Partituren. Importiere eine Datei oder ziehe sie in das Fenster.';

  @override
  String get songLibrarySearch => 'Partituren suchen';

  @override
  String get scoreDropHint => 'Partiturdatei zum Importieren hier ablegen';

  @override
  String get scoreDelete => 'Löschen';

  @override
  String get scoreDeleteConfirm =>
      'Diese Partitur aus der Bibliothek entfernen?';

  @override
  String get scorePractice => 'Üben';

  @override
  String scoreBars(int count) {
    return '$count Takte';
  }

  @override
  String scoreTimeSignature(String time) {
    return 'Takt $time';
  }
}
