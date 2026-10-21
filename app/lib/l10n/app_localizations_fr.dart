// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Easy Piano';

  @override
  String get logoLabel => 'Logo d\'Easy Piano';

  @override
  String get navLearn => 'Apprendre';

  @override
  String get navPractice => 'Entraînement';

  @override
  String get navProfile => 'Profil';

  @override
  String get sectionMore => 'Plus';

  @override
  String get kickerContinue => 'Continuer';

  @override
  String get play => 'Jouer';

  @override
  String get comingSoon => 'Bientôt';

  @override
  String moduleNumber(int number) {
    return 'Module $number';
  }

  @override
  String get kindSong => 'Chanson';

  @override
  String get kindBoss => 'Boss';

  @override
  String get kindChallenge => 'Défi';

  @override
  String get kindStarGate => 'Porte étoilée';

  @override
  String get kindLesson => 'Leçon';

  @override
  String taskCount(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString tâches',
      one: '1 tâche',
    );
    return '$_temp0';
  }

  @override
  String get practiceSubtitle => 'Travaille tes compétences hors du parcours.';

  @override
  String get freePlay => 'Jeu libre';

  @override
  String get noteNames => 'Do,Do♯,Ré,Ré♯,Mi,Fa,Fa♯,Sol,Sol♯,La,La♯,Si';

  @override
  String get freePlayHint =>
      'Joue n\'importe quelle touche. Utilise un clavier MIDI ou touche l\'écran.';

  @override
  String get octaveDown => 'Octave plus grave';

  @override
  String get octaveUp => 'Octave plus aiguë';

  @override
  String get freePlayDesc =>
      'Joue ce que tu veux sur ton clavier MIDI ou à l\'écran.';

  @override
  String get sightReading => 'Déchiffrage';

  @override
  String get sightReadingDesc =>
      'Lis de courtes phrases aléatoires à ton niveau.';

  @override
  String get rhythmDrills => 'Exercices de rythme';

  @override
  String get rhythmDrillsDesc =>
      'Tape la pulsation : noires, blanches, croches.';

  @override
  String get songLibrary => 'Bibliothèque de chansons';

  @override
  String get songLibraryDesc =>
      'Travaille n\'importe quelle chanson débloquée, à n\'importe quel tempo.';

  @override
  String get soon => 'Bientôt';

  @override
  String get statStars => 'Étoiles';

  @override
  String get statTasks => 'Tâches';

  @override
  String get statModules => 'Modules';

  @override
  String get profileSubtitle => 'Ta progression sur cet appareil.';

  @override
  String get settings => 'Réglages';

  @override
  String get developerTools => 'Outils de développement';

  @override
  String get soundEffects => 'Effets sonores';

  @override
  String get language => 'Langue';

  @override
  String get languageSystem => 'Langue de l\'appareil';

  @override
  String get midiNotFound =>
      'Aucun clavier MIDI trouvé. Branche-le et réessaie.';

  @override
  String get midiUnavailable =>
      'Web MIDI n\'est pas disponible dans ce navigateur.';

  @override
  String get scenePending =>
      '(La scène animée arrive avec le lecteur de scènes de la phase 2.)';

  @override
  String get notAvailableYet => 'Pas encore disponible.';

  @override
  String get continueButton => 'Continuer';

  @override
  String get exit => 'Quitter';

  @override
  String get playFollowingNotes => 'Joue les notes suivantes';

  @override
  String get resume => 'Reprendre';

  @override
  String get restart => 'Recommencer';

  @override
  String get exitToMap => 'Retour à la carte';

  @override
  String get pause => 'Pause';

  @override
  String get listenFirst => 'Écoute d\'abord…';

  @override
  String playAlongTempo(int percent) {
    return 'Joue avec la musique · $percent %';
  }

  @override
  String get skip => 'Passer';

  @override
  String get connectMidi => 'Connecter le MIDI';

  @override
  String get mutePianoSound => 'Couper le son du piano';

  @override
  String get playPianoSound => 'Activer le son du piano';

  @override
  String get metronomeOff => 'Désactiver le métronome';

  @override
  String get metronomeOn => 'Activer le métronome';

  @override
  String get hideKeyboard => 'Masquer le clavier';

  @override
  String get showKeyboard => 'Afficher le clavier';

  @override
  String get getReady => 'Prépare-toi…';

  @override
  String passRulePlayAlong(int percent) {
    return 'Réussis $percent % des notes de chaque partie pour valider.';
  }

  @override
  String get passRuleOneNote => 'Joue plus de 80 % des notes.';

  @override
  String get passRuleWait =>
      'Joue plus de 80 % des notes avant que l\'indice n\'apparaisse.';

  @override
  String get trySlowerTempo => 'Essaie un tempo plus lent.';

  @override
  String get completed => 'Terminé !';

  @override
  String get almostThere => 'Presque !';

  @override
  String get statNotes => 'Notes';

  @override
  String get statTiming => 'Timing';

  @override
  String get statAssists => 'Aides';

  @override
  String get retry => 'Réessayer';

  @override
  String get next => 'Suivant';

  @override
  String get locked => 'Verrouillé';

  @override
  String get middleCLabel => 'Do';

  @override
  String gateProgress(int need, int have) {
    return 'Gagne $need étoiles avec n\'importe lesquels de ces morceaux ($have/$need)';
  }

  @override
  String get micInput => 'Microphone';

  @override
  String get micUseMidi => 'Utiliser MIDI / touches à l\'écran';

  @override
  String get micExplainTitle => 'Jouer avec le microphone';

  @override
  String get micExplainBody =>
      'Easy Piano écoute votre piano par le microphone pour jouer sans câble. L\'audio est analysé sur cet appareil, jamais enregistré ni envoyé. Le son de piano de l\'app est coupé pendant l\'écoute.';

  @override
  String get micAllow => 'Autoriser le microphone';

  @override
  String get cancel => 'Annuler';

  @override
  String get micDenied =>
      'L\'accès au microphone est bloqué. Autorisez-le dans les paramètres du site du navigateur, puis réessayez.';

  @override
  String get micUnavailable =>
      'L\'entrée microphone n\'est pas disponible dans ce navigateur.';

  @override
  String get micCalibrate => 'Calibrer';

  @override
  String get micCalibrateTitle => 'Calibrer le microphone';

  @override
  String get micCalibrateBody =>
      'Jouez une touche chaque fois que le cercle s\'allume.';

  @override
  String get micCalibrateRetry =>
      'Je n\'ai pas entendu assez de notes. Réessayez un peu plus fort.';

  @override
  String micCalibrateDone(int ms) {
    return 'Terminé : $ms ms de délai';
  }

  @override
  String get micListening => 'Écoute';

  @override
  String get micDefaultDevice => 'Microphone par défaut';

  @override
  String micHeard(String note) {
    return 'Entendu : $note';
  }

  @override
  String get micTestHint =>
      'Jouez une touche : la barre bouge et la note s\'affiche ici.';

  @override
  String get micTurnOff => 'Couper';

  @override
  String get micNoteNames => 'Do,Do♯,Ré,Ré♯,Mi,Fa,Fa♯,Sol,Sol♯,La,La♯,Si';

  @override
  String get micNotFound =>
      'Aucun microphone trouvé. Branchez-en un ou choisissez une autre entrée.';

  @override
  String get micBusy =>
      'Le microphone est utilisé par une autre app. Fermez-la et réessayez.';

  @override
  String get micQuietTip =>
      'Idéal dans une pièce calme : voix, frappe au clavier ou musique proches peuvent être prises pour des notes.';
}
