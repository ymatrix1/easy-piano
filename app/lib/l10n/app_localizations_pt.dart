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
  String get early => 'Adiantado';

  @override
  String get late => 'Atrasado';

  @override
  String get slowPractice => 'Prática lenta';

  @override
  String get slowPracticeIntro => 'Vamos praticar esta parte mais devagar';

  @override
  String get sectionTryAgain => 'Tente esta parte de novo';

  @override
  String get sectionFullSpeed => 'Agora na velocidade normal!';

  @override
  String get micInput => 'Microfone';

  @override
  String get micUseMidi => 'Usar MIDI / teclas na tela';

  @override
  String get micExplainTitle => 'Tocar com o microfone';

  @override
  String get micExplainBody =>
      'O Easy Piano escuta o seu piano pelo microfone para você tocar sem cabo. O áudio é analisado neste aparelho e nunca é gravado nem enviado. O som de piano do app fica mudo enquanto escuta.';

  @override
  String get micAllow => 'Permitir microfone';

  @override
  String get cancel => 'Cancelar';

  @override
  String get micDenied =>
      'O acesso ao microfone foi bloqueado. Permita nas configurações do site no navegador e tente de novo.';

  @override
  String get micUnavailable =>
      'A entrada por microfone não está disponível neste navegador.';

  @override
  String get micCalibrate => 'Calibrar';

  @override
  String get micCalibrateTitle => 'Calibrar o microfone';

  @override
  String get micCalibrateBody =>
      'Toque qualquer tecla cada vez que o círculo acender.';

  @override
  String get micCalibrateRetry =>
      'Não ouvi notas suficientes. Tente de novo um pouco mais forte.';

  @override
  String micCalibrateDone(int ms) {
    return 'Pronto: atraso de $ms ms';
  }

  @override
  String get micListening => 'Escutando';

  @override
  String get micDefaultDevice => 'Microfone padrão';

  @override
  String micHeard(String note) {
    return 'Ouvi: $note';
  }

  @override
  String get micTestHint =>
      'Toque uma tecla: a barra se move e a nota aparece aqui.';

  @override
  String get micTurnOff => 'Desligar';

  @override
  String get micNoteNames => 'Dó,Dó♯,Ré,Ré♯,Mi,Fá,Fá♯,Sol,Sol♯,Lá,Lá♯,Si';

  @override
  String get micNotFound =>
      'Nenhum microfone encontrado. Conecte um ou escolha outra entrada.';

  @override
  String get micBusy =>
      'O microfone está em uso por outro app. Feche-o e tente de novo.';

  @override
  String get micQuietTip =>
      'Funciona melhor em silêncio: conversa, digitação ou música por perto podem soar como notas.';
}

/// The translations for Portuguese, as used in Brazil (`pt_BR`).
class AppLocalizationsPtBr extends AppLocalizationsPt {
  AppLocalizationsPtBr() : super('pt_BR');

  @override
  String gateProgress(int need, int have) {
    return 'Ganhe $need estrelas em qualquer uma destas músicas ($have/$need)';
  }
}
