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

  /// Explicitly select All Notes filter
  void selectAllNotes() {
    state = state.copyWith(
      folderFilter: const FolderFilter.all(),
      isFavoritesOnly: false,
      isRecentOnly: false,
      isPinnedOnly: false,
      clearTags: true,
    );
  }

  /// Toggle Favorites filter
  void toggleFavoritesOnly() {
    final next = !state.isFavoritesOnly;
    state = state.copyWith(
      isFavoritesOnly: next,
      isRecentOnly: false,
      isPinnedOnly: false,
      // When entering Favorites, reset to All Notes folder filter
      clearFolder: next,
    );
  }

  /// Explicitly set Favorites filter
  void setFavoritesOnly(bool value) {
    state = state.copyWith(
      isFavoritesOnly: value,
      isRecentOnly: false,
      isPinnedOnly: false,
      clearFolder: value,
    );
  }

  /// Toggle Recent filter
  void toggleRecentOnly() {
    final next = !state.isRecentOnly;
    state = state.copyWith(
      isRecentOnly: next,
      isFavoritesOnly: false,
      isPinnedOnly: false,
      clearFolder: next,
      sortOrder: NoteSortOrder.recentlyModified,
    );
  }

  /// Explicitly set Recent filter
  void setRecentOnly(bool value) {
    state = state.copyWith(
      isRecentOnly: value,
      isFavoritesOnly: false,
      isPinnedOnly: false,
      clearFolder: value,
      sortOrder: NoteSortOrder.recentlyModified,
    );
  }

  /// Toggle Pinned filter
  void togglePinnedOnly() {
    final next = !state.isPinnedOnly;
    state = state.copyWith(
      isPinnedOnly: next,
      isFavoritesOnly: false,
      isRecentOnly: false,
      clearFolder: next,
    );
  }

  /// Explicitly set Pinned filter
  void setPinnedOnly(bool value) {
    state = state.copyWith(
      isPinnedOnly: value,
      isFavoritesOnly: false,
      isRecentOnly: false,
      clearFolder: value,
    );
  }

  /// Toggle a tag in the filter set
  void toggleTag(String tagId) {
    final current = Set<String>.from(state.selectedTagIds);
    if (current.contains(tagId)) {
      current.remove(tagId);
    } else {
      current.add(tagId);
    }
    state = state.copyWith(selectedTagIds: current);
  }

  /// Clear all selected tags
  void clearTags() {
    state = state.copyWith(clearTags: true);
  }

  /// Set tag match mode (any vs all)
  void setTagMatchMode(TagFilterMatchMode mode) {
    state = state.copyWith(tagMatchMode: mode);
  }

  /// Explicitly select a specific folder, or toggle off to All Notes if already active
  void selectFolder(String folderId) {
    if (state.folderFilter.folderId == folderId) {
      state = state.copyWith(folderFilter: const FolderFilter.all());
    } else {
      state = state.copyWith(
        folderFilter: FolderFilter.folder(folderId),
        isFavoritesOnly: false,
        isRecentOnly: false,
        isPinnedOnly: false,
      );
    }
  }

  /// Sets selected folder: null unconditionally selects All Notes
  void setSelectedFolder(String? folderId) {
    if (folderId == null) {
      selectAllNotes();
    } else {
      selectFolder(folderId);
    }
  }

  void setSortOrder(NoteSortOrder sortOrder) {
    state = state.copyWith(sortOrder: sortOrder);
  }

  void reset() {
    state = const NoteFilterState();
  }
}

final noteFilterProvider =
    StateNotifierProvider<NoteFilterNotifier, NoteFilterState>((ref) {
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
  final tagsAsync = ref.watch(tagsStreamProvider);

  return notesAsync.whenData((notes) {
    // Validate folderFilter against active folders
    final validFolders = foldersAsync.value ?? [];
    final activeFolderId = switch (filter.folderFilter) {
      AllNotesFilter() => null,
      SpecificFolderFilter(folderId: final id) =>
        validFolders.any((f) => f.id == id) ? id : null,
    };

    final validTags = tagsAsync.value ?? [];
    final tagMap = {for (var t in validTags) t.id: t};

    // 1. Filter by folder
    var filtered = notes.where((note) {
      if (activeFolderId != null && note.folderId != activeFolderId) {
        return false;
      }
      return true;
    }).toList();

    // 2. Filter by Favorites
    if (filter.isFavoritesOnly) {
      filtered = filtered.where((note) => note.isFavorite).toList();
    }

    // 3. Filter by Recent (updated within 7 days or recently modified)
    if (filter.isRecentOnly) {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      final recent = filtered
          .where((note) => note.updatedAt.isAfter(cutoff))
          .toList();
      // If none in last 7 days, fallback to the 10 most recently modified notes
      if (recent.isNotEmpty) {
        filtered = recent;
      } else if (filtered.isNotEmpty) {
        final sorted = List<NoteEntity>.from(filtered)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        filtered = sorted.take(10).toList();
      }
    }

    // 4. Filter by Pinned
    if (filter.isPinnedOnly) {
      filtered = filtered.where((note) => note.isPinned).toList();
    }

    // 3. Filter by Tags
    if (filter.selectedTagIds.isNotEmpty) {
      filtered = filtered.where((note) {
        if (filter.tagMatchMode == TagFilterMatchMode.any) {
          return filter.selectedTagIds.any((id) => note.tagIds.contains(id));
        } else {
          return filter.selectedTagIds.every((id) => note.tagIds.contains(id));
        }
      }).toList();
    }

    // 4. Filter by search query (Title, Content, AND Tag Names)
    if (filter.searchQuery.trim().isNotEmpty) {
      final query = filter.searchQuery.toLowerCase().trim();
      filtered = filtered.where((note) {
        final titleMatch = note.title.toLowerCase().contains(query);
        final plainContent = NoteHelper.extractPlainText(note.content)
            .toLowerCase();
        final contentMatch = plainContent.contains(query);
        final tagMatch = note.tagIds.any((tid) {
          final tag = tagMap[tid];
          return tag != null && tag.name.toLowerCase().contains(query);
        });
        return titleMatch || contentMatch || tagMatch;
      }).toList();
    }

    // 5. Sort
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

    // 6. Split into pinned and unpinned
    final pinned = filtered.where((n) => n.isPinned).toList();
    final other = filtered.where((n) => !n.isPinned).toList();

    return HomeNotesData(
      pinnedNotes: pinned,
      otherNotes: other,
      totalCount: filtered.length,
    );
  });
});
