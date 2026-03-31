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
      const title = document.title || '';
      const url = location.href || '';
      const normalizeText = (value) => (value || '').replace(/\s+/g, ' ').trim();
      const toAbsoluteHref = (href) => {
        if (!href) return '';
        try {
          const u = new URL(href, location.href);
          if (!['http:', 'https:', 'file:'].includes(u.protocol)) return '';
          return u.href;
        } catch {
          return '';
        }
      };
      const isPreferredTopicHref = (href) => {
        const absolute = toAbsoluteHref(href);
        if (!absolute) return false;
        try {
          const u = new URL(absolute);
          return (
            /^\/t\//.test(u.pathname) ||
            /\/(topic|thread|discussion|comment|comments|question|questions|item)s?(\/|$)/i.test(u.pathname) ||
            (/viewtopic\.php$/i.test(u.pathname) && u.searchParams.has('t'))
          );
        } catch {
          return false;
        }
      };

      const topicRoots = Array.from(new Set([
        document.querySelector('main'),
        document.querySelector('article'),
        document.querySelector('[role=main]')
      ].filter(Boolean)));

      const chooseAnchor = (anchors) => {
        const ranked = anchors.map((anchor, index) => {
          const text = normalizeText(anchor.innerText || anchor.textContent);
          const href = toAbsoluteHref(anchor.getAttribute('href') || anchor.href || '');
          if (!text || !href) return null;
          let score = 0;
          if (isPreferredTopicHref(href)) score += 4;
          if (anchor.closest('h1, h2, h3, h4')) score += 2;
          const className = normalizeText([
            anchor.className || '',
            anchor.parentElement ? anchor.parentElement.className || '' : ''
          ].join(' ')).toLowerCase();
          if (/(^| )(title|topic|question|result|headline|subject)( |$)/.test(className)) score += 1;
          score += Math.min(text.length, 120) / 120;
          return { anchor, href, index, score, text };
        }).filter(Boolean);
        ranked.sort((a, b) => b.score - a.score || b.text.length - a.text.length || a.index - b.index);
        return ranked[0] || null;
      };

      const seen = new Set();
      const results = [];

      const collectFromContainer = (container) => {
        const chosen = chooseAnchor(Array.from(container.querySelectorAll('a[href]')));
        if (!chosen || seen.has(chosen.href)) return;
        seen.add(chosen.href);

        const item = {
          text: chosen.text,
          href: chosen.href,
        };
        const meta = normalizeText(container.innerText || '');
        if (meta) item.meta = meta.slice(0, 400);
        const topicId = container.getAttribute('data-topic-id');
        if (topicId) item.topicId = topicId;
        results.push(item);
      };

      const repeatedContainers = [];
      const repeatedRoots = topicRoots.length ? topicRoots : [document.body].filter(Boolean);
      for (const root of repeatedRoots) {
        for (const child of Array.from(root.children || [])) {
          if (child.querySelector('a[href]')) repeatedContainers.push(child);
        }
      }
      if (repeatedContainers.length >= 2) {
        for (const container of repeatedContainers) {
          collectFromContainer(container);
        }
      }

      if (!results.length) {
        const roots = topicRoots.length ? topicRoots : [document.body].filter(Boolean);
        for (const root of roots) {
          for (const anchor of Array.from(root.querySelectorAll('a[href]'))) {
            const text = normalizeText(anchor.innerText || anchor.textContent);
            const href = toAbsoluteHref(anchor.getAttribute('href') || anchor.href || '');
            if (!text || !href || seen.has(href)) continue;
            seen.add(href);
            results.push({ text, href });
          }
        }
      }

      return { title, url, content: JSON.stringify(results) };
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
