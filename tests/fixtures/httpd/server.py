#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Tiny test HTTP server for the Phase-6 WebEngine end-to-end suite.

Endpoints (the comments above each handler describe the contract the
matching tests/e2e/*.cpp binary asserts):

  /basic            HTTP Basic auth challenge → 401, 200 on
                    Authorization: Basic dXNlcjpzZWNyZXQ= (user:secret).
  /authelia-redir   302 → /authelia/2fa to mimic an Authelia forwarding
                    proxy. The Location header lets WebTab's
                    onAutheliaHost overlay fire.
  /authelia/2fa     200 with a tiny login page (textual marker so the
                    test can assert via runJavaScript).
  /d/<uid>/<slug>   200 with a JS snippet that POSTs the page's
                    location.href to /_report so the test can assert
                    that any /d/→/d-solo/ rewrite landed.
  /d-solo/<uid>/<slug>  Same but explicitly d-solo.
  /goto/<id>        302 → /d/abc/slug?viewPanel=panel-7 so a /goto/
                    short link can be followed through to the rewrite
                    target.
  /_report          GET returns the most recent URL recorded by
                    /d/* page-load + the most recent Authorization
                    header received on /basic, as JSON.
  /theme.html?theme=<x>  page whose body background reflects
                    the ?theme= param so the theme substitution can be
                    asserted by reading the rendered style.

The server runs on 127.0.0.1; pick port 0 to let the OS choose. Print
the chosen port to stdout as one line "LISTEN <port>" so the launching
test can capture it.
"""
import argparse
import base64
import json
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


# Shared mutable state — accessed under lock so the request handlers
# (each on its own thread) and /_report don't race.
_LOCK = threading.Lock()
_LAST_URL_RECEIVED: str = ""
_LAST_AUTHORIZATION: str = ""
_HEARTBEAT_COUNT: int = 0
_COOKIE_HITS: int = 0


class FixtureHandler(BaseHTTPRequestHandler):
    server_version = "iframe-plasma-fixture/1.0"

    # ----- response helpers ---------------------------------------------------
    def _send(self, status: int, body: bytes,
              content_type: str = "text/plain",
              extra_headers: dict | None = None) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        if extra_headers:
            for k, v in extra_headers.items():
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _record_url(self) -> None:
        global _LAST_URL_RECEIVED
        with _LOCK:
            _LAST_URL_RECEIVED = self.path

    def _record_auth(self) -> None:
        global _LAST_AUTHORIZATION
        auth = self.headers.get("Authorization", "")
        with _LOCK:
            _LAST_AUTHORIZATION = auth

    # ----- routes -------------------------------------------------------------
    def do_GET(self) -> None:  # noqa: N802 (BaseHTTPRequestHandler convention)
        # Python's `global` declarations must precede first use of the
        # name; hoisting them here lets every endpoint below assign freely.
        global _LAST_URL_RECEIVED, _LAST_AUTHORIZATION
        global _HEARTBEAT_COUNT, _COOKIE_HITS
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        # Skip self-recording for the read-only / counter endpoints —
        # otherwise /_report would overwrite lastUrl with "/_report"
        # before the caller could inspect what the test page actually
        # fetched. /_beat and /_record are similarly noisy.
        if path not in ("/_report", "/_record", "/_reset", "/_beat"):
            self._record_url()

        if path == "/basic":
            self._record_auth()
            auth = self.headers.get("Authorization", "")
            expected = "Basic " + base64.b64encode(b"user:secret").decode()
            if auth == expected:
                self._send(200, b"<html><body>basic-ok</body></html>",
                           content_type="text/html")
            else:
                self._send(401, b"<html><body>auth-required</body></html>",
                           content_type="text/html",
                           extra_headers={"WWW-Authenticate": 'Basic realm="test"'})
            return

        if path == "/authelia-redir":
            self._send(302, b"redirecting",
                       extra_headers={"Location": "/authelia/2fa"})
            return

        if path == "/authelia/2fa":
            self._send(200, b"<html><body>authelia-2fa-login</body></html>",
                       content_type="text/html")
            return

        if path.startswith("/d/") or path.startswith("/d-solo/"):
            # Record the URL again before responding so /_report sees it
            # (the initial _record_url runs before the response body).
            body = (
                "<html><head></head><body>"
                "<div id='m'>fixture-grafana</div>"
                "<script>"
                "fetch('/_record?u=' + encodeURIComponent(location.href));"
                "</script>"
                "</body></html>"
            ).encode()
            self._send(200, body, content_type="text/html")
            return

        if path.startswith("/goto/"):
            self._send(302, b"goto-redirect",
                       extra_headers={"Location": "/d/abc/slug?viewPanel=panel-7"})
            return

        if path == "/_record":
            # Internal: invoked by the /d-solo page's JS to record the
            # final navigated-to URL (after browser-side redirect handling).
            q = urllib.parse.parse_qs(parsed.query)
            if "u" in q:
                with _LOCK:
                    _LAST_URL_RECEIVED = q["u"][0]
            self._send(200, b"recorded")
            return

        if path == "/_report":
            with _LOCK:
                payload = {
                    "lastUrl": _LAST_URL_RECEIVED,
                    "lastAuthorization": _LAST_AUTHORIZATION,
                    "heartbeats": _HEARTBEAT_COUNT,
                    "cookieHits": _COOKIE_HITS,
                }
            self._send(200, json.dumps(payload).encode(),
                       content_type="application/json")
            return

        if path == "/_reset":
            # Zero the counters so a single test process can run multiple
            # phases without stale state contaminating later assertions.
            with _LOCK:
                _HEARTBEAT_COUNT = 0
                _COOKIE_HITS = 0
                _LAST_URL_RECEIVED = ""
                _LAST_AUTHORIZATION = ""
            self._send(200, b"reset")
            return

        if path == "/_beat":
            # The page's setInterval JS pings here; we tally calls so
            # the lifecycle E2E can verify Frozen actually pauses JS.
            with _LOCK:
                _HEARTBEAT_COUNT += 1
            self._send(200, b"beat")
            return

        if path == "/beat-page":
            body = (
                "<html><head></head><body>"
                "<div id='m'>beating</div>"
                "<script>"
                "setInterval(function() { "
                "  fetch('/_beat'); "
                "}, 100);"
                "</script>"
                "</body></html>"
            ).encode()
            self._send(200, body, content_type="text/html")
            return

        if path == "/cookie-set":
            # First-hit endpoint: returns Set-Cookie. Subsequent hits to
            # /cookie-check verify the cookie was retained — used by the
            # tst_cookies_persist E2E to confirm cookies survive across
            # lifecycle transitions.
            body = (
                "<html><body>cookie-set</body></html>"
            ).encode()
            self._send(200, body, content_type="text/html",
                       extra_headers={"Set-Cookie": "iframeplasma_test=present; Path=/"})
            return

        if path == "/cookie-check":
            cookie = self.headers.get("Cookie", "")
            with _LOCK:
                _COOKIE_HITS += 1
            if "iframeplasma_test=present" in cookie:
                self._send(200, b"<html><body>cookie-present</body></html>",
                           content_type="text/html")
            else:
                self._send(401, b"<html><body>cookie-missing</body></html>",
                           content_type="text/html")
            return

        if path == "/theme.html":
            q = urllib.parse.parse_qs(parsed.query)
            theme = q.get("theme", ["unset"])[0]
            body = (
                f"<html><head><title>theme</title></head>"
                f"<body data-theme='{theme}'>theme={theme}</body></html>"
            ).encode()
            self._send(200, body, content_type="text/html")
            return

        self._send(404, b"not found")

    # Silence the default per-request stderr log; tests grep journald.
    def log_message(self, format: str, *args) -> None:  # noqa: A002
        pass


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--port", type=int, default=0,
                   help="0 = OS-chosen (default); prints 'LISTEN <port>' to stdout")
    p.add_argument("--host", default="127.0.0.1")
    args = p.parse_args(argv)

    server = ThreadingHTTPServer((args.host, args.port), FixtureHandler)
    chosen = server.server_address[1]
    print(f"LISTEN {chosen}", flush=True)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
