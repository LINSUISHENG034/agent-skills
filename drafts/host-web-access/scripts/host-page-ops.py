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


def open_session(port: int, target_id: str | None):
    websocket = cdp.resolve_websocket_url(port, target_id)
    return cdp.CdpSession(websocket)


def run_eval(port: int, target_id: str | None, expression: str) -> None:
    result = cdp.evaluate(port, target_id, expression)
    print(json.dumps(result, ensure_ascii=False))


def run_navigate(port: int, target_id: str | None, url: str, wait_selector: str | None, wait_navigation: bool) -> None:
    result = cdp.navigate_and_wait(port, target_id, url, wait_selector, wait_navigation)
    print(json.dumps(result, ensure_ascii=False))


def run_check(port: int, target_id: str | None, mode: str) -> None:
    page_info = cdp.gather_page_info(port, target_id)
    if mode == "page-info":
        payload = {
            "title": page_info.get("title", ""),
            "url": page_info.get("url", ""),
            "bodySnippet": page_info.get("bodySnippet", ""),
        }
    elif mode == "challenge":
        payload = cdp.detect_challenge(page_info)
    else:
        payload = cdp.detect_login_wall(page_info)
    print(json.dumps(payload, ensure_ascii=False))


def run_click(port: int, target_id: str | None, selector: str) -> None:
    js = f"""
(() => {{
  const el = document.querySelector({json.dumps(selector)});
  if (!el) return {{clicked: false, selector: {json.dumps(selector)}}};
  el.scrollIntoView({{block: 'center', inline: 'center'}});
  el.click();
  return {{clicked: true, selector: {json.dumps(selector)}}};
}})()
"""
    result = cdp.evaluate(port, target_id, js)
    print(json.dumps(result, ensure_ascii=False))


def run_click_at(port: int, target_id: str | None, selector: str) -> None:
    with open_session(port, target_id) as session:
        response = session.call(
            "Runtime.evaluate",
            {
                "expression": f"""
(() => {{
  const el = document.querySelector({json.dumps(selector)});
  if (!el) return null;
  el.scrollIntoView({{block: 'center', inline: 'center'}});
  const rect = el.getBoundingClientRect();
  return {{ x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 }};
}})()
""",
                "returnByValue": True,
            },
        )
        point = response.get("result", {}).get("result", {}).get("value")
        if not isinstance(point, dict):
            raise cdp.CdpError(f"selector not found for click-at: {selector}")
        for event_type in ("mouseMoved", "mousePressed", "mouseReleased"):
            params = {
                "type": event_type,
                "x": point["x"],
                "y": point["y"],
                "button": "left",
                "clickCount": 1,
            }
            session.call("Input.dispatchMouseEvent", params)
    print(json.dumps({"clicked": True, "selector": selector}, ensure_ascii=False))


def run_scroll(port: int, target_id: str | None, amount: int) -> None:
    result = cdp.evaluate(
        port,
        target_id,
        f"(() => {{ window.scrollBy(0, {amount}); return {{scroll: {amount}}}; }})()",
    )
    print(json.dumps(result, ensure_ascii=False))


def run_set_files(port: int, target_id: str | None, selector: str, files: list[str]) -> None:
    with open_session(port, target_id) as session:
        session.call("DOM.enable")
        response = session.call(
            "Runtime.evaluate",
            {
                "expression": f"document.querySelector({json.dumps(selector)})",
                "returnByValue": False,
            },
        )
        object_id = response.get("result", {}).get("result", {}).get("objectId")
        if not object_id:
            raise cdp.CdpError(f"selector not found for set-files: {selector}")
        node_response = session.call("DOM.requestNode", {"objectId": object_id})
        node_id = node_response.get("result", {}).get("nodeId")
        if not node_id:
            raise cdp.CdpError(f"unable to resolve DOM node for selector: {selector}")
        session.call("DOM.setFileInputFiles", {"files": files, "nodeId": node_id})
    print(json.dumps({"selector": selector, "files": files}, ensure_ascii=False))


def main() -> int:
    parser = argparse.ArgumentParser(description="Host page CDP helper")
    parser.add_argument("--port", type=int, default=9222)
    parser.add_argument("--target-id")
    parser.add_argument("--eval")
    parser.add_argument("--navigate")
    parser.add_argument("--wait-navigation", action="store_true")
    parser.add_argument("--wait-for")
    parser.add_argument("--click")
    parser.add_argument("--click-link-text")
    parser.add_argument("--click-at")
    parser.add_argument("--set-files", nargs="+", metavar="FILE")
    parser.add_argument("--set-files-selector")
    parser.add_argument("--scroll", type=int)
    parser.add_argument("--check", choices=["page-info", "challenge", "login-wall"])
    args = parser.parse_args()

    port = args.port
    target_id = args.target_id

    if args.navigate:
        run_navigate(port, target_id, args.navigate, args.wait_for, args.wait_navigation)
        return 0
    if args.eval:
        run_eval(port, target_id, args.eval)
        return 0
    if args.click:
        run_click(port, target_id, args.click)
        return 0
    if args.click_link_text:
        print(json.dumps(cdp.click_link(port, target_id, args.click_link_text), ensure_ascii=False))
        return 0
    if args.click_at:
        run_click_at(port, target_id, args.click_at)
        return 0
    if args.set_files or args.set_files_selector:
        selector = args.set_files_selector or ""
        if not selector or not args.set_files:
            parser.error("--set-files requires --set-files-selector and at least one file")
        run_set_files(port, target_id, selector, args.set_files)
        return 0
    if args.scroll is not None:
        run_scroll(port, target_id, args.scroll)
        return 0
    if args.check:
        run_check(port, target_id, args.check)
        return 0

    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
