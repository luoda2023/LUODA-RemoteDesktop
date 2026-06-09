#!/usr/bin/env python3
"""
Fix kotlinOptions placement in Flutter plugin build.gradle files.

AGP 8.x removed kotlinOptions() from CompileOptions (CompileOptions$AgpDecorated).
Some Flutter plugins (e.g. file_picker) had kotlinOptions nested inside compileOptions {},
which worked in older AGP but fails in AGP 8.x.

This script:
  1. Scans the Flutter pub cache for plugin build.gradle files
  2. Moves kotlinOptions {} blocks OUTSIDE of compileOptions {} (to android {} level)
  3. If moving is not possible, removes the nested kotlinOptions block (safe because
     the app-level build.gradle.kts already sets kotlinOptions globally)
"""

import glob
import os
import re
import sys


def fix_kotlin_options_in_file(filepath):
    """Move kotlinOptions {} blocks outside of compileOptions {} blocks."""
    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    
    original = content
    lines = content.split('\n')
    
    # State machine states
    result = []
    i = 0
    pending_kotlin_lines = []  # lines from kotlinOptions to be moved outside
    
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        
        # Skip lines that are kotlinOptions lines caught by the marker system
        if pending_kotlin_lines and i in pending_kotlin_lines:
            i += 1
            continue
            
        result.append(line)
        i += 1
    
    new_content = '\n'.join(result)
    if new_content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        return True
    return False


def find_kotlin_options_blocks(content):
    """
    Find kotlinOptions blocks and determine if they are inside compileOptions.
    Returns list of (start_line, end_line, is_inside_compile_options) tuples.
    """
    lines = content.split('\n')
    blocks = []
    
    # Track scope nesting
    in_android = False
    android_depth = 0
    in_compile_options = False
    compile_depth = 0
    in_kotlin_options = False
    kotlin_start = -1
    kotlin_depth = 0
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        braces_open = stripped.count('{')
        braces_close = stripped.count('}')
        
        # Detect android { block
        if not in_android and re.match(r'^\s*android\s*\{', stripped):
            in_android = True
            android_depth = 1
            continue
        
        if in_android:
            # Check if we're entering compileOptions
            if not in_compile_options and re.match(r'^\s*compileOptions\s*\{', stripped):
                in_compile_options = True
                compile_depth += 1
            
            # Check if we're inside a kotlinOptions block
            if not in_kotlin_options and re.match(r'^\s*kotlinOptions\s*\{', stripped):
                in_kotlin_options = True
                kotlin_start = i
                kotlin_depth += braces_open
            
            if in_kotlin_options:
                kotlin_depth += braces_open - braces_close
                if kotlin_depth <= 0:
                    # End of kotlinOptions block
                    blocks.append({
                        'start': kotlin_start,
                        'end': i,
                        'inside_compile': in_compile_options,
                    })
                    in_kotlin_options = False
                    kotlin_start = -1
            
            # Track compileOptions depth
            if in_compile_options:
                compile_depth += braces_open - braces_close
                if compile_depth <= 0:
                    in_compile_options = False
                    compile_depth = 0
            
            # Track android depth
            android_depth += braces_open - braces_close
            if android_depth <= 0:
                in_android = False
    
    return blocks


def move_kotlin_options_outside_compile(filepath):
    """Move kotlinOptions from inside compileOptions to android level."""
    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    
    original = content
    blocks = find_kotlin_options_blocks(content)
    
    # Find kotlinOptions blocks that are inside compileOptions
    bad_blocks = [b for b in blocks if b['inside_compile']]
    if not bad_blocks:
        return False
    
    lines = content.split('\n')
    
    # Process blocks in reverse order to maintain line numbers
    for block in sorted(bad_blocks, key=lambda x: x['start'], reverse=True):
        start = block['start']
        end = block['end']
        
        # Extract the kotlinOptions block content
        kotlin_lines = lines[start:end + 1]
        
        # Determine indentation (use 4 spaces)
        kotlin_indent = '    '
        
        # Find the compileOptions block start (scan backwards)
        compile_start = -1
        for j in range(start - 1, -1, -1):
            if re.match(r'^\s*compileOptions\s*\{', lines[j]):
                compile_start = j
                break
        
        # Find the android block start (scan backwards from compile start)
        android_start = -1
        for j in range(compile_start - 1, -1, -1):
            if re.match(r'^\s*android\s*\{', lines[j]):
                android_start = j
                break
        
        if android_start < 0:
            # Can't find android block, just remove the kotlinOptions (safe fallback)
            lines[start:end + 1] = []
        else:
            # Remove kotlinOptions from inside compileOptions
            lines[start:end + 1] = []
            
            # Insert kotlinOptions at android level (after android { line)
            new_kotlin_block = []
            for kl in kotlin_lines:
                # Preserve content but indent at android level
                content_line = kl.strip()
                if content_line == 'kotlinOptions {' or content_line == '}' or re.match(r'^\s*\}', content_line):
                    new_kotlin_block.append(kotlin_indent + content_line)
                else:
                    new_kotlin_block.append(kotlin_indent * 2 + content_line.strip())
            
            # Find the position right after android { line
            insert_pos = -1
            for j in range(android_start + 1, len(lines)):
                stripped = lines[j].strip()
                if stripped == '' or stripped.startswith('//'):
                    continue
                # Insert before the first non-comment line inside android block
                insert_pos = j
                break
            
            if insert_pos < 0:
                insert_pos = android_start + 1
            
            # Insert the kotlinOptions block
            for kl in reversed(new_kotlin_block):
                lines.insert(insert_pos, kl)
    
    new_content = '\n'.join(lines)
    if new_content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"    -> FIXED: moved kotlinOptions outside compileOptions in {filepath}")
        return True
    return False


def main():
    # Scan pub cache dirs
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
    total_fixed = 0
    
    for cache_dir in candidates:
        if not os.path.isdir(cache_dir):
            print(f"SKIP: {cache_dir} not found")
            continue
        
        print(f"\nScanning: {cache_dir}")
        pattern = os.path.join(cache_dir, '**', 'build.gradle')
        for fp in sorted(glob.glob(pattern, recursive=True)):
            try:
                with open(fp, 'r', encoding='utf-8', errors='replace') as f:
                    content = f.read()
            except Exception:
                continue
            
            # Only process Android library or application modules
            if 'com.android.library' not in content and 'com.android.application' not in content:
                continue
            
            # Quick check: does this file have kotlinOptions?
            if 'kotlinOptions' not in content:
                continue
            
            total_found += 1
            print(f"  CHECK: {os.path.relpath(fp, cache_dir)}")
            
            if move_kotlin_options_outside_compile(fp):
                total_fixed += 1
    
    print(f"\n=== Result: {total_found} files with kotlinOptions, {total_fixed} fixed ===")
    return 0 if total_fixed >= 0 else 1


if __name__ == '__main__':
    sys.exit(main())
