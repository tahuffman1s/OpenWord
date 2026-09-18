import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../app_version.dart';
import 'update_target.dart';

/// Everything that needs a real operating system: one HTTPS request to the
/// GitHub API, a download with progress, and handing the result to whatever
/// installs software on this platform.
class NativeUpdateBackend implements UpdateBackend {
  NativeUpdateBackend({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Matches the channel the Android side listens on.
  static const String channelName = 'openword/updates';

  /// GitHub asks for a user agent and answers 403 without one.
  static const String userAgent =
      'OpenWord/$appVersion (+github.com/'
      '$releaseOwner/$releaseRepo)';

  final MethodChannel _channel;

  @override
  TargetKind get target {
    if (Platform.isAndroid) return TargetKind.android;
    if (Platform.isWindows) return TargetKind.windows;
    if (Platform.isLinux) return TargetKind.linux;
    return TargetKind.other;
  }

  @override
  bool get isSupported => true;

  /// Only Android: the desktop archives are unpacked wherever the reader
  /// keeps them, which is not the app's business, and iOS and macOS need a
  /// signed build from elsewhere.
  @override
  bool get canInstall => Platform.isAndroid;

  @override
  Future<String> readString(Uri url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close();
      if (response.statusCode != 200) {
        // Draining matters: an undrained response holds the socket open.
        await response.drain<void>();
        throw HttpException('GitHub answered ${response.statusCode}', uri: url);
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  @override
  Future<String> download(
    Uri url, {
    required String fileName,
    void Function(int received, int total)? onProgress,
  }) async {
    final directory = await _workingDirectory();
    final file = File('${directory.path}/$fileName');
    if (file.existsSync()) file.deleteSync();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException(
          'The download answered ${response.statusCode}',
          uri: url,
        );
      }

      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      return file.path;
    } finally {
      client.close();
    }
  }

  /// The APK has to be written somewhere the Android FileProvider is
  /// configured to share from, so the platform side names the directory.
  Future<Directory> _workingDirectory() async {
    if (Platform.isAndroid) {
      final path = await _channel.invokeMethod<String>('updateDirectory');
      if (path == null) {
        throw StateError('Android gave no place to download to');
      }
      return Directory(path)..createSync(recursive: true);
    }
    return Directory.systemTemp.createTemp('openword-update');
  }

  @override
  Future<void> install(String path) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('OpenWord cannot install updates here');
    }
    await _channel.invokeMethod<void>('install', {'path': path});
  }

  @override
  Future<void> uninstall() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('OpenWord cannot remove itself here');
    }
    await _channel.invokeMethod<void>('uninstall');
  }

  @override
  Future<void> openExternal(Uri url) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('open', {'url': url.toString()});
      return;
    }
    // Desktop: hand it to whatever the desktop uses for links. No plugin is
    // needed for three one-line commands.
    final (command, arguments) = switch (Platform.operatingSystem) {
      'linux' => ('xdg-open', [url.toString()]),
      'macos' => ('open', [url.toString()]),
      'windows' => ('cmd', ['/c', 'start', '', url.toString()]),
      _ => throw UnsupportedError('no way to open a link here'),
    };
    final result = await Process.run(command, arguments);
    if (result.exitCode != 0) {
      throw ProcessException(command, arguments, '${result.stderr}'.trim());
    }
  }
}

UpdateBackend createUpdateBackend() => NativeUpdateBackend();
