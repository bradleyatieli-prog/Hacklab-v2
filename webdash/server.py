#!/usr/bin/env python3
"""
hacklab-v2 / webdash/server.py

Static dashboard + a small JSON API so the browser dashboard can
actually do things (start/stop/restart services, install tool
modules, tail logs) instead of only showing status.json.

Trust boundary: bound to loopback by default (see services/webdash/run)
— same boundary as local shell access, so these actions aren't more
dangerous than what's already reachable from a Termux/chroot prompt.
Every name coming from the client is checked against the real
services/ and modules/ directories before anything runs; subprocess
calls always use an argument list, never shell=True with interpolated
strings, so there's no command-injection surface from request bodies.

Heavy installs (metasploit etc.) run in a background thread and must
be explicitly confirmed in the request body — mirrors `gum confirm`
in the CLI menu, just over HTTP instead of a terminal prompt.

Interactive tools (msfconsole, an aircrack-ng workflow) are NOT
exposed here — a stateless HTTP request can't usefully drive an
interactive terminal program. Those stay in the TUI (core/menu.sh).
"""
import http.server
import json
import os
import re
import subprocess
import threading
from pathlib import Path

HACKLAB_HOME = Path(os.environ.get("HACKLAB_HOME", str(Path.home() / ".hacklab")))
SVC_ENGINE = HACKLAB_HOME / "lib" / "svc-engine.sh"
SERVICES_DIR = HACKLAB_HOME / "services"
MODULES_DIR = HACKLAB_HOME / "modules"
STATE_FILE = HACKLAB_HOME / "installed-modules"
LOG_DIR = HACKLAB_HOME / "logs"
WEBROOT = Path(__file__).resolve().parent

NAME_RE = re.compile(r"^[a-zA-Z0-9_-]+$")

_install_state = {}   # module name -> "installing" | "done" | "error"
_install_lock = threading.Lock()


def valid_service(name):
    return bool(NAME_RE.match(name)) and (SERVICES_DIR / name).is_dir()


def valid_module(name):
    return bool(NAME_RE.match(name)) and (MODULES_DIR / f"{name}.sh").is_file()


def module_desc(name):
    f = MODULES_DIR / f"{name}.sh"
    try:
        for line in f.read_text().splitlines():
            if line.startswith("# DESC:"):
                return line[len("# DESC:"):].strip()
    except OSError:
        pass
    return ""


def module_installed(name):
    if not STATE_FILE.exists():
        return False
    return name in STATE_FILE.read_text().splitlines()


def run_engine(*args, timeout=30):
    return subprocess.run(
        ["bash", str(SVC_ENGINE), *args],
        capture_output=True, text=True, timeout=timeout,
    )


def _do_install(name):
    with _install_lock:
        _install_state[name] = "installing"
    try:
        result = subprocess.run(
            ["bash", str(MODULES_DIR / f"{name}.sh"), "install"],
            capture_output=True, text=True, timeout=1800,
        )
        ok = result.returncode == 0
    except Exception:
        ok = False
    with _install_lock:
        _install_state[name] = "done" if ok else "error"
    if ok and not module_installed(name):
        with open(STATE_FILE, "a") as f:
            f.write(name + "\n")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEBROOT), **kwargs)

    def log_message(self, fmt, *args):
        pass  # the metrics service already logs system state elsewhere

    def _json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/modules":
            mods = []
            for f in sorted(MODULES_DIR.glob("*.sh")):
                name = f.stem
                mods.append({
                    "name": name,
                    "desc": module_desc(name),
                    "installed": module_installed(name),
                    "status": _install_state.get(name, "idle"),
                })
            return self._json(200, mods)

        m = re.match(r"^/api/logs/([a-zA-Z0-9_-]+)$", self.path)
        if m:
            name = m.group(1)
            if not (valid_service(name) or valid_module(name)):
                return self._json(404, {"error": "unknown name"})
            logfile = LOG_DIR / f"{name}.log"
            text = ""
            if logfile.exists():
                text = logfile.read_text(errors="replace")[-8000:]
            return self._json(200, {"name": name, "log": text})

        return super().do_GET()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            body = {}

        m = re.match(r"^/api/service/([a-zA-Z0-9_-]+)/(start|stop|restart)$", self.path)
        if m:
            name, action = m.group(1), m.group(2)
            if not valid_service(name):
                return self._json(404, {"error": "unknown service"})
            try:
                result = run_engine(action, name)
            except subprocess.TimeoutExpired:
                return self._json(504, {"error": "engine command timed out"})
            return self._json(200, {
                "ok": result.returncode == 0,
                "output": (result.stdout + result.stderr).strip(),
            })

        m = re.match(r"^/api/module/([a-zA-Z0-9_-]+)/install$", self.path)
        if m:
            name = m.group(1)
            if not valid_module(name):
                return self._json(404, {"error": "unknown module"})
            if not body.get("confirm"):
                return self._json(400, {
                    "error": "install requires confirm:true — same gate as `gum confirm` in the CLI menu, just surfaced in the UI instead of a terminal prompt",
                })
            with _install_lock:
                if _install_state.get(name) == "installing":
                    return self._json(409, {"error": "already installing"})
            threading.Thread(target=_do_install, args=(name,), daemon=True).start()
            return self._json(202, {"ok": True, "status": "installing"})

        if re.match(r"^/api/module/([a-zA-Z0-9_-]+)/run$", self.path):
            return self._json(400, {
                "error": "interactive tools run from the TUI menu (core/menu.sh) — a web request can't drive an interactive terminal program",
            })

        return self._json(404, {"error": "not found"})


def main():
    port = int(os.environ.get("HACKLAB_WEBDASH_PORT", "8080"))
    bind = os.environ.get("HACKLAB_WEBDASH_BIND", "127.0.0.1")
    httpd = http.server.ThreadingHTTPServer((bind, port), Handler)
    print(f"webdash serving on {bind}:{port}")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
