#!/usr/bin/env python3
"""检查PDF格式/页数/版权与目录候选；不推断PDF页号等于印刷页号。"""
from pathlib import Path
import hashlib,json,sys
import fitz
p=Path(sys.argv[1])
with p.open("rb") as f: assert f.read(5)==b'%PDF-',"不是PDF"
doc=fitz.open(p)
if len(doc)<350: raise ValueError("总页数异常，停止核验")
out=Path(__file__).resolve().parents[1]/"local_pdf_audit"
out.mkdir(parents=True,exist_ok=True)
sample_indexes=sorted(set([0,1,2,12,13,14,15]+[n+14 for n in [1,7,52,66,100,123,145,208,219,320] if n+14<len(doc)]))
images=[]
for i in sample_indexes:
    name=f"pdf_{i+1:04d}.png"
    doc[i].get_pixmap(matrix=fitz.Matrix(1,1)).save(out/name)
    images.append({"pdf_page_one_based":i+1,"file":name,"candidate_only":True})
report={"source_pdf":str(p),"size_bytes":p.stat().st_size,"sha256":hashlib.sha256(p.read_bytes()).hexdigest(),"page_count":len(doc),"sample_text_chars":[len(doc[i].get_text()) for i in sample_indexes],"rendered_page_samples":images,"isbn_9787040535136_confirmed":False,"2020_edition_confirmed_by_visual_inspection":False,"printed_page_offset_confirmed":False,"note":"所有候选图都要人工核对页脚印刷页与版权页。当前未确定PDF页序与纸书页码的偏移。"}
(out/"report.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
print("完成结构审计，请查看",out/"report.json")
