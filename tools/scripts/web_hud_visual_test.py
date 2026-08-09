"""HUD v2 视觉验收：CDP 截屏 + 像素断言。

覆盖：主菜单→进入战斗后 HUD 渲染（HP/构筑条/无 Boss 血条）、
物品格详情弹窗、构筑条折叠。窗口为 1280x720 headless Chrome，
Godot 整数缩放下画布可能不是 2x，脚本通过 getBoundingClientRect 动态定位。

Usage (needs escalated shell for Chrome):
    python tools/scripts/web_hud_visual_test.py
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
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WEB_DIR = os.path.join(ROOT, "export", "web")
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
PORT = 8124
CDP_PORT = 9223
PROFILE = os.path.join(ROOT, ".tools", "cdp_hud_%d" % int(time.time()))
SHOT_DIR = os.path.join(ROOT, ".tools")

failures: list[str] = []


def fail(msg: str) -> None:
    failures.append(msg)
    print("FAIL:", msg)


def check(ok: bool, msg: str) -> None:
    if ok:
        print("PASS:", msg)
    else:
        fail(msg)


def crop_ratio(im: Image.Image, box, pred) -> float:
    region = im.crop(box)
    px = list(region.getdata())
    n = max(len(px), 1)
    return sum(1 for p in px if pred(p)) / n


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

        url = "http://127.0.0.1:%d/index.html?v=hud2" % PORT
        req = urllib.request.Request(
            "http://127.0.0.1:%d/json/new?" % CDP_PORT + urllib.parse.quote(url), method="PUT")
        with urllib.request.urlopen(req, timeout=10) as r:
            target = json.loads(r.read())
        ws = websocket.create_connection(target["webSocketDebuggerUrl"], timeout=15)
        msg_id = 0

        def send(method, params=None):
            nonlocal msg_id
            msg_id += 1
            ws.send(json.dumps({"id": msg_id, "method": method, "params": params or {}}))
            return msg_id

        def recv_until(pred, timeout=20):
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
                data = m["result"].get("data", "")
                with open(path, "wb") as f:
                    f.write(base64.b64decode(data))
                return True
            return False

        def click(x, y):
            send("Input.dispatchMouseEvent", {"type": "mousePressed", "x": x, "y": y, "button": "left", "clickCount": 1})
            send("Input.dispatchMouseEvent", {"type": "mouseReleased", "x": x, "y": y, "button": "left", "clickCount": 1})

        send("Page.enable")
        send("Page.navigate", {"url": url})

        # 等待 Godot 引导完成（canvas 出现且可交互）
        canvas = None
        deadline = time.time() + 45
        while time.time() < deadline and not canvas:
            time.sleep(2)
            canvas = evaluate(
                "(()=>{const c=document.querySelector('canvas');if(!c)return null;"
                "const r=c.getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height};})()")
        check(canvas is not None, "Godot canvas 已出现")
        if not canvas:
            return
        cx, cy, cw, ch = canvas["x"], canvas["y"], canvas["w"], canvas["h"]

        def game_area():
            """整数缩放下画布填满窗口，游戏实际渲染区居中，用像素扫描定位。"""
            shot = os.path.join(SHOT_DIR, "v2_probe.png")
            screenshot(shot)
            im = Image.open(shot).convert("RGB")
            w, h = im.size
            px = im.load()
            minx, miny, maxx, maxy = w, h, -1, -1
            for y in range(0, h, 4):
                for x in range(0, w, 4):
                    r, g, b = px[x, y]
                    if r + g + b > 60:
                        if x < minx:
                            minx = x
                        if x > maxx:
                            maxx = x
                        if y < miny:
                            miny = y
                        if y > maxy:
                            maxy = y
            if maxx < 0:
                return 0, 0, 1.0
            s = (maxx - minx + 4) / 640.0
            return minx, miny, s

        gx, gy, s = game_area()
        print("game area:", gx, gy, "scale:", s)

        # 主菜单 → 开始游戏（按钮逻辑中心 320,144）
        click(gx + 320 * s, gy + 144 * s)
        time.sleep(5)
        check(screenshot(os.path.join(SHOT_DIR, "v2_game.png")), "游戏画面截屏")

        im = Image.open(os.path.join(SHOT_DIR, "v2_game.png")).convert("RGB")
        # 1) 左上 HP 条（蓝色填充）
        hp_blue = crop_ratio(im, (gx + 64 * s, gy + 6 * s, gx + 160 * s, gy + 16 * s),
                             lambda p: p[2] > 120 and p[0] < 100)
        check(hp_blue > 0.05, "左上 HP 条渲染 (blue=%.1f%%)" % (hp_blue * 100))
        # 2) 底部构筑条：半透明暗面板（与亮色地面区分）
        bar_dark = crop_ratio(im, (gx + 27 * s, gy + 310 * s, gx + 590 * s, gy + 350 * s),
                              lambda p: p[0] + p[1] + p[2] < 180)
        check(bar_dark > 0.15, "构筑条面板渲染 (dark=%.1f%%)" % (bar_dark * 100))
        # 3) 顶部中央无 Boss 血条（红像素 < 2%）
        boss_red = crop_ratio(im, (gx + 170 * s, gy + 4 * s, gx + 470 * s, gy + 24 * s),
                              lambda p: p[0] > 120 and p[1] < 80 and p[2] < 80)
        check(boss_red < 0.02, "顶部中央无 Boss 血条遮挡 (red=%.2f%%)" % (boss_red * 100))

        # 4) 点击第一个物品格 → 详情弹窗
        click(gx + 188 * s, gy + 330 * s)
        time.sleep(1)
        check(screenshot(os.path.join(SHOT_DIR, "v2_detail.png")), "详情弹窗截屏")
        im2 = Image.open(os.path.join(SHOT_DIR, "v2_detail.png")).convert("RGB")
        panel_ratio = crop_ratio(im2, (gx + 170 * s, gy + 80 * s, gx + 470 * s, gy + 175 * s),
                                 lambda p: abs(p[0] - 32) < 30 and abs(p[1] - 26) < 30 and abs(p[2] - 48) < 40)
        check(panel_ratio > 0.2, "详情弹窗面板渲染 (panel=%.1f%%)" % (panel_ratio * 100))

        # 5) 点击弹窗外空白处关闭详情（左上角）
        click(gx + 60 * s, gy + 60 * s)
        time.sleep(0.8)

        # 6) 折叠构筑条：暗色面板占比应显著下降
        click(gx + 22 * s, gy + 326 * s)
        time.sleep(0.8)
        check(screenshot(os.path.join(SHOT_DIR, "v2_collapsed.png")), "折叠后截屏")
        im3 = Image.open(os.path.join(SHOT_DIR, "v2_collapsed.png")).convert("RGB")
        bar_dark2 = crop_ratio(im3, (gx + 27 * s, gy + 310 * s, gx + 590 * s, gy + 350 * s),
                               lambda p: p[0] + p[1] + p[2] < 180)
        check(bar_dark2 < bar_dark * 0.6, "折叠后构筑条隐藏 (dark %.1f%% -> %.1f%%)" %
              (bar_dark * 100, bar_dark2 * 100))

        print("=== HUD VISUAL TEST %s ===" % ("FAIL" if failures else "ALL PASS"))
    finally:
        if chrome:
            chrome.terminate()
        httpd.shutdown()
        shutil.rmtree(PROFILE, ignore_errors=True)


if __name__ == "__main__":
    main()
