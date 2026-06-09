#!/usr/bin/env python3
"""Fix JVM targets in a single build.gradle file. Usage: fix_jvm_file.py <file>"""
import sys, re

def fix_file(fp):
    with open(fp, 'r') as f:
        content = f.read()
    new_content = content

    # 1. Replace EXISTING sourceCompatibility/targetCompatibility values
    for old, new in [
        ('sourceCompatibility = JavaVersion.VERSION_1_8', 'sourceCompatibility = JavaVersion.VERSION_17'),
        ('sourceCompatibility = JavaVersion.VERSION_11', 'sourceCompatibility = JavaVersion.VERSION_17'),
        ('sourceCompatibility = 1.8', 'sourceCompatibility = JavaVersion.VERSION_17'),
        ("sourceCompatibility = '1.8'", 'sourceCompatibility = JavaVersion.VERSION_17'),
        ('sourceCompatibility JavaVersion.VERSION_1_8', 'sourceCompatibility JavaVersion.VERSION_17'),
        ('targetCompatibility = JavaVersion.VERSION_1_8', 'targetCompatibility = JavaVersion.VERSION_17'),
        ('targetCompatibility = JavaVersion.VERSION_11', 'targetCompatibility = JavaVersion.VERSION_17'),
        ('targetCompatibility = 1.8', 'targetCompatibility = JavaVersion.VERSION_17'),
        ("targetCompatibility = '1.8'", 'targetCompatibility = JavaVersion.VERSION_17'),
        ('targetCompatibility JavaVersion.VERSION_1_8', 'targetCompatibility JavaVersion.VERSION_17'),
        ('jvmTarget = JavaVersion.VERSION_1_8', "jvmTarget = '17'"),
        ('jvmTarget = JavaVersion.VERSION_11', "jvmTarget = '17'"),
        ("jvmTarget = '1.8'", "jvmTarget = '17'"),
        ('jvmTarget = "1.8"', 'jvmTarget = "17"'),
    ]:
        new_content = new_content.replace(old, new)

    # 2. If the android block has NO compileOptions, add them before the closing }
    if 'compileOptions {' not in content and 'android {' in content:
        # Find the android block and add compileOptions before the first closing brace
        # that closes the android block
        android_end = None
        depth = 0
        in_android = False
        for i, line in enumerate(content.split('\n')):
            if 'android {' in line:
                in_android = True
                depth = 1
            elif in_android:
                depth += line.count('{') - line.count('}')
                if depth <= 0:
                    android_end = i
                    break
        
        if android_end is not None:
            lines = new_content.split('\n')
            indent = '    '  # 4 spaces
            insert = [
                f'{indent}compileOptions {{',
                f'{indent}    sourceCompatibility = JavaVersion.VERSION_17',
                f'{indent}    targetCompatibility = JavaVersion.VERSION_17',
                f'{indent}}}',
            ]
            for ins_line in reversed(insert):
                lines.insert(android_end, ins_line)
            new_content = '\n'.join(lines)

    # 3. If the android block has compileOptions but NO kotlinOptions, add them
    # Only add if the plugin uses kotlin-android (AGP 8.x LibraryExtension doesn't have kotlinOptions())
    if 'compileOptions {' in new_content and 'kotlinOptions {' not in new_content and 'kotlin-android' in new_content:
        lines = new_content.split('\n')
        insert_after = -1
        for i, line in enumerate(lines):
            if 'targetCompatibility' in line and 'VERSION_17' in line:
                insert_after = i
                break
        if insert_after >= 0:
            indent = '    '
            insert = [
                f'',
                f'{indent}kotlinOptions {{',
                f'{indent}    jvmTarget = \'17\'',
                f'{indent}}}',
            ]
            for ins_line in reversed(insert):
                lines.insert(insert_after + 1, ins_line)
            new_content = '\n'.join(lines)

    if new_content != content:
        with open(fp, 'w') as f:
            f.write(new_content)
        return True
    return False

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: fix_jvm_file.py <file>", file=sys.stderr)
        sys.exit(1)
    changed = fix_file(sys.argv[1])
    sys.exit(0 if changed else 1)
