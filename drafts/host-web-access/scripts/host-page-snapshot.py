#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path


def load_cdp_module():
    module_path = Path(__file__).with_name("host-cdp-core.py")
    spec = importlib.util.spec_from_file_location("host_cdp_core", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("unable to load host-cdp-core.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cdp = load_cdp_module()

FORMAT_JS = {
    "markdown": r"""(() => {
      const lines = [];
      const title = document.title || '';
      if (title) lines.push('# ' + title, '');
      const url = location.href || '';
      if (url) lines.push('URL: ' + url, '');
      function walk(node) {
        if (node.nodeType === Node.TEXT_NODE) {
          const text = node.textContent.trim();
          if (text) lines.push(text);
          return;
        }
        if (node.nodeType !== Node.ELEMENT_NODE) return;
        const tag = node.tagName;
        if (['SCRIPT', 'STYLE', 'NOSCRIPT', 'SVG'].includes(tag)) return;
        if (tag === 'A') {
          const href = node.getAttribute('href') || '';
          const text = (node.innerText || '').trim();
          if (text && href) lines.push('[' + text + '](' + href + ')');
          return;
        }
        if (tag === 'LI') {
          lines.push('- ' + (node.innerText || '').trim());
          return;
        }
        for (const child of node.childNodes) walk(child);
        if (['P', 'DIV', 'SECTION', 'ARTICLE', 'BR'].includes(tag)) lines.push('');
      }
      if (document.body) walk(document.body);
      return { title, url, content: lines.join('\n') };
    })()""",
    "text": r"""(() => ({
      title: document.title || '',
      url: location.href || '',
      content: document.body ? (document.body.innerText || '') : ''
    }))()""",
    "links": r"""(() => ({
      title: document.title || '',
      url: location.href || '',
      content: JSON.stringify(Array.from(document.querySelectorAll('a[href]')).map(anchor => ({
        text: (anchor.innerText || '').trim(),
        href: anchor.href
      })).filter(item => item.text && item.href))
    }))()""",
    "topic-links": r"""(() => {
      const normalize = (value) => (value || '').replace(/\s+/g, ' ').trim();
      const links = Array.from(document.querySelectorAll('a[href]')).map((anchor, index) => ({
        index,
        text: normalize(anchor.innerText || anchor.textContent),
        href: anchor.href,
        topicId: anchor.closest('[data-topic-id]')?.getAttribute('data-topic-id') || ''
      })).filter(item => item.text && item.href);
      return {
        title: document.title || '',
        url: location.href || '',
        content: JSON.stringify(links)
      };
    })()""",
}


def snapshot(port: int, target_id: str | None, fmt: str, max_chars: int | None) -> dict[str, str]:
    value = cdp.evaluate(port, target_id, FORMAT_JS[fmt])
    if not isinstance(value, dict):
        raise cdp.CdpError("snapshot did not return an object")
    content = str(value.get("content", ""))
    if max_chars and len(content) > max_chars:
        content = content[:max_chars] + "\n[truncated]"
    return {
        "title": str(value.get("title", "")),
        "url": str(value.get("url", "")),
        "content": content,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Capture page snapshot via CDP")
    parser.add_argument("--port", type=int, default=9222)
    parser.add_argument("--target-id")
    parser.add_argument("--format", choices=["markdown", "text", "links", "topic-links"], default="markdown")
    parser.add_argument("--max-chars", type=int)
    args = parser.parse_args()

    payload = snapshot(args.port, args.target_id, args.format, args.max_chars)
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
