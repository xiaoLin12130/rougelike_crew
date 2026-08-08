"""E2E test of the exported Web build via Chrome DevTools Protocol.

Loads the page, collects console errors, clicks the start button, waits for
the game scene, simulates movement, takes screenshots for analysis.

Usage (needs escalated shell for Chrome):
    python tools/scripts/web_e2e_test.py
"""

import base64
import json
import os
import shutil
import subprocess
import threading
import time
import urllib.parse
import urllib.request

import websocket

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WEB_DIR = os.path.join(ROOT, "export", "web")
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
PORT = 8124
CDP_PORT = 9222
PROFILE = os.path.join(ROOT, ".tools", "cdp_%d" % int(time.time()))


def main():
    import http.server
    import socketserver

    class H(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a):
            pass

    os.chdir(WEB_DIR)
    httpd = socketserver.TCPServer(("127.0.0.1", PORT), H)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    shutil.rmtree(PROFILE, ignore_errors=True)
    chrome = None
    try:
        chrome = subprocess.Popen(
            [CHROME, "--headless=new", "--no-sandbox", "--disable-gpu-sandbox", "--in-process-gpu",
             "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
             f"--user-data-dir={PROFILE}",
             "--remote-debugging-port=%d" % CDP_PORT, "--no-first-run",
             "--no-default-browser-check", "--remote-allow-origins=*",
             "--window-size=1280,720", "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        time.sleep(2.5)

        url = f"http://127.0.0.1:{PORT}/index.html?v=e2e"
        req = urllib.request.Request(
            f"http://127.0.0.1:{CDP_PORT}/json/new?" + urllib.parse.quote(url), method="PUT")
        with urllib.request.urlopen(req, timeout=10) as r:
            target = json.loads(r.read())
        ws_url = target["webSocketDebuggerUrl"]

        ws = websocket.create_connection(ws_url, timeout=10)
        msg_id = 0
        console = []

        def send(method, params=None):
            nonlocal msg_id
            msg_id += 1
            ws.send(json.dumps({"id": msg_id, "method": method, "params": params or {}}))
            return msg_id

        def screenshot(path):
            send("Page.captureScreenshot", {"format": "png"})
            deadline = time.time() + 15
            while time.time() < deadline:
                raw = ws.recv()
                if not raw:
                    continue
                msg = json.loads(raw)
                if msg.get("id") == msg_id and "result" in msg:
                    data = msg["result"].get("data", "")
                    with open(path, "wb") as f:
                        f.write(base64.b64decode(data))
                    return True
            return False

        def click(x, y):
            send("Input.dispatchMouseEvent", {"type": "mousePressed", "x": x, "y": y, "button": "left", "clickCount": 1})
            send("Input.dispatchMouseEvent", {"type": "mouseReleased", "x": x, "y": y, "button": "left", "clickCount": 1})

        def key(code, down):
            vk = ord(code[-1].upper()) if len(code) == 4 and code[0] == "K" else 0
            send("Input.dispatchKeyEvent", {"type": "keyDown" if down else "keyUp",
                                            "code": code, "windowsVirtualKeyCode": vk,
                                            "nativeVirtualKeyCode": vk, "key": code[-1].lower() if vk else ""})

        send("Runtime.enable")
        send("Log.enable")
        send("Page.enable")
        send("Page.navigate", {"url": url})

        # collect messages for ~28s (WASM boot + menu)
        deadline = time.time() + 28
        while time.time() < deadline:
            ws.settimeout(1.0)
            try:
                raw = ws.recv()
            except Exception:
                continue
            if not raw:
                continue
            try:
                msg = json.loads(raw)
            except Exception:
                continue
            method = msg.get("method", "")
            if method == "Runtime.consoleAPICalled":
                for arg in msg.get("params", {}).get("args", []):
                    console.append("console: " + str(arg.get("value", arg.get("description", "")))[:300])
            elif method == "Runtime.exceptionThrown":
                d = msg.get("params", {}).get("exceptionDetails", {})
                console.append("EXCEPTION: " + str(d.get("text", "")) + " " + str(d.get("exception", {}).get("description", ""))[:300])
            elif method == "Log.entryAdded":
                e = msg.get("params", {}).get("entry", {})
                if e.get("level") in ("error", "warning"):
                    console.append("log[%s]: %s" % (e.get("level"), str(e.get("text", ""))[:300]))
            elif method == "Page.loadEventFired":
                console.append("loadEventFired")

        screenshot(os.path.join(ROOT, ".tools", "e2e_menu.png"))

        # click 开始游戏 (viewport 640x360, button at 0.42*360=151 -> window 302)
        click(640, 302)
        time.sleep(3)
        for i in range(3):
            screenshot(os.path.join(ROOT, ".tools", "e2e_game_%d.png" % i))
            time.sleep(2)
        key("KeyD", True)
        time.sleep(2.0)
        key("KeyD", False)
        time.sleep(1)
        screenshot(os.path.join(ROOT, ".tools", "e2e_game_move.png"))

        # JS side info
        send("Runtime.evaluate", {"expression":
            "JSON.stringify({w: innerWidth, h: innerHeight, canvases: [...document.querySelectorAll('canvas')].map(c => [c.width, c.height])})",
            "returnByValue": True})
        deadline = time.time() + 10
        while time.time() < deadline:
            raw = ws.recv()
            if not raw:
                continue
            msg = json.loads(raw)
            if msg.get("id") == msg_id and "result" in msg:
                console.append("JSINFO: " + str(msg["result"].get("result", {}).get("value", "")))
                break

        print("=== console messages ===")
        for c in console:
            print(" ", c)
        print("=== done ===")
    finally:
        if chrome:
            chrome.terminate()
        httpd.shutdown()
        shutil.rmtree(PROFILE, ignore_errors=True)


if __name__ == "__main__":
    main()
