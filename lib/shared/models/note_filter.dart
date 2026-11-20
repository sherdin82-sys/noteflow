enum NoteSortOrder {
  recentlyModified,
  recentlyCreated,
  titleAZ,
  titleZA,
}

enum TagFilterMatchMode {
  any,
  all,
}

sealed class FolderFilter {
  const FolderFilter();

  const factory FolderFilter.all() = AllNotesFilter;
  const factory FolderFilter.folder(String folderId) = SpecificFolderFilter;

  bool get isAll => this is AllNotesFilter;
  String? get folderId => switch (this) {
        AllNotesFilter() => null,
        SpecificFolderFilter(folderId: final id) => id,
      };
}

class AllNotesFilter extends FolderFilter {
  const AllNotesFilter();

  @override
  bool operator ==(Object other) => identical(this, other) || other is AllNotesFilter;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'FolderFilter.all()';
}

class SpecificFolderFilter extends FolderFilter {
  @override
  final String folderId;

  const SpecificFolderFilter(this.folderId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SpecificFolderFilter && other.folderId == folderId);

  @override
  int get hashCode => folderId.hashCode;

  @override
  String toString() => 'FolderFilter.folder($folderId)';
}

class NoteFilterState {
  final String searchQuery;
  final FolderFilter folderFilter;
  final bool isFavoritesOnly;
  final Set<String> selectedTagIds;
  final TagFilterMatchMode tagMatchMode;
  final bool showArchived;
  final NoteSortOrder sortOrder;

  const NoteFilterState({
    this.searchQuery = '',
    this.folderFilter = const FolderFilter.all(),
    this.isFavoritesOnly = false,
    this.selectedTagIds = const {},
    this.tagMatchMode = TagFilterMatchMode.any,
    this.showArchived = false,
    this.sortOrder = NoteSortOrder.recentlyModified,
  });

  /// Backward-compatible convenience getters
  String? get selectedFolderId => folderFilter.folderId;
  bool get isAllNotes => folderFilter.isAll && !isFavoritesOnly && selectedTagIds.isEmpty;
  bool get hasTagFilter => selectedTagIds.isNotEmpty;

  NoteFilterState copyWith({
    String? searchQuery,
    FolderFilter? folderFilter,
    String? selectedFolderId,
    bool clearFolder = false,
    bool? isFavoritesOnly,
    Set<String>? selectedTagIds,
    bool clearTags = false,
    TagFilterMatchMode? tagMatchMode,
    bool? showArchived,
    NoteSortOrder? sortOrder,
  }) {
    final FolderFilter newFolderFilter;
    if (folderFilter != null) {
      newFolderFilter = folderFilter;
    } else if (clearFolder) {
      newFolderFilter = const FolderFilter.all();
    } else if (selectedFolderId != null) {
      newFolderFilter = FolderFilter.folder(selectedFolderId);
    } else {
      newFolderFilter = this.folderFilter;
    }

    final Set<String> newSelectedTagIds;
    if (clearTags) {
      newSelectedTagIds = const {};
    } else if (selectedTagIds != null) {
      newSelectedTagIds = Set.unmodifiable(selectedTagIds);
    } else {
      newSelectedTagIds = this.selectedTagIds;
    }

    return NoteFilterState(
      searchQuery: searchQuery ?? this.searchQuery,
      folderFilter: newFolderFilter,
      isFavoritesOnly: isFavoritesOnly ?? this.isFavoritesOnly,
      selectedTagIds: newSelectedTagIds,
      tagMatchMode: tagMatchMode ?? this.tagMatchMode,
      showArchived: showArchived ?? this.showArchived,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
