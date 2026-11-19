import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/utils/audio_helper.dart';

enum PlaybackStatus {
  idle,
  loading,
  playing,
  paused,
  completed,
  error,
}

class VoicePlaybackState {
  final String? activeRecordingId;
  final PlaybackStatus status;
  final Duration position;
  final Duration duration;
  final String? errorMessage;

  const VoicePlaybackState({
    this.activeRecordingId,
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.errorMessage,
  });

  bool get isPlaying => status == PlaybackStatus.playing;
  bool get isLoading => status == PlaybackStatus.loading;
  bool get isPaused => status == PlaybackStatus.paused;
  bool get isCompleted => status == PlaybackStatus.completed;
  bool get isError => status == PlaybackStatus.error;
  bool get isIdle => status == PlaybackStatus.idle;

  bool isRecordingActive(String id) => activeRecordingId == id;
  bool isRecordingPlaying(String id) => activeRecordingId == id && isPlaying;
  bool isRecordingLoading(String id) => activeRecordingId == id && isLoading;
  bool isRecordingPaused(String id) => activeRecordingId == id && isPaused;

  PlayerState get playerState {
    switch (status) {
      case PlaybackStatus.playing:
        return PlayerState.playing;
      case PlaybackStatus.paused:
        return PlayerState.paused;
      case PlaybackStatus.completed:
        return PlayerState.completed;
      case PlaybackStatus.idle:
      case PlaybackStatus.loading:
      case PlaybackStatus.error:
        return PlayerState.stopped;
    }
  }

  VoicePlaybackState copyWith({
    String? activeRecordingId,
    bool clearActive = false,
    PlaybackStatus? status,
    Duration? position,
    Duration? duration,
    String? errorMessage,
    bool clearError = false,
  }) {
    return VoicePlaybackState(
      activeRecordingId: clearActive ? null : (activeRecordingId ?? this.activeRecordingId),
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class VoicePlayerNotifier extends StateNotifier<VoicePlaybackState> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _completeSub;
  StreamSubscription? _logSub;

  static final AudioContext _audioContext = AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: true,
      stayAwake: true,
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gain,
      audioMode: AndroidAudioMode.normal,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: const {
        AVAudioSessionOptions.defaultToSpeaker,
      },
    ),
  );

  VoicePlayerNotifier() : super(const VoicePlaybackState()) {
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await AudioPlayer.global.setAudioContext(_audioContext);
      await _player.setAudioContext(_audioContext);
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(1.0);
    } catch (_) {}

    _posSub = _player.onPositionChanged.listen((pos) {
      if (state.activeRecordingId != null) {
        state = state.copyWith(position: pos);
      }
    });

    _durSub = _player.onDurationChanged.listen((dur) {
      if (state.activeRecordingId != null && dur.inMilliseconds > 0) {
        state = state.copyWith(duration: dur);
      }
    });

    _stateSub = _player.onPlayerStateChanged.listen((pState) {
      if (state.activeRecordingId == null) return;
      if (pState == PlayerState.playing && state.status != PlaybackStatus.playing) {
        state = state.copyWith(status: PlaybackStatus.playing);
      } else if (pState == PlayerState.paused && state.status != PlaybackStatus.paused) {
        state = state.copyWith(status: PlaybackStatus.paused);
      } else if (pState == PlayerState.completed && state.status != PlaybackStatus.completed) {
        state = state.copyWith(status: PlaybackStatus.completed, position: Duration.zero);
      }
    });

    _completeSub = _player.onPlayerComplete.listen((_) {
      state = state.copyWith(
        status: PlaybackStatus.completed,
        position: Duration.zero,
      );
    });

    _logSub = _player.onLog.listen((log) {
      if (log.contains('Error') || log.contains('MEDIA_ERROR')) {
        if (state.status == PlaybackStatus.loading || state.status == PlaybackStatus.playing) {
          state = state.copyWith(
            status: PlaybackStatus.error,
            errorMessage: 'Playback error: $log',
          );
        }
      }
    });
  }

  Future<void> playRecording(String recordingId, String filePath) async {
    if (recordingId.isEmpty || filePath.isEmpty) {
      state = VoicePlaybackState(
        activeRecordingId: recordingId.isEmpty ? null : recordingId,
        status: PlaybackStatus.error,
        errorMessage: 'Invalid audio recording file path.',
      );
      return;
    }

    // 1. If currently playing this exact recording, toggle pause
    if (state.activeRecordingId == recordingId && state.isPlaying) {
      await pause();
      return;
    }

    // 2. If paused on this exact recording, resume
    if (state.activeRecordingId == recordingId && state.isPaused) {
      await resume();
      return;
    }

    // 3. If completed on this exact recording, replay from beginning
    if (state.activeRecordingId == recordingId && state.isCompleted) {
      try {
        await _player.seek(Duration.zero);
        await _player.resume();
        state = state.copyWith(status: PlaybackStatus.playing, position: Duration.zero);
      } catch (e) {
        state = state.copyWith(
          status: PlaybackStatus.error,
          errorMessage: 'Failed to restart audio: $e',
        );
      }
      return;
    }

    // 4. Starting fresh or switching recordings:
    // Step A: First verify audio file exists and is not 0 bytes on disk
    String? basePath;
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      basePath = appDocDir.path;
    } catch (_) {}

    final resolvedPath = await AudioHelper.resolveAudioPath(filePath, basePath);
    if (resolvedPath == null) {
      state = VoicePlaybackState(
        activeRecordingId: recordingId,
        status: PlaybackStatus.error,
        errorMessage: 'Audio file not found on device storage.',
      );
      return;
    }

    final file = File(resolvedPath);
    if (!await file.exists() || await file.length() == 0) {
      state = VoicePlaybackState(
        activeRecordingId: recordingId,
        status: PlaybackStatus.error,
        errorMessage: 'Audio recording file is empty or corrupted (0 bytes).',
      );
      return;
    }

    // Step B: Set state to LOADING before starting playback (do NOT set playing prematurely)
    state = VoicePlaybackState(
      activeRecordingId: recordingId,
      status: PlaybackStatus.loading,
      position: Duration.zero,
      duration: Duration.zero,
    );

    // Step C: Stop any previous playback session cleanly
    try {
      await _player.stop();
    } catch (_) {}

    // Step D: Ensure AudioContext & volume are correctly configured for loudspeaker
    try {
      await _player.setAudioContext(_audioContext);
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(1.0);

      // Step E: Play the verified local file
      await _player.play(DeviceFileSource(resolvedPath));

      // Step F: Transition to playing ONLY when play has initiated successfully
      state = state.copyWith(
        status: PlaybackStatus.playing,
        clearError: true,
      );
    } catch (e) {
      state = VoicePlaybackState(
        activeRecordingId: recordingId,
        status: PlaybackStatus.error,
        errorMessage: 'Failed to start audio playback: $e',
      );
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (_) {}
    state = state.copyWith(status: PlaybackStatus.paused);
  }

  Future<void> resume() async {
    try {
      await _player.resume();
      state = state.copyWith(status: PlaybackStatus.playing);
    } catch (e) {
      state = state.copyWith(
        status: PlaybackStatus.error,
        errorMessage: 'Failed to resume audio: $e',
      );
    }
  }

  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
      state = state.copyWith(position: position);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    state = const VoicePlaybackState();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _logSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}

final voicePlayerProvider = StateNotifierProvider<VoicePlayerNotifier, VoicePlaybackState>((ref) {
  return VoicePlayerNotifier();
});
