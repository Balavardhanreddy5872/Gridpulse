"""
PDF ingestion for infrastructure/outage reports.

Uses pdfplumber (lightweight, reliable) to pull raw text, then applies a
few forgiving regex passes to *try* to auto-fill capacity_impact_mw,
start_date, end_date, and description. Auto-extraction is best-effort:
if a field can't be found confidently, it is left as None so the caller
(the API) can fall back to values the operator supplies manually in the
upload form. We never guess silently - the extracted_text is always
stored so a human can verify.
"""
import re
from datetime import datetime
from typing import Optional

import pdfplumber

CAPACITY_PATTERN = re.compile(
    r"(?:reduc\w*|impact\w*|derat\w*)\D{0,20}?(\d+(?:\.\d+)?)\s*MW", re.IGNORECASE
)
DATE_PATTERN = re.compile(
    r"(\d{4}-\d{2}-\d{2})|(\d{1,2}/\d{1,2}/\d{2,4})"
)


def extract_text(filepath: str) -> str:
    text_chunks = []
    with pdfplumber.open(filepath) as pdf:
        for page in pdf.pages:
            page_text = page.extract_text() or ""
            text_chunks.append(page_text)
    return "\n".join(text_chunks).strip()


def _parse_date(raw: str) -> Optional[datetime]:
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y"):
        try:
            return datetime.strptime(raw, fmt)
        except ValueError:
            continue
    return None


def auto_extract_fields(text: str) -> dict:
    """
    Best-effort field extraction. Returns a dict with keys:
    capacity_impact_mw, start_date, end_date, description
    Any field that can't be found is None.
    """
    result = {
        "capacity_impact_mw": None,
        "start_date": None,
        "end_date": None,
        "description": None,
    }
    if not text:
        return result

    cap_match = CAPACITY_PATTERN.search(text)
    if cap_match:
        try:
            result["capacity_impact_mw"] = float(cap_match.group(1))
        except ValueError:
            pass

    dates_found = [m.group(0) for m in DATE_PATTERN.finditer(text)]
    parsed_dates = [d for d in (_parse_date(d) for d in dates_found) if d]
    parsed_dates.sort()
    if parsed_dates:
        result["start_date"] = parsed_dates[0]
    if len(parsed_dates) > 1:
        result["end_date"] = parsed_dates[-1]

    # Use the first non-trivial line as a short description fallback.
    for line in text.splitlines():
        clean = line.strip()
        if len(clean) > 15:
            result["description"] = clean[:300]
            break

    return result
