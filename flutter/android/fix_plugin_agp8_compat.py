#!/usr/bin/env python3
"""
Fix AGP 8.x compatibility issues in Flutter plugin build.gradle files.

Scans pub cache for Android library modules and fixes:
1. Replace conditional namespace wrappers with direct namespace assignments
2. Rename 'compileSdk NNN' to 'compileSdkVersion NNN' (AGP 8.x compat)
3. Remove kotlinOptions blocks that are nested inside compileOptions blocks
4. Add missing compileSdkVersion to plugins without any compileSdk setting
5. Add missing kotlinOptions to plugins with compileOptions but no kotlinOptions
"""

import glob
import os
import re
import sys


def has_property_condition(text, match_str):
    """Check if file has a hasProperty check for the given property."""
    return bool(re.search(r'hasProperty\s*\(\s*["\']' + re.escape(match_str) + r'["\']', text))


def remove_conditional_namespace(content):
    """Remove if (project.android.hasProperty('namespace')) {...} wrapper and replace with direct namespace."""
    # Find conditional namespace blocks and replace with direct namespace
    lines = content.split('\n')
    result = []
    i = 0
    modified = False
    
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        indent = line[:len(line) - len(line.lstrip())]
        
        # Check if this line starts a conditional namespace block
        if ('if' in stripped and 'hasProperty' in stripped and 'namespace' in stripped):
            # Found the conditional namespace check
            # Scan ahead to find the namespace value inside
            namespace_value = None
            block_depth = 1
            j = i + 1
            while j < len(lines) and block_depth > 0:
                js = lines[j].strip()
                # Check for namespace assignment
                ns_match = re.search(r"namespace\s+['\"]([\w.]+)['\"]", js)
                if ns_match and block_depth == 1:
                    namespace_value = ns_match.group(1)
                block_depth += js.count('{') - js.count('}')
                j += 1
            
            if namespace_value:
                # In AGP 8.x, use direct namespace assignment
                result.append(f'{indent}    namespace = "{namespace_value}"')
                modified = True
                # Skip to after the closing brace
                i = j
                continue
        
        result.append(line)
        i += 1
    
    return '\n'.join(result), modified


def fix_compile_sdk(content):
    """Replace 'compileSdk NNN' with 'compileSdkVersion NNN'."""
    lines = content.split('\n')
    result = []
    modified = False
    
    for line in lines:
        stripped = line.strip()
        # Match compileSdk (without Version) followed by a number
        if re.match(r'^\s*compileSdk\s+\d+\s*$', stripped):
            new_line = re.sub(r'compileSdk\s+(\d+)', r'compileSdkVersion \1', line)
            result.append(new_line)
            modified = True
        else:
            result.append(line)
    
    return '\n'.join(result), modified


def fix_kotlin_options_in_android(content):
    """Fix kotlinOptions block issues inside android {} blocks.
    
    1. kotlinOptions inside compileOptions { ... } → moved outside
    2. kotlinOptions at android {} level for plugins WITHOUT kotlin-android → REMOVED
       (LibraryExtension in AGP 8.x does not support kotlinOptions())
    3. kotlinOptions at android {} for plugins WITH kotlin-android → KEPT
       (needed to prevent Java/Kotlin JVM target mismatch)
    """
    has_kotlin = 'kotlin-android' in content or 'kotlin.android' in content
    
    lines = content.split('\n')
    result = []
    i = 0
    modified = False
    in_android = False
    in_compile_options = False
    android_depth = 0
    compile_depth = 0
    ko_lines_buffer = []  # buffer kotlinOptions from inside compileOptions
    # First pass: find android block boundaries
    lines = content.split('\n')
    result = []
    i = 0
    modified = False
    in_android = False
    in_compile_options = False
    android_depth = 0
    compile_depth = 0
    ko_lines_buffer = []  # buffer kotlinOptions lines to re-insert outside compileOptions
    
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        indent = line[:len(line) - len(line.lstrip())]
        
        # Track android block
        if not in_android and re.match(r'^\s*android\s*\{', stripped):
            in_android = True
            android_depth = 1
            result.append(line)
            i += 1
            continue
        
        if not in_android:
            result.append(line)
            i += 1
            continue
        
        # Inside android block now
        
        # Track compileOptions nesting (at top, before depth tracking)
        if re.match(r'^\s*compileOptions\s*\{', stripped):
            in_compile_options = True
            compile_depth = 1
            android_depth += 1  # the { contributes to android depth
            result.append(line)
            i += 1
            continue
        
        if in_compile_options:
            # Inside compileOptions - check for kotlinOptions
            if re.match(r'^\s*kotlinOptions\s*\{', stripped):
                # Found kotlinOptions inside compileOptions - buffer it
                modified = True
                ko_lines_buffer = [stripped]
                ko_depth = 1
                i += 1
                while i < len(lines) and ko_depth > 0:
                    sk = lines[i].strip()
                    ko_depth += sk.count('{') - sk.count('}')
                    if ko_depth >= 0:
                        ko_lines_buffer.append(sk)
                    i += 1
                continue
            
            compile_depth += stripped.count('{') - stripped.count('}')
            if compile_depth <= 0:
                in_compile_options = False
                compile_depth = 0
                android_depth -= 1  # the } that closes compileOptions
                result.append(line)
                # Insert buffered kotlinOptions right after compileOptions closes
                if ko_lines_buffer:
                    and_indent = indent
                    for kl in ko_lines_buffer:
                        result.append(f'{and_indent}    {kl}')
                    ko_lines_buffer = []
                i += 1
                continue
            
            result.append(line)
            i += 1
            continue
        
        # Handle kotlinOptions at android level for non-kotlin plugins
        if not has_kotlin and re.match(r'^\s*kotlinOptions\s*\{', stripped):
            # Remove kotlinOptions block (LibraryExtension doesn't support it)
            modified = True
            ko_depth = 1
            i += 1
            while i < len(lines) and ko_depth > 0:
                sk = lines[i].strip()
                ko_depth += sk.count('{') - sk.count('}')
                i += 1
            continue
        
        # Track android depth (only when NOT in nested blocks)
        android_depth += stripped.count('{') - stripped.count('}')
        if android_depth <= 0:
            in_android = False
        
        result.append(line)
        i += 1
    
    return '\n'.join(result), modified


def fix_missing_compile_sdk(content):
    """Add compileSdkVersion if the android block exists but has no compileSdk."""
    if 'compileSdk' in content or 'compileSdkVersion' in content:
        return content, False
    
    if 'android {' not in content:
        return content, False
    
    lines = content.split('\n')
    result = []
    in_android = False
    android_depth = 0
    compile_added = False
    
    for line in lines:
        stripped = line.strip()
        indent = line[:len(line) - len(line.lstrip())]
        
        if not in_android and re.match(r'^\s*android\s*\{', stripped):
            in_android = True
            android_depth = 1
            result.append(line)
            # Add compileSdkVersion as the first line inside android
            result.append(f'{indent}    compileSdkVersion 34')
            compile_added = True
            continue
        
        if in_android:
            android_depth += stripped.count('{') - stripped.count('}')
            if android_depth <= 0:
                in_android = False
        
        result.append(line)
    
    return '\n'.join(result), compile_added


def fix_missing_kotlin_options(content):
    """Add kotlinOptions to android block if compileOptions exists but no kotlinOptions.
    This prevents Java/Kotlin JVM target mismatch (external_path issue)."""
    if 'kotlinOptions' in content:
        return content, False
    if 'compileOptions' not in content:
        return content, False
    if 'android {' not in content:
        return content, False
    
    lines = content.split('\n')
    result = []
    in_android = False
    android_depth = 0
    in_compile_options = False
    compile_depth = 0
    wrapped_kotlin = False
    
    for line in lines:
        stripped = line.strip()
        indent = line[:len(line) - len(line.lstrip())]
        
        if not in_android and re.match(r'^\s*android\s*\{', stripped):
            in_android = True
            android_depth = 1
        elif in_android:
            android_depth += stripped.count('{') - stripped.count('}')
            if android_depth <= 0:
                in_android = False
        
        if not in_compile_options and re.match(r'^\s*compileOptions\s*\{', stripped):
            in_compile_options = True
            compile_depth = 1
        elif in_compile_options:
            compile_depth += stripped.count('{') - stripped.count('}')
            if compile_depth <= 0:
                in_compile_options = False
                # Right after compileOptions closes, add kotlinOptions
                if 'kotlinOptions' not in content and in_android:
                    result.append(line)
                    result.append(f'{indent}    kotlinOptions {{')
                    result.append(f'{indent}        jvmTarget = "17"')
                    result.append(f'{indent}    }}')
                    wrapped_kotlin = True
                    continue
        
        result.append(line)
    
    return '\n'.join(result), wrapped_kotlin


def has_namespace(content):
    """Check if the content already has a namespace declaration in android block."""
    return bool(re.search(r'namespace\s*(?:=\s*)?[\'"][\w.]+[\'"]', content))


def infer_namespace_from_manifest(build_gradle_path):
    """Try to get namespace from AndroidManifest.xml."""
    manifest = os.path.join(os.path.dirname(build_gradle_path), 'src', 'main', 'AndroidManifest.xml')
    alt_manifest = os.path.join(os.path.dirname(build_gradle_path), 'AndroidManifest.xml')
    
    for mf in [manifest, alt_manifest]:
        if os.path.isfile(mf):
            try:
                with open(mf, 'r', encoding='utf-8', errors='replace') as f:
                    mf_content = f.read(2000)
                m = re.search(r'package\s*=\s*"([\w.]+)"', mf_content)
                if m:
                    return m.group(1)
            except Exception:
                pass
    return None


def infer_namespace_from_source(build_gradle_path):
    """Try to get package from source files."""
    src_dir = os.path.join(os.path.dirname(build_gradle_path), 'src', 'main')
    if not os.path.isdir(src_dir):
        return None
    
    for root, _, files in os.walk(src_dir):
        for fn in files:
            if fn.endswith(('.java', '.kt')):
                fp = os.path.join(root, fn)
                try:
                    with open(fp, 'r', encoding='utf-8', errors='replace') as f:
                        content = f.read(2000)
                    m = re.search(r'^package\s+([\w.]+)', content, re.MULTILINE)
                    if m:
                        return m.group(1)
                except Exception:
                    continue
    return None


def infer_namespace_from_path(build_gradle_path):
    """Infer namespace from the plugin cache directory path."""
    parts = build_gradle_path.split(os.sep)
    try:
        # Find the pub cache plugin directory name (e.g., external_path-1.0.3)
        for i, part in enumerate(parts):
            if part in ('pub.dev',) and i + 1 < len(parts):
                plugin_dir = parts[i + 1]
                # Remove version suffix
                plugin_name = re.sub(r'-\d+\.\d+.*$', '', plugin_dir)
                # Convert underscores/hyphens to dots
                pkg_name = plugin_name.replace('-', '.').replace('_', '.')
                return f"io.flutter.plugins.{pkg_name}"
    except Exception:
        pass
    return None


def add_namespace_to_android(content, filepath):
    """Add namespace to android block if missing."""
    if has_namespace(content):
        return content, False
    
    if 'android {' not in content:
        return content, False
    
    # Try to find namespace
    ns = infer_namespace_from_manifest(filepath)
    if not ns:
        ns = infer_namespace_from_source(filepath)
    if not ns:
        ns = infer_namespace_from_path(filepath)
    if not ns:
        return content, False
    
    lines = content.split('\n')
    result = []
    in_android = False
    android_depth = 0
    ns_added = False
    
    for line in lines:
        stripped = line.strip()
        indent = line[:len(line) - len(line.lstrip())]
        
        if not in_android and re.match(r'^\s*android\s*\{', stripped):
            in_android = True
            android_depth = 1
            result.append(line)
            # Insert namespace as first line inside android block
            result.append(f'{indent}    namespace = "{ns}"')
            ns_added = True
            continue
        
        if in_android:
            android_depth += stripped.count('{') - stripped.count('}')
            if android_depth <= 0:
                in_android = False
        
        result.append(line)
    
    return '\n'.join(result), ns_added


def fix_file(filepath):
    """Run all fixes on a single file."""
    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    
    original = content
    
    # Fix 1: Skip - conditional namespace wrappers (if hasProperty("namespace") { namespace ... })
    # are VALID in AGP 8.x and work correctly. Don't replace them.
    ns_con_fixed = False
    
    # Fix 2: Fix compileSdk naming
    content, cs_fixed = fix_compile_sdk(content)
    
    # Fix 3: Add missing kotlinOptions after compileOptions (run BEFORE removal check)
    content, ko_added = fix_missing_kotlin_options(content)
    
    # Fix 4: Add missing compileSdkVersion (only if still missing)
    content, cs_added = fix_missing_compile_sdk(content)
    
    # Fix 5: Remove kotlinOptions for non-kotlin-android plugins (AGP 8.x LibraryExtension)
    content, ko_fixed = fix_kotlin_options_in_android(content)
    
    # Fix 6: Add missing namespace
    content, ns_added = add_namespace_to_android(content, filepath)
    
    if content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        return True, (ns_con_fixed, cs_fixed, ko_fixed, cs_added, ko_added, ns_added)
    return False, (False, False, False, False, False, False)


def main():
    total_checked = 0
    total_fixed = 0
    
    # Scan pub cache dirs
    candidates = []
    for env_var in ['FLUTTER_ROOT', 'HOME', 'PUB_CACHE']:
        val = os.environ.get(env_var)
        if val and env_var == 'PUB_CACHE':
            candidates.append(val)
        elif val:
            candidates.append(os.path.join(val, '.pub-cache'))
    candidates.append('/opt/hostedtoolcache/flutter/stable-3.24.5-x64/.pub-cache')
    
    gw = os.environ.get('GITHUB_WORKSPACE', '')
    if gw:
        candidates.append(os.path.join(gw, 'flutter', '.pub-cache'))
    
    for cache_dir in candidates:
        if not os.path.isdir(cache_dir):
            print(f"  SKIP: {cache_dir} not found")
            continue
        
        print(f"\nScanning: {cache_dir}")
        pattern = os.path.join(cache_dir, '**', 'build.gradle')
        for fp in sorted(glob.glob(pattern, recursive=True)):
            try:
                with open(fp, 'r', encoding='utf-8', errors='replace') as f:
                    header = f.read(2000)
            except Exception:
                continue
            
            if 'com.android.library' not in header and 'com.android.application' not in header and 'id("com.android.library")' not in header and "id 'com.android.library'" not in header and 'android.library' not in header:
                continue
            
            total_checked += 1
            name = os.path.relpath(fp, cache_dir)
            
            fixed, fixes = fix_file(fp)
            if fixed:
                ns_con, cs, ko, cs_add, ko_add, ns_add = fixes
                details = []
                if ns_con: details.append('namespace_conditional')
                if cs: details.append('compileSdk')
                if ko: details.append('kotlinOptions_position')
                if cs_add: details.append('compileSdk_added')
                if ko_add: details.append('kotlinOptions_added')
                if ns_add: details.append('namespace_added')
                total_fixed += 1
                print(f"  FIXED [{','.join(details)}]: {name}")
            else:
                print(f"  OK: {name}")
    
    print(f"\n=== Result: {total_checked} checked, {total_fixed} fixed ===")
    return 0 if total_fixed >= 0 else 1


if __name__ == '__main__':
    sys.exit(main())
