import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app_version.dart';

/// Where the source of the eSpeak NG that sherpa-onnx 1.13.8 compiles in
/// can be had: its fork, at the commit its build fetches.
const String espeakSource =
    'https://github.com/csukuangfj/espeak-ng/tree/'
    'ed530aa113046142eb5115cf2fc9157854d0ffe1';

/// Who made the voice reading aloud is heard in, and under what licences,
/// as Settings shows it.
///
/// eSpeak NG is GPL-3.0 and is compiled into the library the voice runs
/// on, so the app as built is distributed under the GPL's terms too; the
/// GPL asks that whoever has it can have the source, and says so here.
const String voiceAttribution =
    'KittenTTS nano 0.8 by KittenML, Apache-2.0, run with sherpa-onnx '
    '(Apache-2.0) and ONNX Runtime (MIT). Its pronunciation comes from '
    'eSpeak NG, GPL-3.0, which is built into it, so this app as built is '
    'also under the GPL-3.0. Source: github.com/$releaseOwner/$releaseRepo, '
    'and for eSpeak NG $espeakSource.';

/// Adds the licences of what the voice is made of to those the app shows.
/// Flutter lists its packages' own already — sherpa-onnx's among them —
/// but not the voice's model, nor the libraries sherpa-onnx carries.
void registerVoiceLicences({AssetBundle? bundle}) {
  final assets = bundle ?? rootBundle;
  LicenseRegistry.addLicense(() async* {
    final apache = await assets.loadString('assets/licences/Apache-2.0.txt');
    final gpl = await assets.loadString('assets/licences/GPL-3.0.txt');
    final mit = await assets.loadString('assets/licences/onnxruntime-MIT.txt');
    yield LicenseEntryWithLineBreaks(const [
      'KittenTTS',
    ], 'KittenTTS nano 0.8, copyright KittenML.\n\n$apache');
    yield LicenseEntryWithLineBreaks(
      const ['eSpeak NG'],
      'eSpeak NG, copyright Jonathan Duddington, Reece H. Dunn and its '
      'contributors. Its source, as built into this app: '
      '$espeakSource\n\n$gpl',
    );
    yield LicenseEntryWithLineBreaks(const ['ONNX Runtime'], mit);
  });
}
