// Fetches the voice OpenWord reads aloud with, and makes it the bundled
// asset.
//
//   dart run tool/fetch_voice.dart
//
// The voice is KittenTTS nano 0.8 at full precision (Apache-2.0), as
// sherpa-onnx packages it. It is fifty-odd megabytes, too much to keep in
// the repository with every version of it, so it is fetched here instead —
// before building or testing, as CI does — checked against the SHA-256
// below, and written to assets/voice/kitten.tar.gz, which git ignores.
//
// Only what English needs is kept: the network, its voices and tokens, and
// eSpeak NG's English data. The other languages' dictionaries are 17 MB the
// voice never reads; leaving them out changes nothing it says (checked
// sample for sample).
//
// Run again, it does nothing if the asset is already there.
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

const archive = 'kitten-nano-en-v0_8-fp32';
const sha = '16092117bfe591ddcd58d078e1454603b8e1caea46f85653b2c2efae76bd883e';
const url =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
    '$archive.tar.bz2';
const output = 'assets/voice/kitten.tar.gz';

/// Kept from the archive: paths under its directory.
bool wanted(String path) {
  if (const {
    'model.fp32.onnx',
    'voices.bin',
    'tokens.txt',
    'LICENSE',
  }.contains(path)) {
    return true;
  }
  const data = 'espeak-ng-data/';
  if (!path.startsWith(data)) return false;
  final rest = path.substring(data.length);
  return const {
        'en_dict',
        'phondata',
        'phondata-manifest',
        'phonindex',
        'phontab',
        'intonations',
      }.contains(rest) ||
      rest.startsWith('voices/') ||
      rest.startsWith('lang/gmw/en');
}

Future<void> main() async {
  if (File(output).existsSync()) {
    stdout.writeln('$output is already there');
    return;
  }
  final temp = Directory.systemTemp.createTempSync('openword-voice');
  try {
    final download = File('${temp.path}/$archive.tar.bz2');
    stdout.writeln('Fetching $url');
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(Uri.parse(url))).close();
      if (response.statusCode != 200) {
        throw HttpException('answered ${response.statusCode}');
      }
      await response.pipe(download.openWrite());
    } finally {
      client.close();
    }
    final digest = sha256.convert(download.readAsBytesSync()).toString();
    if (digest != sha) {
      stderr.writeln('The download is not the voice expected: $digest');
      exitCode = 1;
      return;
    }

    final tar = '${temp.path}/$archive.tar';
    final input = InputFileStream(download.path);
    final out = OutputFileStream(tar);
    BZip2Decoder().decodeStream(input, out);
    await input.close();
    await out.close();

    final kept = Archive();
    final source = InputFileStream(tar);
    for (final file in TarDecoder().decodeStream(source)) {
      if (!file.isFile) continue;
      final path = file.name.replaceFirst(RegExp('^(\\./)?$archive/'), '');
      if (!wanted(path)) continue;
      kept.addFile(ArchiveFile.bytes('$archive/$path', file.content));
    }
    await source.close();

    File(output).parent.createSync(recursive: true);
    File(output).writeAsBytesSync(
      GZipEncoder().encodeBytes(TarEncoder().encodeBytes(kept)),
    );
    stdout.writeln(
      'Wrote $output: ${kept.length} files, '
      '${(File(output).lengthSync() / 1000000).toStringAsFixed(1)} MB',
    );
  } finally {
    temp.deleteSync(recursive: true);
  }
}
