"""快速截图：CDP 打开 8125 主页截图，诊断 Web 字体渲染问题。"""

import base64
import json
import os
import shutil
import subprocess
import time
import urllib.parse
import urllib.request

import websocket

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
CDP_PORT = 9224
PROFILE = os.path.join(ROOT, ".tools", "cdp_shot")
URL = "http://127.0.0.1:8125/index.html?v=diag"
OUT = os.path.join(ROOT, ".tools", "main_shot.png")


def main():
    shutil.rmtree(PROFILE, ignore_errors=True)
    chrome = subprocess.Popen(
        [CHROME, "--headless=new", "--no-sandbox", "--disable-gpu-sandbox", "--in-process-gpu",
         "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
         f"--user-data-dir={PROFILE}", "--remote-debugging-port=%d" % CDP_PORT,
         "--no-first-run", "--no-default-browser-check", "--remote-allow-origins=*",
         "--window-size=1280,720", "about:blank"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(2.5)
        req = urllib.request.Request(
            "http://127.0.0.1:%d/json/new?" % CDP_PORT + urllib.parse.quote("about:blank"), method="PUT")
        with urllib.request.urlopen(req, timeout=10) as r:
            target = json.loads(r.read())
        ws = websocket.create_connection(target["webSocketDebuggerUrl"], timeout=20)
        msg_id = 0

        def send(method, params=None):
            nonlocal msg_id
            msg_id += 1
            ws.send(json.dumps({"id": msg_id, "method": method, "params": params or {}}))
            return msg_id

        def recv_until(pred, timeout=30):
            deadline = time.time() + timeout
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
                if pred(msg):
                    return msg
            return None

        def evaluate(expr):
            send("Runtime.evaluate", {"expression": expr, "returnByValue": True})
            m = recv_until(lambda x: x.get("id") == msg_id)
            if m and "result" in m:
                return m["result"].get("result", {}).get("value")
            return None

        def screenshot(path):
            send("Page.captureScreenshot", {"format": "png"})
            m = recv_until(lambda x: x.get("id") == msg_id)
            if m and "result" in m:
                with open(path, "wb") as f:
                    f.write(base64.b64decode(m["result"]["data"]))
                return True
            return False

        send("Runtime.enable")
        send("Page.enable")
        console_lines = []
        send("Log.enable")
        # 先启用监听，再导航到游戏（保证不错过启动阶段的 console 输出）
        send("Page.navigate", {"url": URL})
        # 等 wasm 加载：轮询 canvas 出现且引擎就绪（最多 40s）
        ready = False
        for _ in range(40):
            time.sleep(1.0)
            c = evaluate("document.querySelector('canvas') !== null")
            if c:
                time.sleep(4.0)
                ready = True
                break
        print("canvas ready:", ready)
        time.sleep(3.0)
        ok = screenshot(OUT)
        print("screenshot:", ok, OUT)
        # 收集 console 输出（Godot print/SCRIPT ERROR 都会进 console）
        time.sleep(2.0)
        for _ in range(200):
            try:
                raw = ws.recv()
                if not raw:
                    continue
                m = json.loads(raw)
                if m.get("method") == "Runtime.consoleAPICalled":
                    for a in m["params"].get("args", []):
                        console_lines.append(str(a.get("value", "")))
                elif m.get("method") == "Log.entryAdded":
                    console_lines.append(str(m["params"].get("entry", {}).get("text", "")))
            except Exception:
                break
        print("console lines:", len(console_lines))
        for ln in console_lines:
            if any(k in ln for k in ("FONT", "SCRIPT ERROR", "ERROR", "AUTOPLAY", "SPAWNER", "Godot")):
                print("  >", ln[:220])
    finally:
        ws.close()
        chrome.terminate()
        shutil.rmtree(PROFILE, ignore_errors=True)


if __name__ == "__main__":
    main()
