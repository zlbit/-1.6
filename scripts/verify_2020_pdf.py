#!/usr/bin/env python3
"""Inspect PDF bytes and render candidate pages without assuming a page offset."""
import hashlib
import json
import os
import re
import sys
from pathlib import Path

import fitz

pdf_path = Path(sys.argv[1])
with pdf_path.open("rb") as handle:
    if handle.read(5) != b"%PDF-":
        raise ValueError("不是实际 PDF 文件")

digest = hashlib.sha256()
with pdf_path.open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
sha256 = digest.hexdigest()
doc = fitz.open(pdf_path)
if doc.needs_pass:
    raise ValueError("PDF 受密码保护，无法检查页面")

printed_pages = [1, 19, 52, 66, 80, 100, 123, 140, 145, 208, 219, 272, 320]
footer_candidates = {str(number): [] for number in printed_pages}
page_text_chars = []
for index, page in enumerate(doc):
    text = page.get_text("text")
    page_text_chars.append(len(text.strip()))
    footer = page.get_textbox(fitz.Rect(0, page.rect.height * 0.84, page.rect.width, page.rect.height))
    for number in printed_pages:
        if re.search(rf"(?<!\d)(?:P\s*)?{number}(?!\d)", footer, re.IGNORECASE):
            footer_candidates[str(number)].append(index + 1)

candidate_indexes = set(range(min(24, len(doc))))
for indexes in footer_candidates.values():
    candidate_indexes.update(pdf_page - 1 for pdf_page in indexes)

out = Path(os.environ.get("PDF_AUDIT_DIR", Path(__file__).resolve().parents[1] / "local_pdf_audit"))
out.mkdir(parents=True, exist_ok=True)
images = []
for index in sorted(candidate_indexes):
    name = f"pdf_{index + 1:04d}.png"
    doc[index].get_pixmap(matrix=fitz.Matrix(1, 1)).save(out / name)
    images.append({"pdf_page_one_based": index + 1, "file": name, "candidate_only": True})

expected_sha = os.environ.get("EXPECTED_LFS_SHA256")
expected_size = os.environ.get("EXPECTED_LFS_SIZE")
report = {
    "source_pdf": str(pdf_path),
    "size_bytes": pdf_path.stat().st_size,
    "sha256": sha256,
    "expected_lfs_sha256": expected_sha,
    "lfs_sha256_matches": sha256 == expected_sha if expected_sha else None,
    "expected_lfs_size_bytes": int(expected_size) if expected_size else None,
    "lfs_size_matches": pdf_path.stat().st_size == int(expected_size) if expected_size else None,
    "page_count": len(doc),
    "pages_with_extractable_text": sum(chars > 0 for chars in page_text_chars),
    "text_layer_page_count": len(page_text_chars),
    "page_text_chars": page_text_chars,
    "footer_printed_page_candidates": footer_candidates,
    "rendered_page_samples": images,
    "isbn_9787040535136_confirmed": False,
    "2020_edition_confirmed_by_visual_inspection": False,
    "printed_page_mapping_confirmed": False,
    "note": "页脚数字检索只生成候选页，必须人工检查页面图像和正文；未通过候选检索不能说明该页缺失。",
}
(out / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"PDF 结构检查完成：{len(doc)} 页；候选报告：{out / 'report.json'}")
