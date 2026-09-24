import 'package:flutter/foundation.dart';

import 'neural_voices_stub.dart'
    if (dart.library.io) 'neural_voices_io.dart'
    as platform;
import 'read_aloud.dart';

/// Which kind of network a model is, which decides how it is loaded.
enum NeuralFamily { kitten, kokoro }

/// One voice of a model: a speaker it was trained on.
@immutable
class NeuralSpeaker {
  const NeuralSpeaker(this.id, this.name, this.locale);

  /// The speaker's number in the model.
  final int id;
  final String name;
  final String locale;
}

/// A voice OpenWord can speak with itself, rather than through the
/// platform: an open neural text-to-speech model, run on the device with
/// sherpa-onnx.
///
/// None ships inside the app — the smallest is thirty megabytes — so each
/// is downloaded when someone asks for it, checked against the checksum
/// here, and kept. From then on it speaks with no connection at all.
@immutable
class NeuralModel {
  const NeuralModel({
    required this.id,
    required this.title,
    required this.blurb,
    required this.family,
    required this.archive,
    required this.modelFile,
    required this.bytes,
    required this.sha256,
    required this.speakers,
  });

  /// Short and stable: it is part of the voice name kept in settings.
  final String id;
  final String title;
  final String blurb;
  final NeuralFamily family;

  /// The name of the model's archive among sherpa-onnx's releases, and of
  /// the directory it unpacks to.
  final String archive;

  /// The network itself, among the files the archive unpacks.
  final String modelFile;

  /// The size of the download.
  final int bytes;

  /// Of the archive, so a download that is damaged or not what it claims
  /// to be is never unpacked.
  final String sha256;

  final List<NeuralSpeaker> speakers;

  Uri get url => Uri.parse(
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
    '$archive.tar.bz2',
  );

  /// "31 MB".
  String get size => '${(bytes / 1000000).round()} MB';

  /// KittenTTS nano 0.8 (Apache-2.0): small and quick, and still far more
  /// natural than most voices a device comes with.
  ///
  /// At full precision. The 8-bit edition is half the download, but now
  /// and then garbles a sound — KittenML itself warns of it — and on the
  /// processors tried it is slower, not quicker: turning its numbers back
  /// and forth costs more than it saves.
  static const kitten = NeuralModel(
    id: 'kitten',
    title: 'Kitten',
    blurb: 'Light and quick, for any phone',
    family: NeuralFamily.kitten,
    archive: 'kitten-nano-en-v0_8-fp32',
    modelFile: 'model.fp32.onnx',
    bytes: 63815222,
    sha256: '16092117bfe591ddcd58d078e1454603b8e1caea46f85653b2c2efae76bd883e',
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

  /// Kokoro 82M (Apache-2.0), quantised: the most natural open voice of
  /// its size, American and British, and slower to produce — a recent
  /// phone keeps up with it; an older one may pause between sentences.
  static const kokoro = NeuralModel(
    id: 'kokoro',
    title: 'Kokoro',
    blurb: 'The most natural, for recent phones',
    family: NeuralFamily.kokoro,
    archive: 'kokoro-int8-en-v0_19',
    modelFile: 'model.int8.onnx',
    bytes: 103248205,
    sha256: 'c9f0dd393615805b0bab050c340834d5e684e732aec91c0e860cd30e982c08bd',
    speakers: [
      NeuralSpeaker(1, 'Bella', 'en-US'),
      NeuralSpeaker(6, 'Michael', 'en-US'),
      NeuralSpeaker(3, 'Sarah', 'en-US'),
      NeuralSpeaker(5, 'Adam', 'en-US'),
      NeuralSpeaker(2, 'Nicole', 'en-US'),
      NeuralSpeaker(4, 'Sky', 'en-US'),
      NeuralSpeaker(7, 'Emma', 'en-GB'),
      NeuralSpeaker(9, 'George', 'en-GB'),
      NeuralSpeaker(8, 'Isabella', 'en-GB'),
      NeuralSpeaker(10, 'Lewis', 'en-GB'),
    ],
  );

  static const List<NeuralModel> catalog = [kitten, kokoro];

  /// Both speak English only.
  static bool speaks(String language) =>
      language.toLowerCase().startsWith('en');

  static const String _prefix = 'openword:';

  /// The name a voice of this model is kept by in settings, told apart
  /// from any the platform offers by its prefix.
  String voiceName(NeuralSpeaker speaker) => '$_prefix$id:${speaker.id}';

  /// The model and speaker a kept voice name means, or null for a voice of
  /// the platform's.
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

  /// How the voices of this model appear beside the platform's.
  List<SpeechVoice> get voices => [
    for (final speaker in speakers)
      SpeechVoice(
        name: voiceName(speaker),
        title: '${speaker.name} · $title',
        locale: speaker.locale,
        quality: 4,
        builtIn: true,
      ),
  ];
}

/// The models on this device, and getting more.
///
/// Where the platform has no filesystem or the runtime has no build for
/// it — the web, and Linux, which has no read-aloud at all — nothing is
/// supported and nothing is offered.
abstract class NeuralVoices extends ChangeNotifier {
  bool get isSupported;

  /// Settles once the models already downloaded have been found.
  Future<void> get ready;

  bool isInstalled(NeuralModel model);

  /// How far a download has got, from 0 to 1, while there is one.
  double? progress(NeuralModel model);

  /// Why the last download of [model] failed, if it did.
  String? error(NeuralModel model);

  /// Downloads, checks and unpacks a model. Never throws: a failure is
  /// kept in [error].
  Future<void> install(NeuralModel model);

  /// Stops a download in progress.
  void cancel(NeuralModel model);

  Future<void> remove(NeuralModel model);

  /// Speaks with the voices downloaded here. Only called where
  /// [isSupported].
  SpeechEngine engine();

  /// A model this device has been found to make speech with more slowly
  /// than it is heard, so that reading with it pauses between sentences.
  NeuralModel? get fallingBehind => null;

  /// The installed voices that can read [language], best first.
  List<SpeechVoice> voicesFor(String language) => [
    if (NeuralModel.speaks(language))
      for (final model in NeuralModel.catalog.reversed)
        if (isInstalled(model)) ...model.voices,
  ];
}

/// The device's models. A test puts its own in their place.
NeuralVoices neuralVoices = platform.openNeuralVoices();
