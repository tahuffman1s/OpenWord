import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'read_aloud.dart';

/// Reading aloud as the system sees it: a media session, so it can go on
/// with the screen off and be paused or stepped from the lock screen, a
/// headset's buttons, or a car.
///
/// On Android that is a foreground service with a media notification; on
/// iOS and macOS the Now Playing controls; in a browser the Media Session
/// API. Windows and Linux have none here, and reading aloud works there as
/// before, with the app open.
class ReadAloudHandler extends BaseAudioHandler {
  /// [describe] names the session while it plays: the translation, say.
  ReadAloudHandler(this._voice, this._describe) {
    _voice.addListener(_publish);
    _publish();
  }

  ReadAloud _voice;
  String Function() _describe;

  ReadAloud get voice => _voice;

  /// Hands the session to another voice. The session lasts as long as the
  /// app, and a reader screen built again brings a voice of its own.
  void bind(ReadAloud voice, String Function() describe) {
    if (identical(voice, _voice)) {
      _describe = describe;
      return;
    }
    _voice.removeListener(_publish);
    _voice = voice;
    _describe = describe;
    voice.addListener(_publish);
    _publish();
  }

  /// What the lock screen shows and offers, from the state of the voice.
  static PlaybackState stateFor(ReadAloud voice) => PlaybackState(
    controls: voice.isActive
        ? [
            MediaControl.skipToPrevious,
            voice.isPlaying ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
            MediaControl.stop,
          ]
        : const [],
    systemActions: const {MediaAction.stop},
    // The three shown in Android's compact notification.
    androidCompactActionIndices: voice.isActive ? const [0, 1, 2] : null,
    processingState: voice.isActive
        ? AudioProcessingState.ready
        : AudioProcessingState.idle,
    playing: voice.isPlaying,
  );

  /// "Genesis 1:3", or the chapter while its name is announced.
  static MediaItem? itemFor(ReadAloud voice, String album) {
    final current = voice.current;
    if (current == null) return null;
    final title = current.verse == null
        ? ReadAloud.announcement(current).replaceAll('.', '')
        : current.label;
    return MediaItem(
      // One item per chapter, so the system does not treat every verse as
      // a new track and restart its display.
      id: '${current.bookCode}/${current.chapter}',
      title: title,
      album: album,
      artist: 'OpenWord',
    );
  }

  void _publish() {
    playbackState.add(stateFor(voice));
    final item = itemFor(voice, _describe());
    if (item != null) mediaItem.add(item);
  }

  @override
  Future<void> play() async =>
      voice.state == ReadAloudState.paused ? voice.resume() : null;

  @override
  Future<void> pause() async => voice.pause();

  @override
  Future<void> stop() async {
    voice.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async => voice.skip(1);

  @override
  Future<void> skipToPrevious() async => voice.skip(-1);

  /// A headset's single button, or a tap on the notification's own play
  /// button, arrives here.
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.next:
        voice.skip(1);
      case MediaButton.previous:
        voice.skip(-1);
      case MediaButton.media:
        voice.isPlaying ? voice.pause() : voice.resume();
    }
  }

  /// Lets go of a voice that is going away.
  void release(ReadAloud voice) {
    if (identical(voice, _voice)) voice.removeListener(_publish);
  }
}

/// Whether this platform has a media session to hand reading aloud to.
bool get mediaSessionSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Starts the system's media session for [voice], once per run of the app:
/// the session outlives any one screen, as a notification must.
///
/// A seam, so a test runs without a platform. Never throws: if the session
/// cannot be had, reading aloud goes on in the app as it did before there
/// was one.
Future<ReadAloudHandler?> Function(ReadAloud voice, String Function() describe)
startReadAloudSession = _startPlatformSession;

ReadAloudHandler? _session;

Future<ReadAloudHandler?> _startPlatformSession(
  ReadAloud voice,
  String Function() describe,
) async {
  if (!mediaSessionSupported) return null;
  final existing = _session;
  if (existing != null) {
    // AudioService is started once per run; a reader screen built again
    // hands its voice to the handler already registered.
    existing.bind(voice, describe);
    return existing;
  }
  try {
    _session = await AudioService.init(
      builder: () => ReadAloudHandler(voice, describe),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'org.openword.read_aloud',
        androidNotificationChannelName: 'Reading aloud',
        androidNotificationChannelDescription:
            'Shows what is being read aloud, with its controls',
        // Kept in the foreground while paused: Android 12 and later will
        // not let a service come back to the foreground from the lock
        // screen, so resuming from there would otherwise fail.
        androidStopForegroundOnPause: false,
        androidNotificationIcon: 'drawable/ic_read_aloud',
      ),
    );
    return _session;
  } on Object catch (error) {
    debugPrint('OpenWord: no media session for reading aloud: $error');
    return null;
  }
}
