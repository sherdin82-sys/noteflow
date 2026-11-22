import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../shared/models/backup_models.dart';

class BackupRestoreScreen extends ConsumerStatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  ConsumerState<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  bool _isLoading = false;
  bool _includeAudio = true;
  List<File> _localBackups = [];
  final TextEditingController _customNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  @override
  void dispose() {
    _customNameController.dispose();
    super.dispose();
  }

  Future<void> _loadBackups() async {
    try {
      final repo = ref.read(noteRepositoryProvider);
      final files = await repo.listLocalBackups();
      if (mounted) {
        setState(() {
          _localBackups = files;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleCreateBackup() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(noteRepositoryProvider);
      final customName = _customNameController.text.trim();
      final backupFile = await repo.createBackupFile(
        includeAudio: _includeAudio,
        customName: customName.isNotEmpty ? customName : null,
      );
      _customNameController.clear();
      await _loadBackups();

      if (mounted) {
        final fileName = backupFile.uri.pathSegments.last;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.accent,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Backup created: $fileName',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Failed to create backup: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDeleteBackup(File file) async {
    final fileName = file.uri.pathSegments.last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        ),
        title: const Text('Delete Backup'),
        content: Text('Are you sure you want to permanently delete "$fileName"?'),
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
      final repo = ref.read(noteRepositoryProvider);
      await repo.deleteBackupFile(file.path);
      await _loadBackups();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted $fileName'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _handleCopyPath(File file) {
    Clipboard.setData(ClipboardData(text: file.path));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Backup file path copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _initiateRestore({File? file, String? rawContent}) async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(noteRepositoryProvider);
      final source = file != null ? file.path : rawContent!;
      final preview = await repo.inspectBackup(source);

      if (!mounted) return;
      setState(() => _isLoading = false);

      _showRestoreConfirmationModal(preview, source);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
            ),
            title: const Text('Invalid Backup'),
            content: Text('Could not read backup data:\n$e'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _showRestoreConfirmationModal(BackupPreview preview, String source) {
    RestoreStrategy selectedStrategy = RestoreStrategy.merge;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
            final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
            final secondaryText = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

            return Container(
              padding: EdgeInsets.only(
                left: AppConstants.paddingMedium,
                right: AppConstants.paddingMedium,
                top: AppConstants.paddingMedium,
                bottom: MediaQuery.of(context).padding.bottom + AppConstants.paddingMedium,
              ),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppConstants.radiusLarge),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: secondaryText.withAlpha(76),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(38),
                          borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                        ),
                        child: const Icon(
                          Icons.settings_backup_restore_rounded,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Restore Backup',
                            style: AppTypography.titleLarge(textColor),
                          ),
                          Text(
                            preview.fileName ?? 'External Backup',
                            style: TextStyle(fontSize: 12, color: secondaryText),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Preview Summary Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
                      borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                      border: Border.all(
                        color: isDark ? AppColors.darkBorderSubtle : AppColors.lightBorderSubtle,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Backup Created', style: TextStyle(fontSize: 13, color: secondaryText)),
                            Text(
                              DateFormatter.formatFull(preview.createdAt),
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                            ),
                          ],
                        ),
                        const Divider(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          alignment: WrapAlignment.spaceAround,
                          children: [
                            _buildStatChip(Icons.note_alt_outlined, '${preview.notesCount}', 'Notes', textColor, secondaryText),
                            _buildStatChip(Icons.folder_outlined, '${preview.foldersCount}', 'Folders', textColor, secondaryText),
                            _buildStatChip(
                              Icons.mic_outlined,
                              '${preview.recordingsCount}',
                              preview.hasAudio ? 'Audio Clips' : 'Voice Notes',
                              textColor,
                              secondaryText,
                            ),
                            if (preview.remindersCount > 0)
                              _buildStatChip(Icons.alarm_rounded, '${preview.remindersCount}', 'Reminders', textColor, secondaryText),
                            if (preview.attachmentsCount > 0)
                              _buildStatChip(Icons.attach_file_rounded, '${preview.attachmentsCount}', 'Attachments', textColor, secondaryText),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  Text(
                    'Choose Restore Strategy',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Option 1: Merge
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                      border: Border.all(
                        color: selectedStrategy == RestoreStrategy.merge
                            ? AppColors.primary
                            : (isDark ? AppColors.darkBorderSubtle : AppColors.lightBorderSubtle),
                        width: selectedStrategy == RestoreStrategy.merge ? 2 : 1,
                      ),
                    ),
                    child: RadioListTile<RestoreStrategy>(
                      value: RestoreStrategy.merge,
                      groupValue: selectedStrategy,
                      activeColor: AppColors.primary,
                      title: const Text('Merge with existing notes (Recommended)'),
                      subtitle: const Text(
                        'Keep your current notes and safely add or update notes from this backup.',
                        style: TextStyle(fontSize: 12),
                      ),
                      onChanged: (val) {
                        if (val != null) setModalState(() => selectedStrategy = val);
                      },
                    ),
                  ),

                  // Option 2: Replace
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                      border: Border.all(
                        color: selectedStrategy == RestoreStrategy.replace
                            ? AppColors.danger
                            : (isDark ? AppColors.darkBorderSubtle : AppColors.lightBorderSubtle),
                        width: selectedStrategy == RestoreStrategy.replace ? 2 : 1,
                      ),
                    ),
                    child: RadioListTile<RestoreStrategy>(
                      value: RestoreStrategy.replace,
                      groupValue: selectedStrategy,
                      activeColor: AppColors.danger,
                      title: const Text('Replace all existing notes'),
                      subtitle: const Text(
                        'Caution: Erases all current notes, folders, and recordings, replacing them entirely with the backup contents.',
                        style: TextStyle(fontSize: 12),
                      ),
                      onChanged: (val) {
                        if (val != null) setModalState(() => selectedStrategy = val);
                      },
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(modalCtx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: selectedStrategy == RestoreStrategy.replace
                                ? AppColors.danger
                                : AppColors.primary,
                          ),
                          icon: const Icon(Icons.settings_backup_restore_rounded, size: 18),
                          label: const Text('Restore Now'),
                          onPressed: () async {
                            Navigator.pop(modalCtx);
                            await _performRestore(source, selectedStrategy, preview);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatChip(IconData icon, String count, String label, Color textColor, Color secondaryText) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(height: 4),
        Text(count, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
        Text(label, style: TextStyle(fontSize: 11, color: secondaryText)),
      ],
    );
  }

  Future<void> _performRestore(String source, RestoreStrategy strategy, BackupPreview preview) async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(noteRepositoryProvider);
      await repo.restoreBackup(source, strategy: strategy);
      await _loadBackups();

      if (mounted) {
        final strategyName = strategy == RestoreStrategy.merge ? 'Merged' : 'Replaced';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.accent,
            content: Row(
              children: [
                const Icon(Icons.done_all_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Restored ${preview.notesCount} notes, ${preview.foldersCount} folders${preview.attachmentsCount > 0 ? " & ${preview.attachmentsCount} attachments" : ""} ($strategyName)!',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Restore failed: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showManualImportDialog() {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        ),
        title: const Text('Import Backup File or Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the absolute path to a .noteflow or .json backup file, or paste raw JSON backup data below:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '/path/to/backup.noteflow or {"app":"NoteFlow",...}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final content = textController.text.trim();
              if (content.isNotEmpty) {
                Navigator.pop(dialogCtx);
                if (content.startsWith('{') && content.endsWith('}')) {
                  _initiateRestore(rawContent: content);
                } else {
                  _initiateRestore(file: File(content));
                }
              }
            },
            child: const Text('Inspect & Restore'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final backgroundColor = isDark ? AppColors.darkBackground : AppColors.lightBackground;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Backup & Restore'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: 'Import from Path or Data',
            onPressed: _isLoading ? null : _showManualImportDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Backups',
            onPressed: _isLoading ? null : _loadBackups,
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadBackups,
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.paddingMedium,
                vertical: AppConstants.paddingSmall,
              ),
              children: [
                // Info Banner
                Container(
                  padding: const EdgeInsets.all(AppConstants.paddingMedium),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                          : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                    border: Border.all(
                      color: isDark ? AppColors.darkBorderSubtle : AppColors.lightBorderSubtle,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.accent],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.security_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Offline & Private Persistence',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Backups include all notes, checklists, folders, and embedded audio clips. Stored completely offline on your device.',
                              style: TextStyle(
                                fontSize: 12,
                                color: secondaryTextColor,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Create Backup Card
                Card(
                  color: surfaceColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                    side: BorderSide(
                      color: isDark ? AppColors.darkBorderSubtle : AppColors.lightBorderSubtle,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.paddingMedium),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CREATE BACKUP',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.bold,
                            color: secondaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _customNameController,
                          decoration: InputDecoration(
                            hintText: 'Backup name (optional, e.g. Pre-Update)',
                            prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded, size: 20),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _includeAudio,
                          activeColor: AppColors.primary,
                          title: const Text('Include Voice Audio Recordings'),
                          subtitle: const Text(
                            'Embeds lossless audio data directly inside the .noteflow file',
                            style: TextStyle(fontSize: 12),
                          ),
                          onChanged: (val) => setState(() => _includeAudio = val),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isLoading ? null : _handleCreateBackup,
                            icon: const Icon(Icons.backup_rounded, size: 18),
                            label: const Text('Create Backup Now'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 22),

                // Local Backups Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          'SAVED BACKUPS',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.bold,
                            color: secondaryTextColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(38),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_localBackups.length}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.add_link_rounded, size: 16),
                      label: const Text('Custom Path'),
                      onPressed: _showManualImportDialog,
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Backups List
                if (_localBackups.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 48,
                          color: secondaryTextColor.withAlpha(128),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No backups saved yet',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: primaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap "Create Backup Now" above to create your first safe restore point.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  )
                else
                  ..._localBackups.map((file) => _buildBackupTile(file, isDark, primaryTextColor, secondaryTextColor)),

                const SizedBox(height: 40),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black38,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBackupTile(File file, bool isDark, Color primaryTextColor, Color secondaryTextColor) {
    final fileName = file.uri.pathSegments.last;
    final lastModified = file.lastModifiedSync();
    final fileSize = file.lengthSync();
    final formattedSize = fileSize < 1024
        ? '$fileSize B'
        : fileSize < 1024 * 1024
            ? '${(fileSize / 1024).toStringAsFixed(1)} KB'
            : '${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(AppConstants.paddingMedium),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        border: Border.all(
          color: isDark ? AppColors.darkBorderSubtle : AppColors.lightBorderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.archive_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: primaryTextColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${DateFormatter.formatFull(lastModified)} • $formattedSize',
                      style: TextStyle(fontSize: 12, color: secondaryTextColor),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, size: 20, color: secondaryTextColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                ),
                onSelected: (val) {
                  if (val == 'copy') {
                    _handleCopyPath(file);
                  } else if (val == 'delete') {
                    _handleDeleteBackup(file);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'copy',
                    child: Row(
                      children: [
                        Icon(Icons.copy_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Copy File Path'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                        SizedBox(width: 10),
                        Text('Delete Backup', style: TextStyle(color: AppColors.danger)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              icon: const Icon(Icons.settings_backup_restore_rounded, size: 18),
              label: const Text('Restore from this Backup'),
              onPressed: _isLoading ? null : () => _initiateRestore(file: file),
            ),
          ),
        ],
      ),
    );
  }
}
