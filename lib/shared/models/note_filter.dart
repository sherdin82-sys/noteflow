enum NoteSortOrder {
  recentlyModified,
  recentlyCreated,
  titleAZ,
  titleZA,
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
  final bool showArchived;
  final NoteSortOrder sortOrder;

  const NoteFilterState({
    this.searchQuery = '',
    this.folderFilter = const FolderFilter.all(),
    this.showArchived = false,
    this.sortOrder = NoteSortOrder.recentlyModified,
  });

  /// Backward-compatible convenience getters
  String? get selectedFolderId => folderFilter.folderId;
  bool get isAllNotes => folderFilter.isAll;

  NoteFilterState copyWith({
    String? searchQuery,
    FolderFilter? folderFilter,
    String? selectedFolderId,
    bool clearFolder = false,
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

    return NoteFilterState(
      searchQuery: searchQuery ?? this.searchQuery,
      folderFilter: newFolderFilter,
      showArchived: showArchived ?? this.showArchived,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
