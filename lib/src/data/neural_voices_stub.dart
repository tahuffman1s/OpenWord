import 'neural_voices.dart';
import 'read_aloud.dart';

/// The web has no filesystem to unpack the voice to, so nothing is read
/// aloud there.
NeuralVoices openNeuralVoices() => UnsupportedNeuralVoices();

class UnsupportedNeuralVoices extends NeuralVoices {
  @override
  bool get isSupported => false;

  @override
  Future<void> get ready => Future.value();

  @override
  SpeechEngine engine() => NoSpeechEngine();
}
