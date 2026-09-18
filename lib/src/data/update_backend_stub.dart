import 'update_target.dart';

/// The web build. There is nothing to update: the page is whatever the server
/// served, and a browser cannot install anything anyway.
class WebUpdateBackend implements UpdateBackend {
  const WebUpdateBackend();

  @override
  TargetKind get target => TargetKind.other;

  @override
  bool get isSupported => false;

  @override
  bool get canInstall => false;

  @override
  Future<String> readString(Uri url) =>
      throw UnsupportedError('OpenWord does not check for updates on the web');

  @override
  Future<String> download(
    Uri url, {
    required String fileName,
    void Function(int received, int total)? onProgress,
  }) => throw UnsupportedError('nothing to download on the web');

  @override
  Future<void> install(String path) =>
      throw UnsupportedError('nothing to install on the web');

  @override
  Future<void> uninstall() =>
      throw UnsupportedError('nothing to uninstall on the web');

  @override
  Future<void> openExternal(Uri url) =>
      throw UnsupportedError('no link to open on the web');
}

UpdateBackend createUpdateBackend() => const WebUpdateBackend();
