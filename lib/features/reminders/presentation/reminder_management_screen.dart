import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/reminder_entity.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../editor/presentation/note_editor_screen.dart';
import '../../voice_notes/presentation/voice_note_editor_screen.dart';
import '../providers/reminder_providers.dart';
import '../services/reminder_native_bridge.dart';
import 'widgets/reminder_card.dart';

class ReminderManagementScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const ReminderManagementScreen({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<ReminderManagementScreen> createState() => _ReminderManagementScreenState();
}

class _ReminderManagementScreenState extends ConsumerState<ReminderManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTabIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openNoteForReminder(ReminderEntity reminder) async {
    final repo = ref.read(noteRepositoryProvider);
    final note = await repo.getNoteById(reminder.noteId);
    if (!mounted) return;

    if (note != null && (note.hasAudio || reminder.isVoiceRecordingReminder)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VoiceNoteEditorScreen(
            noteId: note.id,
            initialNote: note,
          ),
        ),
      );
    } else if (note != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NoteEditorScreen(
            noteId: note.id,
            initialNote: note,
            isChecklist: note.isChecklist,
            isVoiceNote: note.hasAudio,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Target note was deleted')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    final upcoming = ref.watch(upcomingRemindersProvider).value ?? [];
    final today = ref.watch(todayRemindersProvider).value ?? [];
    final overdue = ref.watch(overdueRemindersProvider).value ?? [];
    final completed = ref.watch(completedRemindersProvider).value ?? [];

    return Scaffold(
      backgroundColor: surfaceColor,
      appBar: AppBar(
        title: Text('Reminders', style: AppTypography.titleLarge(textColor)),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Notification Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => ReminderNativeBridge.openNotificationSettings(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
          tabs: [
            Tab(
              child: Row(
                children: [
                  const Text('Upcoming'),
                  if (upcoming.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _buildCountBadge(upcoming.length, theme.colorScheme.primary, Colors.white),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                children: [
                  const Text('Today'),
                  if (today.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _buildCountBadge(today.length, Colors.blueAccent, Colors.white),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                children: [
                  const Text('Overdue'),
                  if (overdue.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _buildCountBadge(overdue.length, Colors.redAccent, Colors.white),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                children: [
                  const Text('Completed'),
                  if (completed.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _buildCountBadge(
                      completed.length,
                      isDark ? Colors.white24 : Colors.black12,
                      isDark ? Colors.white70 : Colors.black87,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Upcoming Tab
          _buildReminderList(
            reminders: upcoming,
            emptyIcon: Icons.upcoming_outlined,
            emptyTitle: 'No upcoming reminders',
            emptySubtitle: 'Reminders scheduled for future dates will appear here.',
          ),
          // Today Tab
          _buildReminderList(
            reminders: today,
            emptyIcon: Icons.today_outlined,
            emptyTitle: 'Nothing scheduled for today',
            emptySubtitle: 'Enjoy your free time or schedule a reminder from any note!',
          ),
          // Overdue Tab
          _buildReminderList(
            reminders: overdue,
            emptyIcon: Icons.check_circle_outline_rounded,
            emptyTitle: 'No overdue reminders',
            emptySubtitle: 'You are all caught up on your scheduled tasks!',
          ),
          // Completed Tab
          _buildReminderList(
            reminders: completed,
            emptyIcon: Icons.done_all_rounded,
            emptyTitle: 'No completed reminders',
            emptySubtitle: 'Completed reminders will be listed here for your reference.',
          ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(int count, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildReminderList({
    required List<ReminderEntity> reminders,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptySubtitle,
  }) {
    if (reminders.isEmpty) {
      return Center(
        child: EmptyStateView(
          icon: emptyIcon,
          title: emptyTitle,
          description: emptySubtitle,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppConstants.paddingLarge),
      itemCount: reminders.length,
      itemBuilder: (context, index) {
        final rem = reminders[index];
        return ReminderCard(
          reminder: rem,
          onOpenNote: () => _openNoteForReminder(rem),
        );
      },
    );
  }
}
