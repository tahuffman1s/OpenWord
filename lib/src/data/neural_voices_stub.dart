import 'neural_voices.dart';
import 'read_aloud.dart';

/// The web has no filesystem to keep a model on, and the browser's own
/// voices are what it reads with.
NeuralVoices openNeuralVoices() => UnsupportedNeuralVoices();

class UnsupportedNeuralVoices extends NeuralVoices {
  @override
  bool get isSupported => false;

  @override
  Future<void> get ready => Future.value();

  @override
  bool isInstalled(NeuralModel model) => false;

  @override
  double? progress(NeuralModel model) => null;

  @override
  String? error(NeuralModel model) => null;

  @override
  Future<void> install(NeuralModel model) async {}

  @override
  void cancel(NeuralModel model) {}

  @override
  Future<void> remove(NeuralModel model) async {}

  @override
  SpeechEngine engine() => throw UnsupportedError('No neural voices here');
}
