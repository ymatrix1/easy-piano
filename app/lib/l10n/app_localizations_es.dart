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

  @override
  String get micInput => 'Micrófono';

  @override
  String get micUseMidi => 'Usar MIDI / teclas en pantalla';

  @override
  String get micExplainTitle => 'Tocar con el micrófono';

  @override
  String get micExplainBody =>
      'Easy Piano escucha tu piano por el micrófono para que toques sin cable. El audio se analiza en este dispositivo y nunca se graba ni se envía. El sonido de piano de la app se silencia mientras escucha.';

  @override
  String get micAllow => 'Permitir micrófono';

  @override
  String get cancel => 'Cancelar';

  @override
  String get micDenied =>
      'Se bloqueó el acceso al micrófono. Permítelo en la configuración del sitio del navegador e inténtalo de nuevo.';

  @override
  String get micUnavailable =>
      'La entrada por micrófono no está disponible en este navegador.';

  @override
  String get micCalibrate => 'Calibrar';

  @override
  String get micCalibrateTitle => 'Calibrar el micrófono';

  @override
  String get micCalibrateBody =>
      'Toca cualquier tecla cada vez que se ilumine el círculo.';

  @override
  String get micCalibrateRetry =>
      'No oí suficientes notas. Inténtalo de nuevo un poco más fuerte.';

  @override
  String micCalibrateDone(int ms) {
    return 'Listo: $ms ms de retraso';
  }

  @override
  String get micListening => 'Escuchando';

  @override
  String get micDefaultDevice => 'Micrófono predeterminado';

  @override
  String micHeard(String note) {
    return 'Oí: $note';
  }

  @override
  String get micTestHint =>
      'Toca una tecla: la barra se mueve y la nota aparece aquí.';

  @override
  String get micTurnOff => 'Apagar';

  @override
  String get micNoteNames => 'Do,Do♯,Re,Re♯,Mi,Fa,Fa♯,Sol,Sol♯,La,La♯,Si';

  @override
  String get micNotFound =>
      'No se encontró ningún micrófono. Conecta uno o elige otra entrada.';

  @override
  String get micBusy =>
      'Otra app está usando el micrófono. Ciérrala e inténtalo de nuevo.';

  @override
  String get micQuietTip =>
      'Funciona mejor en silencio: hablar, teclear o música cerca pueden oírse como notas.';

  @override
  String get generatedBadge => 'Generada';

  @override
  String get practiceLoading => 'Preparando el creador de melodías…';

  @override
  String practiceDownload(int percent) {
    return 'Descargando $percent%';
  }

  @override
  String get practiceGenerating => 'Escribiendo una melodía para esta lección…';

  @override
  String get practiceAgain => 'Tocar otra vez';

  @override
  String get practiceFailed =>
      'No se pudo crear una melodía para esta lección. Inténtalo de nuevo.';

  @override
  String get practiceNotYet =>
      'Por ahora las melodías de práctica solo funcionan en el navegador.';

  @override
  String get practiceModelError =>
      'No se pudo cargar el creador de melodías. Revisa tu conexión e inténtalo de nuevo.';

  @override
  String practiceNotesHit(int hit, int total) {
    return '$hit de $total notas';
  }

  @override
  String get practiceNoStars =>
      'Una melodía nueva para esta lección. Solo práctica: sin estrellas.';

  @override
  String get practiceWait => 'Espérame';

  @override
  String get practicePlayAlong => 'Tocar a la vez';

  @override
  String get endlessPractice => 'Práctica sin fin';

  @override
  String get endlessPracticeDesc =>
      'Música nueva para tu nivel, escrita mientras tocas. Elige el nivel y las reglas.';

  @override
  String get setupLevel => 'Nivel';

  @override
  String get setupHands => 'Manos';

  @override
  String setupTempo(int bpm) {
    return 'Tempo · $bpm ppm';
  }

  @override
  String get setupNoteValues => 'Figuras';

  @override
  String get setupMode => 'Modo';

  @override
  String get handRight => 'Derecha';

  @override
  String get handLeft => 'Izquierda';

  @override
  String get handBoth => 'Ambas';

  @override
  String get noteValuesInvalid =>
      'Con estas figuras no se puede llenar un compás. Añade una más larga o más corta.';

  @override
  String get streamEnded => 'No se pudo escribir más música con estos ajustes.';

  @override
  String get setupStyle => 'Estilo';

  @override
  String levelN(int level) {
    return 'Nivel $level';
  }

  @override
  String get styleAny => 'Cualquiera';

  @override
  String get styleClassical => 'Clásica';

  @override
  String get styleFolk => 'Folclórica';

  @override
  String get styleChildren => 'Infantil';

  @override
  String get stylePop => 'Pop';

  @override
  String get styleJazz => 'Jazz';

  @override
  String get styleGame => 'Videojuego';

  @override
  String get methodsCardTitle => 'Métodos';

  @override
  String methodsCardSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count métodos',
      one: '1 método',
    );
    return '$_temp0';
  }

  @override
  String get methodsLibraryTitle => 'Métodos';

  @override
  String get methodsFilterAll => 'Todos';

  @override
  String get methodsFilterBeginner => 'Principiante';

  @override
  String get methodsFilterEarlyIntermediate => 'Intermedio inicial';

  @override
  String get methodsFilterIntermediate => 'Intermedio';

  @override
  String get methodsFilterReading => 'Lectura';

  @override
  String get methodsFilterRhythm => 'Ritmo';

  @override
  String get methodsFilterIndependence => 'Independencia';

  @override
  String methodsBookCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count libros',
      one: '1 libro',
    );
    return '$_temp0';
  }

  @override
  String get methodContinue => 'Continuar';

  @override
  String methodProtectedNotice(String year) {
    return 'Protegido en tu país hasta $year';
  }
}
