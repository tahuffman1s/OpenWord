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
  /// Made when the app starts, before there is anything to read; a voice
  /// is bound to it when reading aloud begins. [describe] names the
  /// session while it plays: the translation, say.
  ReadAloudHandler([ReadAloud? voice, String Function()? describe])
    : _describe = describe ?? (() => '') {
    if (voice != null) bind(voice, _describe);
    _publish();
  }

  ReadAloud? _voice;
  String Function() _describe;

  ReadAloud? get voice => _voice;

  /// Hands the session to a voice. The session lasts as long as the app,
  /// and a reader screen built again brings a voice of its own.
  void bind(ReadAloud voice, String Function() describe) {
    _describe = describe;
    if (identical(voice, _voice)) return;
    _voice?.removeListener(_publish);
    _voice = voice;
    voice.addListener(_publish);
    _publish();
  }

  /// What the lock screen shows and offers, from the state of the voice.
  static PlaybackState stateFor(ReadAloud? voice) => voice == null
      ? PlaybackState()
      : PlaybackState(
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
    final voice = _voice;
    playbackState.add(stateFor(voice));
    if (voice == null) return;
    final item = itemFor(voice, _describe());
    if (item != null) mediaItem.add(item);
  }

  @override
  Future<void> play() async =>
      voice?.state == ReadAloudState.paused ? voice!.resume() : null;

  @override
  Future<void> pause() async => voice?.pause();

  @override
  Future<void> stop() async {
    voice?.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async => voice?.skip(1);

  @override
  Future<void> skipToPrevious() async => voice?.skip(-1);

  /// A headset's single button, or a tap on the notification's own play
  /// button, arrives here.
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    final voice = _voice;
    if (voice == null) return;
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
    if (!identical(voice, _voice)) return;
    voice.removeListener(_publish);
    _voice = null;
  }
}

/// Whether this platform has a media session to hand reading aloud to.
bool get mediaSessionSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Starts the system's media session, once per run of the app. Called as
/// the app starts, which is how the plugin expects to be set up, and not
/// awaited: the first frame does not wait on it.
///
/// Never throws. If the session cannot be had, [readAloudSessionError]
/// says why, and reading aloud goes on with the app open.
Future<ReadAloudHandler?> prepareReadAloudSession() =>
    _starting ??= _startPlatformSession();

Future<ReadAloudHandler?>? _starting;

/// Why the media session could not be started, when it could not.
String? readAloudSessionError;

/// Binds [voice] to the system's media session, starting it if it was not
/// already. A seam, so a test runs without a platform.
Future<ReadAloudHandler?> Function(ReadAloud voice, String Function() describe)
startReadAloudSession = (voice, describe) async {
  final session = await prepareReadAloudSession();
  session?.bind(voice, describe);
  return session;
};

Future<ReadAloudHandler?> _startPlatformSession() async {
  if (!mediaSessionSupported) return null;
  try {
    return await AudioService.init(
      builder: ReadAloudHandler.new,
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
    ).timeout(const Duration(seconds: 20));
  } on Object catch (error) {
    readAloudSessionError = '$error';
    debugPrint('OpenWord: no media session for reading aloud: $error');
    return null;
  }
}
