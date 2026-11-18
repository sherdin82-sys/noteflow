import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/note_entity.dart';
import '../../../shared/models/note_filter.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/utils/note_helper.dart';

class NoteFilterNotifier extends StateNotifier<NoteFilterState> {
  NoteFilterNotifier() : super(const NoteFilterState());

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setSelectedFolder(String? folderId) {
    if (folderId == null || state.selectedFolderId == folderId) {
      // Toggle off or clear folder filter
      state = state.copyWith(clearFolder: true);
    } else {
      state = state.copyWith(selectedFolderId: folderId);
    }
  }

  void setSortOrder(NoteSortOrder sortOrder) {
    state = state.copyWith(sortOrder: sortOrder);
  }

  void reset() {
    state = const NoteFilterState();
  }
}

final noteFilterProvider = StateNotifierProvider<NoteFilterNotifier, NoteFilterState>((ref) {
  return NoteFilterNotifier();
});

class HomeNotesData {
  final List<NoteEntity> pinnedNotes;
  final List<NoteEntity> otherNotes;
  final int totalCount;

  const HomeNotesData({
    required this.pinnedNotes,
    required this.otherNotes,
    required this.totalCount,
  });

  bool get isEmpty => pinnedNotes.isEmpty && otherNotes.isEmpty;
}

final homeNotesProvider = Provider<AsyncValue<HomeNotesData>>((ref) {
  final notesAsync = ref.watch(activeNotesStreamProvider);
  final filter = ref.watch(noteFilterProvider);
  final foldersAsync = ref.watch(foldersStreamProvider);

  return notesAsync.whenData((notes) {
    // Validate selectedFolderId exists in active folders
    final validFolders = foldersAsync.value ?? [];
    final activeFolderId = (filter.selectedFolderId != null &&
            validFolders.any((f) => f.id == filter.selectedFolderId))
        ? filter.selectedFolderId
        : null;

    // 1. Filter by folder
    var filtered = notes.where((note) {
      if (activeFolderId != null && note.folderId != activeFolderId) {
        return false;
      }
      return true;
    }).toList();

    // 2. Filter by search query
    if (filter.searchQuery.trim().isNotEmpty) {
      final query = filter.searchQuery.toLowerCase().trim();
      filtered = filtered.where((note) {
        final titleMatch = note.title.toLowerCase().contains(query);
        final plainContent = NoteHelper.extractPlainText(note.content).toLowerCase();
        final contentMatch = plainContent.contains(query);
        return titleMatch || contentMatch;
      }).toList();
    }

    // 3. Sort
    filtered.sort((a, b) {
      switch (filter.sortOrder) {
        case NoteSortOrder.recentlyModified:
          return b.updatedAt.compareTo(a.updatedAt);
        case NoteSortOrder.recentlyCreated:
          return b.createdAt.compareTo(a.createdAt);
        case NoteSortOrder.titleAZ:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case NoteSortOrder.titleZA:
          return b.title.toLowerCase().compareTo(a.title.toLowerCase());
      }
    });

    // 4. Split into pinned and unpinned
    final pinned = filtered.where((n) => n.isPinned).toList();
    final other = filtered.where((n) => !n.isPinned).toList();

    return HomeNotesData(
      pinnedNotes: pinned,
      otherNotes: other,
      totalCount: filtered.length,
    );
  });
});
