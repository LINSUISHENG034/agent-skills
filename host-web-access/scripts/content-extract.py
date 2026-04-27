#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import html.parser
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


class ReadableHtmlParser(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.title_parts: list[str] = []
        self.body_parts: list[str] = []
        self.links: list[tuple[str, str]] = []
        self._skip_depth = 0
        self._in_title = False
        self._link_href = ""
        self._link_text: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()
        if tag in {"script", "style", "noscript", "svg"}:
            self._skip_depth += 1
            return
        if tag == "title":
            self._in_title = True
            return
        if tag == "a":
            attrs_map = {name.lower(): value or "" for name, value in attrs}
            self._link_href = attrs_map.get("href", "")
            self._link_text = []
        if tag in {"p", "div", "section", "article", "br", "li", "h1", "h2", "h3"}:
            self.body_parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if self._skip_depth:
            if tag in {"script", "style", "noscript", "svg"}:
                self._skip_depth -= 1
            return
        if tag == "title":
            self._in_title = False
            return
        if tag == "a" and self._link_href:
            text = clean_text(" ".join(self._link_text))
            if text:
                self.links.append((text, self._link_href))
            self._link_href = ""
            self._link_text = []
        if tag in {"p", "div", "section", "article", "li", "h1", "h2", "h3"}:
            self.body_parts.append("\n")

    def handle_data(self, data: str) -> None:
        if self._skip_depth:
            return
        if self._in_title:
            self.title_parts.append(data)
            return
        if self._link_href:
            self._link_text.append(data)
        self.body_parts.append(data)


def clean_text(value: str) -> str:
    return re.sub(r"\s+", " ", value or "").strip()


def normalize_markdown_text(value: str) -> str:
    lines = [clean_text(line) for line in re.split(r"[\r\n]+", value or "")]
    compact: list[str] = []
    previous_blank = False
    for line in lines:
        if not line:
            if not previous_blank:
                compact.append("")
            previous_blank = True
            continue
        compact.append(line)
        previous_blank = False
    return "\n".join(compact).strip()


def source_type(url: str) -> str:
    host = urllib.parse.urlparse(url).netloc.lower()
    if host.endswith("x.com") or host.endswith("twitter.com"):
        return "x"
    if host == "mp.weixin.qq.com":
        return "wechat"
    if "feishu" in host or "larksuite" in host:
        return "feishu"
    return "web"


def quality_for(markdown: str, error: str = "") -> str:
    if error:
        return "low"
    length = len(clean_text(markdown))
    if length >= 1200:
        return "high"
    if length >= 250:
        return "medium"
    return "low"


def fetch_url(url: str, timeout: float) -> tuple[bytes, str]:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (compatible; host-web-access/1.0; +https://github.com/)",
            "Accept": "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.8",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        content_type = response.headers.get_content_type() or ""
        charset = response.headers.get_content_charset() or "utf-8"
        return response.read().decode(charset, errors="replace").encode("utf-8"), content_type


def extract(url: str, timeout: float, max_chars: int | None) -> dict[str, object]:
    fetched_at = dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    error = ""
    content_type = ""
    title = ""
    markdown = ""
    method = "http-fetch"

    try:
        raw_bytes, content_type = fetch_url(url, timeout)
        raw = raw_bytes.decode("utf-8", errors="replace")
        if "html" in content_type or "<html" in raw[:1000].lower():
            parser = ReadableHtmlParser()
            parser.feed(raw)
            title = clean_text(" ".join(parser.title_parts))
            body = normalize_markdown_text("".join(parser.body_parts))
            markdown = body
            method = "http-html"
        else:
            markdown = normalize_markdown_text(raw)
            method = "http-text"
    except (OSError, urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as exc:
        error = str(exc)

    if max_chars and markdown and len(markdown) > max_chars:
        markdown = markdown[:max_chars].rstrip() + "\n\n[truncated]"

    parsed = urllib.parse.urlparse(url)
    fallback_title = parsed.netloc + parsed.path
    title = title or clean_text(fallback_title) or url
    quality = quality_for(markdown, error)
    needs_browser = bool(error) or quality == "low"
    needs_browser_reason = "extraction-failed" if error else ("low-quality-extraction" if needs_browser else "")

    return {
        "title": title,
        "url": url,
        "source_type": source_type(url),
        "content_type": "article",
        "extraction_method": method,
        "quality": quality,
        "fetched_at": fetched_at,
        "markdown": markdown,
        "summary": clean_text(markdown)[:500],
        "needs_browser": needs_browser,
        "needs_browser_reason": needs_browser_reason,
        "error": error,
    }


def frontmatter_value(value: object) -> str:
    text = str(value or "").replace("\n", " ").strip()
    return json.dumps(text, ensure_ascii=False)


def render_snapshot(payload: dict[str, object]) -> str:
    keys = [
        "title",
        "url",
        "source_type",
        "content_type",
        "extraction_method",
        "fetched_at",
        "quality",
    ]
    lines = ["---"]
    for key in keys:
        lines.append(f"{key}: {frontmatter_value(payload.get(key, ''))}")
    if payload.get("needs_browser"):
        lines.append(f"needs_browser: {str(payload.get('needs_browser')).lower()}")
        lines.append(f"needs_browser_reason: {frontmatter_value(payload.get('needs_browser_reason', ''))}")
    lines.extend(["---", "", str(payload.get("markdown") or "")])
    return "\n".join(lines).rstrip() + "\n"


def safe_filename(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    base = f"{parsed.netloc}{parsed.path}".strip("/") or "snapshot"
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", base).strip("-._")
    return (slug or "snapshot")[:120] + ".md"


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract URL content into a markdown snapshot contract")
    parser.add_argument("--url", required=True)
    parser.add_argument("--output-dir")
    parser.add_argument("--max-chars", type=int, default=20000)
    parser.add_argument("--timeout", type=float, default=12)
    args = parser.parse_args()

    payload = extract(args.url, args.timeout, args.max_chars)
    if args.output_dir:
        output_dir = Path(args.output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        saved_path = output_dir / safe_filename(args.url)
        saved_path.write_text(render_snapshot(payload), encoding="utf-8")
        payload["saved_path"] = str(saved_path)

    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
