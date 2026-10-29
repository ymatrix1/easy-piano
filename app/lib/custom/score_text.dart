import '../l10n/app_localizations.dart';
import 'import_problem.dart';
import 'score_info.dart';

/// Plain-language text for each way an import can fail, with what to do next.
String importProblemText(AppLocalizations l, ImportProblem problem) =>
    switch (problem) {
      ImportProblem.unsupportedType => l.importProblemUnsupportedType,
      ImportProblem.empty => l.importProblemEmpty,
      ImportProblem.tooLarge => l.importProblemTooLarge,
      ImportProblem.unreadable => l.importProblemUnreadable,
      ImportProblem.noNotes => l.importProblemNoNotes,
      ImportProblem.unsupportedMusic => l.importProblemUnsupportedMusic,
      ImportProblem.duplicate => l.importProblemDuplicate,
      ImportProblem.libraryFull => l.importProblemLibraryFull,
      ImportProblem.storageFull => l.importProblemStorageFull,
      ImportProblem.unknown => l.importProblemUnknown,
    };

String scoreHandsText(AppLocalizations l, ScoreInfo info) {
  if (info.rightHand && !info.leftHand) return l.scoreHandsRight;
  if (info.leftHand && !info.rightHand) return l.scoreHandsLeft;
  return l.scoreHandsBoth;
}

String scoreLevelText(AppLocalizations l, ScoreLevel level) => switch (level) {
  ScoreLevel.beginner => l.scoreLevelBeginner,
  ScoreLevel.intermediate => l.scoreLevelIntermediate,
  ScoreLevel.advanced => l.scoreLevelAdvanced,
};
