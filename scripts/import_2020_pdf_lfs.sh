#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
SOURCE_COMMIT="81d52af8c7dcc1b9a20a2185c2d6f21110d76018"
SRC="https://github.com/3210448723/CSUDialecticsOfNatureCourse.git"
SP="教材/自然辩证法概论（修订版）/自然辩证法概论（修订版）.pdf"
OUT="$ROOT/00_原始资料/CSU/教材/自然辩证法概论（修订版）.pdf"
AUDIT_OUT="$ROOT/local_pdf_audit/$SOURCE_COMMIT"
if [[ -n "${PYTHON:-}" ]]; then
  PYTHON_BIN="$PYTHON"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN=python
else
  echo "找不到 Python；请安装 Python 与 PyMuPDF。" >&2
  exit 2
fi
git lfs version >/dev/null || { echo "请先安装 Git LFS。" >&2; exit 2; }
"$PYTHON_BIN" -c 'import fitz' || { echo "请安装 PyMuPDF：python -m pip install pymupdf" >&2; exit 2; }
[[ ! -e "$OUT" ]] || { echo "目标文件已存在，为避免覆盖而停止：$OUT" >&2; exit 3; }
[[ ! -e "$AUDIT_OUT" ]] || { echo "本次审计目录已存在，为避免覆盖而停止：$AUDIT_OUT" >&2; exit 3; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git init -q "$TMP/src"
git -C "$TMP/src" remote add origin "$SRC"
GIT_LFS_SKIP_SMUDGE=1 git -C "$TMP/src" fetch --depth=1 origin "$SOURCE_COMMIT"
GIT_LFS_SKIP_SMUDGE=1 git -C "$TMP/src" checkout --detach FETCH_HEAD
git -C "$TMP/src" show "$SOURCE_COMMIT:$SP" > "$TMP/pointer"
git -C "$TMP/src" lfs fetch --include="$SP" origin "$SOURCE_COMMIT"
git -C "$TMP/src" lfs checkout "$SP"
read -r EXPECTED_OID EXPECTED_SIZE < <("$PYTHON_BIN" - "$TMP/pointer" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
oid = re.search(r"(?m)^oid sha256:([0-9a-f]{64})$", text)
size = re.search(r"(?m)^size (\d+)$", text)
if not text.startswith("version https://git-lfs.github.com/spec/v1\n") or not oid or not size:
    raise SystemExit("固定提交中的文件不是有效的 Git LFS 指针")
print(oid.group(1), size.group(1))
PY
)
"$PYTHON_BIN" - "$TMP/src/$SP" "$EXPECTED_OID" "$EXPECTED_SIZE" <<'PY'
import hashlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
expected_sha, expected_size = sys.argv[2], int(sys.argv[3])
digest = hashlib.sha256()
with path.open("rb") as handle:
    header = handle.read(5)
    digest.update(header)
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
actual_sha = digest.hexdigest()
actual_size = path.stat().st_size
if header != b"%PDF-":
    raise SystemExit("下载内容不是实际 PDF 文件")
if actual_sha != expected_sha or actual_size != expected_size:
    raise SystemExit(f"LFS 校验失败：SHA-256 {actual_sha}，字节数 {actual_size}")
print(f"LFS 校验通过：SHA-256 {actual_sha}，字节数 {actual_size}")
PY
mkdir -p "$TMP/audit"
EXPECTED_LFS_SHA256="$EXPECTED_OID" EXPECTED_LFS_SIZE="$EXPECTED_SIZE" PDF_AUDIT_DIR="$TMP/audit" \
  "$PYTHON_BIN" "$ROOT/scripts/verify_2020_pdf.py" "$TMP/src/$SP"
git -C "$ROOT" lfs track '00_原始资料/CSU/教材/*.pdf'
mkdir -p "$(dirname "$OUT")" "$(dirname "$AUDIT_OUT")"
cp "$TMP/src/$SP" "$OUT"
mv "$TMP/audit" "$AUDIT_OUT"
echo "已本地导入并生成审计；请检查校验报告、图片与纸书后自行git add/commit/push。"
