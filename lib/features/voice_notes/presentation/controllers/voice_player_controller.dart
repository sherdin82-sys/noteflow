import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VoicePlaybackState {
  final String? activeRecordingId;
  final PlayerState playerState;
  final Duration position;
  final Duration duration;

  const VoicePlaybackState({
    this.activeRecordingId,
    this.playerState = PlayerState.stopped,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  bool get isPlaying => playerState == PlayerState.playing;
  bool isRecordingActive(String id) => activeRecordingId == id;
  bool isRecordingPlaying(String id) => activeRecordingId == id && isPlaying;

  VoicePlaybackState copyWith({
    String? activeRecordingId,
    bool clearActive = false,
    PlayerState? playerState,
    Duration? position,
    Duration? duration,
  }) {
    return VoicePlaybackState(
      activeRecordingId: clearActive ? null : (activeRecordingId ?? this.activeRecordingId),
      playerState: playerState ?? this.playerState,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }
}

class VoicePlayerNotifier extends StateNotifier<VoicePlaybackState> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _completeSub;

  VoicePlayerNotifier() : super(const VoicePlaybackState()) {
    _initListeners();
  }

  void _initListeners() {
    _posSub = _player.onPositionChanged.listen((pos) {
      state = state.copyWith(position: pos);
    });

    _durSub = _player.onDurationChanged.listen((dur) {
      state = state.copyWith(duration: dur);
    });

    _stateSub = _player.onPlayerStateChanged.listen((pState) {
      state = state.copyWith(playerState: pState);
    });

    _completeSub = _player.onPlayerComplete.listen((_) {
      state = state.copyWith(
        playerState: PlayerState.completed,
        position: Duration.zero,
      );
    });
  }

  Future<void> playRecording(String recordingId, String filePath) async {
    if (filePath.isEmpty) return;

    // If currently playing this exact recording, toggle pause
    if (state.activeRecordingId == recordingId && state.isPlaying) {
      await pause();
      return;
    }

    // If paused on this exact recording, resume
    if (state.activeRecordingId == recordingId && state.playerState == PlayerState.paused) {
      await resume();
      return;
    }

    // Switching to a different recording or starting fresh
    await _player.stop();
    state = VoicePlaybackState(
      activeRecordingId: recordingId,
      playerState: PlayerState.playing,
    );

    try {
      await _player.play(DeviceFileSource(filePath));
    } catch (_) {
      state = state.copyWith(playerState: PlayerState.stopped, clearActive: true);
    }
  }

  Future<void> pause() async {
    await _player.pause();
    state = state.copyWith(playerState: PlayerState.paused);
  }

  Future<void> resume() async {
    await _player.resume();
    state = state.copyWith(playerState: PlayerState.playing);
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    state = state.copyWith(position: position);
  }

  Future<void> stop() async {
    await _player.stop();
    state = const VoicePlaybackState();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}

final voicePlayerProvider = StateNotifierProvider<VoicePlayerNotifier, VoicePlaybackState>((ref) {
  return VoicePlayerNotifier();
});
