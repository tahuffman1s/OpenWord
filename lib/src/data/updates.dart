import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../app_version.dart';
import 'settings.dart';
import 'update_backend.dart';

/// A version as a release tags it: `v1.4.0`, `1.4.0+5`, `1.5.0-beta.1`.
@immutable
class AppRelease implements Comparable<AppRelease> {
  const AppRelease(this.numbers, this.preRelease);

  /// Parses a tag, or null if it is not a version at all. A leading `v` and
  /// anything after `+` (the build number) are dropped; a `-suffix` marks a
  /// pre-release, which sorts *before* the same version without one.
  static AppRelease? parse(String text) {
    var body = text.trim();
    if (body.startsWith('v') || body.startsWith('V')) body = body.substring(1);
    final plus = body.indexOf('+');
    if (plus >= 0) body = body.substring(0, plus);

    String? preRelease;
    final dash = body.indexOf('-');
    if (dash >= 0) {
      preRelease = body.substring(dash + 1);
      body = body.substring(0, dash);
    }

    final numbers = <int>[];
    for (final part in body.split('.')) {
      final value = int.tryParse(part);
      if (value == null || value < 0) return null;
      numbers.add(value);
    }
    if (numbers.isEmpty) return null;
    return AppRelease(numbers, preRelease);
  }

  final List<int> numbers;
  final String? preRelease;

  @override
  int compareTo(AppRelease other) {
    final length = numbers.length > other.numbers.length
        ? numbers.length
        : other.numbers.length;
    for (var i = 0; i < length; i++) {
      final mine = i < numbers.length ? numbers[i] : 0;
      final theirs = i < other.numbers.length ? other.numbers[i] : 0;
      if (mine != theirs) return mine.compareTo(theirs);
    }
    if (preRelease == other.preRelease) return 0;
    // 1.5.0-beta comes before 1.5.0.
    if (preRelease == null) return 1;
    if (other.preRelease == null) return -1;
    return preRelease!.compareTo(other.preRelease!);
  }

  bool isNewerThan(AppRelease other) => compareTo(other) > 0;

  @override
  String toString() =>
      numbers.join('.') + (preRelease == null ? '' : '-$preRelease');

  @override
  bool operator ==(Object other) =>
      other is AppRelease && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}

/// A file attached to a release.
@immutable
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final Uri url;
  final int size;

  String get readableSize {
    const mb = 1024 * 1024;
    if (size >= mb) return '${(size / mb).toStringAsFixed(1)} MB';
    return '${(size / 1024).round()} kB';
  }
}

/// A published release, as GitHub describes it.
@immutable
class Release {
  const Release({
    required this.version,
    required this.tag,
    required this.name,
    required this.notes,
    required this.page,
    required this.assets,
  });

  final AppRelease version;
  final String tag;
  final String name;

  /// The release notes, in the Markdown GitHub stores them as.
  final String notes;
  final Uri page;
  final List<ReleaseAsset> assets;

  /// The file this platform can install, if the release carries one.
  ReleaseAsset? assetFor(TargetKind target) {
    final suffix = switch (target) {
      TargetKind.android => '-android.apk',
      TargetKind.windows => '-windows-x64.zip',
      TargetKind.linux => '-linux-x64.tar.gz',
      TargetKind.other => null,
    };
    if (suffix == null) return null;
    for (final asset in assets) {
      if (asset.name.endsWith(suffix)) return asset;
    }
    return null;
  }

  static Release? parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;

    final tag = decoded['tag_name'];
    if (tag is! String) return null;
    final version = AppRelease.parse(tag);
    if (version == null) return null;
    if (decoded['draft'] == true || decoded['prerelease'] == true) return null;

    final assets = <ReleaseAsset>[];
    for (final raw in (decoded['assets'] as List<Object?>?) ?? const []) {
      if (raw is! Map) continue;
      final name = raw['name'];
      final url = Uri.tryParse('${raw['browser_download_url']}');
      if (name is! String || url == null) continue;
      assets.add(
        ReleaseAsset(
          name: name,
          url: url,
          size: (raw['size'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    return Release(
      version: version,
      tag: tag,
      name: decoded['name'] as String? ?? tag,
      notes: decoded['body'] as String? ?? '',
      page:
          Uri.tryParse('${decoded['html_url']}') ??
          Uri.parse(
            'https://github.com/$releaseOwner/$releaseRepo/releases/latest',
          ),
      assets: assets,
    );
  }
}

/// What the update machinery is doing, for the sheet and the settings page to
/// show.
enum UpdateStage {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  readyToInstall,
  failed,
}

/// Checks GitHub for a newer release, fetches it where the platform allows,
/// and hands it to the system installer.
///
/// This is the only part of OpenWord that touches the network. It asks for
/// one small JSON document, at most once a day, and only while the reader
/// leaves the switch in Settings on.
class UpdateService extends ChangeNotifier {
  UpdateService({
    required this.settings,
    UpdateBackend? backend,
    String currentVersion = appVersion,
    Uri? endpoint,
    DateTime Function() clock = DateTime.now,
  }) : _now = clock,
       _backend = backend ?? createUpdateBackend(),
       _current =
           AppRelease.parse(currentVersion) ?? const AppRelease([0], null),
       _endpoint =
           endpoint ??
           Uri.parse(
             'https://api.github.com/repos/$releaseOwner/$releaseRepo'
             '/releases/latest',
           );

  /// How long to leave it between automatic checks.
  static const Duration checkInterval = Duration(days: 1);

  final Settings settings;
  final UpdateBackend _backend;
  final AppRelease _current;
  final Uri _endpoint;
  final DateTime Function() _now;

  UpdateStage _stage = UpdateStage.idle;
  Release? _release;
  String? _error;
  double? _progress;
  String? _downloaded;

  UpdateStage get stage => _stage;
  Release? get release => _release;
  String? get error => _error;

  /// 0–1 while a download runs, or null when its size is not known.
  double? get progress => _progress;

  AppRelease get currentVersion => _current;
  TargetKind get target => _backend.target;

  /// False on the web, where the page is whatever the server last served.
  bool get isSupported => _backend.isSupported;

  /// True where the app can install the update itself rather than sending the
  /// reader to a browser.
  bool get canInstall => _backend.canInstall;

  /// The file for this platform, when there is a release with one.
  ReleaseAsset? get asset => _release?.assetFor(_backend.target);

  bool get updateAvailable =>
      _release != null && _release!.version.isNewerThan(_current);

  /// Checks at most once a day unless [force]d, and never at all where the
  /// reader has turned the check off or the platform cannot use it.
  Future<void> check({bool force = false}) async {
    if (!isSupported) return;
    if (!force) {
      if (!settings.checkForUpdates) return;
      final last = settings.lastUpdateCheck;
      if (last != null && _now().difference(last) < checkInterval) return;
    }
    if (_stage == UpdateStage.checking || _stage == UpdateStage.downloading) {
      return;
    }

    _set(UpdateStage.checking, error: null);
    try {
      final body = await _backend.readString(_endpoint);
      final release = Release.parse(body);
      settings.lastUpdateCheck = _now();
      if (release == null) {
        _set(UpdateStage.failed, error: 'GitHub sent something unexpected.');
        return;
      }
      _release = release;
      _set(
        release.version.isNewerThan(_current)
            ? UpdateStage.available
            : UpdateStage.upToDate,
      );
    } on Object catch (error) {
      _set(UpdateStage.failed, error: _readable(error));
    }
  }

  /// Fetches the release file for this platform, reporting progress.
  Future<void> download() async {
    final wanted = asset;
    if (wanted == null || !canInstall) return;

    _progress = null;
    _set(UpdateStage.downloading, error: null);
    try {
      final path = await _backend.download(
        wanted.url,
        fileName: wanted.name,
        onProgress: (received, total) {
          _progress = total > 0 ? received / total : null;
          notifyListeners();
        },
      );
      _downloaded = path;
      _set(UpdateStage.readyToInstall);
    } on Object catch (error) {
      _set(UpdateStage.failed, error: _readable(error));
    }
  }

  /// Hands the downloaded file to the system installer. Android shows its own
  /// confirmation; nothing is installed behind the reader's back.
  Future<void> install() async {
    final path = _downloaded;
    if (path == null) return;
    try {
      await _backend.install(path);
    } on Object catch (error) {
      _set(UpdateStage.failed, error: _readable(error));
    }
  }

  /// Opens the release page, for the platforms the app cannot install itself.
  Future<void> openReleasePage() async {
    final release = _release;
    if (release == null) return;
    try {
      await _backend.openExternal(release.page);
    } on Object catch (error) {
      _set(UpdateStage.failed, error: _readable(error));
    }
  }

  /// Stops the launch check mentioning this version again. Settings still
  /// shows it, and "Check now" still finds it.
  void skipThisVersion() {
    final release = _release;
    if (release == null) return;
    settings.skippedUpdate = release.version.toString();
    notifyListeners();
  }

  bool get isSkipped =>
      _release != null &&
      settings.skippedUpdate == _release!.version.toString();

  /// True when a new version is worth interrupting the reader for.
  bool get shouldAnnounce => updateAvailable && !isSkipped;

  void _set(UpdateStage stage, {String? error}) {
    _stage = stage;
    if (stage != UpdateStage.failed) {
      _error = null;
    } else if (error != null) {
      _error = error;
    }
    notifyListeners();
  }

  static String _readable(Object error) {
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup')) {
      return 'No connection to GitHub.';
    }
    return text;
  }
}
