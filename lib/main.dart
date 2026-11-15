import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/home/presentation/home_screen.dart';

import 'core/database/database_provider.dart';
import 'core/database/local_note_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = LocalNoteRepository(
    directoryProvider: () async {
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    },
  );
  await repo.init();

  runApp(
    ProviderScope(
      overrides: [
        noteRepositoryProvider.overrideWithValue(repo),
      ],
      child: const NoteFlowApp(),
    ),
  );
}

class NoteFlowApp extends ConsumerWidget {
  const NoteFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'NoteFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: FlutterQuillLocalizations.supportedLocales,
      home: const HomeScreen(),
    );
  }
}
