import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/audio_helper.dart';

class VoiceNoteRecordedData {
  final String audioPath;
  final int durationMs;

  const VoiceNoteRecordedData({
    required this.audioPath,
    required this.durationMs,
  });
}

class VoiceNoteWidget extends StatefulWidget {
  final String? audioPath;
  final int? audioDurationMs;
  final bool autoStartRecording;
  final ValueChanged<VoiceNoteRecordedData> onAudioRecorded;
  final VoidCallback onAudioDeleted;

  const VoiceNoteWidget({
    super.key,
    required this.audioPath,
    this.audioDurationMs,
    this.autoStartRecording = false,
    required this.onAudioRecorded,
    required this.onAudioDeleted,
  });

  @override
  State<VoiceNoteWidget> createState() => _VoiceNoteWidgetState();
}

class _VoiceNoteWidgetState extends State<VoiceNoteWidget> with SingleTickerProviderStateMixin {
  // Playback state
  AudioPlayer? _audioPlayer;
  PlayerState _playerState = PlayerState.stopped;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _playbackSpeed = 1.0;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _compSub;

  // Recording state
  AudioRecorder? _audioRecorder;
  bool _isRecording = false;
  bool _isRecordingPaused = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  String? _tempAudioPath;

  // Pulse animation for recording
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.audioDurationMs != null && widget.audioDurationMs! > 0) {
      _totalDuration = Duration(milliseconds: widget.audioDurationMs!);
    }

    if (widget.audioPath != null && widget.audioPath!.isNotEmpty) {
      _initPlayer(widget.audioPath!);
    } else if (widget.autoStartRecording) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _startRecording();
        }
      });
    }
  }

  @override
  void didUpdateWidget(VoiceNoteWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.audioPath != oldWidget.audioPath) {
      if (widget.audioPath != null && widget.audioPath!.isNotEmpty) {
        _initPlayer(widget.audioPath!);
      } else {
        _disposePlayer();
      }
    }
    if (widget.audioDurationMs != oldWidget.audioDurationMs && widget.audioDurationMs != null) {
      _totalDuration = Duration(milliseconds: widget.audioDurationMs!);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _recordingTimer?.cancel();
    if (_isRecording && _audioRecorder != null) {
      _audioRecorder!.cancel().catchError((_) {});
    }
    _audioRecorder?.dispose();
    _disposePlayer();
    super.dispose();
  }

  // --- Audio Player Initialization ---
  void _initPlayer(String path) {
    _disposePlayer();
    _audioPlayer = AudioPlayer();

    _stateSub = _audioPlayer!.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _playerState = state;
        });
      }
    });

    _posSub = _audioPlayer!.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() {
          _currentPosition = pos;
        });
      }
    });

    _durSub = _audioPlayer!.onDurationChanged.listen((dur) {
      if (mounted && dur.inMilliseconds > 0) {
        setState(() {
          _totalDuration = dur;
        });
      }
    });

    _compSub = _audioPlayer!.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playerState = PlayerState.completed;
          _currentPosition = Duration.zero;
        });
      }
    });

    _audioPlayer!.setSource(DeviceFileSource(path)).catchError((_) {});
  }

  void _disposePlayer() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _compSub?.cancel();
    _audioPlayer?.dispose();
    _audioPlayer = null;
  }

  Future<void> _togglePlayPause() async {
    if (_audioPlayer == null || widget.audioPath == null) return;

    if (_playerState == PlayerState.playing) {
      await _audioPlayer!.pause();
    } else {
      if (_playerState == PlayerState.completed) {
        await _audioPlayer!.seek(Duration.zero);
      }
      await _audioPlayer!.play(DeviceFileSource(widget.audioPath!));
    }
  }

  Future<void> _seekTo(double valueMs) async {
    if (_audioPlayer == null) return;
    final target = Duration(milliseconds: valueMs.toInt());
    await _audioPlayer!.seek(target);
  }

  Future<void> _cyclePlaybackSpeed() async {
    if (_audioPlayer == null) return;
    double newSpeed;
    if (_playbackSpeed == 1.0) {
      newSpeed = 1.5;
    } else if (_playbackSpeed == 1.5) {
      newSpeed = 2.0;
    } else {
      newSpeed = 1.0;
    }

    setState(() {
      _playbackSpeed = newSpeed;
    });
    await _audioPlayer!.setPlaybackRate(newSpeed);
  }

  // --- Audio Recorder ---
  Future<void> _startRecording() async {
    try {
      _audioRecorder ??= AudioRecorder();

      final hasPermission = await _audioRecorder!.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is required to record audio')),
          );
        }
        return;
      }

      String basePath;
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        basePath = docsDir.path;
      } catch (_) {
        try {
          final tempDir = await getTemporaryDirectory();
          basePath = tempDir.path;
        } catch (_) {
          basePath = Directory.systemTemp.path;
        }
      }
      final audioDir = Directory('$basePath/voice_notes');
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
      }

      // Ensure any lingering session is cleanly ended
      if (await _audioRecorder!.isRecording()) {
        try {
          await _audioRecorder!.stop();
        } catch (_) {}
      }

      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _tempAudioPath = '${audioDir.path}/$fileName';

      // Multi-tier robust hardware codec configuration
      bool started = false;
      try {
        await _audioRecorder!.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            numChannels: 1,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: _tempAudioPath!,
        );
        started = true;
      } catch (_) {
        try {
          await _audioRecorder!.start(
            const RecordConfig(
              encoder: AudioEncoder.aacLc,
              numChannels: 1,
            ),
            path: _tempAudioPath!,
          );
          started = true;
        } catch (_) {
          try {
            await _audioRecorder!.start(
              const RecordConfig(numChannels: 1),
              path: _tempAudioPath!,
            );
            started = true;
          } catch (_) {
            await _audioRecorder!.start(
              const RecordConfig(),
              path: _tempAudioPath!,
            );
            started = true;
          }
        }
      }

      if (!started) {
        throw Exception('Audio recorder could not be initialized on this device.');
      }

      setState(() {
        _isRecording = true;
        _isRecordingPaused = false;
        _recordingDuration = Duration.zero;
      });

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && !_isRecordingPaused) {
          setState(() {
            _recordingDuration += const Duration(seconds: 1);
          });
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
    }
  }

  Future<void> _pauseResumeRecording() async {
    if (_audioRecorder == null || !_isRecording) return;
    if (_isRecordingPaused) {
      await _audioRecorder!.resume();
      setState(() {
        _isRecordingPaused = false;
      });
    } else {
      await _audioRecorder!.pause();
      setState(() {
        _isRecordingPaused = true;
      });
    }
  }

  Future<void> _stopAndSaveRecording() async {
    if (_audioRecorder == null || !_isRecording) return;
    _recordingTimer?.cancel();

    final finalPath = await _audioRecorder!.stop();
    final durationMs = _recordingDuration.inMilliseconds > 0
        ? _recordingDuration.inMilliseconds
        : 1000;

    setState(() {
      _isRecording = false;
      _isRecordingPaused = false;
    });

    if (finalPath != null && File(finalPath).existsSync()) {
      widget.onAudioRecorded(
        VoiceNoteRecordedData(
          audioPath: finalPath,
          durationMs: durationMs,
        ),
      );
    }
  }

  Future<void> _cancelRecording() async {
    if (_audioRecorder == null) return;
    _recordingTimer?.cancel();

    try {
      final path = await _audioRecorder!.stop();
      if (path != null) {
        final f = File(path);
        if (await f.exists()) {
          await f.delete();
        }
      }
    } catch (_) {}

    setState(() {
      _isRecording = false;
      _isRecordingPaused = false;
      _recordingDuration = Duration.zero;
      _tempAudioPath = null;
    });
  }

  Future<void> _confirmDeleteAudio() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        ),
        title: const Text('Delete Voice Recording'),
        content: const Text('Are you sure you want to delete this voice recording from this note?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _disposePlayer();
      widget.onAudioDeleted();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Mode 1: Active Recording in Progress
    if (_isRecording) {
      return _buildRecordingView(isDark);
    }

    // Mode 2: Audio Recorded — Full Player with Speed & Scrubbing
    if (widget.audioPath != null && widget.audioPath!.isNotEmpty) {
      return _buildPlayerView(isDark);
    }

    // Mode 3: No Audio Attached — Record Prompt Button
    return _buildAttachAudioPrompt(isDark);
  }

  Widget _buildRecordingView(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        border: Border.all(
          color: AppColors.danger.withAlpha(120),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.danger.withAlpha(20),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Pulsing recording red dot
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _isRecordingPaused ? 'RECORDING PAUSED' : 'RECORDING VOICE MEMO',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: _isRecordingPaused ? AppColors.accent : AppColors.danger,
                ),
              ),
              const Spacer(),
              // Elapsed Duration Counter
              Text(
                AudioHelper.formatTwoDigits(_recordingDuration),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Animated visualizer simulator bars
          SizedBox(
            height: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(24, (index) {
                final height = _isRecordingPaused
                    ? 4.0
                    : 6.0 + ((index * 7 + _recordingDuration.inSeconds * 9) % 18).toDouble();
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 3,
                  height: height,
                  decoration: BoxDecoration(
                    color: AppColors.danger.withAlpha(_isRecordingPaused ? 80 : 180),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),
          // Action buttons: Cancel, Pause/Resume, Finish
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.danger),
                label: const Text('Discard', style: TextStyle(color: AppColors.danger)),
                onPressed: _cancelRecording,
              ),
              IconButton.filledTonal(
                icon: Icon(
                  _isRecordingPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 22,
                ),
                tooltip: _isRecordingPaused ? 'Resume' : 'Pause',
                onPressed: _pauseResumeRecording,
              ),
              FilledButton.icon(
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Done'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: _stopAndSaveRecording,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerView(bool isDark) {
    final isPlaying = _playerState == PlayerState.playing;
    final maxMs = _totalDuration.inMilliseconds > 0 ? _totalDuration.inMilliseconds.toDouble() : 1.0;
    final currentMs = _currentPosition.inMilliseconds.toDouble().clamp(0.0, maxMs);

    final cardBg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final primaryTextColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Voice Memo Badge, Speed Pill, Delete Button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic_rounded, size: 13, color: AppColors.primary),
                    SizedBox(width: 4),
                    Text(
                      'Voice Memo',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Speed toggle pill: 1.0x / 1.5x / 2.0x
              InkWell(
                onTap: _cyclePlaybackSpeed,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_playbackSpeed}x',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: primaryTextColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Delete recording button
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.danger),
                tooltip: 'Delete recording',
                onPressed: _confirmDeleteAudio,
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Player Controls: Play/Pause Button + Seek Slider
          Row(
            children: [
              IconButton.filled(
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 26,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _togglePlayPause,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: (isDark ? Colors.white : Colors.black).withAlpha(20),
                        thumbColor: AppColors.primary,
                      ),
                      child: Slider(
                        value: currentMs,
                        min: 0.0,
                        max: maxMs,
                        onChanged: _seekTo,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            AudioHelper.formatDuration(_currentPosition),
                            style: TextStyle(
                              fontSize: 11,
                              color: secondaryTextColor,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          Text(
                            AudioHelper.formatDuration(_totalDuration),
                            style: TextStyle(
                              fontSize: 11,
                              color: secondaryTextColor,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttachAudioPrompt(bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.mic_none_rounded, size: 16),
          label: const Text('Record Voice Memo'),
          style: OutlinedButton.styleFrom(
            foregroundColor: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            side: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
            ),
          ),
          onPressed: _startRecording,
        ),
      ),
    );
  }
}
