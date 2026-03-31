#!/usr/bin/env python3
"""Local CDP helpers for host-web-access using only the Python standard library."""

from __future__ import annotations

import base64
import hashlib
import json
import os
import socket
import struct
import time
import urllib.parse
import urllib.request

TIMEOUT_SECONDS = 5
NAVIGATE_TIMEOUT_SECONDS = 15
WAIT_FOR_TIMEOUT_SECONDS = 10
USER_AGENT = "host-web-access/cdp"


class CdpError(RuntimeError):
    pass


def http_get_json(url: str) -> object:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        return json.loads(response.read().decode("utf-8"))


def resolve_websocket_url(port: int, target_id: str | None) -> str:
    targets = http_get_json(f"http://127.0.0.1:{port}/json/list")
    if not isinstance(targets, list):
      raise CdpError("invalid target list response")

    page_targets = [target for target in targets if target.get("type") == "page"]
    if target_id:
        for target in page_targets:
            if target.get("id") == target_id:
                websocket_url = target.get("webSocketDebuggerUrl")
                if websocket_url:
                    return str(websocket_url)
        raise CdpError("target-id not found")

    for target in page_targets:
        websocket_url = target.get("webSocketDebuggerUrl")
        if websocket_url:
            return str(websocket_url)

    version = http_get_json(f"http://127.0.0.1:{port}/json/version")
    websocket_url = version.get("webSocketDebuggerUrl") if isinstance(version, dict) else None
    if not websocket_url:
        raise CdpError("missing webSocketDebuggerUrl")
    return str(websocket_url)


def websocket_key() -> str:
    return base64.b64encode(os.urandom(16)).decode("ascii")


def build_frame(payload: str) -> bytes:
    raw = payload.encode("utf-8")
    mask_key = os.urandom(4)
    length = len(raw)
    header = bytearray([0x81])
    if length < 126:
        header.append(0x80 | length)
    elif length < (1 << 16):
        header.append(0x80 | 126)
        header.extend(struct.pack("!H", length))
    else:
        header.append(0x80 | 127)
        header.extend(struct.pack("!Q", length))
    masked = bytes(byte ^ mask_key[index % 4] for index, byte in enumerate(raw))
    return bytes(header) + mask_key + masked


def recv_exact(sock: socket.socket, size: int) -> bytes:
    chunks = []
    remaining = size
    while remaining > 0:
        chunk = sock.recv(remaining)
        if not chunk:
            raise CdpError("unexpected websocket EOF")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def read_frame(sock: socket.socket) -> str:
    first, second = recv_exact(sock, 2)
    opcode = first & 0x0F
    masked = second & 0x80
    length = second & 0x7F
    if length == 126:
        length = struct.unpack("!H", recv_exact(sock, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", recv_exact(sock, 8))[0]
    mask_key = recv_exact(sock, 4) if masked else b""
    payload = recv_exact(sock, length)
    if masked:
        payload = bytes(byte ^ mask_key[index % 4] for index, byte in enumerate(payload))
    if opcode == 0x8:
        raise CdpError("websocket closed by peer")
    if opcode == 0x9:
        sock.sendall(bytes([0x8A, 0x00]))
        return read_frame(sock)
    if opcode != 0x1:
        raise CdpError(f"unsupported websocket opcode: {opcode}")
    return payload.decode("utf-8")


class CdpSession:
    def __init__(self, websocket_url: str, timeout: float = TIMEOUT_SECONDS):
        parsed = urllib.parse.urlparse(websocket_url)
        host = parsed.hostname or "127.0.0.1"
        port = parsed.port or 80
        if parsed.scheme != "ws":
            raise CdpError("only ws:// CDP endpoints are supported")

        request_path = parsed.path or "/"
        if parsed.query:
            request_path += f"?{parsed.query}"

        key = websocket_key()
        self._sock = socket.create_connection((host, port), timeout=timeout)
        self._sock.settimeout(timeout)
        handshake = (
            f"GET {request_path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        self._sock.sendall(handshake.encode("utf-8"))
        response = b""
        while b"\r\n\r\n" not in response:
            chunk = self._sock.recv(4096)
            if not chunk:
                raise CdpError("incomplete websocket handshake")
            response += chunk
        header_blob = response.split(b"\r\n\r\n", 1)[0].decode("utf-8", errors="replace")
        if "101" not in header_blob.splitlines()[0]:
            raise CdpError(f"handshake failed: {header_blob.splitlines()[0]}")
        expected_accept = base64.b64encode(
            hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()
        ).decode("ascii")
        if f"Sec-WebSocket-Accept: {expected_accept}" not in header_blob:
            raise CdpError("invalid websocket accept header")
        self._next_id = 1

    def __enter__(self) -> "CdpSession":
        return self

    def __exit__(self, *_args: object) -> None:
        self._sock.close()

    def send(self, method: str, params: dict | None = None) -> int:
        message_id = self._next_id
        self._next_id += 1
        payload: dict[str, object] = {"id": message_id, "method": method}
        if params:
            payload["params"] = params
        self._sock.sendall(build_frame(json.dumps(payload)))
        return message_id

    def recv(self) -> dict:
        return json.loads(read_frame(self._sock))

    def call(self, method: str, params: dict | None = None) -> dict:
        message_id = self.send(method, params)
        while True:
            payload = self.recv()
            if payload.get("id") == message_id:
                if "error" in payload:
                    raise CdpError(str(payload["error"]))
                return payload

    def wait_for_event(self, event_method: str, timeout: float) -> dict:
        deadline = time.monotonic() + timeout
        original_timeout = self._sock.gettimeout()
        try:
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise CdpError(f"timeout waiting for {event_method}")
                self._sock.settimeout(remaining)
                payload = self.recv()
                if payload.get("method") == event_method:
                    return payload
        finally:
            self._sock.settimeout(original_timeout)


def evaluate(port: int, target_id: str | None, expression: str) -> object:
    websocket_url = resolve_websocket_url(port, target_id)
    with CdpSession(websocket_url) as session:
        response = session.call(
            "Runtime.evaluate",
            {
                "expression": expression,
                "returnByValue": True,
            },
        )
    result = response.get("result", {})
    if "exceptionDetails" in result:
        details = result["exceptionDetails"]
        description = details.get("exception", {}).get("description") or details.get("text") or "evaluation failed"
        raise CdpError(str(description))
    payload = result.get("result", {})
    return payload.get("value") if "value" in payload else payload


def gather_page_info(port: int, target_id: str | None) -> dict[str, object]:
    expression = """(() => {
      const title = document.title || '';
      const url = location.href || '';
      const bodyText = document.body ? (document.body.innerText || '') : '';
      const html = document.documentElement ? (document.documentElement.outerHTML || '') : '';
      return {
        title,
        url,
        bodySnippet: bodyText.slice(0, 2000),
        htmlSnippet: html.slice(0, 4000)
      };
    })()"""
    value = evaluate(port, target_id, expression)
    if not isinstance(value, dict):
        raise CdpError("page-info did not return an object")
    return value


def detect_challenge(page_info: dict[str, object]) -> dict[str, object]:
    indicators = []
    haystack = " ".join(
        [
            str(page_info.get("title", "")),
            str(page_info.get("bodySnippet", "")),
            str(page_info.get("htmlSnippet", "")),
        ]
    ).lower()
    for token in (
        "请稍候",
        "just a moment",
        "checking your browser",
        "verify you are human",
        "cf-challenge",
        "challenge-platform",
        "turnstile",
        "captcha",
    ):
        if token.lower() in haystack:
            indicators.append(token)
    return {
        "hasChallenge": bool(indicators),
        "indicators": indicators,
        "title": page_info.get("title", ""),
        "url": page_info.get("url", ""),
    }


def detect_login_wall(page_info: dict[str, object]) -> dict[str, object]:
    login_hits = []
    combined = " ".join([str(page_info.get("bodySnippet", "")), str(page_info.get("title", ""))]).lower()
    for token in ("sign in", "log in", "登录", "create your account", "sign up"):
        if token.lower() in combined:
            login_hits.append(token)
    url = str(page_info.get("url", "")).lower()
    for token in ("/login", "/signin", "/auth", "/i/flow/login"):
        if token in url and token not in login_hits:
            login_hits.append(token)
    return {
        "hasLoginWall": bool(login_hits),
        "loginHits": login_hits,
        "title": page_info.get("title", ""),
        "url": page_info.get("url", ""),
    }


def _wait_for_selector(session: CdpSession, selector: str) -> None:
    expression = f"!!document.querySelector({json.dumps(selector)})"
    deadline = time.monotonic() + WAIT_FOR_TIMEOUT_SECONDS
    while True:
        response = session.call("Runtime.evaluate", {"expression": expression, "returnByValue": True})
        value = response.get("result", {}).get("result", {}).get("value")
        if value:
            return
        if time.monotonic() >= deadline:
            raise CdpError(f"timeout waiting for selector: {selector}")
        time.sleep(0.3)


def navigate_and_wait(
    port: int,
    target_id: str | None,
    url: str,
    wait_selector: str | None = None,
    wait_navigation: bool = False,
) -> dict[str, object]:
    websocket_url = resolve_websocket_url(port, target_id)
    with CdpSession(websocket_url, timeout=NAVIGATE_TIMEOUT_SECONDS) as session:
        session.call("Page.enable")
        session.call("Page.navigate", {"url": url})
        if wait_navigation:
            session.wait_for_event("Page.loadEventFired", timeout=NAVIGATE_TIMEOUT_SECONDS)
        if wait_selector:
            _wait_for_selector(session, wait_selector)
        response = session.call(
            "Runtime.evaluate",
            {
                "expression": "({title: document.title, url: location.href})",
                "returnByValue": True,
            },
        )
    result = response.get("result", {}).get("result", {})
    value = result.get("value", result)
    if not isinstance(value, dict):
        raise CdpError("navigate did not return an object")
    return value


def click_link(port: int, target_id: str | None, text: str) -> dict[str, object]:
    expression = r"""((needle) => {
      const normalize = (value) => (value || '').replace(/\s+/g, ' ').trim();
      const isVisible = (anchor) => {
        if (!anchor || !anchor.isConnected) return false;
        if (anchor.hidden || anchor.getAttribute('aria-hidden') === 'true') return false;
        const style = window.getComputedStyle(anchor);
        if (!style || style.display === 'none' || style.visibility === 'hidden') return false;
        if (Number(style.opacity || '1') === 0) return false;
        return anchor.getClientRects().length > 0;
      };
      const wanted = normalize(needle).toLowerCase();
      const anchors = Array.from(document.querySelectorAll('a[href]'));
      const ranked = anchors.map((anchor, index) => {
        const anchorText = normalize(anchor.innerText || anchor.textContent);
        return {
          index,
          anchor,
          text: anchorText,
          href: anchor.href || '',
          visible: isVisible(anchor),
          exact: anchorText.toLowerCase() === wanted,
          includes: wanted && anchorText.toLowerCase().includes(wanted),
        };
      }).filter(item => item.text && item.href && item.visible);

      ranked.sort((a, b) => {
        const score = (item) => item.exact ? 0 : (item.includes ? 1 : 9);
        return score(a) - score(b) || a.text.length - b.text.length || a.index - b.index;
      });

      const hit = ranked.find(item => item.exact || item.includes);
      if (!hit) {
        return {
          clicked: false,
          requestedText: needle,
          candidates: ranked.slice(0, 10).map(item => ({ text: item.text, href: item.href }))
        };
      }

      hit.anchor.scrollIntoView({block: 'center', inline: 'center'});
      hit.anchor.click();
      return {
        clicked: true,
        requestedText: needle,
        text: hit.text,
        href: hit.href
      };
    })(%s)""" % json.dumps(text)
    value = evaluate(port, target_id, expression)
    if not isinstance(value, dict):
        raise CdpError("click-link did not return an object")
    return value
