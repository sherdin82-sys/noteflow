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

    # 3. Patch package:jni types.dart to strip JNI descriptor 'L...;' and convert slashes to dots
    jni_types_files = glob.glob(f'{pub_cache}/**/jni-*/lib/src/types.dart', recursive=True) + glob.glob(f'{pub_cache}/**/jni/lib/src/types.dart', recursive=True)
    for p in jni_types_files:
        try:
            with open(p, 'r', encoding='utf-8') as f:
                content = f.read()
            changed = False
            if 'JClass.forName(className ?? signature)' in content:
                content = content.replace(
                    'JClass.forName(className ?? signature)',
                    '''() {
  String name = className ?? signature;
  if (name.startsWith('L') && name.endsWith(';')) {
    name = name.substring(1, name.length - 1);
  }
  name = name.replaceAll('/', '.');
  return JClass.forName(name);
}()'''
                )
                changed = True
            if changed:
                with open(p, 'w', encoding='utf-8') as f:
                    f.write(content)
                print(f'Successfully patched package:jni types.dart at {p}')
        except Exception as e:
            print(f'Error patching {p}: {e}')

    # 4. Patch path_provider.g.dart if present to supply proper binary className
    path_provider_g_files = glob.glob(f'{pub_cache}/**/path_provider_android*/lib/src/path_provider.g.dart', recursive=True)
    for p in path_provider_g_files:
        try:
            with open(p, 'r', encoding='utf-8') as f:
                content = f.read()
            changed = False
            if "String get signature => r'Landroid/content/Context;';" in content and 'String get className' not in content:
                content = content.replace(
                    "String get signature => r'Landroid/content/Context;';",
                    "String get signature => r'Landroid/content/Context;';\n  @jni\$_.internal\n  @core\$_.override\n  String get className => r'android.content.Context';"
                )
                changed = True
            if changed:
                with open(p, 'w', encoding='utf-8') as f:
                    f.write(content)
                print(f'Successfully patched path_provider.g.dart at {p}')
        except Exception as e:
            print(f'Error patching {p}: {e}')

    # 5. Patch dartjni.h if present to normalize JNI type descriptors for Android ClassLoader
    dartjni_h_files = glob.glob(f'{pub_cache}/**/dartjni.h', recursive=True)
    for p in dartjni_h_files:
        try:
            with open(p, 'r', encoding='utf-8') as f:
                content = f.read()
            changed = False
            target = 'jstring className = (*jniEnv)->NewStringUTF(jniEnv, name);'
            replacement = '''char cleanName[256];
  const char* src = name;
  if (src[0] == 'L' && src[strlen(src)-1] == ';') {
    size_t len = strlen(src) - 2;
    if (len >= sizeof(cleanName)) len = sizeof(cleanName) - 1;
    strncpy(cleanName, src + 1, len);
    cleanName[len] = '\\0';
  } else {
    strncpy(cleanName, src, sizeof(cleanName) - 1);
    cleanName[sizeof(cleanName) - 1] = '\\0';
  }
  for (int i = 0; cleanName[i] != '\\0'; i++) {
    if (cleanName[i] == '/') cleanName[i] = '.';
  }
  jstring className = (*jniEnv)->NewStringUTF(jniEnv, cleanName);'''
            if target in content and replacement not in content:
                content = content.replace(target, replacement)
                changed = True
            if changed:
                with open(p, 'w', encoding='utf-8') as f:
                    f.write(content)
                print(f'Successfully patched dartjni.h at {p}')
        except Exception as e:
            print(f'Error patching {p}: {e}')

if __name__ == '__main__':
    main()

