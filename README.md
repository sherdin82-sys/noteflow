# NoteFlow

A premium, modern, offline-first Android notepad application built with Flutter, Riverpod, and Drift SQLite.

## Application Details
- **App Name**: NoteFlow
- **Package ID**: `com.noteflow.app`
- **Platform**: Android
- **Architecture**: Clean Architecture with feature modules (`home`, `editor`, `folders`, `archive`, `backup`)
- **Offline Persistence**: Drift + SQLite (`app_database.dart` & `local_note_repository.dart`)

---

## Building the Android APK

### Prerequisites
1. **Flutter SDK** (>= 3.22.0)
2. **Android SDK** (API Level 34 or 35 with Android Build Tools)
3. **Java Development Kit** (OpenJDK 17)

### Build Commands
From the project root:

```bash
# 1. Fetch dependencies
flutter pub get

# 2. Build debug APK
flutter build apk --debug

# 3. Or build optimized release APK
flutter build apk --release
```

Alternatively, from the `android/` directory:
```bash
./gradlew assembleDebug
```

---

## Output APK File Locations

Once the build executes, the generated APK file is located at:

- **Debug APK**:
  `build/app/outputs/flutter-apk/app-debug.apk`
  *(or `android/app/build/outputs/apk/debug/app-debug.apk`)*

- **Release APK**:
  `build/app/outputs/flutter-apk/app-release.apk`
  *(or `android/app/build/outputs/apk/release/app-release.apk`)*

---

## Running Verification Tests
To run the automated domain model, SQLite repository, and auto-save test suite:
```bash
dart run test/unit/noteflow_core_test.dart
```
