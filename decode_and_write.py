import os, sys, json, py_compile, base64

fpath = r'C:\Users\Administrator\.qclaw\workspace-yw3plsutb1jupnif\tmp_check\LUODA-RemoteDesktop\auto_build_and_test.py'

# Read the b64 encoded data from this same file
with open(__file__, 'r', encoding='utf-8') as f:
    lines = f.readlines()

b64_lines = []
in_b64 = False
for line in lines:
    if line.strip() == '# B64_START':
        in_b64 = True
        continue
    if line.strip() == '# B64_END':
        in_b64 = False
        continue
    if in_b64:
        b64_lines.append(line.strip())

if b64_lines:
    b64_data = ''.join(b64_lines)
    decoded = base64.b64decode(b64_data).decode('utf-8')
    with open(fpath, 'w', encoding='utf-8') as f:
        f.write(decoded)
    print(f'Written: {os.path.getsize(fpath)} bytes')
    try:
        py_compile.compile(fpath, doraise=True)
        print('Syntax OK')
    except py_compile.PyCompileError as e:
        print(f'Syntax error: {e}')
else:
    print('No B64 data found')
