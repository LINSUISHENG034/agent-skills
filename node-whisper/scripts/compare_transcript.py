#!/usr/bin/env python3
import argparse
import json
import re
from difflib import SequenceMatcher
from pathlib import Path


def normalize(text: str) -> str:
    replacements = {
        "，": ",",
        "。": ".",
        "：": ":",
        "；": ";",
        "！": "!",
        "？": "?",
        "“": "\"",
        "”": "\"",
        "（": "(",
        "）": ")",
        "、": ",",
        "K P I": "KPI",
        "B B C": "BBC",
    }
    out = text
    for src, dst in replacements.items():
        out = out.replace(src, dst)
    out = re.sub(r"\s+", "", out)
    return out.strip().lower()


def load_reference(path: Path) -> tuple[str | None, str]:
    raw = path.read_text(encoding="utf-8").strip()
    lines = raw.splitlines()
    if len(lines) >= 2 and len(lines[0].strip()) < 32:
        return lines[0].strip(), "\n".join(lines[1:]).strip()
    return None, raw


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--json-out", required=False)
    args = parser.parse_args()

    ref_lang, ref_text = load_reference(Path(args.reference))
    cand_text = Path(args.candidate).read_text(encoding="utf-8").strip()

    ref_norm = normalize(ref_text)
    cand_norm = normalize(cand_text)
    ratio = SequenceMatcher(None, ref_norm, cand_norm).ratio()

    payload = {
        "reference_language": ref_lang,
        "reference_chars": len(ref_text),
        "candidate_chars": len(cand_text),
        "reference_normalized_chars": len(ref_norm),
        "candidate_normalized_chars": len(cand_norm),
        "normalized_similarity_ratio": ratio,
        "exact_match": ref_text == cand_text,
        "normalized_match": ref_norm == cand_norm,
        "reference_preview": ref_text[:200],
        "candidate_preview": cand_text[:200],
    }

    if args.json_out:
        Path(args.json_out).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
