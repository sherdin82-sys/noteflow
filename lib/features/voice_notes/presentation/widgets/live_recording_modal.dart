import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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

class _LiveRecordingModalState extends State<LiveRecordingModal>
    with SingleTickerProviderStateMixin {
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
    if (_isRecording && !_isSaving) {
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
            _initError =
                'Microphone permission is required to record audio memos.';
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

      String tempBasePath;
      try {
        final tempDir = await getTemporaryDirectory();
        tempBasePath = tempDir.path;
      } catch (_) {
        tempBasePath = Directory.systemTemp.path;
      }
      final tempDir = Directory('$tempBasePath/voice_recordings_temp');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      _recordingId = const Uuid().v4();
      final filePath = '${tempDir.path}/$_recordingId.m4a';
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
            const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
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
            await _recorder.start(const RecordConfig(), path: filePath);
            started = true;
          }
        }
      }

      if (!started) {
        throw Exception(
          'Audio recorder could not be initialized on this device.',
        );
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
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (
        _,
      ) async {
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
    _isRecording = false;
    final fileToDelete = _currentRecordingPath;
    _currentRecordingPath = null;
    try {
      await _recorder.cancel();
      if (fileToDelete != null) {
        final f = File(fileToDelete);
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
      _isRecording = false;
      final finalPath = path ?? _currentRecordingPath;
      _currentRecordingPath = null;

      if (finalPath == null) {
        if (mounted) Navigator.pop(context, null);
        return;
      }

      final tempFile = File(finalPath);
      // Ensure file handles are flushed by the Android media subsystem
      int attempts = 0;
      while (attempts < 10) {
        if (await tempFile.exists() && await tempFile.length() > 0) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
        attempts++;
      }

      int tempSize = 0;
      if (await tempFile.exists()) {
        tempSize = await tempFile.length();
      }

      if (tempSize == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Audio recording is empty (0 bytes). Please try recording again.',
              ),
              backgroundColor: AppColors.danger,
            ),
          );
          Navigator.pop(context, null);
        }
        return;
      }

      // Safe transfer to permanent storage inside app documents directory
      String documentsBasePath;
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        documentsBasePath = appDocDir.path;
      } catch (_) {
        documentsBasePath = Directory.systemTemp.path;
      }

      final recordingId = _recordingId ?? const Uuid().v4();
      final permanentPath = await AudioHelper.saveRecordingToPermanentStorage(
        tempPath: finalPath,
        voiceNoteId: widget.voiceNoteId,
        recordingId: recordingId,
        documentsBasePath: documentsBasePath,
        format: 'm4a',
      );

      if (permanentPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Failed to persist audio recording to permanent storage.',
              ),
              backgroundColor: AppColors.danger,
            ),
          );
          Navigator.pop(context, null);
        }
        return;
      }

      final permanentFile = File(permanentPath);
      final finalFileSize = await permanentFile.length();

      // If recording duration is 0, provide at least 1 second fallback if file was created
      final durationMs = _elapsed.inMilliseconds > 0
          ? _elapsed.inMilliseconds
          : 1000;

      final title = _titleController.text.trim().isEmpty
          ? 'Recording ${widget.nextSortOrder + 1}'
          : _titleController.text.trim();

      final recording = VoiceRecordingEntity(
        id: recordingId,
        voiceNoteId: widget.voiceNoteId,
        title: title,
        audioPath: permanentPath,
        durationMs: durationMs,
        fileSize: finalFileSize,
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
    final primaryTextColor = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final surfaceColor = isDark
        ? AppColors.darkSurface
        : AppColors.lightSurface;
    final backgroundColor = isDark
        ? AppColors.darkBackground
        : AppColors.lightBackground;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final mediaQuery = MediaQuery.of(context);
    final double bottomSystemInset = math.max(
      mediaQuery.viewPadding.bottom,
      mediaQuery.padding.bottom,
    );
    final double keyboardInset = mediaQuery.viewInsets.bottom;
    final bool isKeyboardOpen = keyboardInset > 0;

    // Generous bottom inset ensuring all action buttons sit cleanly and fully above
    // the Android 3-button navigation bar (48-56dp) or gesture pill (24-32dp),
    // and push smoothly above the keyboard when open.
    final double baseBottomSpacing = bottomSystemInset > 0
        ? bottomSystemInset + 20.0
        : 28.0;
    final double effectiveBottomPadding = isKeyboardOpen
        ? keyboardInset + 16.0
        : baseBottomSpacing;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.88),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusLarge),
          ),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, 12, 20, effectiveBottomPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header Row with Title and Close button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.mic_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Voice Recording',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: primaryTextColor,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: secondaryTextColor,
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: _cancelRecording,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Title input field inside styled card
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(
                    AppConstants.radiusMedium,
                  ),
                  border: Border.all(color: borderColor),
                ),
                child: TextField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: primaryTextColor,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Recording Title...',
                    hintStyle: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 15,
                      fontWeight: FontWeight.normal,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (!_hasPermission) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(25),
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusMedium,
                    ),
                    border: Border.all(color: Colors.amber.withAlpha(60)),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.mic_off_rounded,
                        size: 36,
                        color: Colors.amber,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Microphone Permission Required',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'NoteFlow requires microphone permission to record audio memos.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: secondaryTextColor,
                        ),
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
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                            ),
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
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusMedium,
                    ),
                    border: Border.all(color: AppColors.danger.withAlpha(60)),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 36,
                        color: AppColors.danger,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Recording Initialization Error',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _initError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: secondaryTextColor,
                        ),
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
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                            ),
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
                Center(
                  child: Text(
                    'Preparing microphone...',
                    style: TextStyle(color: secondaryTextColor, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 24),
              ] else ...[
                // Live Recording Indicator & Elapsed Time
                Center(
                  child: Column(
                    children: [
                      // Status pill: RECORDING / PAUSED
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _isPaused
                              ? Colors.amber.withAlpha(25)
                              : AppColors.danger.withAlpha(20),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _isPaused
                                ? Colors.amber.withAlpha(70)
                                : AppColors.danger.withAlpha(60),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                return Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _isPaused
                                        ? Colors.amber
                                        : AppColors.danger.withAlpha(
                                            (140 + 115 * _pulseController.value)
                                                .toInt(),
                                          ),
                                    boxShadow: [
                                      if (!_isPaused)
                                        BoxShadow(
                                          color: AppColors.danger.withAlpha(
                                            (100 * _pulseController.value)
                                                .toInt(),
                                          ),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isPaused ? 'PAUSED' : 'RECORDING',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                                color: _isPaused
                                    ? Colors.amber
                                    : AppColors.danger,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Timer display
                      Text(
                        AudioHelper.formatTwoDigits(_elapsed),
                        style: TextStyle(
                          fontSize: 36,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: primaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Waveform Visualizer
                Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withAlpha(6)
                        : Colors.black.withAlpha(6),
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusMedium,
                    ),
                  ),
                  alignment: Alignment.center,
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
                              : AppColors.primary.withAlpha(
                                  (120 + 135 * amp).toInt(),
                                ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),

                // Control Actions with Labels: Discard, Pause/Resume, Save
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Discard / Cancel Button
                    _buildActionButton(
                      icon: Icons.delete_outline_rounded,
                      label: 'Discard',
                      tooltip: 'Discard',
                      iconColor: AppColors.danger,
                      backgroundColor: AppColors.danger.withAlpha(25),
                      onTap: _cancelRecording,
                      secondaryTextColor: secondaryTextColor,
                    ),

                    // Pause / Resume Button
                    _buildActionButton(
                      icon: _isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      label: _isPaused ? 'Resume' : 'Pause',
                      tooltip: _isPaused ? 'Resume' : 'Pause',
                      iconColor: _isPaused
                          ? Colors.black
                          : (isDark ? Colors.white : Colors.black87),
                      backgroundColor: _isPaused
                          ? Colors.amber
                          : (isDark ? Colors.white12 : Colors.black12),
                      size: 58,
                      iconSize: 28,
                      onTap: _isPaused ? _resumeRecording : _pauseRecording,
                      secondaryTextColor: secondaryTextColor,
                    ),

                    // Stop & Save Button
                    _buildActionButton(
                      icon: Icons.check_rounded,
                      label: 'Save',
                      tooltip: 'Save Recording',
                      iconColor: Colors.white,
                      backgroundColor: AppColors.primary,
                      onTap: _saveRecording,
                      secondaryTextColor: secondaryTextColor,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String tooltip,
    required Color iconColor,
    required Color backgroundColor,
    required VoidCallback onTap,
    required Color secondaryTextColor,
    double size = 48,
    double iconSize = 24,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: tooltip,
          style: IconButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: iconColor,
            fixedSize: Size(size, size),
            padding: EdgeInsets.zero,
          ),
          icon: Icon(icon, size: iconSize, color: iconColor),
          onPressed: onTap,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: secondaryTextColor,
          ),
        ),
      ],
    );
  }
}
