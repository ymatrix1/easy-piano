import 'package:flutter/foundation.dart';

/// A song that grows while it is played (streaming practice,
/// docs/specs/practice-mode.md). The owner pushes the whole song with bars
/// appended; [PracticeStage] extends its session and keeps going. The stage
/// reports how many beats are left through [onDemand] so the owner can
/// generate ahead, and finishes only after [end].
class SongFeed extends ChangeNotifier {
  SongFeed(this._json);

  String _json;
  bool _ended = false;

  String get json => _json;
  bool get ended => _ended;

  /// Called from the stage's ticker with the beats left before the last note.
  void Function(double beatsLeft)? onDemand;

  void push(String json) {
    _json = json;
    notifyListeners();
  }

  /// No more bars will come: the stage may finish.
  void end() {
    _ended = true;
    notifyListeners();
  }
}
