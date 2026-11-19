import glob
import os
import re
import sys

def main():
    pub_cache = os.environ.get('PUB_CACHE', os.path.expanduser('~/.pub-cache'))
    print(f'Checking pub cache at: {pub_cache}')

    # 1. Patch Android build.gradle files in pub cache for AGP 9 compatibility
    android_gradles = glob.glob(f'{pub_cache}/**/android/build.gradle', recursive=True)
    for p in android_gradles:
        try:
            with open(p, 'r', encoding='utf-8') as f:
                content = f.read()
            changed = False
            if "apply plugin: 'kotlin-android'" in content:
                content = content.replace("apply plugin: 'kotlin-android'", "// apply plugin: 'kotlin-android'")
                changed = True
            if 'apply plugin: "kotlin-android"' in content:
                content = content.replace('apply plugin: "kotlin-android"', '// apply plugin: "kotlin-android"')
                changed = True
            if 'kotlinOptions' in content:
                content = re.sub(r'kotlinOptions\s*\{[^}]*\}', '// kotlinOptions removed for AGP 9', content)
                changed = True
            if 'android {' in content and 'compileSdk' not in content:
                content = content.replace('android {', 'android {\n    compileSdk 35')
                changed = True
            if changed:
                with open(p, 'w', encoding='utf-8') as f:
                    f.write(content)
                print(f'Patched Android build.gradle at {p}')
        except Exception as e:
            print(f'Error patching {p}: {e}')

    # 2. Patch record_linux.dart if present for record_platform_interface compatibility
    record_linux_files = glob.glob(f'{pub_cache}/**/record_linux.dart', recursive=True)
    for p in record_linux_files:
        try:
            with open(p, 'r', encoding='utf-8') as f:
                content = f.read()
            changed = False
            if 'dart:typed_data' not in content:
                content = "import 'dart:typed_data';\n" + content
                changed = True
            if 'startStream' not in content:
                content = content.replace(
                    'class RecordLinux extends RecordPlatform {',
                    'class RecordLinux extends RecordPlatform {\n  @override\n  Future<Stream<Uint8List>> startStream(String recorderId, RecordConfig config) async => const Stream.empty();\n'
                )
                changed = True
            if 'Future<bool> hasPermission(String recorderId) {' in content:
                content = content.replace(
                    'Future<bool> hasPermission(String recorderId) {',
                    'Future<bool> hasPermission(String recorderId, {bool request = true}) {'
                )
                changed = True
            if changed:
                with open(p, 'w', encoding='utf-8') as f:
                    f.write(content)
                print(f'Successfully patched record_linux at {p}')
        except Exception as e:
            print(f'Error patching {p}: {e}')

if __name__ == '__main__':
    main()
