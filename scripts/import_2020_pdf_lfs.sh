#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
SRC="https://github.com/3210448723/CSUDialecticsOfNatureCourse.git"
SP="教材/自然辩证法概论（修订版）/自然辩证法概论（修订版）.pdf"
OUT="$ROOT/00_原始资料/CSU/教材/自然辩证法概论（修订版）.pdf"
git lfs version >/dev/null || { echo "请先安装 Git LFS"; exit 2; }
python3 -c 'import fitz' || { echo "请先安装 PyMuPDF: python3 -m pip install pymupdf"; exit 2; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --filter=blob:none "$SRC" "$TMP/src"
git -C "$TMP/src" lfs pull --include="$SP" --exclude=""
python3 - "$TMP/src/$SP" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]); assert p.exists() and p.read_bytes()[:5]==b'%PDF-', '下载到的不是实际PDF'
print("上游真实PDF字节数:",p.stat().st_size)
PY
mkdir -p "$(dirname "$OUT")"
cp "$TMP/src/$SP" "$OUT"
python3 "$ROOT/scripts/verify_2020_pdf.py" "$OUT"
git -C "$ROOT" lfs track '00_原始资料/CSU/教材/*.pdf'
echo "已本地导入并生成审计；请检查校验报告、图片与纸书后自行git add/commit/push。"
