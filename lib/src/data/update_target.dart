/// The platforms the update machinery treats differently.
enum TargetKind {
  android,
  windows,
  linux,

  /// iOS, macOS and the web: releases carry nothing they can install, so the
  /// app points at the release page instead.
  other,
}

/// Everything the updater needs from the platform it is running on.
///
/// Split out behind a conditional import for two reasons: the web build has
/// no `dart:io` to fetch or save anything with, and a fake here lets the
/// tests exercise the whole flow without a network.
abstract class UpdateBackend {
  TargetKind get target;

  /// False where updating makes no sense — the web, where the page came from
  /// a server that already has whatever version it has.
  bool get isSupported;

  /// True where the app can fetch and install the update itself.
  bool get canInstall;

  Future<String> readString(Uri url);

  /// Downloads to a working directory and returns the path written.
  Future<String> download(
    Uri url, {
    required String fileName,
    void Function(int received, int total)? onProgress,
  });

  /// Hands a downloaded file to the system installer.
  Future<void> install(String path);

  /// Opens the system's prompt to remove the installed copy. Needed where a
  /// release was signed with a different key than the copy on the device:
  /// Android will not replace one with the other.
  Future<void> uninstall();

  /// Opens a link outside the app.
  Future<void> openExternal(Uri url);
}
