import 'package:flutter/foundation.dart';

import 'neural_voices_stub.dart'
    if (dart.library.io) 'neural_voices_io.dart'
    as platform;
import 'read_aloud.dart';

/// One voice of a model: a speaker it was trained on.
@immutable
class NeuralSpeaker {
  const NeuralSpeaker(this.id, this.name, this.locale);

  /// The speaker's number in the model.
  final int id;
  final String name;
  final String locale;
}

/// The voice OpenWord reads aloud with: an open neural text-to-speech
/// model, run on the device with sherpa-onnx.
///
/// It ships inside the app, as the asset `tool/fetch_voice.dart` makes, and
/// is unpacked into the app's support directory the first time it is
/// needed. Nothing is fetched and nothing leaves the device.
@immutable
class NeuralModel {
  const NeuralModel({
    required this.id,
    required this.title,
    required this.archive,
    required this.modelFile,
    required this.speakers,
  });

  /// Short and stable: it is part of the voice name kept in settings.
  final String id;
  final String title;

  /// The directory the model unpacks to, named as sherpa-onnx names its
  /// archive.
  final String archive;

  /// The network itself, among the files it unpacks.
  final String modelFile;

  final List<NeuralSpeaker> speakers;

  /// KittenTTS nano 0.8 (Apache-2.0), at full precision. The 8-bit edition
  /// is half the size but now and then garbles a sound — KittenML itself
  /// warns of it — and on the processors tried it is slower, not quicker:
  /// turning its numbers back and forth costs more than it saves.
  static const kitten = NeuralModel(
    id: 'kitten',
    title: 'Kitten',
    archive: 'kitten-nano-en-v0_8-fp32',
    modelFile: 'model.fp32.onnx',
    speakers: [
      NeuralSpeaker(1, 'Bella', 'en-US'),
      NeuralSpeaker(0, 'Jasper', 'en-US'),
      NeuralSpeaker(3, 'Luna', 'en-US'),
      NeuralSpeaker(2, 'Bruno', 'en-US'),
      NeuralSpeaker(5, 'Rosie', 'en-US'),
      NeuralSpeaker(4, 'Hugo', 'en-US'),
      NeuralSpeaker(7, 'Kiki', 'en-US'),
      NeuralSpeaker(6, 'Leo', 'en-US'),
    ],
  );

  static const List<NeuralModel> catalog = [kitten];

  static const String _prefix = 'openword:';

  /// The name a voice of this model is kept by in settings.
  String voiceName(NeuralSpeaker speaker) => '$_prefix$id:${speaker.id}';

  /// The model and speaker a kept voice name means, or null for a name
  /// this version does not know — a voice of the device's that an earlier
  /// version read with, say.
  static (NeuralModel, NeuralSpeaker)? parse(String? voice) {
    if (voice == null || !voice.startsWith(_prefix)) return null;
    final parts = voice.substring(_prefix.length).split(':');
    if (parts.length != 2) return null;
    final id = int.tryParse(parts[1]);
    for (final model in catalog) {
      if (model.id != parts[0]) continue;
      for (final speaker in model.speakers) {
        if (speaker.id == id) return (model, speaker);
      }
    }
    return null;
  }

  /// The voice a kept name means, or the first voice where it means none.
  static (NeuralModel, NeuralSpeaker) chosen(String? voice) =>
      parse(voice) ?? (kitten, kitten.speakers.first);

  /// How the voices of this model are offered.
  List<SpeechVoice> get voices => [
    for (final speaker in speakers)
      SpeechVoice(
        name: voiceName(speaker),
        title: speaker.name,
        locale: speaker.locale,
      ),
  ];
}

/// The voice on this device, made ready to speak.
///
/// Where the platform has no filesystem to unpack it to — the web — it is
/// not supported, and nothing offers to read aloud.
abstract class NeuralVoices extends ChangeNotifier {
  bool get isSupported;

  /// Settles once the voice has been unpacked, the first time it is
  /// needed, or found already unpacked.
  Future<void> get ready;

  /// Speaks with the voice. Only called where [isSupported].
  SpeechEngine engine();

  /// Where this device has been found to make speech more slowly than it
  /// is heard, so that reading pauses between sentences.
  bool get fallingBehind => false;
}

/// The device's voice. A test puts its own in its place.
NeuralVoices neuralVoices = platform.openNeuralVoices();
