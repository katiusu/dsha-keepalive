#!/usr/bin/env bash
# 打包成可刷入的模块 zip
set -e
cd "$(dirname "$0")"
VER=$(sed -n 's/^version=//p' module.prop)
OUT="dsha-keepalive-${VER}.zip"
python3 - "$OUT" <<'PY'
import sys, zipfile, os
out = sys.argv[1]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for dirpath, _, files in os.walk('.'):
        for f in sorted(files):
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, '.')
            if rel.startswith('.') or rel.endswith('.zip'):
                continue
            zi = zipfile.ZipInfo(rel)
            zi.external_attr = (0o100755 << 16) if f.endswith('.sh') else (0o100644 << 16)
            zi.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(zi, open(p, 'rb').read())
print(out, os.path.getsize(out), 'bytes')
PY
