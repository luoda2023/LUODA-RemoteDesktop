#!/usr/bin/env python3
"""Debug: find all build.gradle files with com.android.library and show targets."""
import hashlib, os, re, sys, glob

FIXES = [
    (re.compile(r'sourceCompatibility\s*=\s*JavaVersion\.[A-Z_0-9]+'), 'sourceCompatibility = JavaVersion.VERSION_17'),
    (re.compile(r"sourceCompatibility\s*=\s*['\"]?\d+\.\d+['\"]?"), 'sourceCompatibility = JavaVersion.VERSION_17'),
    (re.compile(r'sourceCompatibility\s+JavaVersion\.[A-Z_0-9]+'), 'sourceCompatibility JavaVersion.VERSION_17'),
    (re.compile(r'targetCompatibility\s*=\s*JavaVersion\.[A-Z_0-9]+'), 'targetCompatibility = JavaVersion.VERSION_17'),
    (re.compile(r"targetCompatibility\s*=\s*['\"]?\d+\.\d+['\"]?"), 'targetCompatibility = JavaVersion.VERSION_17'),
    (re.compile(r'targetCompatibility\s+JavaVersion\.[A-Z_0-9]+'), 'targetCompatibility JavaVersion.VERSION_17'),
    (re.compile(r"jvmTarget\s*=\s*'[0-9.]+'"), "jvmTarget = '17'"),
    (re.compile(r'jvmTarget\s*=\s*"[0-9.]+"'), 'jvmTarget = "17"'),
    (re.compile(r'jvmTarget\s*=\s*JavaVersion\.[A-Z_0-9]+'), "jvmTarget = '17'"),
]


def main():
    candidates = []
    for env_var in ['FLUTTER_ROOT', 'HOME']:
        val = os.environ.get(env_var)
        if val:
            candidates.append(os.path.join(val, '.pub-cache'))
    candidates.append('/opt/hostedtoolcache/flutter/stable-3.24.5-x64/.pub-cache')
    gw = os.environ.get('GITHUB_WORKSPACE', '')
    if gw:
        candidates.append(os.path.join(gw, 'flutter', '.pub-cache'))

    total_found = 0
    total_changed = 0

    # First check: does external_path exist?
    for cache_dir in candidates:
        if os.path.isdir(cache_dir):
            ext_dir = os.path.join(cache_dir, 'hosted', 'pub.dev', 'external_path-1.0.3', 'android')
            if os.path.isdir(ext_dir):
                print(f"  CHECK: external_path directory EXISTS at {ext_dir}")
                for item in os.listdir(ext_dir):
                    print(f"    - {item}")
            else:
                print(f"  CHECK: external_path directory NOT FOUND at {ext_dir}")
        else:
            print(f"  CHECK: {cache_dir} not found")

    for cache_dir in candidates:
        if not os.path.isdir(cache_dir):
            continue
        print(f"\nScanning: {cache_dir}")
        # Use glob to find all build.gradle files recursively
        pattern = os.path.join(cache_dir, '**', 'build.gradle')
        for fp in glob.glob(pattern, recursive=True):
            try:
                with open(fp, 'r', encoding='utf-8', errors='replace') as fh:
                    content = fh.read()
            except Exception as e:
                continue

            if 'com.android.library' not in content and 'com.android.application' not in content:
                continue

            total_found += 1

            # Print every found file with targets
            if any(k in content for k in ['sourceCompatibility', 'targetCompatibility', 'jvmTarget']):
                print(f"  FOUND: {fp}")
                for i, line in enumerate(content.split('\n'), 1):
                    s = line.strip()
                    if any(k in s for k in ['sourceCompatibility', 'targetCompatibility', 'jvmTarget']):
                        print(f"    L{i}: {repr(line)}")

            new_content = content
            for pattern, replacement in FIXES:
                new_content = pattern.sub(replacement, new_content)

            # 3. If compileOptions exists but NO kotlinOptions AND kotlin-android, add kotlinOptions
            # (Prevents Java/Kotlin JVM target mismatch in AGP 8.x)
            if 'compileOptions {' in new_content and 'kotlinOptions {' not in new_content and 'kotlin-android' in new_content:
                nlines = new_content.split('\n')
                ins_idx = -1
                for idx, ln in enumerate(nlines):
                    if 'targetCompatibility' in ln and 'VERSION_17' in ln:
                        ins_idx = idx
                        break
                if ins_idx >= 0:
                    igr = '    '
                    add = ['', igr + 'kotlinOptions {', igr + '    jvmTarget = \'17\'', igr + '}']
                    for al in reversed(add):
                        nlines.insert(ins_idx + 1, al)
                    new_content = '\n'.join(nlines)
                    print("    -> kotlinOptions ADDED")

            if new_content != content:
                with open(fp, 'w', encoding='utf-8') as fh:
                    fh.write(new_content)
                total_changed += 1
                print(f"    -> PATCHED")

    print(f"\n=== Result: {total_found} found, {total_changed} patched ===")


if __name__ == '__main__':
    main()
