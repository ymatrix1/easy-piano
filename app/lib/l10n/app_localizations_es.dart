// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Easy Piano';

  @override
  String get logoLabel => 'Logotipo de Easy Piano';

  @override
  String get navLearn => 'Aprender';

  @override
  String get navPractice => 'Práctica';

  @override
  String get navProfile => 'Perfil';

  @override
  String get sectionMore => 'Más';

  @override
  String get kickerContinue => 'Continuar';

  @override
  String get play => 'Jugar';

  @override
  String get comingSoon => 'Próximamente';

  @override
  String moduleNumber(int number) {
    return 'Módulo $number';
  }

  @override
  String get kindSong => 'Canción';

  @override
  String get kindBoss => 'Jefe';

  @override
  String get kindChallenge => 'Desafío';

  @override
  String get kindStarGate => 'Portal estelar';

  @override
  String get kindLesson => 'Lección';

  @override
  String taskCount(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString tareas',
      one: '1 tarea',
    );
    return '$_temp0';
  }

  @override
  String get practiceSubtitle =>
      'Entrena habilidades fuera de la ruta del curso.';

  @override
  String get freePlay => 'Juego libre';

  @override
  String get noteNames => 'Do,Do♯,Re,Re♯,Mi,Fa,Fa♯,Sol,Sol♯,La,La♯,Si';

  @override
  String get freePlayHint =>
      'Toca cualquier tecla. Usa un teclado MIDI o toca la pantalla.';

  @override
  String get octaveDown => 'Octava más grave';

  @override
  String get octaveUp => 'Octava más aguda';

  @override
  String get freePlayDesc =>
      'Toca lo que quieras en tu teclado MIDI o en la pantalla.';

  @override
  String get sightReading => 'Lectura a primera vista';

  @override
  String get sightReadingDesc => 'Lee frases cortas al azar de tu nivel.';

  @override
  String get rhythmDrills => 'Ejercicios de ritmo';

  @override
  String get rhythmDrillsDesc => 'Marca el pulso: negras, blancas, corcheas.';

  @override
  String get songLibrary => 'Biblioteca de canciones';

  @override
  String get songLibraryDesc =>
      'Practica cualquier canción desbloqueada, a cualquier tempo.';

  @override
  String get soon => 'Pronto';

  @override
  String get statStars => 'Estrellas';

  @override
  String get statTasks => 'Tareas';

  @override
  String get statModules => 'Módulos';

  @override
  String get profileSubtitle => 'Tu progreso en este dispositivo.';

  @override
  String get settings => 'Ajustes';

  @override
  String get developerTools => 'Herramientas de desarrollo';

  @override
  String get soundEffects => 'Efectos de sonido';

  @override
  String get language => 'Idioma';

  @override
  String get languageSystem => 'Predeterminado del dispositivo';

  @override
  String get midiNotFound =>
      'No se encontró ningún teclado MIDI. Conéctalo e inténtalo de nuevo.';

  @override
  String get midiUnavailable =>
      'Web MIDI no está disponible en este navegador.';

  @override
  String get scenePending =>
      '(La escena animada llega con el reproductor de escenas de la Fase 2.)';

  @override
  String get notAvailableYet => 'Aún no disponible.';

  @override
  String get continueButton => 'Continuar';

  @override
  String get exit => 'Salir';

  @override
  String get playFollowingNotes => 'Toca las siguientes notas';

  @override
  String get resume => 'Reanudar';

  @override
  String get restart => 'Reiniciar';

  @override
  String get exitToMap => 'Volver al mapa';

  @override
  String get pause => 'Pausa';

  @override
  String get listenFirst => 'Primero escucha…';

  @override
  String playAlongTempo(int percent) {
    return 'Toca con la música · $percent%';
  }

  @override
  String get skip => 'Saltar';

  @override
  String get connectMidi => 'Conectar MIDI';

  @override
  String get mutePianoSound => 'Silenciar el piano';

  @override
  String get playPianoSound => 'Activar el sonido del piano';

  @override
  String get metronomeOff => 'Apagar el metrónomo';

  @override
  String get metronomeOn => 'Encender el metrónomo';

  @override
  String get hideKeyboard => 'Ocultar teclado';

  @override
  String get showKeyboard => 'Mostrar teclado';

  @override
  String get getReady => 'Prepárate…';

  @override
  String passRulePlayAlong(int percent) {
    return 'Acierta el $percent% de las notas de cada parte para pasar.';
  }

  @override
  String get passRuleOneNote => 'Toca más del 80% de las notas.';

  @override
  String get passRuleWait =>
      'Toca más del 80% de las notas antes de que aparezca la pista.';

  @override
  String get trySlowerTempo => 'Prueba un tempo más lento.';

  @override
  String get completed => '¡Completado!';

  @override
  String get almostThere => '¡Casi lo logras!';

  @override
  String get statNotes => 'Notas';

  @override
  String get statTiming => 'Ritmo';

  @override
  String get statAssists => 'Ayudas';

  @override
  String get retry => 'Reintentar';

  @override
  String get next => 'Siguiente';

  @override
  String get locked => 'Bloqueado';

  @override
  String get middleCLabel => 'Do';

  @override
  String gateProgress(int need, int have) {
    return 'Gana $need estrellas con cualquiera de estas canciones ($have/$need)';
  }

  @override
  String get early => 'Pronto';

  @override
  String get late => 'Tarde';

  @override
  String get slowPractice => 'Práctica lenta';

  @override
  String get slowPracticeIntro => 'Practiquemos esta parte más lento';

  @override
  String get sectionTryAgain => 'Intenta esta parte otra vez';

  @override
  String get sectionFullSpeed => '¡Ahora a velocidad normal!';
}
