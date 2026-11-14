enum NoteSortOrder {
  recentlyModified,
  recentlyCreated,
  titleAZ,
  titleZA,
}

class NoteFilterState {
  final String searchQuery;
  final String? selectedFolderId;
  final bool showArchived;
  final NoteSortOrder sortOrder;

  const NoteFilterState({
    this.searchQuery = '',
    this.selectedFolderId,
    this.showArchived = false,
    this.sortOrder = NoteSortOrder.recentlyModified,
  });

  NoteFilterState copyWith({
    String? searchQuery,
    String? selectedFolderId,
    bool clearFolder = false,
    bool? showArchived,
    NoteSortOrder? sortOrder,
  }) {
    return NoteFilterState(
      searchQuery: searchQuery ?? this.searchQuery,
      selectedFolderId: clearFolder ? null : (selectedFolderId ?? this.selectedFolderId),
      showArchived: showArchived ?? this.showArchived,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
