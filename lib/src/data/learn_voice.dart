import 'package:flutter/foundation.dart';

import 'read_aloud.dart';

/// The voice in learning: says a verse, a tile, or any words, at the
/// reader's pace or slowly, and says whether it is speaking.
///
/// Practice and the rounds speak the way a language app does — the verse
/// as it appears, a tile as it is tapped, the verse again once an answer
/// is checked — so this is the one place those screens come to. The
/// engine is told how to sound only when first asked to speak, since for
/// OpenWord's own voice that means loading its model.
class LearnVoice extends ChangeNotifier {
  LearnVoice({
    required this.engine,
    required this.language,
    required this.rate,
    this.voice,
  });

  final SpeechEngine engine;
  final String language;

  /// The reader's chosen pace, as reading aloud uses it.
  final double rate;
  final String? voice;

  /// How much slower "slowly" is.
  static const double slowFactor = 0.65;

  bool get isAvailable => engine.isAvailable;

  bool _speaking = false;
  bool get isSpeaking => _speaking;

  bool _disposed = false;

  void _setSpeaking(bool value) {
    if (_disposed || _speaking == value) return;
    _speaking = value;
    notifyListeners();
  }

  double? _appliedRate;
  Future<void> _applying = Future.value();
  int _generation = 0;

  Future<void> _apply(double wanted) {
    if (_appliedRate == wanted) return _applying;
    _appliedRate = wanted;
    return _applying = _applying.then(
      (_) => engine
          .configure(language: language, rate: wanted, voice: voice)
          .catchError((Object _) {}),
    );
  }

  /// Says [text], stopping whatever was being said. Completes when it has
  /// been said, or cut short.
  Future<void> say(String text, {bool slow = false}) async {
    if (!isAvailable || text.isEmpty) return;
    final generation = ++_generation;
    await engine.stop();
    await _apply(slow ? rate * slowFactor : rate);
    if (generation != _generation) return;
    _setSpeaking(true);
    await engine.speak(ReadAloud.speakable(text));
    if (generation == _generation) _setSpeaking(false);
  }

  Future<void> stop() async {
    _generation++;
    await engine.stop();
    _setSpeaking(false);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    engine.stop();
    super.dispose();
  }
}
