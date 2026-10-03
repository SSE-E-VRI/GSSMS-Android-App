"""
extract_spec.py <pdf_path>
Extracts and dumps text spans (font, size, color, bbox, text) and drawings (rects, lines, fills) from a PDF.
"""
import sys
import json
import fitz  # PyMuPDF

def extract(pdf_path):
    doc = fitz.open(pdf_path)
    pages_data = []

    for page_num, page in enumerate(doc):
        # Extract text blocks and spans
        text_page = page.get_text("dict")
        spans = []
        for block in text_page.get("blocks", []):
            if block.get("type") == 0:  # text
                for line in block.get("lines", []):
                    for span in line.get("spans", []):
                        color = span.get("color")
                        # Format color as hex
                        hex_color = f"#{color:06x}" if isinstance(color, int) else str(color)
                        spans.append({
                            "text": span.get("text"),
                            "font": span.get("font"),
                            "size": round(span.get("size", 0), 2),
                            "color": hex_color,
                            "flags": span.get("flags"),
                            "bbox": [round(c, 2) for c in span.get("bbox", [])],
                        })

        # Extract drawings
        drawings = []
        for d in page.get_drawings():
            drawings.append({
                "type": d.get("type"),
                "rect": [round(c, 2) for c in d.get("rect", [])],
                "color": d.get("color"),
                "fill": d.get("fill"),
                "width": round(d.get("width", 0), 2) if d.get("width") is not None else None,
                "dashes": d.get("dashes"),
            })

        pages_data.append({
            "page": page_num + 1,
            "rect": [round(c, 2) for c in page.rect],
            "spans_count": len(spans),
            "drawings_count": len(drawings),
            "spans": spans,
            "drawings": drawings,
        })

    return {
        "file": pdf_path,
        "page_count": len(doc),
        "pages": pages_data,
    }

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: py extract_spec.py <pdf_path> [out.json]")
        sys.exit(1)

    pdf_file = sys.argv[1]
    data = extract(pdf_file)

    if len(sys.argv) >= 3:
        out_file = sys.argv[2]
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        print(f"Dumped spec to {out_file}")
    else:
        print(json.dumps(data, indent=2))
