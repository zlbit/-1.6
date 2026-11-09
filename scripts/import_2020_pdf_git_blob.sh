#!/usr/bin/env bash
# 导入CSU固定Git提交中的真实PDF（上游是普通Git Blob，而非LFS指针）。
# 使用说明：
#   bash import_2020_pdf_git_blob.sh
#   bash import_2020_pdf_git_blob.sh --browser-pdf '/c/Users/USER/Downloads/自然辩证法概论（修订版）.pdf'
# 在目标仓库根目录运行。不会自动提交或推送。
set -Eeuo pipefail

SOURCE_REPO="https://github.com/3210448723/CSUDialecticsOfNatureCourse.git"
SOURCE_COMMIT="81d52af8c7dcc1b9a20a2185c2d6f21110d76018"
SOURCE_PATH="教材/自然辩证法概论（修订版）/自然辩证法概论（修订版）.pdf"
EXPECTED_BLOB_SHA1="b3dbd2937bc101f3c55e220554cd6ef02651316f"
EXPECTED_SIZE=63524345

ROOT="$(git rev-parse --show-toplevel)"
DEST="$ROOT/00_原始资料/CSU/教材/自然辩证法概论（修订版）.pdf"
AUDIT="$ROOT/local_pdf_audit/$SOURCE_COMMIT"
VERIFY="$ROOT/scripts/verify_2020_pdf.py"

if [[ ! -f "$ROOT/01_教材索引/考点总索引.csv" || ! -f "$VERIFY" ]]; then
  echo '错误：请在 zlbit/-1.6 项目根目录执行（并确认已同步验证脚本）' >&2
  exit 2
fi
if [[ -e "$DEST" || -e "$AUDIT" ]]; then
  echo '错误：目标PDF或审计目录已存在，为防覆盖停止。请先人工检查。' >&2
  exit 3
fi
if [[ -n "${PYTHON:-}" ]]; then
  PYTHON_BIN="$PYTHON"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN=python
else
  echo '错误：无法找到Python' >&2
  exit 2
fi
"$PYTHON_BIN" -c 'import fitz' >/dev/null || {
  echo '错误：PyMuPDF缺失。请执行 python -m pip install pymupdf' >&2
  exit 2
}
git lfs version >/dev/null || {
  echo '错误：请先安装Git LFS（用于向你自己的仓库推送PDF）' >&2
  exit 2
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BOOK="$TMP/book.pdf"

if [[ "${1:-}" == '--browser-pdf' ]]; then
  if [[ $# -ne 2 || ! -f "$2" ]]; then
    echo '用法：bash import_2020_pdf_git_blob.sh --browser-pdf <已下载PDF的路径>' >&2
    exit 2
  fi
  cp "$2" "$BOOK"
elif [[ $# -ne 0 ]]; then
  echo '错误：未知参数。仅支持无参数或 --browser-pdf <路径>' >&2
  exit 2
else
  echo '[1/4] 从固定Git提交按需取得PDF普通Blob（不调用上游git-lfs fetch）'
  git init -q "$TMP/upstream"
  git -C "$TMP/upstream" remote add origin "$SOURCE_REPO"
  GIT_LFS_SKIP_SMUDGE=1 git -C "$TMP/upstream" fetch --no-tags --depth=1 --filter=blob:none origin "$SOURCE_COMMIT" || {
    echo 'GitHub网络访问失败。可以改由浏览器下载文件后使用 --browser-pdf 模式。' >&2
    exit 4
  }
  ACTUAL_BLOB_SHA1="$(git -C "$TMP/upstream" rev-parse "FETCH_HEAD:$SOURCE_PATH")"
  if [[ "$ACTUAL_BLOB_SHA1" != "$EXPECTED_BLOB_SHA1" ]]; then
    echo "错误：源提交文件Blob SHA不符: $ACTUAL_BLOB_SHA1" >&2
    exit 5
  fi
  # GitHub的按需对象下载有时会在这里失败；这意味着网络阻塞，不是LFS对象不存在。
  git -C "$TMP/upstream" cat-file blob "$ACTUAL_BLOB_SHA1" > "$BOOK" || {
    echo '无法从GitHub下载实际Git Blob；尝试浏览器下载备用入口。' >&2
    exit 4
  }
fi

echo '[2/4] 精确校验文件大小、Git Blob SHA-1、PDF文件头，计算SHA-256'
ACTUAL_BLOB_SHA1="$(git hash-object "$BOOK")"
if [[ "$ACTUAL_BLOB_SHA1" != "$EXPECTED_BLOB_SHA1" ]]; then
  echo "错误：下载内容不是固定源提交的原始Git Blob: $ACTUAL_BLOB_SHA1" >&2
  exit 5
fi
"$PYTHON_BIN" - "$BOOK" "$EXPECTED_SIZE" <<'PY'
import hashlib, sys
from pathlib import Path
p = Path(sys.argv[1]); size = int(sys.argv[2])
with p.open('rb') as f:
    magic = f.read(5)
if magic != b'%PDF-':
    raise SystemExit('错误：不是实际PDF文件')
if p.stat().st_size != size:
    raise SystemExit(f'错误：文件大小与固定Git树不一致 {p.stat().st_size} != {size}')
sha = hashlib.sha256()
with p.open('rb') as f:
    for chunk in iter(lambda: f.read(1024*1024), b''):
        sha.update(chunk)
print('Git Blob验证通过；bytes:', p.stat().st_size)
print('实际文件 SHA-256:', sha.hexdigest())
PY

echo '[3/4] 使用项目既有PDF验证器生成页面报告和抽查样张'
mkdir -p "$TMP/audit"
PDF_AUDIT_DIR="$TMP/audit" "$PYTHON_BIN" "$VERIFY" "$BOOK"

# 验证通过后才向工作树落盘。上游是Git Blob，目标仓库仍通过Git LFS追踪。
echo '[4/4] 保存真实PDF与本地审计；配置目标仓库Git LFS'
mkdir -p "$(dirname "$DEST")" "$(dirname "$AUDIT")"
cp "$BOOK" "$DEST"
mv "$TMP/audit" "$AUDIT"
git -C "$ROOT" lfs track '00_原始资料/CSU/教材/*.pdf'
echo "完成。真实PDF: $DEST"
echo "校验报告: $AUDIT/report.json"
echo '注意：版权页及印刷页码仍需人工核对，不要直接标记验收通过。'
echo '若未被忽略，请在 .gitignore 添加 local_pdf_audit/ ，避免将抽查图片一并推送。'
