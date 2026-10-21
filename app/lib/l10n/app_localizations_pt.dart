// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'Easy Piano';

  @override
  String get logoLabel => 'Logo do Easy Piano';

  @override
  String get navLearn => 'Aprender';

  @override
  String get navPractice => 'Treino';

  @override
  String get navProfile => 'Perfil';

  @override
  String get sectionMore => 'Mais';

  @override
  String get kickerContinue => 'Continuar';

  @override
  String get play => 'Jogar';

  @override
  String get comingSoon => 'Em breve';

  @override
  String moduleNumber(int number) {
    return 'Módulo $number';
  }

  @override
  String get kindSong => 'Música';

  @override
  String get kindBoss => 'Chefão';

  @override
  String get kindChallenge => 'Desafio';

  @override
  String get kindStarGate => 'Portal estelar';

  @override
  String get kindLesson => 'Lição';

  @override
  String taskCount(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString tarefas',
      one: '1 tarefa',
    );
    return '$_temp0';
  }

  @override
  String get practiceSubtitle => 'Treine habilidades fora da trilha do curso.';

  @override
  String get freePlay => 'Toque livre';

  @override
  String get noteNames => 'Dó,Dó♯,Ré,Ré♯,Mi,Fá,Fá♯,Sol,Sol♯,Lá,Lá♯,Si';

  @override
  String get freePlayHint =>
      'Toque qualquer tecla. Use um teclado MIDI ou toque na tela.';

  @override
  String get octaveDown => 'Oitava mais grave';

  @override
  String get octaveUp => 'Oitava mais aguda';

  @override
  String get freePlayDesc => 'Toque o que quiser no teclado MIDI ou na tela.';

  @override
  String get sightReading => 'Leitura à primeira vista';

  @override
  String get sightReadingDesc => 'Leia frases curtas aleatórias no seu nível.';

  @override
  String get rhythmDrills => 'Exercícios de ritmo';

  @override
  String get rhythmDrillsDesc =>
      'Marque o pulso: semínimas, mínimas, colcheias.';

  @override
  String get songLibrary => 'Biblioteca de músicas';

  @override
  String get songLibraryDesc =>
      'Pratique qualquer música desbloqueada, em qualquer andamento.';

  @override
  String get soon => 'Em breve';

  @override
  String get statStars => 'Estrelas';

  @override
  String get statTasks => 'Tarefas';

  @override
  String get statModules => 'Módulos';

  @override
  String get profileSubtitle => 'Seu progresso neste dispositivo.';

  @override
  String get settings => 'Configurações';

  @override
  String get developerTools => 'Ferramentas de desenvolvedor';

  @override
  String get soundEffects => 'Efeitos sonoros';

  @override
  String get language => 'Idioma';

  @override
  String get languageSystem => 'Padrão do dispositivo';

  @override
  String get midiNotFound =>
      'Nenhum teclado MIDI encontrado. Conecte-o e tente de novo.';

  @override
  String get midiUnavailable => 'Web MIDI não está disponível neste navegador.';

  @override
  String get scenePending =>
      '(A cena animada chega com o player de cenas da Fase 2.)';

  @override
  String get notAvailableYet => 'Ainda não disponível.';

  @override
  String get continueButton => 'Continuar';

  @override
  String get exit => 'Sair';

  @override
  String get playFollowingNotes => 'Toque as notas a seguir';

  @override
  String get resume => 'Continuar';

  @override
  String get restart => 'Recomeçar';

  @override
  String get exitToMap => 'Voltar ao mapa';

  @override
  String get pause => 'Pausar';

  @override
  String get listenFirst => 'Primeiro, ouça…';

  @override
  String playAlongTempo(int percent) {
    return 'Toque junto · $percent%';
  }

  @override
  String get skip => 'Pular';

  @override
  String get connectMidi => 'Conectar MIDI';

  @override
  String get mutePianoSound => 'Silenciar o piano';

  @override
  String get playPianoSound => 'Ativar som do piano';

  @override
  String get metronomeOff => 'Desligar metrônomo';

  @override
  String get metronomeOn => 'Ligar metrônomo';

  @override
  String get hideKeyboard => 'Ocultar teclado';

  @override
  String get showKeyboard => 'Mostrar teclado';

  @override
  String get getReady => 'Prepare-se…';

  @override
  String passRulePlayAlong(int percent) {
    return 'Acerte $percent% das notas de cada parte para passar.';
  }

  @override
  String get passRuleOneNote => 'Toque mais de 80% das notas.';

  @override
  String get passRuleWait =>
      'Toque mais de 80% das notas antes de a dica aparecer.';

  @override
  String get trySlowerTempo => 'Tente um andamento mais lento.';

  @override
  String get completed => 'Concluído!';

  @override
  String get almostThere => 'Quase lá!';

  @override
  String get statNotes => 'Notas';

  @override
  String get statTiming => 'Tempo';

  @override
  String get statAssists => 'Ajudas';

  @override
  String get retry => 'Tentar de novo';

  @override
  String get next => 'Próximo';

  @override
  String get locked => 'Bloqueado';

  @override
  String get middleCLabel => 'Dó';

  @override
  String gateProgress(int need, int have) {
    return 'Ganhe $need estrelas em qualquer uma destas músicas ($have/$need)';
  }

  @override
  String get practiceTune => 'Melodia de treino';

  @override
  String get generatedBadge => 'Gerada';

  @override
  String get practiceLoading => 'A preparar o criador de melodias…';

  @override
  String practiceDownload(int percent) {
    return 'A transferir $percent%';
  }

  @override
  String get practiceGenerating => 'A escrever uma melodia para esta lição…';

  @override
  String get practiceAnother => 'Outra';

  @override
  String get practiceAgain => 'Tocar de novo';

  @override
  String get practiceFailed =>
      'Não foi possível criar uma melodia para esta lição. Tenta de novo.';

  @override
  String get practiceNotYet =>
      'Por agora, as melodias de treino só funcionam no navegador.';

  @override
  String get practiceModelError =>
      'Não foi possível carregar o criador de melodias. Verifica a ligação e tenta de novo.';

  @override
  String practiceNotesHit(int hit, int total) {
    return '$hit de $total notas';
  }

  @override
  String get practiceNoStars =>
      'Uma melodia nova para esta lição. Só treino: sem estrelas.';

  @override
  String get practiceWait => 'Espera por mim';

  @override
  String get practicePlayAlong => 'Tocar junto';
}

/// The translations for Portuguese, as used in Brazil (`pt_BR`).
class AppLocalizationsPtBr extends AppLocalizationsPt {
  AppLocalizationsPtBr() : super('pt_BR');

  @override
  String gateProgress(int need, int have) {
    return 'Ganhe $need estrelas em qualquer uma destas músicas ($have/$need)';
  }

  @override
  String get practiceTune => 'Melodia de treino';

  @override
  String get generatedBadge => 'Gerada';

  @override
  String get practiceLoading => 'Preparando o criador de melodias…';

  @override
  String practiceDownload(int percent) {
    return 'Baixando $percent%';
  }

  @override
  String get practiceGenerating => 'Escrevendo uma melodia para esta lição…';

  @override
  String get practiceAnother => 'Outra';

  @override
  String get practiceAgain => 'Tocar de novo';

  @override
  String get practiceFailed =>
      'Não deu para criar uma melodia para esta lição. Tente de novo.';

  @override
  String get practiceNotYet =>
      'Por enquanto, as melodias de treino só funcionam no navegador.';

  @override
  String get practiceModelError =>
      'Não deu para carregar o criador de melodias. Confira a conexão e tente de novo.';

  @override
  String practiceNotesHit(int hit, int total) {
    return '$hit de $total notas';
  }

  @override
  String get practiceNoStars =>
      'Uma melodia nova para esta lição. Só treino: sem estrelas.';

  @override
  String get practiceWait => 'Espere por mim';

  @override
  String get practicePlayAlong => 'Tocar junto';
}
