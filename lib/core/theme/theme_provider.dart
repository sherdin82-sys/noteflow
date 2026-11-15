import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database_provider.dart';
import '../database/local_note_repository.dart';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final LocalNoteRepository? _repo;

  ThemeModeNotifier([this._repo, ThemeMode initial = ThemeMode.dark]) : super(initial);

  void setThemeMode(ThemeMode mode) {
    state = mode;
    _repo?.setThemeMode(
      mode == ThemeMode.light
          ? 'light'
          : (mode == ThemeMode.dark ? 'dark' : 'system'),
    );
  }

  void toggleTheme() {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setThemeMode(next);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final repo = ref.watch(noteRepositoryProvider);
  ThemeMode initial = ThemeMode.dark;
  if (repo is LocalNoteRepository) {
    final modeStr = repo.themeMode;
    if (modeStr == 'light') {
      initial = ThemeMode.light;
    } else if (modeStr == 'dark') {
      initial = ThemeMode.dark;
    } else {
      initial = ThemeMode.system;
    }
    return ThemeModeNotifier(repo, initial);
  }
  return ThemeModeNotifier(null, initial);
});
