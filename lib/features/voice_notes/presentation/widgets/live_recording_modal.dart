import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/audio_helper.dart';
import '../../../../shared/models/voice_recording_entity.dart';

class LiveRecordingModal extends StatefulWidget {
  final String voiceNoteId;
  final int nextSortOrder;
  final String? defaultTitle;

  const LiveRecordingModal({
    super.key,
    required this.voiceNoteId,
    required this.nextSortOrder,
    this.defaultTitle,
  });

  @override
  State<LiveRecordingModal> createState() => _LiveRecordingModalState();
}

class _LiveRecordingModalState extends State<LiveRecordingModal> with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  late final AnimationController _pulseController;
  late final TextEditingController _titleController;

  Timer? _durationTimer;
  Timer? _amplitudeTimer;

  Duration _elapsed = Duration.zero;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isSaving = false;
  bool _hasPermission = true;
  bool _isInitializing = true;
  String? _initError;
  String? _currentRecordingPath;
  String? _recordingId;

  // Waveform visualization values
  final List<double> _waveformAmplitudes = List.filled(24, 0.15);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _titleController = TextEditingController(
      text: widget.defaultTitle ?? 'Recording ${widget.nextSortOrder + 1}',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _startRecording();
      }
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _amplitudeTimer?.cancel();
    _pulseController.dispose();
    _titleController.dispose();
    if (_isRecording) {
      _recorder.cancel().catchError((_) {});
      if (_currentRecordingPath != null) {
        final f = File(_currentRecordingPath!);
        f.exists().then((exists) {
          if (exists) f.delete().catchError((_) => f);
        });
      }
    }
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    setState(() {
      _isInitializing = true;
      _initError = null;
    });

    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          setState(() {
            _hasPermission = false;
            _isInitializing = false;
            _initError = 'Microphone permission is required to record audio memos.';
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _hasPermission = true;
        });
      }

      // Ensure any existing recording session is cleanly finalized before starting
      try {
        if (await _recorder.isRecording()) {
          await _recorder.stop();
        }
      } catch (_) {}

      String basePath;
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        basePath = appDocDir.path;
      } catch (_) {
        try {
          final tempDir = await getTemporaryDirectory();
          basePath = tempDir.path;
        } catch (_) {
          basePath = Directory.systemTemp.path;
        }
      }
      final dir = Directory('$basePath/voice_notes/${widget.voiceNoteId}');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _recordingId = const Uuid().v4();
      final filePath = '${dir.path}/$_recordingId.m4a';
      _currentRecordingPath = filePath;

      // Multi-tier robust hardware codec configuration:
      // Tier 1: AAC-LC Mono 128kbps / 44.1kHz (High quality, standard)
      // Tier 2: AAC-LC Mono (device-native sample rate & bitrate)
      // Tier 3: Default hardware encoder Mono
      // Tier 4: Fallback default configuration
      bool started = false;
      try {
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            numChannels: 1,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: filePath,
        );
        started = true;
      } catch (_) {
        try {
          await _recorder.start(
            const RecordConfig(
              encoder: AudioEncoder.aacLc,
              numChannels: 1,
            ),
            path: filePath,
          );
          started = true;
        } catch (_) {
          try {
            await _recorder.start(
              const RecordConfig(numChannels: 1),
              path: filePath,
            );
            started = true;
          } catch (_) {
            await _recorder.start(
              const RecordConfig(),
              path: filePath,
            );
            started = true;
          }
        }
      }

      if (!started) {
        throw Exception('Audio recorder could not be initialized on this device.');
      }

      if (!mounted) return;

      setState(() {
        _isRecording = true;
        _isPaused = false;
        _isInitializing = false;
        _elapsed = Duration.zero;
      });

      _durationTimer?.cancel();
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_isPaused && mounted) {
          setState(() {
            _elapsed += const Duration(seconds: 1);
          });
        }
      });

      // Sample amplitudes for live waveform safely
      _amplitudeTimer?.cancel();
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
        if (_isRecording && !_isPaused && mounted) {
          try {
            final amp = await _recorder.getAmplitude();
            if (!mounted) return;
            final normalized = ((amp.current + 60) / 60).clamp(0.08, 1.0);
            setState(() {
              _waveformAmplitudes.removeAt(0);
              _waveformAmplitudes.add(normalized);
            });
          } catch (_) {
            // Amplitude polling errors should never crash the recording engine
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _isRecording = false;
          _initError = 'Failed to initialize recording: $e';
        });
      }
    }
  }

  Future<void> _pauseRecording() async {
    if (!_isRecording || _isPaused) return;
    try {
      await _recorder.pause();
      setState(() {
        _isPaused = true;
      });

    } catch (_) {}
  }

  Future<void> _resumeRecording() async {
    if (!_isRecording || !_isPaused) return;
    try {
      await _recorder.resume();
      setState(() {
        _isPaused = false;
      });
    } catch (_) {}
  }

  Future<void> _cancelRecording() async {
    _durationTimer?.cancel();
    _amplitudeTimer?.cancel();
    try {
      await _recorder.cancel();
      if (_currentRecordingPath != null) {
        final f = File(_currentRecordingPath!);
        if (await f.exists()) {
          await f.delete();
        }
      }
    } catch (_) {}

    if (mounted) {
      Navigator.pop(context, null);
    }
  }

  Future<void> _saveRecording() async {
    if (_isSaving) return;
    _isSaving = true;

    _durationTimer?.cancel();
    _amplitudeTimer?.cancel();

    try {
      final path = await _recorder.stop();
      final finalPath = path ?? _currentRecordingPath;

      if (finalPath == null) {
        if (mounted) Navigator.pop(context, null);
        return;
      }

      final file = File(finalPath);
      // Ensure file handles are flushed by the Android media subsystem
      int attempts = 0;
      while (attempts < 10) {
        if (await file.exists() && await file.length() > 0) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
        attempts++;
      }

      int fileSize = 0;
      if (await file.exists()) {
        fileSize = await file.length();
      }

      if (fileSize == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Audio recording is empty (0 bytes). Please try recording again.'),
              backgroundColor: AppColors.danger,
            ),
          );
          Navigator.pop(context, null);
        }
        return;
      }

      // If recording duration is 0, provide at least 1 second fallback if file was created
      final durationMs = _elapsed.inMilliseconds > 0 ? _elapsed.inMilliseconds : 1000;

      final title = _titleController.text.trim().isEmpty
          ? 'Recording ${widget.nextSortOrder + 1}'
          : _titleController.text.trim();

      final recording = VoiceRecordingEntity(
        id: _recordingId ?? const Uuid().v4(),
        voiceNoteId: widget.voiceNoteId,
        title: title,
        audioPath: finalPath,
        durationMs: durationMs,
        fileSize: fileSize,
        createdAt: DateTime.now(),
        sortOrder: widget.nextSortOrder,
        isCompleted: false,
        format: 'm4a',
      );

      if (mounted) {
        Navigator.pop(context, recording);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save audio recording: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
        Navigator.pop(context, null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppConstants.radiusLarge)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title input
          TextField(
            controller: _titleController,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: primaryTextColor,
            ),
            decoration: InputDecoration(
              hintText: 'Recording Title...',
              hintStyle: TextStyle(color: secondaryTextColor),
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.mic_rounded, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 12),

          if (!_hasPermission) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(25),
                borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                border: Border.all(color: Colors.amber.withAlpha(60)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.mic_off_rounded, size: 36, color: Colors.amber),
                  const SizedBox(height: 10),
                  const Text(
                    'Microphone Permission Required',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'NoteFlow requires microphone permission to record audio memos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: secondaryTextColor),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                        onPressed: _startRecording,
                        icon: const Icon(Icons.mic_rounded, size: 18),
                        label: const Text('Grant Access'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else if (_initError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.danger.withAlpha(25),
                borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                border: Border.all(color: AppColors.danger.withAlpha(60)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 36, color: AppColors.danger),
                  const SizedBox(height: 10),
                  const Text(
                    'Recording Initialization Error',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _initError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: secondaryTextColor),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                        onPressed: _startRecording,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else if (_isInitializing) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            Text(
              'Preparing microphone...',
              style: TextStyle(color: secondaryTextColor, fontSize: 13),
            ),
            const SizedBox(height: 24),
          ] else ...[
            // Live Pulse & Elapsed Time
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isPaused
                            ? Colors.amber
                            : AppColors.danger.withAlpha((140 + 115 * _pulseController.value).toInt()),
                        boxShadow: [
                          if (!_isPaused)
                            BoxShadow(
                              color: AppColors.danger.withAlpha((100 * _pulseController.value).toInt()),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  _isPaused ? 'PAUSED' : 'RECORDING',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: _isPaused ? Colors.amber : AppColors.danger,
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  AudioHelper.formatDuration(_elapsed),
                  style: TextStyle(
                    fontSize: 22,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Live Audio Visualizer Bars
            SizedBox(
              height: 48,
              child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: _waveformAmplitudes.map((amp) {
                final barHeight = (44 * amp).clamp(4.0, 44.0);
                return Container(
                  width: 3.5,
                  height: barHeight,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: _isPaused
                        ? Colors.amber.withAlpha(160)
                        : AppColors.primary.withAlpha((120 + 135 * amp).toInt()),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // Control Actions: Discard, Pause/Resume, Stop & Save
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Discard / Cancel
              IconButton.filledTonal(
                tooltip: 'Discard',
                style: IconButton.styleFrom(
                  backgroundColor: isDark ? Colors.white10 : Colors.black12,
                  foregroundColor: secondaryTextColor,
                  padding: const EdgeInsets.all(12),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 24),
                onPressed: _cancelRecording,
              ),

              // Pause / Resume
              IconButton.filled(
                tooltip: _isPaused ? 'Resume' : 'Pause',
                style: IconButton.styleFrom(
                  backgroundColor: _isPaused ? Colors.amber : (isDark ? Colors.white24 : Colors.black26),
                  foregroundColor: _isPaused ? Colors.black : Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
                icon: Icon(
                  _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 28,
                ),
                onPressed: _isPaused ? _resumeRecording : _pauseRecording,
              ),

              // Stop & Save
              IconButton.filled(
                tooltip: 'Save Recording',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
                icon: const Icon(Icons.check_rounded, size: 28),
                onPressed: _saveRecording,
              ),
            ],
          ),
        ],
      ],
    ),
  );
}
}
